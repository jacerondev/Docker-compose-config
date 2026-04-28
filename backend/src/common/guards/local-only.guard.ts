// filepath: backend/src/common/guards/local-only.guard.ts
import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';

const ALLOWED_NETS = ['127.0.0.1', '::1', '::ffff:127.0.0.1'];
// Rango 172.16.0.0/12 cubre las redes bridge de Docker
const DOCKER_NET_REGEX = /^172\.(1[6-9]|2\d|3[01])\./;

@Injectable()
export class LocalOnlyGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    const ip: string = req.ip ?? req.connection.remoteAddress ?? '';
    const clean = ip.replace('::ffff:', '');

    if (ALLOWED_NETS.includes(ip) || DOCKER_NET_REGEX.test(clean)) {
      return true;
    }
    throw new ForbiddenException('Acceso restringido a red interna');
  }
}