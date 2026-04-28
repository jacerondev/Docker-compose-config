// filepath: backend/src/config/secrets.ts
// ══════════════════════════════════════════════════════════════════════════════
// Utilidad centralizada para leer secretos
//
// Principio: un solo lugar donde se lee un secreto, con comportamiento
// consistente en toda la aplicación.
//
// Flujo de resolución:
//   1. Lee {fileVar} del entorno → abre el archivo y devuelve su contenido
//   2. Si no hay archivo → lee {plainVar} del entorno
//   3. Si tampoco existe y es requerido → lanza error con mensaje claro
//
// Uso:
//   readSecret('DB_PASSWORD_FILE', 'DB_PASSWORD')         // requerido
//   readSecret('COOKIE_SECRET_FILE', 'COOKIE_SECRET', false) // opcional
// ══════════════════════════════════════════════════════════════════════════════

import * as fs from 'fs';
import * as crypto from 'crypto';

const PLACEHOLDER_PREFIXES = ['CAMBIAR_', 'placeholder', 'changeme', 'your_', 'TODO'];

function isPlaceholder(value: string): boolean {
  return PLACEHOLDER_PREFIXES.some(p => value.toLowerCase().startsWith(p.toLowerCase()));
}

function hasMinimumEntropy(value: string): boolean {
  // Al menos 8 caracteres únicos de entre 32+ total
  return value.length >= 32 && new Set(value).size >= 8;
}

/**
 * Lee un secreto desde Docker Secret (archivo) o variable de entorno directa.
 *
 * @param fileVar   Variable que apunta al archivo  (ej: 'DB_PASSWORD_FILE')
 * @param plainVar  Variable con el valor directo   (ej: 'DB_PASSWORD')
 * @param required  Si es true (default), lanza error cuando el secreto no existe
 * @param options   Opciones adicionales:
 *   - minLength: longitud mínima del secreto (default: 32)
 *   - requireEntropy: si true, verifica que el secreto no sea un placeholder común
 *   - allowPlaceholderInDev: si true, permite placeholders en desarrollo (default: false)
 */
export function readSecret(
  fileVar: string,
  plainVar: string,
  required = true,
  options: {
    minLength?: number;
    requireEntropy?: boolean;
    allowPlaceholderInDev?: boolean;
  } = {},
): string | undefined {
  const {
    minLength = 0,
    requireEntropy = false,
    allowPlaceholderInDev = true,
  } = options;

  const isProduction = process.env.NODE_ENV === 'production';
  const filePath = process.env[fileVar];

  let value: string | undefined;

  if (filePath) {
    try {
      value = fs.readFileSync(filePath, 'utf8').trim();
    } catch (err) {
      throw new Error(
        `[secrets] No se pudo leer "${filePath}" (${fileVar}).\n` +
        `  Verifica que el Docker Secret está montado correctamente.\n` +
        `  ¿Ejecutaste "make secrets-init"?`,
      );
    }
  } else {
    value = process.env[plainVar];
  }

  if (!value) {
    if (required) {
      throw new Error(
        `[secrets] "${plainVar}" no definido y "${fileVar}" tampoco.\n` +
        `  En desarrollo: revisa tu .env\n` +
        `  En producción: ejecuta "make secrets-init" y "make secrets-check"`,
      );
    }
    return undefined;
  }

  // Validaciones de calidad
  if (minLength > 0 && value.length < minLength) {
    throw new Error(
      `[secrets] "${plainVar}" demasiado corto (${value.length} chars, mínimo ${minLength}).`
    );
  }

  if (isPlaceholder(value)) {
    if (isProduction || !allowPlaceholderInDev) {
      throw new Error(
        `[secrets] "${plainVar}" contiene un valor placeholder ("${value.substring(0, 8)}...").`
      );
    }
    // En desarrollo: warn pero no bloquear
    console.warn(`[secrets] ⚠️  "${plainVar}" parece un placeholder. Ejecuta "make setup".`);
  }

  if (requireEntropy && !hasMinimumEntropy(value)) {
    if (isProduction) {
      throw new Error(
        `[secrets] "${plainVar}" tiene entropía insuficiente. Genera con: openssl rand -base64 48`
      );
    }
  }

  return value;
}