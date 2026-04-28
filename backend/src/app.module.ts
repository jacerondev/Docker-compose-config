// filepath: backend/src/app.module.ts
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { APP_GUARD } from '@nestjs/core';
import { HealthModule } from './health/health.module';
import { PrometheusModule } from '@willsoto/nestjs-prometheus';
import { TypeOrmModule } from '@nestjs/typeorm';
import { getDatabaseConfig } from '@config/database.config';
import { AuthModule } from './auth/auth.module';
import { JwtAuthGuard } from './auth/guards/jwt-auth.guard';
import { MetricsAuthGuard } from './auth/guards/metrics-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { UserThrottlerGuard } from './common/guards/user-throttler.guard';
import { CspReportController } from './common/controllers/csp-report.controller';
import { LoggerModule } from 'nestjs-pino';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.NODE_ENV === 'production' ? 'info' : 'debug',
        transport: process.env.NODE_ENV !== 'production'
          ? { target: 'pino-pretty' }
          : undefined,
        // Redactar campos sensibles
        redact: {
          paths: ['req.headers.authorization', 'req.headers.cookie', 'req.body.password'],
          censor: '[REDACTED]',
        },
        // Añadir request_id de X-Request-Id
        customProps: (req) => ({
          requestId: req.headers['x-request-id'],
        }),
      },
    }),
    ConfigModule.forRoot({ isGlobal: true }),
    ThrottlerModule.forRoot([
      { name: 'short',  ttl: 1000,  limit: 10 },
      { name: 'medium', ttl: 60000, limit: 100 },
    ]),
    // ThrottlerModule.forRootAsync({
    //   useFactory: (config: ConfigService) => ({
    //     throttlers: [{ ttl: 60, limit: 100 }],
    //     storage: new ThrottlerStorageRedisService({
    //       host: config.get('REDIS_HOST'),
    //       port: config.get('REDIS_PORT'),
    //       password: readSecret('REDIS_SECRET_FILE', 'REDIS_PASSWORD'),
    //     }),
    //   }),
    // }),
    PrometheusModule.register({
      defaultMetrics: { enabled: true },
      path: '/metrics',
      customMetricsByDefault: true,
    }),
    HealthModule,
    TypeOrmModule.forRootAsync({
      useFactory: getDatabaseConfig,
    }),
    // AUTH_MODE=development → JwtAuthGuard usa usuario simulado (bloqueado en NODE_ENV=production)
    // AUTH_MODE=real        → JwtAuthGuard verifica JWT real (ver jwt-auth.guard.ts)
    AuthModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: UserThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },  // primero autenticar
    { provide: APP_GUARD, useClass: RolesGuard },    // luego verificar rol
    { provide: APP_GUARD, useClass: MetricsAuthGuard }, // proteger /metrics
  ],
  controllers: [CspReportController],
})
export class AppModule {}
