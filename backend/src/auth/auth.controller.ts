// filepath: backend/src/auth/auth.controller.ts
// ══════════════════════════════════════════════════════════════════════════════
// PLANTILLA DE AUTENTICACIÓN — SIN LÓGICA DE NEGOCIO
//
// Este archivo es una plantilla estructural.
//
// Estrategia de tokens: httpOnly Cookies (ADR-022)
//   - Login emite cookies httpOnly en lugar de devolver tokens en el body.
//   - El frontend usa `credentials: 'include'` — no gestiona tokens manualmente.
//   - Refresh lee la cookie del refresh token y emite una nueva cookie de access.
//   - Logout limpia las cookies desde el servidor.
//   Ver: docs/DECISIONS.md ADR-022
//
// TODO al implementar auth real:
//   1. pnpm add @nestjs/jwt @nestjs/passport passport passport-jwt argon2 cookie-parser
//   2. pnpm add -D @types/passport-jwt @types/cookie-parser
//   3. Registrar CookieParser en main.ts: app.use(cookieParser())
//   4. Implementar register() y login() en auth.service.ts
//   5. Cambiar AUTH_MODE=real en .env.production
//   6. Lockout temporal y rate limiting por IP+email cuando Redis esté disponible (ver sección al final del archivo)
//
// Estado: Esqueleto — endpoints definidos, sin lógica implementada
// ══════════════════════════════════════════════════════════════════════════════

import {
  Controller,
  Post,
  Get,
  Body,
  Req,
  Res,
  HttpCode,
  HttpStatus,
  NotImplementedException,
  UnauthorizedException,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBody,
  ApiCookieAuth,
} from '@nestjs/swagger';
import { Request as ExpressRequest, Response as ExpressResponse } from 'express';
import { Throttle, SkipThrottle } from '@nestjs/throttler';
import { Public } from '@common/decorators/public.decorator';
import { LoginDto } from './dto/login.dto';
import { RegisterDto } from './dto/register.dto';
import { AuthService } from './auth.service';
import { Roles } from '@common/decorators/roles.decorator';
import { UserRole } from '@common/decorators/roles.decorator';

// const config = new DocumentBuilder()
//   .setTitle('NOMBRE_DEL_PROYECTO API')
//   .setDescription(`
// ## Autenticación
// Todos los endpoints (excepto los marcados como públicos) requieren una cookie \`access_token\` httpOnly.
// Para obtenerla: \`POST /api/auth/login\`.

// ## Rate Limiting
// - Global: 10 req/s por IP, 100 req/min
// - CSP Report: 5 por minuto
// - Login: 5 por minuto (anti-brute-force)
//   `)
//   .setVersion('1.0')
//   .addCookieAuth('access_token', { type: 'apiKey', in: 'cookie' })
//   .addServer('http://localhost:4000', 'Desarrollo local')
//   .build();

// Configuración de cookies de auth (centralizada para consistencia)
const COOKIE_OPTIONS = {
  httpOnly: true,                                              // Inaccesible desde JS — previene robo via XSS
  secure: process.env.NODE_ENV === 'production',              // Solo HTTPS en producción
  sameSite: 'strict' as const,                               // Previene CSRF cross-site
  // sameSite: 'lax' as const,                              // Protege contra CSRF sin romper navegación desde links
};

// Tipo del usuario inyectado por JwtAuthGuard (temporal o real)
interface AuthenticatedUser {
  userId: number;
  email: string;
  role: string;
}

