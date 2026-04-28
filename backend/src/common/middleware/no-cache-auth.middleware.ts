// filepath: backend/src/common/middleware/no-cache-auth.middleware.ts
import { Injectable, NestMiddleware } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';

@Injectable()
export class NoCacheAuthMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
    res.setHeader('Pragma', 'no-cache'); // compatibilidad HTTP/1.0
    res.setHeader('Expires', '0');       // proxies antiguos
    next();
  }
}