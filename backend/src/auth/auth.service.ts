// filepath: backend/src/auth/auth.service.ts
// ══════════════════════════════════════════════════════════════════════════════
// PLANTILLA DE AUTH SERVICE — Implementación parcial
//
// Estado actual: solo refreshTokens() está implementado (verifica el JWT
// del refresh token y emite un nuevo access token), codigo temporal para funcionamiento.
// El resto de funcionalidades (login, logout, refresh con rotación) están
// esbozadas pero no activas (ver comentarios TODO). Ver codigo comentado al final del archivo.
// ══════════════════════════════════════════════════════════════════════════════

import { Injectable, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { readSecret } from '@config/secrets';

@Injectable()
export class AuthService {
  private readonly jwtSecret: string;

  constructor(private jwtService: JwtService) {
    // Se lee UNA vez al instanciar el servicio (al arrancar la app)
    const secret = readSecret('JWT_SECRET_FILE', 'JWT_SECRET');
    if (!secret) {
      throw new Error('[AuthService] JWT_SECRET no disponible. Verifica Docker Secrets o .env');
    }
    this.jwtSecret = secret;
  }

  async refreshTokens(refreshToken: string): Promise<{ access_token: string }> {
    let payload: { sub: number; email: string; role: string; type: string };

    try {
      payload = this.jwtService.verify(refreshToken, { secret: this.jwtSecret });
    } catch {
      throw new UnauthorizedException('Refresh token inválido o expirado');
    }

    if (payload.type !== 'refresh') {
      throw new UnauthorizedException('Token inválido');
    }

    const expiresIn = process.env.JWT_EXPIRES_IN ?? '15m';
    // Validar formato antes de usarlo
    if (!/^\d+[smhd]$/.test(expiresIn)) {
      throw new Error(`[AuthService] JWT_EXPIRES_IN con formato inválido: "${expiresIn}". Use "15m", "1h", etc.`);
    }

    return {
      access_token: this.jwtService.sign(
        { sub: payload.sub, email: payload.email, role: payload.role, type: 'access' },
        { expiresIn },
      ),
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// filepath: backend/src/auth/auth.service.ts
// ══════════════════════════════════════════════════════════════════════════════
// ROTACIÓN DE REFRESH TOKENS — Esqueleto listo para implementar
//
// Patrón: cada uso del refresh token lo invalida y emite uno nuevo.
// Si se detecta reuso de un token ya invalidado → revocar TODA la familia
// del usuario (señal de robo de token).
//
// PREREQUISITOS para activar:
//   1. Crear entidad RefreshToken en BD (ver esquema abajo)
//   2. Inyectar RefreshTokenRepository en el constructor
//   3. Descomentar el método refreshTokens() de abajo
//   4. Comentar el método actual refreshTokens() simplificado
//   5. pnpm add uuid && pnpm add -D @types/uuid
//
// ESQUEMA BD (crear migración):
//   CREATE TABLE refresh_tokens (
//     id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
//     jti         VARCHAR(36) UNIQUE NOT NULL,  -- JWT ID del token
//     user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
//     family      VARCHAR(36) NOT NULL,          -- familia de tokens del usuario
//     revoked     BOOLEAN NOT NULL DEFAULT false,
//     expires_at  TIMESTAMPTZ NOT NULL,
//     created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
//   );
//   CREATE INDEX ON refresh_tokens(jti);
//   CREATE INDEX ON refresh_tokens(user_id);
// ══════════════════════════════════════════════════════════════════════════════

// import { v4 as uuidv4 } from 'uuid';
// import { InjectRepository } from '@nestjs/typeorm';
// import { Repository } from 'typeorm';
// import { RefreshToken } from '../tokens/refresh-token.entity';

// async refreshTokensWithRotation(
//   oldRefreshToken: string,
// ): Promise<{ access_token: string; refresh_token: string }> {
//
//   // 1. Verificar firma del token
//   let payload: { sub: number; email: string; role: string; type: string; jti: string; family: string };
//   try {
//     payload = this.jwtService.verify(oldRefreshToken, { secret: this.jwtSecret });
//   } catch {
//     throw new UnauthorizedException('Refresh token inválido o expirado');
//   }
//
//   if (payload.type !== 'refresh') throw new UnauthorizedException('Token inválido');
//
//   // 2. Buscar el token en BD
//   const stored = await this.refreshTokenRepo.findOne({ where: { jti: payload.jti } });
//
//   // 3. DETECCIÓN DE REUSO: si el token ya fue revocado, revocar TODA la familia
//   //    Esto indica que el token fue robado y usado dos veces
//   if (!stored || stored.revoked) {
//     await this.refreshTokenRepo.update(
//       { family: payload.family },
//       { revoked: true },
//     );
//     throw new UnauthorizedException('Token reutilizado: todas las sesiones revocadas por seguridad');
//   }
//
//   // 4. Revocar el token usado
//   await this.refreshTokenRepo.update({ jti: payload.jti }, { revoked: true });

//   const refreshExpiresIn = process.env.JWT_REFRESH_EXPIRES_IN ?? '7d';
//   if (!/^\d+[smhd]$/.test(refreshExpiresIn)) throw new Error(`JWT_REFRESH_EXPIRES_IN inválido: "${refreshExpiresIn}"`);

//   const accesExpiresIn = process.env.JWT_EXPIRES_IN ?? '15m';
//   if (!/^\d+[smhd]$/.test(accesExpiresIn)) throw new Error(`JWT_EXPIRES_IN inválido: "${accesExpiresIn}"`);
//
//   // 5. Emitir nuevo refresh token con el mismo family
//   const newJti = uuidv4();
//   const newRefreshToken = this.jwtService.sign(
//     { sub: payload.sub, email: payload.email, role: payload.role,
//       type: 'refresh', jti: newJti, family: payload.family },
//     { expiresIn: refreshExpiresIn },
//   );
//
//   // 6. Persistir el nuevo token
//   await this.refreshTokenRepo.save({
//     jti: newJti,
//     userId: payload.sub,
//     family: payload.family,
//     revoked: false,
//     expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
//   });
//
//   // 7. Emitir nuevo access token
//   const access_token = this.jwtService.sign(
//     { sub: payload.sub, email: payload.email, role: payload.role, type: 'access' },
//     { expiresIn: accesExpiresIn },
//   );
//
//   return { access_token, refresh_token: newRefreshToken };
// }