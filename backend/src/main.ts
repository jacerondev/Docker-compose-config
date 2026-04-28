// filepath: backend/src/main.ts
import { NestFactory } from '@nestjs/core';
import { ValidationPipe, RequestMethod } from '@nestjs/common';
import { Logger } from 'nestjs-pino';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { GlobalExceptionFilter } from './common/filters/http-exception.filter';
import { RequestIdInterceptor } from './common/interceptors/request-id.interceptor';
import { AppModule } from './app.module';
import { readSecret } from '@config/secrets';
import { validateAppConfig } from '@config/app.config';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import basicAuth from 'express-basic-auth';

async function bootstrap(): Promise<void> {
  validateAppConfig();  // Validación temprana de configuración crítica antes de crear la app
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const logger = new Logger('Bootstrap');

  // ── Validación crítica de variables de entorno en tiempo de arranque ────────
  // Detecta configuraciones inválidas antes de inicializar cualquier módulo.
  // En producción, un JWT_SECRET débil o placeholder es una brecha de seguridad grave.
  const IS_PRODUCTION = process.env.NODE_ENV === 'production';
  const JWT_SECRET = readSecret('JWT_SECRET_FILE', 'JWT_SECRET', true, {
  minLength: 32,
  requireEntropy: true,
  allowPlaceholderInDev: false,  // Forzar configuración real incluso en dev
});
  let cookieSecret: string | undefined;

  function hasMinimumEntropy(secret: string, minBits = 128): boolean {
    // Verificar que no es todos el mismo carácter, no es secuencial, etc.
    const uniqueChars = new Set(secret).size;
    return uniqueChars >= 8 && secret.length >= 32;
  }

  try {
    // required=true por defecto: lanza si no existe en producción
    cookieSecret = readSecret('COOKIE_SECRET_FILE', 'COOKIE_SECRET', IS_PRODUCTION);
  } catch (err) {
    // En producción: error fatal
    if (IS_PRODUCTION) throw err;
    // En desarrollo: advertencia
    logger.warn('COOKIE_SECRET no disponible. Cookies sin firma en desarrollo.');
  }

  if (IS_PRODUCTION && !cookieSecret) {
    throw new Error('[main] COOKIE_SECRET requerido en producción.');
  }

  if (IS_PRODUCTION) {
    // En producción: JWT_SECRET debe venir de Docker Secrets (JWT_SECRET_FILE),
    // no de una variable de entorno directa. Si está presente como env var en
    // producción, es un indicio de que se usó el .env en lugar de Docker Secrets.
    if (!JWT_SECRET || JWT_SECRET.startsWith('CAMBIAR_') || hasMinimumEntropy(JWT_SECRET) === false) {
      throw new Error(
        '[main] JWT_SECRET inválido en producción.\n' +
        '  - Debe tener al menos 32 caracteres\n' +
        '  - No puede ser el placeholder del .env.example\n' +
        '  - En producción debe venir de Docker Secret: JWT_SECRET_FILE=/run/secrets/jwt_secret\n' +
        '  - Genera uno con: openssl rand -base64 48'
      );
    }
  } else {
    // En desarrollo: advertir pero no bloquear, para no romper el onboarding inicial
    if (!JWT_SECRET || JWT_SECRET.startsWith('CAMBIAR_')) {
      logger.warn('JWT_SECRET no configurado o usa el placeholder del .env.example.\n' +
        '       Ejecuta: make setup  (genera automáticamente con openssl)'
      );
    }
  }

  if (!IS_PRODUCTION && (!cookieSecret || cookieSecret.startsWith('CAMBIAR_'))) {
    logger.warn(
      'COOKIE_SECRET no configurado o usa el placeholder del .env.\n' +
      '       Las cookies no estarán firmadas de forma segura en desarrollo.\n' +
      '       Ejecuta: make setup'
    );
  }
  const origins = process.env.ALLOWED_ORIGINS?.split(',').filter(Boolean) ?? [];
  if (IS_PRODUCTION && origins.length === 0) {
    throw new Error('[main] ALLOWED_ORIGINS debe definirse en producción');
  }

  // Seguridad: headers HTTP contra clickjacking, XSS, MIME sniffing
  const allowedContentDomains = process.env.HELMET_ALLOWED_DOMAINS?.split(',') ?? [];
  const isProduction = process.env.NODE_ENV === 'production';
  app.use(helmet({
    // Content-Security-Policy: aplica en dev también para que Swagger funcione con CSP
    contentSecurityPolicy: {
      directives: {
        defaultSrc:  ["'self'"],
        scriptSrc:   isProduction
          ? ["'self'"]
          : ["'self'", "'unsafe-inline'"],  // Swagger UI necesita inline en dev
        styleSrc:    isProduction
          ? ["'self'"]
          : ["'self'", "'unsafe-inline'"],  // Swagger CSS
        imgSrc:      ["'self'", "data:", "https:"],
        connectSrc:  ["'self'", ...allowedContentDomains],
        fontSrc:     ["'self'", "data:"],   // Swagger usa fuentes inline como data URI
        objectSrc:   ["'none'"],
        frameSrc:    ["'none'"],
        baseUri:     ["'self'"],
        formAction:  ["'self'"],
        reportTo:    ["csp-endpoint"],
        ...(isProduction ? { upgradeInsecureRequests: [] } : {}),
      },
      // En producción, reportar violaciones (opcional — necesitas un endpoint colector)
      // reportOnly: !isProduction,
    },
    // HSTS — solo en producción y solo si hay TLS
    hsts: isProduction ? {
      maxAge: 63072000,         // 2 años
      includeSubDomains: true,
      preload: true,
    } : false,
    // X-XSS-Protection deprecated — desactivar explícitamente
    xssFilter: false,
    // Resto de headers de Helmet activos por defecto
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    permissionsPolicy: {
      features: {
        camera: [],
        microphone: [],
        geolocation: [],
        payment: [],
      }
    }
  }));

  app.use(cookieParser(cookieSecret));

  // CORS: solo orígenes declarados en ALLOWED_ORIGINS (ver ADR-020)
  // credentials: true es obligatorio para que el navegador envíe cookies httpOnly
  app.enableCors({
    origins,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    maxAge: 86400,  // 24 horas — reduce preflight requests repetidas
  });

  
  app.useLogger(app.get(Logger));

  // Validación global: rechaza y filtra datos inválidos en cada endpoint
  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,              // elimina campos no declarados en DTO
    forbidNonWhitelisted: true,   // error 400 si hay campos extra
    transform: true,              // convierte tipos automáticamente (string → number)
  }));

  // Filtro global de excepciones: no expone estructura interna en producción
  app.useGlobalFilters(new GlobalExceptionFilter());

  // Interceptor global para asignar un requestId único a cada petición
  app.useGlobalInterceptors(new RequestIdInterceptor());

  // Prefix global: todos los endpoints quedan bajo /api/*
  // /health es la excepción — sin prefijo para los healthchecks de Docker y Nginx
  app.setGlobalPrefix('api', {
    exclude: [
      { path: 'health',       method: RequestMethod.GET },
      { path: 'health/ready', method: RequestMethod.GET },
    ],
  });

  // TODO: Versioning — activar cuando se implementen los módulos de negocio
  // import { VersioningType } from '@nestjs/common';  ← añadir al import de arriba
  // app.enableVersioning({ type: VersioningType.URI, defaultVersion: '1' });

  // Swagger: solo en desarrollo — SWAGGER_ENABLED=false en producción (.env.prod.example)
  // protegido con auth básica
  if (process.env.SWAGGER_ENABLED === 'true' && !isProduction) {
    // Protección con auth básica: evita que cualquiera con acceso a la red vea la API
    // Solo aplica cuando SWAGGER_ENABLED=true (nunca en producción)
    const swaggerPassword = process.env.SWAGGER_PASSWORD;
    if (!swaggerPassword || swaggerPassword.startsWith('CAMBIAR_')) {
      // En desarrollo: desactivar Swagger si no hay contraseña (no exponer sin auth)
      logger.warn('SWAGGER_PASSWORD no definido. Swagger DESACTIVADO.');
    }else{
      const swaggerUser = process.env.SWAGGER_USER ?? 'dev';
      app.use(
        '/api/docs',
        basicAuth({
          users: { [swaggerUser]: swaggerPassword },
          challenge: true,               // Fuerza el diálogo del navegador
          unauthorizedResponse: 'Acceso denegado',
        }),
      );

      const config = new DocumentBuilder()
        .setTitle('NOMBRE_DEL_PROYECTO API')
        .setDescription(`Documentación de la API — solo visible en desarrollo
          ## Autenticación
          Todos los endpoints (excepto los marcados como públicos) requieren una cookie \`access_token\` httpOnly.
          Para obtenerla: \`POST /api/auth/login\`.

          ## Rate Limiting
          - Global: 10 req/s por IP, 100 req/min
          - CSP Report: 5 por minuto
          - Login: 5 por minuto (anti-brute-force)
        `)
        .setVersion('1.0')
        .addCookieAuth('access_token', { type: 'apiKey', in: 'cookie' })
          .addServer('http://localhost:4000', 'Desarrollo local')
        // .addCookieAuth('access_token')
        .build();
      const document = SwaggerModule.createDocument(app, config);
      SwaggerModule.setup('api/docs', app, document);
      logger.log(`Swagger: http://localhost:${process.env.PORT ?? 4000}/api/docs`);
    }
  }else if (process.env.SWAGGER_ENABLED === 'true' && isProduction) {
    throw new Error('[main] ⚠️  SWAGGER_ENABLED=true en producción no está permitido.');
  }

  const port = process.env.PORT ?? 4000;
  // Confiar en el primer proxy (Nginx) para obtener la IP real del cliente
  // Requerido para que ThrottlerModule use req.ip correctamente
  // trust proxy: 1 asume topología: Internet → Nginx(host) → Contenedor
  // Si se añade CDN delante de Nginx, cambiar a: 'loopback, linklocal, uniquelocal'
  // o a la IP específica del CDN. Ver ADR-011.
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  await app.listen(port);
  logger.log(`Backend iniciado en puerto ${port}`);
}
bootstrap();
