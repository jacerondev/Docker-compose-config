import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { randomUUID } from 'crypto';

@Injectable()
export class RequestIdInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request  = context.switchToHttp().getRequest();
    const response = context.switchToHttp().getResponse();

    // Usar el ID que viene del cliente (frontend) o generar uno nuevo
    const requestId = request.headers['x-request-id'] ?? randomUUID();
    request.requestId = requestId;

    // Propagarlo en la respuesta para que el cliente pueda correlacionar
    response.setHeader('X-Request-Id', requestId);

    return next.handle();
  }
}