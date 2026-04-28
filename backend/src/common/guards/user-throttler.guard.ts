// filepath: backend/src/common/guards/user-throttler.guard.ts
import { ThrottlerGuard } from '@nestjs/throttler';
import { Injectable, ExecutionContext } from '@nestjs/common';

@Injectable()
export class UserThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    const userId = req.user?.userId;
    return userId ? `user-${userId}` : (req.ip ?? 'unknown');
  }
}
