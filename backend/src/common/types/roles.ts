// backend/src/common/types/roles.ts
export enum Role {
  SUPER_ADMIN = 'SUPER_ADMIN',   // Administración total del sistema
  ADMIN       = 'ADMIN',         // Administración de usuarios y datos
  MANAGER     = 'MANAGER',       // Gestión de contenido, sin acceso a sistema
  ANALYST     = 'ANALYST',       // Lectura + generación de reportes
  VIEWER      = 'VIEWER',        // Solo lectura
}

export const ROLE_HIERARCHY: Record<Role, Role[]> = {
  [Role.SUPER_ADMIN]: [Role.ADMIN, Role.MANAGER, Role.ANALYST, Role.VIEWER],
  [Role.ADMIN]:       [Role.MANAGER, Role.ANALYST, Role.VIEWER],
  [Role.MANAGER]:     [Role.ANALYST, Role.VIEWER],
  [Role.ANALYST]:     [Role.VIEWER],
  [Role.VIEWER]:      [],
};