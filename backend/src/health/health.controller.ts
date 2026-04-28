// filepath: backend/src/health/health.controller.ts
import { Controller, Get, Post, Body, HttpCode } from '@nestjs/common';
import { Logger } from 'nestjs-pino'
import { HealthCheck, HealthCheckService, HealthCheckResult, TypeOrmHealthIndicator } from '@nestjs/terminus';
import { SkipThrottle } from '@nestjs/throttler';
import { ApiTags, ApiOperation } from '@nestjs/swagger';
import { Public } from '@common/decorators/public.decorator';
import { UseGuards } from '@nestjs/common';
import { LocalOnlyGuard } from '@common/guards/local-only.guard';

@ApiTags('health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly db: TypeOrmHealthIndicator
  ) {}

  // PÚBLICO — Nginx lo expone al exterior. Sin detalle de BD.
  // Docker NO usa este endpoint para su healthcheck.
  @Public()
  @SkipThrottle()
  @Get()
  @ApiOperation({ summary: 'Estado del servicio (público, sin detalle de BD)' })
  ping(): { status: string } {
    return { status: 'ok' };
  }

  // PRIVADO — Solo usado por el Docker healthcheck (curl dentro del contenedor).
  // Nginx NO debe hacer proxy de esta ruta. Verifica BD real.
  @Public()
  @SkipThrottle()
  @UseGuards(LocalOnlyGuard)
  @Get('ready')
  @HealthCheck()
  @ApiOperation({ summary: 'Estado completo con BD (interno, no exponer via Nginx)' })
  ready(): Promise<HealthCheckResult> {
    return this.health.check([
      () => this.db.pingCheck('database'),
    ]);
  }
}