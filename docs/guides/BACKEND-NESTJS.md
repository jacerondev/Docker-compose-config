# BACKEND-NESTJS.md — Guía de Desarrollo del Backend

> **Referencia técnica viva.** Actualizar al añadir módulos, patrones o decisiones.
>
> Stack: NestJS 11 · TypeScript 5 · TypeORM · PostgreSQL · pnpm

---

## Índice

1. [Estructura de módulos — 15 módulos planificados](#1-estructura-de-módulos--15-módulos-planificados)
2. [Cómo crear un módulo nuevo](#2-cómo-crear-un-módulo-nuevo)
3. [Paths de importación (@alias)](#3-paths-de-importación-alias)
4. [DTOs — validación obligatoria vs opcional](#4-dtos--validación-obligatoria-vs-opcional)
5. [Base de datos con TypeORM](#5-base-de-datos-con-typeorm)
6. [Autenticación JWT](#6-autenticación-jwt)
7. [Rate Limiting por endpoint](#7-rate-limiting-por-endpoint)
8. [Documentación Swagger](#8-documentación-swagger)
9. [Métricas Prometheus](#9-métricas-prometheus)
10. [Filtro de excepciones — Stack traces](#10-filtro-de-excepciones--stack-traces)
11. [Correlation IDs en logs](#11-correlation-ids-en-logs)
12. [Nginx — Rate Limiting a nivel de red](#12-nginx--rate-limiting-a-nivel-de-red)
13. [Tests](#13-tests)
14. [Logging estructurado con nestjs-pino](#14-logging-estructurado-con-nestjs-pino)
15. [Cache con Redis](#15-cache-con-redis)
16. [SAST — análisis estático del código fuente](#16-sast--análisis-estático-del-código-fuente)

---

## 1. Estructura de módulos — 15 módulos planificados

```
backend/src/
│
├── modules/                    ← Módulos de negocio (feature modules)
│   ├── auth/                   ← Autenticación JWT (pendiente)
│   ├── users/                  ← Gestión de usuarios
│   ├── roles/                  ← RBAC — permisos y roles
│   ├── reports/                ← Integración con el servicio Python
│   ├── dashboard/              ← Datos agregados para el frontend
│   ├── notifications/          ← Emails / push notifications
│   ├── audit-log/              ← Historial de acciones del sistema
│   ├── settings/               ← Configuración de la aplicación
│   └── [tus módulos aquí]/
│
├── common/                     ← Código compartido entre TODOS los módulos
│   ├── decorators/
│   │   └── public.decorator.ts ← @Public() para endpoints sin JWT
│   ├── filters/
│   │   └── http-exception.filter.ts
│   ├── guards/
│   ├── interceptors/
│   └── pipes/
│
├── config/
│   └── database.config.ts      ← TypeORM: lee secrets/env, configura pool
│
├── health/
│   ├── health.controller.ts    ← GET /api/health → proceso + PostgreSQL
│   └── health.module.ts
│
├── app.module.ts               ← Módulo raíz — importa todo
└── main.ts                     ← Bootstrap, middleware global
```

**Convención de nombres:**
| Tipo | Formato | Ejemplo |
|---|---|---|
| Archivos | `kebab-case.tipo.ts` | `create-user.dto.ts` |
| Clases | `PascalCase` | `CreateUserDto` |
| Variables | `camelCase` | `usersService` |
| Imports entre módulos | **Siempre path alias** | `@modules/users/...` |

---

## 2. Cómo crear un módulo nuevo

```bash
# Desde la raíz del proyecto
cd backend

# NestJS CLI genera la estructura base
npx nest generate module    modules/users
npx nest generate controller modules/users --no-spec
npx nest generate service    modules/users --no-spec
```

**Registrar en `app.module.ts`:**
```typescript
import { UsersModule } from '@modules/users/users.module';

@Module({
  imports: [
    // ... otros módulos ya configurados ...
    UsersModule,   // ← añadir aquí
  ],
})
```

**Template completo de módulo:**
```typescript
// src/modules/users/users.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { UsersController } from './users.controller';
import { UsersService }    from './users.service';
import { User }            from './entities/user.entity';

@Module({
  imports:     [TypeOrmModule.forFeature([User])],
  controllers: [UsersController],
  providers:   [UsersService],
  exports:     [UsersService],  // exponer si otros módulos lo necesitan
})
export class UsersModule {}
```

---

## 3. Paths de importación (@alias)

Configurados en `tsconfig.json` (compilación) y `package.json` → `jest.moduleNameMapper` (tests).

| Alias | Carpeta | Cuándo usarlo |
|---|---|---|
| `@modules/*` | `src/modules/*` | Imports entre módulos de negocio |
| `@common/*` | `src/common/*` | Guards, filters, decorators compartidos |
| `@config/*` | `src/config/*` | database.config, jwt.config, etc. |
| `@health/*` | `src/health/*` | HealthModule |
| `@shared/*` | `src/shared/*` | Tipos, interfaces, constantes globales |

```typescript
// ❌ Rutas relativas — se rompen al mover archivos
import { UsersService } from '../../../modules/users/users.service';
import { Public }       from '../../common/decorators/public.decorator';

// ✅ Path alias — estables sin importar la ubicación del archivo
import { UsersService } from '@modules/users/users.service';
import { Public }       from '@common/decorators/public.decorator';
import { getDatabaseConfig } from '@config/database.config';
```

**Añadir un path nuevo** (ej: al crear `src/infrastructure/`):

En `tsconfig.json`:
```json
"paths": {
  "@infrastructure/*": ["infrastructure/*"]
}
```

En `package.json` → `jest.moduleNameMapper`:
```json
"^@infrastructure/(.*)$": "<rootDir>/infrastructure/$1"
```

**NestJS CLI resuelve los paths automáticamente** con `nest start --watch` sin configuración extra. `tsconfig-paths` ya está en devDependencies para `ts-node` y el modo debug.

---

## 4. DTOs — validación obligatoria vs opcional

### ¿Forzar decoradores o dejarlos opcionales?

**Decisión del proyecto: obligatorios por convención de equipo, no por código.**

El `ValidationPipe` global en `main.ts` valida automáticamente cualquier `@Body()` que tenga decoradores de `class-validator`. Si el DTO no tiene decoradores, el pipe deja pasar los datos sin validar. No hay forma de forzarlo a nivel de TypeScript en compilación, pero sí hay estrategias prácticas:

**Estrategia recomendada — regla de code review:**
> "Todo `@Body()` debe usar un DTO con al menos un decorador de `class-validator`."

**Cómo se ve en práctica:**

```typescript
// ❌ NUNCA hacer — @Body() sin DTO tipado
@Post('login')
async login(@Body() body: any) { ... }        // no hay validación

// ❌ EVITAR — DTO sin decoradores
export class LoginDto { email: string; password: string; }
@Post('login')
async login(@Body() dto: LoginDto) { ... }    // DTO existe pero no valida nada

// ✅ CORRECTO — DTO con decoradores
export class LoginDto {
  @IsEmail()          email: string;
  @MinLength(8)       password: string;
}
@Post('login')
async login(@Body() dto: LoginDto) { ... }    // ValidationPipe valida automáticamente
```

### Campos opcionales vs obligatorios en DTOs

```typescript
import {
  IsEmail, IsString, IsOptional, IsEnum,
  MinLength, MaxLength, IsInt, Min, Max
} from 'class-validator';
import { Type } from 'class-transformer';

// ── Obligatorios: sin @IsOptional() ──────────────────────────────────────────
export class CreateUserDto {
  @IsEmail({}, { message: 'Formato de email inválido' })
  email: string;                    // ← obligatorio: 400 si falta o es inválido

  @IsString()
  @MinLength(8,  { message: 'Mínimo 8 caracteres' })
  @MaxLength(64, { message: 'Máximo 64 caracteres' })
  password: string;                 // ← obligatorio

  @IsString()
  @MinLength(2)
  name: string;                     // ← obligatorio
}

// ── Opcionales: con @IsOptional() ────────────────────────────────────────────
export class UpdateUserDto {
  @IsEmail()
  @IsOptional()
  email?: string;                   // ← si se envía, debe ser email válido
                                    //   si NO se envía, se ignora silenciosamente

  @IsString()
  @MinLength(2)
  @IsOptional()
  name?: string;

  @IsEnum(['admin', 'user', 'viewer'])
  @IsOptional()
  role?: string;
}

// ── Query params con transformación automática ────────────────────────────────
export class PaginationDto {
  @IsInt()
  @Min(1)
  @IsOptional()
  @Type(() => Number)               // convierte el string "10" → número 10
  page?: number = 1;                // valor por defecto si no se envía

  @IsInt()
  @Min(1)
  @Max(100)
  @IsOptional()
  @Type(() => Number)
  limit?: number = 20;
}
```

**¿Cuándo usar `@IsOptional()`?**
- Campos que tienen valor por defecto (`page`, `limit`, `status`)
- Campos de actualización parcial (PATCH requests)
- Filtros de búsqueda que el usuario puede omitir

**¿Cuándo NO usar `@IsOptional()`?**
- Credenciales (`email`, `password`)
- IDs de recursos requeridos para la operación
- Campos sin los cuales la operación no tiene sentido

---

## 5. Base de datos con TypeORM

### Configuración (ya implementada en `src/config/database.config.ts`)

Lee credenciales usando esta prioridad:
1. Docker Secret (archivo en `/run/secrets/`) — producción
2. Variable de entorno directa (`.env`) — desarrollo

`app.module.ts` ya está configurado con `TypeOrmModule.forRootAsync({ useFactory: getDatabaseConfig })`.

### Definir una entidad

```typescript
// src/modules/users/entities/user.entity.ts
import {
  Entity, PrimaryGeneratedColumn, Column,
  CreateDateColumn, UpdateDateColumn, Index
} from 'typeorm';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Index({ unique: true })
  @Column()
  email: string;

  @Column()
  name: string;

  @Column({ select: false })   // ← NUNCA devuelve el hash en queries normales
  password: string;

  @Column({ default: 'user' })
  role: string;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

### Service con repositorio

```typescript
// src/modules/users/users.service.ts
import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './entities/user.entity';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private readonly repo: Repository<User>,
  ) {}

  findAll(): Promise<User[]> {
    return this.repo.find({ where: { isActive: true } });
  }

  async findById(id: number): Promise<User> {
    const user = await this.repo.findOne({ where: { id } });
    if (!user) throw new NotFoundException(`Usuario #${id} no encontrado`);
    return user;
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.repo.findOne({ where: { email } });
  }

  async create(dto: CreateUserDto): Promise<User> {
    const exists = await this.findByEmail(dto.email);
    if (exists) throw new ConflictException('El email ya está registrado');
    const user = this.repo.create(dto);
    return this.repo.save(user);
  }

  async update(id: number, dto: UpdateUserDto): Promise<User> {
    const user = await this.findById(id);
    Object.assign(user, dto);
    return this.repo.save(user);
  }

  async remove(id: number): Promise<void> {
    const user = await this.findById(id);
    user.isActive = false;           // soft delete — no borrar físicamente
    await this.repo.save(user);
  }
}
```

### Healthcheck con DB (ya activo en `health.controller.ts`)

`TypeOrmHealthIndicator.pingCheck('database')` ejecuta un `SELECT 1` y marca el contenedor como `unhealthy` si PostgreSQL no responde. Esto activa alertas en Prometheus/Grafana automáticamente.

---

## 6. Autenticación JWT

> **Estado:** Pendiente de implementar — `auth.controller.ts` es un esqueleto.

**Instalar cuando sea el momento:**
```bash
pnpm add @nestjs/jwt @nestjs/passport passport passport-jwt argon2
pnpm add -D @types/passport-jwt
```

**Patrón recomendado — proteger todo por defecto con `@Public()` para excepciones:**

```typescript
// src/common/decorators/public.decorator.ts
import { SetMetadata } from '@nestjs/common';
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);
```

```typescript
// src/modules/auth/guards/jwt-auth.guard.ts
import { Injectable, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { IS_PUBLIC_KEY } from '@common/decorators/public.decorator';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private reflector: Reflector) { super(); }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

```typescript
// Uso en controllers:
@Public()                    // login y register son públicos
@Post('login')
async login(@Body() dto: LoginDto) { ... }

@Get('profile')              // sin @Public() → requiere JWT automáticamente
getProfile(@Request() req) {
  return req.user;           // { userId, email } del payload del JWT
}
```

**Variables de entorno a añadir en `.env.example`:**
```bash
JWT_SECRET=genera_con_openssl_rand_base64_48
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d
```

### Hashing de contraseñas — password.service.ts

El proyecto usa **Argon2id** (ganador de Password Hashing Competition) con un pepper.
```typescript
// src/auth/password.service.ts — ya implementado
import { hashPassword, verifyPassword } from './password.service';

// En AuthService.register():
const hash = await hashPassword(dto.password);
// → almacenar hash en BD (nunca dto.password)

// En AuthService.login():
const valid = await verifyPassword(user.passwordHash, dto.password);
```

**Parámetros Argon2id configurados:**
- `memoryCost: 65536` (64 MB) — ajustar si el VPS tiene < 512 MB RAM
- `timeCost: 3` — iteraciones
- `parallelism: 4` — threads

**El pepper** (`PEPPER_SECRET`) se combina con la contraseña antes del hash.
En producción viene de Docker Secret. ⚠️ Ver advertencia de rotación en `DATA-DICTIONARY.md`.

---

## 7. Rate Limiting por endpoint

El `ThrottlerGuard` global aplica `short` (10 req/seg) y `medium` (100 req/min) a todos los endpoints. Se puede ajustar por endpoint:

```typescript
import { Throttle, SkipThrottle } from '@nestjs/throttler';

// Login: estricto — 5 intentos/min por IP
@Throttle({ short: { limit: 5, ttl: 60000 } })
@Post('login')
async login(@Body() dto: LoginDto) { ... }

// Registro: muy estricto — 3 registros/hora
@Throttle({ medium: { limit: 3, ttl: 3_600_000 } })
@Post('register')
async register(@Body() dto: CreateUserDto) { ... }

// Monitoreo y healthcheck: sin límite
@SkipThrottle()
@Get('health')
health() { return { status: 'ok' }; }
```

**Respuesta al superar el límite:**
```json
HTTP 429 Too Many Requests
{ "statusCode": 429, "message": "ThrottlerException: Too Many Requests" }
```

---

## 8. Documentación Swagger

Habilitado solo en desarrollo. Acceder en: `http://localhost:4000/api/docs`

```typescript
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth, ApiBody } from '@nestjs/swagger';

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {

  @ApiOperation({ summary: 'Listar todos los usuarios' })
  @ApiResponse({ status: 200, description: 'Array de usuarios', type: [User] })
  @Get()
  findAll() { ... }

  @ApiOperation({ summary: 'Crear usuario' })
  @ApiBody({ type: CreateUserDto })
  @ApiResponse({ status: 201, description: 'Usuario creado' })
  @ApiResponse({ status: 409, description: 'Email ya registrado' })
  @Post()
  create(@Body() dto: CreateUserDto) { ... }
}
```

---

## 9. Métricas Prometheus

`PrometheusModule` ya está configurado. Expone `GET /metrics` automáticamente.

**Métricas personalizadas por módulo:**
```typescript
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Counter } from 'prom-client';
import { makeCounterProvider } from '@willsoto/nestjs-prometheus';

// En el módulo — registrar el contador:
@Module({
  providers: [
    makeCounterProvider({ name: 'users_created_total', help: 'Total de usuarios creados' }),
    UsersService,
  ],
})

// En el service — usar el contador:
@Injectable()
export class UsersService {
  constructor(
    @InjectMetric('users_created_total') private readonly counter: Counter<string>,
  ) {}

  async create(dto: CreateUserDto): Promise<User> {
    const user = await this.repo.save(dto);
    this.counter.inc();               // ← incrementa al crear usuario
    return user;
  }
}
```

---

## 10. Filtro de excepciones — Stack traces

`GlobalExceptionFilter` ya está registrado en `main.ts`. Comportamiento automático:
- **Desarrollo:** incluye `stack` en la respuesta para debugging
- **Producción:** respuesta genérica + log interno con el stack completo

**Lanzar errores HTTP desde services:**
```typescript
import {
  NotFoundException, BadRequestException,
  UnauthorizedException, ForbiddenException, ConflictException
} from '@nestjs/common';

throw new NotFoundException('Usuario no encontrado');       // 404
throw new BadRequestException('Email inválido');            // 400
throw new UnauthorizedException('Token expirado');          // 401
throw new ForbiddenException('Sin permisos');               // 403
throw new ConflictException('El email ya existe');          // 409
```

---

## 11. Correlation IDs en logs

> **Estado:** No urgente — implementar cuando haya usuarios reales en producción.

Permite rastrear un request a través de backend + reports usando el mismo ID en ambos logs.

**Implementación futura:**
```bash
pnpm add nestjs-cls
```
```typescript
// En app.module.ts imports:
ClsModule.forRoot({
  middleware: { mount: true, generateId: true, idGenerator: () => crypto.randomUUID() },
}),
```

---

## 12. Nginx — Rate Limiting a nivel de red

> **Referencia:** Código para cuando se configure el servidor. Ver también `README.prod.md`.

Nginx bloquea ataques masivos **antes** de que lleguen a NestJS.  
Archivo en el host: `/etc/nginx/sites-available/nombre_del_proyecto`

```nginx
http {
  limit_req_zone $binary_remote_addr zone=login:10m    rate=5r/m;
  limit_req_zone $binary_remote_addr zone=register:10m rate=3r/m;
  limit_req_zone $binary_remote_addr zone=api:10m      rate=60r/m;

  server {
    location /api/auth/login    { limit_req zone=login    burst=3  nodelay; proxy_pass http://127.0.0.1:4000; }
    location /api/auth/register { limit_req zone=register burst=1  nodelay; proxy_pass http://127.0.0.1:4000; }
    location /api/                 { limit_req zone=api      burst=20 nodelay; proxy_pass http://127.0.0.1:4000; }
  }
}
```

---

## 13. Tests

```bash
cd backend
pnpm test           # todos los tests
pnpm test:cov       # reporte de cobertura → backend/coverage/index.html
pnpm test:watch     # modo watch durante desarrollo
```

**Template de test para controller con mocks:**
```typescript
// src/modules/users/users.controller.spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { UsersController } from './users.controller';
import { UsersService }    from './users.service';

describe('UsersController', () => {
  let controller: UsersController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [UsersController],
      providers: [
        {
          provide: UsersService,
          useValue: {
            findAll: jest.fn().mockResolvedValue([]),
            findById: jest.fn().mockResolvedValue({ id: 1, email: 'test@test.com' }),
            create:   jest.fn(),
          },
        },
      ],
    }).compile();

    controller = module.get<UsersController>(UsersController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });

  it('findAll returns array', async () => {
    expect(await controller.findAll()).toEqual([]);
  });
});
```

---

## 14. Logging estructurado con nestjs-pino

> **Estado:** No instalado — añadir antes del primer deploy en producción con usuarios reales.

### El problema con el logger por defecto de NestJS

El logger integrado escribe texto plano:
```
[Nest] LOG  [NestApplication] Application running on port 4000
[Nest] LOG  [POST /api/auth/login] 200 - 45ms
[Nest] ERROR [AuthService] Invalid credentials for user abc@test.com
```

Con 10,000 líneas al día, buscar todos los errores de un usuario concreto requiere `grep` manual. Es imposible filtrar, agregar ni visualizar en tiempo real. No hay estructura que una herramienta pueda parsear.

### La solución: JSON estructurado con nestjs-pino

`nestjs-pino` escribe cada log como un objeto JSON:
```json
{"level":"info","time":1710062400,"req":{"method":"POST","url":"/api/auth/login","id":"abc-123","ip":"192.168.1.1"},"res":{"statusCode":200},"responseTime":45,"msg":"request completed"}
{"level":"error","time":1710062500,"req":{"id":"xyz-789"},"err":{"message":"Invalid credentials"},"userId":"u_42","msg":"Authentication failed"}
```

Con JSON, Grafana Loki puede hacer queries como:
```
{service="backend"} | json | level="error" | responseTime > 1000
```
*"Dame todos los errores del backend que tardaron más de 1 segundo"* — en tiempo real, en un gráfico.

### Cuándo añadirlo

| Situación | Recomendación |
|---|---|
| Desarrollo solo, sin plataforma de logs | ❌ No vale la pena — el JSON es ilegible en consola sin pretty-print |
| Desarrollo en equipo | ✅ Añadir con `pino-pretty` — logs legibles y estructurados |
| Producción sin Grafana Loki | ✅ JSON puro — facilita `grep` y futuros pipelines |
| Producción con Grafana Loki | ✅ Necesario — sin JSON no puedes hacer queries en Loki |

### Instalación

```bash
pnpm add nestjs-pino pino-http
pnpm add -D pino-pretty
```

### Configuración en `app.module.ts`

```typescript
import { LoggerModule } from 'nestjs-pino';

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        // Desarrollo: formato legible con colores en consola
        // Producción: JSON puro (Loki y cualquier agregador lo parsea)
        transport: process.env.NODE_ENV !== 'production'
          ? { target: 'pino-pretty', options: { colorize: true, singleLine: false } }
          : undefined,

        level: process.env.NODE_ENV !== 'production' ? 'debug' : 'info',

        // Loguea automáticamente cada request + response con tiempos
        autoLogging: true,

        // CRÍTICO: nunca loguear credenciales ni tokens
        redact: [
          'req.headers.authorization',
          'req.body.password',
          'req.body.currentPassword',
          'req.body.newPassword',
        ],
      },
    }),
    // ... resto de imports
  ],
})
export class AppModule {}
```

### Activar en `main.ts`

```typescript
import { Logger } from 'nestjs-pino';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

  // Reemplaza el logger por defecto de NestJS con pino
  app.useLogger(app.get(Logger));

  // ... resto del bootstrap
}
```

### Usar en services y controllers

```typescript
import { Injectable, Logger } from '@nestjs/common';

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  async create(dto: CreateUserDto): Promise<User> {
    // ✅ Objeto estructurado como primer argumento — pino lo incluye en el JSON
    this.logger.log({ email: dto.email, action: 'user_create' }, 'Creating user');

    const user = await this.repo.save(dto);

    this.logger.log({ userId: user.id, action: 'user_created' }, 'User created successfully');
    return user;
  }

  async findById(id: number): Promise<User> {
    const user = await this.repo.findOne({ where: { id } });
    if (!user) {
      // ❌ No loguear datos sensibles — solo el ID
      this.logger.warn({ userId: id, action: 'user_not_found' }, 'User not found');
      throw new NotFoundException(`Usuario #${id} no encontrado`);
    }
    return user;
  }
}
```

### Relación con Correlation IDs (sección 11)

`nestjs-pino` + `nestjs-cls` se complementan: `nestjs-cls` genera un UUID por request y `nestjs-pino` lo incluye automáticamente en cada log de ese request. Así todos los logs de una misma petición tienen el mismo `requestId`, aunque pasen por 3 services distintos.

```typescript
// Con ambos instalados, cada log tiene automáticamente:
{"level":"info","requestId":"abc-123","userId":"u_42","service":"UsersService","msg":"User found"}
{"level":"info","requestId":"abc-123","service":"ReportsService","msg":"Generating report"}
// → Puedes filtrar por requestId y ver el flujo completo de un request
```

---

## 15. Cache con Redis

> **Estado:** No instalado — añadir cuando aparezcan queries lentas repetidas (>200ms) en producción.

### Cuándo tiene sentido Redis para cache

Redis añade un contenedor extra, 50-100MB de RAM y un punto más de fallo. Solo merece la pena cuando resuelve un problema real y medible. Los tres casos de uso son distintos:

| Caso de uso | Problema que resuelve | Cuándo activarlo |
|---|---|---|
| **Cache de queries** | `GET /products` golpea PostgreSQL 500 veces/min con la misma query | Cuando veas queries >200ms repetidas en producción |
| **Sesiones stateful** | Necesitas invalidar un JWT antes de que expire | Solo si decides NO usar JWT stateless |
| **Cola de tareas** | Reportes pesados hacen timeout (ver `REPORTS-PYTHON.md` §12) | Cuando reportes tarden >10-15s en promedio |

Con el patrón JWT stateless documentado en la sección 6, **no necesitas Redis para sesiones**. El token expira solo por TTL.

### Instalación (para cache de queries)

```bash
pnpm add @nestjs/cache-manager cache-manager cache-manager-redis-yet ioredis
```

Añadir el contenedor Redis en `docker-compose.yml`:
```yaml
  redis:
    image: redis:7-alpine
    container_name: nombre_del_proyecto_redis
    restart: unless-stopped
    command: redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - app
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  redis_data:
```

Añadir a `.env.example`:
```bash
REDIS_HOST=redis
REDIS_PORT=6379
```

### Configuración en `app.module.ts`

```typescript
import { CacheModule } from '@nestjs/cache-manager';
import { redisStore } from 'cache-manager-redis-yet';

@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true,   // disponible en toda la app sin reimportar
      useFactory: async () => ({
        store: redisStore,
        host: process.env.REDIS_HOST ?? 'redis',
        port: parseInt(process.env.REDIS_PORT ?? '6379', 10),
        ttl: 60_000,    // 60 segundos por defecto — sobreescribir por caso de uso
      }),
    }),
    // ... resto de imports
  ],
})
export class AppModule {}
```

### Uso en un service — cachear una query costosa

```typescript
import { Inject, Injectable } from '@nestjs/common';
import { Cache } from 'cache-manager';
import { CACHE_MANAGER } from '@nestjs/cache-manager';

@Injectable()
export class ProductsService {
  constructor(
    @InjectRepository(Product) private readonly repo: Repository<Product>,
    @Inject(CACHE_MANAGER) private readonly cache: Cache,
  ) {}

  async findAll(): Promise<Product[]> {
    const KEY = 'products:all';

    // 1. Intentar leer del cache
    const cached = await this.cache.get<Product[]>(KEY);
    if (cached) {
      return cached;       // respuesta en <1ms en vez de 200ms de PostgreSQL
    }

    // 2. Cache miss → consultar PostgreSQL
    const products = await this.repo.find({ where: { isActive: true } });

    // 3. Guardar en cache 60 segundos
    await this.cache.set(KEY, products, 60_000);
    return products;
  }

  async create(dto: CreateProductDto): Promise<Product> {
    const product = await this.repo.save(dto);

    // IMPORTANTE: invalidar el cache al crear/modificar datos
    await this.cache.del('products:all');
    return product;
  }
}
```

### Decorador `@CacheKey` para rutas simples (alternativa al manual)

```typescript
import { CacheKey, CacheTTL } from '@nestjs/cache-manager';
import { UseInterceptors, CacheInterceptor } from '@nestjs/cache-manager';

@Controller('products')
@UseInterceptors(CacheInterceptor)   // cachea automáticamente los GET
export class ProductsController {

  @Get()
  @CacheKey('products:all')
  @CacheTTL(60_000)                  // 60 segundos
  findAll(): Promise<Product[]> {
    return this.productsService.findAll();
    // ← No necesitas leer/escribir el cache manualmente
    // ← Pero tampoco puedes controlar la invalidación fácilmente
  }
}
```

> **Recomendación:** usa el patrón manual para endpoints donde necesitas invalidar el cache al mutar datos. Usa el decorador solo para endpoints de solo lectura donde los datos cambian poco (catálogos, configuraciones).

### Estrategia de keys de cache

```typescript
// Convención: "entidad:criterio" para poder invalidar por prefijo
await this.cache.set('products:all', data);            // lista completa
await this.cache.set(`products:id:${id}`, data);       // por ID
await this.cache.set(`products:category:${cat}`, data);// por categoría

// Al modificar un producto, invalidar todas las keys afectadas:
await Promise.all([
  this.cache.del('products:all'),
  this.cache.del(`products:id:${id}`),
  this.cache.del(`products:category:${product.category}`),
]);
```

---

## 16. SAST — análisis estático del código fuente

> **Estado:** No configurado — añadir al primer PR con código de negocio real.

### Qué es SAST y en qué se diferencia de Trivy

**Trivy** (ya en `security.yml`) busca CVEs en dependencias instaladas. Detecta que `lodash@4.17.15` tiene la vulnerabilidad `CVE-2021-23337`.

**SAST** analiza el código fuente que tú escribes. Detecta patrones peligrosos como:
- `const SECRET = "abc123"` — credencial hardcodeada en código
- `` query = `SELECT * FROM users WHERE id = ${userId}` `` — SQL injection
- `eval(userInput)` — ejecución arbitraria de código
- `Math.random()` para generar tokens — no criptográfico

Son capas complementarias: Trivy defiende contra vulnerabilidades de terceros, SAST defiende contra errores del propio equipo.

### Herramientas recomendadas para este stack

| Herramienta | Lenguaje | Velocidad | Lo que detecta |
|---|---|---|---|
| **Semgrep** | TypeScript / cualquiera | ~30s | Secrets, OWASP Top 10, patrones NestJS |
| **Bandit** | Python | ~10s | Vulnerabilidades Python/Flask clásicas |

**Semgrep** tiene reglas mantenidas por la comunidad para NestJS, Express, y secretos genéricos. Es la opción correcta para el backend TypeScript.

**Bandit** es el estándar de facto para Python. Detecta inyecciones SQL, uso de `exec()`, `pickle`, `yaml.load()` sin `Loader`, etc.

### Añadir a `.github/workflows/security.yml`

```yaml
  semgrep:
    name: SAST — Semgrep (TypeScript + Python)
    runs-on: ubuntu-latest
    container:
      image: semgrep/semgrep:latest
    steps:
      - uses: actions/checkout@v4

      # Escaneo del backend TypeScript
      - name: Semgrep — backend
        run: |
          semgrep scan \
            --config p/typescript \
            --config p/nodejs \
            --config p/secrets \
            --config p/owasp-top-ten \
            --json-output /tmp/semgrep-backend.json \
            backend/src/ \
            --error || true
        # --error: falla el job si encuentra findings de severidad ERROR
        # || true: permite que el siguiente paso suba los resultados aunque falle

      # Escaneo del servicio Python
      - name: Semgrep — reports
        run: |
          semgrep scan \
            --config p/python \
            --config p/flask \
            --config p/secrets \
            --json-output /tmp/semgrep-reports.json \
            reports/ \
            --error || true

      - name: Upload SAST results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: semgrep-${{ github.sha }}
          path: /tmp/semgrep-*.json
          retention-days: 30

  bandit:
    name: SAST — Bandit (Python)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install bandit

      - name: Bandit scan
        run: |
          bandit \
            -r reports/src/ \
            -ll \
            -f json \
            -o bandit-results.json || true
          # -ll: reporta solo severidad MEDIUM y HIGH (ignora LOW)

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: bandit-${{ github.sha }}
          path: bandit-results.json
          retention-days: 30
```

### Reglas que activa cada config de Semgrep

| Config | Detecta |
|---|---|
| `p/typescript` | Patrones TypeScript peligrosos (prototype pollution, etc.) |
| `p/nodejs` | `eval()`, `child_process.exec()` con input del usuario, path traversal |
| `p/secrets` | API keys, tokens, passwords hardcodeados en el código |
| `p/owasp-top-ten` | XSS, SQL injection, SSRF, insecure deserialization |
| `p/flask` | Rutas sin autenticación, debug mode en producción, `render_template_string` |

### Qué hacer con los findings

Cuando Semgrep reporta un finding:
1. **Secrets hardcodeados** → rotar la credencial inmediatamente aunque sea de desarrollo
2. **SQL injection** → usar parámetros preparados (`$1`, `$2`) en vez de interpolación de strings
3. **Falso positivo confirmado** → añadir `# nosemgrep: rule-id` en la línea con un comentario explicando por qué es seguro en este contexto
