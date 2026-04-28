// filepath: backend/src/common/decorators/roles.decorator.ts
import { SetMetadata } from '@nestjs/common';

export enum UserRole {
  SUPER_ADMIN = 'SUPER_ADMIN',
  ADMIN       = 'ADMIN',
  MANAGER     = 'MANAGER',
  ANALYST     = 'ANALYST',
  MODERATOR   = 'MODERATOR',
  VIEWER      = 'VIEWER',
  // Mantener USER para compatibilidad si ya hay datos:
  USER        = 'USER',
}

export const ROLES_KEY = 'roles';

/**
 * Restringe un endpoint a los roles especificados.
 * @example @Roles(UserRole.ADMIN)
 */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);