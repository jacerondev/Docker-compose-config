// filepath: backend/src/common/decorators/public.decorator.ts
// ══════════════════════════════════════════════════════════════════════════════
// Decorator @Public() — marca un endpoint como accesible sin JWT
//
// Uso:
//   @Public()
//   @Post('login')
//   async login() { ... }
//
// Cómo funciona:
//   SetMetadata escribe IS_PUBLIC_KEY = true en los metadatos del handler.
//   JwtAuthGuard lo lee con Reflector.getAllAndOverride() y, si es true,
//   deja pasar la request sin verificar el token.
//
// Sin este decorator → JwtAuthGuard exige token (comportamiento por defecto).
// ══════════════════════════════════════════════════════════════════════════════

import { SetMetadata } from '@nestjs/common';

/**
 * Clave usada para almacenar el metadata del decorator en Reflect.
 * Exportada para que JwtAuthGuard la pueda leer.
 */
export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Marca un endpoint como público (no requiere autenticación JWT).
 *
 * @example
 * // Endpoint de login — no requiere token previo
 * @Public()
 * @Post('login')
 * async login(@Body() dto: LoginDto) { ... }
 *
 * @example
 * // Endpoint de registro — accesible sin token
 * @Public()
 * @Post('register')
 * async register(@Body() dto: RegisterDto) { ... }
 */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
