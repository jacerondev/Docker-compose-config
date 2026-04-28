// filepath: backend/src/auth/password.service.ts
import * as argon2 from 'argon2';
import { readSecret } from '@config/secrets';
import { Logger } from 'nestjs-pino'

const logger = new Logger('PasswordService');

// El pepper se lee UNA vez al cargar el módulo.
// Añade una capa extra: aunque la DB se filtre, el hash no es reversible sin el pepper.
// En producción: PEPPER_SECRET_FILE=/run/secrets/pepper_secret
// En desarrollo: PEPPER_SECRET en .env
const PEPPER = readSecret('PEPPER_SECRET_FILE', 'PEPPER_SECRET') ?? '';
if (process.env.NODE_ENV !== 'production' && PEPPER.startsWith('CAMBIAR_')) {
  logger.warn('PEPPER_SECRET usa placeholder. Ejecuta: make setup');
}
if (process.env.NODE_ENV === 'production' && (!PEPPER || PEPPER.startsWith('CAMBIAR_'))) {
  throw new Error('[password.service] PEPPER_SECRET inválido en producción.');
}

const ARGON2_OPTIONS: argon2.Options = {
  type: argon2.argon2id,
  memoryCost: 65536,   // 64 MB — ajustar según RAM disponible
  timeCost: 3,          // 3 iteraciones
  parallelism: 4,       // hilos paralelos
};

export async function hashPassword(plain: string): Promise<string> {
  // Combinar con pepper antes de hashear
  // El pepper añade una capa extra: si la DB se filtra, el hash no es reversible
  // sin conocer también el pepper (almacenado en secret, no en DB)
  return argon2.hash(plain + PEPPER, ARGON2_OPTIONS);
}

export async function verifyPassword(
  hash: string,
  plain: string,
): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain + PEPPER);
  } catch {
    // argon2.verify lanza si el hash tiene formato inválido
    return false;
  }
}