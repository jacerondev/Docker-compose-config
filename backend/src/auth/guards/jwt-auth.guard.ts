// filepath: backend/src/auth/guards/jwt-auth.guard.ts
// ══════════════════════════════════════════════════════════════════════════════
// Guard JWT — MODO TEMPORAL: simula usuario autenticado
//
// ⚠️  SEGURIDAD: Este guard está en modo temporal (AUTH_MODE=development).
//    En producción (NODE_ENV=production), lanzará un error si AUTH_MODE no es 'real'.
//    Esto impide despliegues accidentales con autenticación deshabilitada.
//
// Para activar JWT real:
//   1. Implementar AuthService completo (ver auth.service.ts y BACKEND-NESTJS.md)
//   2. Cambiar AUTH_MODE=real en .env.production
//   3. Descomentar las líneas marcadas con "JWT REAL"
// ══════════════════════════════════════════════════════════════════════════════

import {
  Injectable,
  ExecutionContext,
  InternalServerErrorException,
  UnauthorizedException,
} from '@nestjs/common';
// import { AuthGuard } from '@nestjs/passport';
import { Request } from 'express';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from '@common/decorators/public.decorator';

// AUTH_MODE controla si el guard usa JWT real o el simulado temporal.
// Valores válidos: 'development' (temporal) | 'real' (JWT verificado)
// En producción (NODE_ENV=production), AUTH_MODE=development es un error de configuración.
const AUTH_MODE = process.env.AUTH_MODE ?? 'development';
const IS_PRODUCTION = process.env.NODE_ENV === 'production';

// Protección en tiempo de carga del módulo:
// Si alguien despliega a producción con el guard temporal, el servidor
// fallará al arrancar con un mensaje claro, no silenciosamente.
if (IS_PRODUCTION && AUTH_MODE !== 'real') {
  throw new Error(
    '[JwtAuthGuard] AUTH_MODE=development no está permitido en NODE_ENV=production.\n' +
    'Para producción: establece AUTH_MODE=real en .env.production\n' +
    'y completa la implementación de JWT (ver docs/guides/BACKEND-NESTJS.md).',
  );
}

@Injectable()
// JWT REAL — reemplazar la línea de abajo por:
// export class JwtAuthGuard extends AuthGuard('jwt') {
export class JwtAuthGuard {
  // JWT REAL — reemplazar la línea de abajo por:
  // constructor(
  //   private reflector: Reflector,
  //   private tokenBlacklist: TokenBlacklistService,
  // ) {
  //   super();
  // }
  constructor(private reflector: Reflector) {}

  // JWT REAL — reemplazar la línea de abajo por:
  // async canActivate(context: ExecutionContext): Promise<boolean> {
  canActivate(context: ExecutionContext): boolean {
    // 1. Si el endpoint tiene @Public(), dejar pasar sin autenticación
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    // Verificar JWT via Passport
    // const canActivate = await super.canActivate(context);
    // if (!canActivate) return false;

    // Verificar que el token no esté en blacklist (post-logout)
    // const req = context.switchToHttp().getRequest();
    // const token = req.cookies?.access_token;
    // if (token && await this.tokenBlacklist.isBlacklisted(token)) {
    //   throw new UnauthorizedException('Token revocado');
    // }

    // return true;

    // ===========================MODO TEMPORAL: SIMULACIÓN DE USUARIO AUTENTICADO===========================
    // Nota: este bloque se activa solo es temporal. Con el guard real descomentar codigo JWT y eliminar este bloque.
    // 2. MODO TEMPORAL: inyectar un usuario simulado en req.user
    //    Solo activo cuando AUTH_MODE=development (bloqueado en producción).
    //    Cuando se implemente JWT real: borrar este bloque y descomentar (3).
    if (AUTH_MODE === 'development') {
      const request = context.switchToHttp().getRequest<Request>();
      request.user = {
        userId: 9999999,          // ID temporal — reemplazar con el real del JWT
        email: 'dev@local.dev',   // Email temporal
        role: 'VIEWER',           // Rol temporal — reemplazar con el del JWT
      };
      return true;
    }

    // Fallback defensivo: si AUTH_MODE tiene un valor inesperado, denegar acceso
    return false;
    // ===========================MODO TEMPORAL: SIMULACIÓN DE USUARIO AUTENTICADO===========================
  }
}