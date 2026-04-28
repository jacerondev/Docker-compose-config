// filepath: backend/src/common/guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY, UserRole } from '@common/decorators/roles.decorator';

// Jerarquía: cada rol hereda los permisos de los inferiores
const ROLE_HIERARCHY: Record<UserRole, UserRole[]> = {
  [UserRole.SUPER_ADMIN]: [UserRole.ADMIN, UserRole.MANAGER, UserRole.ANALYST, UserRole.VIEWER, UserRole.USER],
  [UserRole.ADMIN]:       [UserRole.MANAGER, UserRole.ANALYST, UserRole.VIEWER, UserRole.USER],
  [UserRole.MANAGER]:     [UserRole.ANALYST, UserRole.VIEWER, UserRole.USER],
  [UserRole.ANALYST]:     [UserRole.VIEWER, UserRole.USER],
  [UserRole.VIEWER]:      [UserRole.USER],
  [UserRole.USER]:        [],
};

function hasRequiredRole(userRole: UserRole, requiredRoles: UserRole[]): boolean {
  const effectiveRoles = [userRole, ...(ROLE_HIERARCHY[userRole] ?? [])];
  return requiredRoles.some(r => effectiveRoles.includes(r));
}

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (!requiredRoles || requiredRoles.length === 0) return true;

    const { user } = context.switchToHttp().getRequest();
    if (!user) throw new ForbiddenException('Autenticación requerida');

    if (!hasRequiredRole(user.role as UserRole, requiredRoles)) {
      throw new ForbiddenException(`Acceso denegado. Requiere: ${requiredRoles.join(', ')}`);
    }
    return true;
  }
}