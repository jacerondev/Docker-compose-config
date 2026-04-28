// filepath: backend/src/auth/guards/metrics-auth.guard.ts
import { Injectable, CanActivate, ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Request } from 'express';
import { readSecret } from '@config/secrets';

@Injectable()
export class MetricsAuthGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const path = context.switchToHttp().getRequest().path;
    if (path !== '/metrics') return true; // Solo aplica a /metrics

    const request = context.switchToHttp().getRequest<Request>();
    const authHeader = request.headers['authorization'];

    if (!authHeader?.startsWith('Basic ')) {
      throw new UnauthorizedException('Basic auth requerida para /metrics');
    }

    const base64 = authHeader.slice(6);
    const [user, pass] = Buffer.from(base64, 'base64').toString('utf8').split(':');

    const validUser = process.env.METRICS_USER ?? 'prometheus';
    const validPass = readSecret('METRICS_PASSWORD_FILE', 'METRICS_PASSWORD', false);

    if (!validPass || user !== validUser || pass !== validPass) {
      throw new UnauthorizedException();
    }
    return true;
  }
}
