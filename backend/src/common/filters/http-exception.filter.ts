// filepath: backend/src/common/filters/http-exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Logger } from 'nestjs-pino'
import { Request, Response } from 'express';

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const isProduction = process.env.NODE_ENV === 'production';
    const isClientError = status >= 400 && status < 500;
    const isServerError = status >= 500;

    // En producción: mensajes sanitizados para errores de servidor
    const clientMessage = (() => {
      if (exception instanceof HttpException) {
        // 4xx: el mensaje está diseñado para el cliente
        return exception.message;
      }
      // 5xx: NUNCA exponer detalles internos en producción
      return isProduction ? 'Internal server error' : 
             (exception instanceof Error ? exception.message : 'Unknown error');
    })();

    // const errorResponse = {
    //   statusCode: status,
    //   timestamp: new Date().toISOString(),
    //   // path se omite en producción: la URL del request puede contener IDs,
    //   // tokens parciales o rutas internas que no deben exponerse al cliente.
    //   // En desarrollo sí se incluye para facilitar el debugging.
    //   ...(!isProduction && { path: request.url }),
    //   message:
    //     exception instanceof HttpException
    //       ? exception.message
    //       : 'Internal server error',
    //   // Stack SOLO en desarrollo — nunca en producción
    //   ...(!isProduction && {
    //     stack: exception instanceof Error ? exception.stack : undefined,
    //   }),
    // };

    const errorResponse: Record<string, unknown> = {
      statusCode: status,
      timestamp: new Date().toISOString(),
      message: clientMessage,
    };

    // // En producción: logear el error completo server-side para debugging interno
    // // Los detalles nunca salen en la respuesta HTTP al cliente
    // if (isProduction && status >= 500) {
    //   this.logger.error(
    //     `[${request.method}] ${request.url} → ${status}`,
    //     exception instanceof Error ? exception.stack : String(exception),
    //   );
    // }

    // path y stack: SOLO en desarrollo
    if (!isProduction) {
      errorResponse.path = request.url;
      if (exception instanceof Error) {
        errorResponse.stack = exception.stack;
      }
    }

    // Server-side: loggear TODO para debugging interno
    if (isServerError) {
      this.logger.error(
        `[${request.method}] ${request.url} → ${status} | requestId: ${request.headers['x-request-id']}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else if (isClientError && !isProduction) {
      this.logger.warn(
        `[${request.method}] ${request.url} → ${status}`,
      );
    }

    response.status(status).json(errorResponse);
  }
}
