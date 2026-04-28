// filepath: backend/src/common/controllers/csp-report.controller.ts
import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { Logger } from 'nestjs-pino'
import { Public } from '@common/decorators/public.decorator';
import { Throttle } from '@nestjs/throttler';

interface CspReport {
  'csp-report': {
    'document-uri'?: string;
    'blocked-uri'?: string;
    'violated-directive'?: string;
    'effective-directive'?: string;
    'original-policy'?: string;
    'disposition'?: string;
    'status-code'?: number;
  };
}

@Controller()
export class CspReportController {
  private readonly logger = new Logger('CSP');

  @Public()
  // Los navegadores legítimos raramente envían más de 1-2 reportes por minuto
  // 5 por minuto por IP es suficiente para uso real y bloquea ataques de DoS de logs
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('csp-report')
  @HttpCode(HttpStatus.NO_CONTENT)  // 204 es el estándar para CSP reports
  report(@Body() body: unknown): void {
    // Verificar que sea un objeto con la estructura esperada
    // No loggear document-uri completos (pueden revelar rutas internas)
    const report = (body as CspReport)?.['csp-report'];
    if (!report || typeof report !== 'object') return;

    // Sanitizar: solo loggear campos esperados, truncar a 200 chars
    const safe = {
      blockedUri: String(report['blocked-uri'] ?? '').slice(0, 200),
      violatedDirective: String(report['violated-directive'] ?? '').slice(0, 100),
      // NO loggear document-uri completo — puede revelar rutas autenticadas
    };
    this.logger.warn('CSP_VIOLATION', safe);
    // TODO: en producción, enviar a Sentry / Grafana Loki para alertas
  }
  // report(@Body() body: CspReport): void {
  //   const report = body?.['csp-report'];
  //   if (!report) return;

  //   this.logger.warn('CSP_VIOLATION', {
  //     blockedUri:          report['blocked-uri'],
  //     violatedDirective:   report['violated-directive'],
  //     effectiveDirective:  report['effective-directive'],
  //     documentUri:         report['document-uri'],
  //     disposition:         report['disposition'],
  //   });
  //   // TODO: en producción, enviar a Sentry / Grafana Loki para alertas
  // }
}