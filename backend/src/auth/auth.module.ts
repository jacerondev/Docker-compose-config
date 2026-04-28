// filepath: backend/src/auth/auth.module.ts
import {
  Module,
  NestModule,
  MiddlewareConsumer,
  RequestMethod,
} from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
// import { PassportModule } from '@nestjs/passport';  // TODO: descomentar al activar JWT real
// import { JwtStrategy } from './strategies/jwt.strategy'; // TODO: descomentar
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { NoCacheAuthMiddleware } from '@common/middleware/no-cache-auth.middleware';
import { readSecret } from '@config/secrets';

// JwtModule.register() es obligatorio aunque AuthService sea plantilla:
// el constructor inyecta JwtService, y sin este registro NestJS no puede
// resolver la dependencia — el servidor falla al arrancar con:
//   "Nest can't resolve dependencies of the AuthService (?). Please make
//    sure that the argument JwtService at index [0] is available in the AuthModule context."
//
// Cuando se complete la implementación, migrar a JwtModule.registerAsync()
// con ConfigService para leer JWT_SECRET de forma segura y tipada.
@Module({
  imports: [
    JwtModule.register({
      // JWT_SECRET en desarrollo viene de .env vía docker-compose.yml
      // JWT_SECRET en producción viene de Docker Secret vía JWT_SECRET_FILE
      // (docker-compose.prod.yml lo monta en /run/secrets/jwt_secret)
      secret: readSecret('JWT_SECRET_FILE', 'JWT_SECRET'),
      signOptions: {
        expiresIn: process.env.JWT_EXPIRES_IN ?? '15m',
      },
    }),
    // PassportModule.register({ defaultStrategy: 'jwt' }),  // TODO
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    // JwtStrategy,  // TODO: descomentar al activar JWT real
  ],
  exports: [
    AuthService,
    JwtModule,  // Exportado para que otros módulos puedan verificar tokens si lo necesitan
  ],
})
export class AuthModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(NoCacheAuthMiddleware)
      .exclude({ path: 'auth/health', method: RequestMethod.GET })
      .forRoutes('auth'); // esto cubre /auth/*
  }
}