const ACCESS_TOKEN_COOKIE  = 'access_token';
const REFRESH_TOKEN_COOKIE = 'refresh_token';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // POST /auth/register — 3 intentos/hora por IP
  @Public()
  @Throttle({ medium: { limit: 3, ttl: 3_600_000 } })
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Registrar nuevo usuario' })
  @ApiResponse({ status: 201, description: 'Usuario creado exitosamente' })
  @ApiResponse({ status: 409, description: 'El email ya está registrado' })
  async register(@Body() dto: RegisterDto) {
    // TODO: return this.authService.register(dto);
    throw new NotImplementedException(
      'Registro pendiente de implementar. Ver docs/guides/BACKEND-NESTJS.md',
    );
  }

  // POST /auth/login — 5 intentos/minuto por IP
  // Con cookies (ADR-022): no devuelve tokens en el body — los emite como cookies httpOnly.
  // @ApiTags('auth')
  @Public()
  @Throttle({ short: { limit: 5, ttl: 60_000 } })
  @Post('login')
  @HttpCode(HttpStatus.OK)
  // @ApiOperation({ summary: 'Iniciar sesión — emite cookies httpOnly de auth' })
  @ApiOperation({
    summary: 'Iniciar sesión',
    description: 'Autentica al usuario y devuelve un access token en cookie httpOnly.'
  })
  @ApiBody({ type: LoginDto })
  @ApiResponse({ status: 200, description: 'Login exitoso — cookies de auth emitidas' })
  // @ApiResponse({ status: 200, description: 'Login exitoso. Cookie access_token establecida.' })
  @ApiResponse({ status: 400, description: 'Credenciales inválidas o payload malformado.' })
  @ApiResponse({ status: 401, description: 'Credenciales inválidas' })
  // @ApiResponse({ status: 401, description: 'Email o contraseña incorrectos.' })
  @ApiResponse({ status: 429, description: 'Rate limit excedido.' })
  @ApiResponse({ status: 501, description: 'No implementado aún' })
  async login(
    @Body() dto: LoginDto,
    @Res({ passthrough: true }) res: ExpressResponse,
  ) {
    // TODO: Implementar cuando AuthService esté completo:
    //
    // const { accessToken, refreshToken } = await this.authService.login(dto);
    //
    // res.cookie(ACCESS_TOKEN_COOKIE, accessToken, {
    //   ...COOKIE_OPTIONS,
    //   maxAge: 15 * 60 * 1000,           // 15 minutos
    // });
    // res.cookie(REFRESH_TOKEN_COOKIE, refreshToken, {
    //   ...COOKIE_OPTIONS,
    //   maxAge: 7 * 24 * 60 * 60 * 1000,  // 7 días
    //   path: '/api/auth/refresh',         // Solo accesible en el endpoint de refresh
    // });
    //
    // return { message: 'Login exitoso' };

    throw new NotImplementedException(
      'Login pendiente de implementar. Ver docs/guides/BACKEND-NESTJS.md',
    );
  }

  // POST /auth/refresh — renueva access_token leyendo la cookie de refresh
  @Public()
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Renovar access token via cookie de refresh' })
  @ApiResponse({ status: 200, description: 'Nueva cookie de access_token emitida' })
  @ApiResponse({ status: 401, description: 'Refresh token inválido o expirado' })
  @ApiResponse({ status: 501, description: 'No implementado aún' })
  async refresh(
    @Req() req: ExpressRequest,
    @Res({ passthrough: true }) res: ExpressResponse,
  ) {
    // TODO: Implementar cuando AuthService esté completo:
    //
    // const refreshToken = req.cookies?.[REFRESH_TOKEN_COOKIE];
    // if (!refreshToken) throw new UnauthorizedException('Refresh token ausente');
    //
    // const { access_token } = await this.authService.refreshTokens(refreshToken);
    //
    // res.cookie(ACCESS_TOKEN_COOKIE, access_token, {
    //   ...COOKIE_OPTIONS,
    //   maxAge: 15 * 60 * 1000,
    //   path: '/',
    // });
    //
    // return { message: 'Token renovado' };

    throw new NotImplementedException(
      'Refresh pendiente de implementar. Ver docs/guides/BACKEND-NESTJS.md',
    );
  }

  // GET /auth/me — perfil del usuario autenticado (requiere cookie de access_token)
  @Roles(UserRole.VIEWER, UserRole.USER, UserRole.MODERATOR, UserRole.ADMIN)
  @Get('me')
  @ApiCookieAuth(ACCESS_TOKEN_COOKIE)
  @ApiOperation({ summary: 'Obtener perfil del usuario autenticado' })
  @ApiResponse({ status: 200, description: 'Perfil del usuario' })
  @ApiResponse({ status: 401, description: 'Token ausente o expirado' })
  getProfile(@Req() req: ExpressRequest & { user?: AuthenticatedUser }) {
    // req.user es inyectado por JwtAuthGuard (temporal en dev, real en prod)
    if (!req.user) {
      throw new UnauthorizedException('Token requerido');
    }
    return {
      userId: req.user.userId,
      email: req.user.email,
      role: req.user.role,
    };
  }

  // POST /auth/logout — limpia las cookies de auth en el servidor
  @Roles(UserRole.VIEWER, UserRole.USER, UserRole.MODERATOR, UserRole.ADMIN)
  @Post('logout')
  @ApiCookieAuth(ACCESS_TOKEN_COOKIE)
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Cerrar sesión — limpia cookies de auth' })
  async logout(@Res({ passthrough: true }) res: ExpressResponse) {
    // Con cookies httpOnly, el logout DEBE hacerse desde el servidor.
    // El cliente no puede limpiar cookies httpOnly con document.cookie.
    res.clearCookie(ACCESS_TOKEN_COOKIE,  { ...COOKIE_OPTIONS, path: '/' });
    res.clearCookie(REFRESH_TOKEN_COOKIE, { ...COOKIE_OPTIONS, path: '/api/auth/refresh' });
    return { message: 'Sesión cerrada correctamente' };
  }

  // GET /auth/health — sin rate limit ni JWT, para healthchecks
  @Public()
  @SkipThrottle()
  @Get('health')
  health() {
    return { status: 'ok' };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// TODO: descomentar junto con el servicio de lockout
// const ip = req.ip ?? req.socket.remoteAddress ?? 'unknown';
// return this.authService.login(dto, ip);   // ← reemplaza el NotImplementedException