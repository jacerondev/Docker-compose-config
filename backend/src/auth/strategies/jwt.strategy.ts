// filepath: backend/src/auth/strategies/jwt.strategy.ts
// ══════════════════════════════════════════════════════════════════════════════
// Estrategia JWT de Passport — valida el token en cada request
//
// Prerequisito:
//   pnpm add @nestjs/jwt @nestjs/passport passport passport-jwt
//   pnpm add -D @types/passport-jwt
// ══════════════════════════════════════════════════════════════════════════════

// import { Injectable } from '@nestjs/common';
// import { PassportStrategy } from '@nestjs/passport';
// import { ExtractJwt, Strategy } from 'passport-jwt';
// import { ConfigService } from '@nestjs/config';
// import { readSecret } from '@config/secrets';

// Payload que se guarda en el JWT al hacer login
export interface JwtPayload {
  sub: number;      // userId — convención JWT
  email: string;
  role: string;
  iat?: number;     // issued at — añadido automáticamente por @nestjs/jwt
  exp?: number;     // expiration — añadido automáticamente
}

// @Injectable()
// export class JwtStrategy extends PassportStrategy(Strategy) {
//   constructor(configService: ConfigService) {
//     super({
//       jwtFromRequest: ExtractJwt.fromExtractors([
//         (req) => req?.cookies?.access_token,
//       ]),
//       ignoreExpiration: false,
//       secretOrKey: readSecret('JWT_SECRET_FILE', 'JWT_SECRET'),
//     });
//   }
//
//   // Este método se llama cuando el token es válido
//   // El resultado se adjunta a req.user en el controller
//   validate(payload: JwtPayload) {
//     if (payload.type !== 'access') {
//       throw new UnauthorizedException('Token type inválido');
//     }
//     return {
//       userId: payload.sub,
//       email: payload.email,
//       role: payload.role,
//     };
//   }
// }
