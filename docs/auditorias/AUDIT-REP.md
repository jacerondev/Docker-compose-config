# Auditoría Profesional de Seguridad y Arquitectura

**Proyecto:** Enterprise Template (Docker Compose · NestJS · Next.js · Python Reports)
**Fecha:** Marzo 2026
**Versión:** 1.0.0
**Clasificación:** CONFIDENCIAL — Uso interno
**Metodología:** STRIDE · OWASP ASVS · NIST CSF · ISO 27001/27002 · CIS Benchmarks · Zero Trust
**Nivel de exigencia:** Big Tech / Banca / Sistemas críticos

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Modelo de Amenazas — STRIDE](#2-modelo-de-amenazas--stride)
3. [Arquitectura de Seguridad — Zero Trust](#3-arquitectura-de-seguridad--zero-trust)
4. [Matriz de Riesgos](#4-matriz-de-riesgos)
5. [Análisis Técnico Profundo](#5-análisis-técnico-profundo)
   - 5.1 [Backend NestJS](#51-backend-nestjs)
   - 5.2 [Frontend Next.js](#52-frontend-nextjs)
   - 5.3 [Servicio de Reports Python](#53-servicio-de-reports-python)
   - 5.4 [Base de Datos PostgreSQL](#54-base-de-datos-postgresql)
   - 5.5 [Redis](#55-redis)
   - 5.6 [Nginx (Proxy Inverso)](#56-nginx-proxy-inverso)
   - 5.7 [Docker y Contenedores](#57-docker-y-contenedores)
   - 5.8 [CI/CD y GitHub Actions](#58-cicd-y-github-actions)
   - 5.9 [Gestión de Secretos](#59-gestión-de-secretos)
   - 5.10 [Código Comentado y Plantillas](#510-código-comentado-y-plantillas)
6. [Políticas de Seguridad](#6-políticas-de-seguridad)
7. [Recomendaciones de Implementación](#7-recomendaciones-de-implementación)
8. [Plan de Implementación por Fases](#8-plan-de-implementación-por-fases)

---

## 1. Resumen Ejecutivo

### Estado General

El proyecto demuestra un nivel de madurez de seguridad **superior a la media** para una plantilla empresarial en desarrollo activo. Se observan decisiones arquitectónicas sólidas: multi-stage Docker builds con imágenes fijadas por hash, gestión de secretos mediante Docker Secrets en producción, CSP con nonces por request, argon2id para hashing de contraseñas con pepper, y un sistema de guardas por capas (JWT → RBAC → métricas).

Sin embargo, existen **riesgos críticos** que deben resolverse antes de cualquier despliegue productivo:

| Criticidad | Hallazgos | Estado |
|-----------|-----------|--------|
| 🔴 CRÍTICO | 4 hallazgos | Requieren acción inmediata |
| 🟠 ALTO | 7 hallazgos | Resolver antes de producción |
| 🟡 MEDIO | 9 hallazgos | Resolver en sprint siguiente |
| 🟢 BAJO | 6 hallazgos | Mejoras de hardening |

### Hallazgos Críticos (Resumen Ejecutivo)

1. **AUTH_MODE=development en toda la superficie** — El guard JWT actualmente inyecta un usuario simulado fijo en todos los endpoints. Cualquier endpoint protegido es accesible sin credenciales en el entorno de desarrollo.
2. **Ausencia de rotación de refresh tokens** — La infraestructura está documentada pero no implementada. Sin rotación, el robo de un refresh token da acceso perpetuo.
3. **Métricas de Prometheus expuestas sin autenticación robusta** — `MetricsAuthGuard` utiliza Basic Auth con credenciales variables de entorno. Si `METRICS_USER` o `METRICS_PASSWORD` son débiles, toda la telemetría interna es pública.
4. **Rate limiting sin backend persistente (Redis)** — ThrottlerModule usa almacenamiento en memoria. Un restart del contenedor reinicia todos los contadores, permitiendo ataques de brute force reiniciando el servicio.

---

## 2. Modelo de Amenazas — STRIDE

### 2.1 Diagrama de Flujo del Sistema

```
[Internet]
    │
    ▼
[Nginx :443] ← Solo punto de entrada público
    │
    ├──→ [Frontend Next.js :3000] ← No accesible directamente desde internet
    │         │
    │         ├──→ /api/* → [Backend NestJS :4000]
    │         └──→ /reports/* → [Reports Python :8000]
    │
    ├──→ /api/* → [Backend NestJS :4000]
    │         │
    │         ├──→ [PostgreSQL] (lectura/escritura)
    │         └──→ [Redis] (sesiones, rate limiting, cache)
    │
    └──→ /reports/* → [Reports Python :8000]
              │
              ├──→ /api/* → [Backend NestJS] (validación de sesión)
              └──→ [PostgreSQL] (solo lectura)

[Red Docker interna: nombre_del_proyecto-private]
  Backend, Frontend, Reports ← aislados en red privada
```

### 2.2 Análisis STRIDE por Componente

#### S — Spoofing (Suplantación de Identidad)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| S-01 | Suplantación de usuario con `AUTH_MODE=development` | Backend | Cualquier request sin header de auth | **CRÍTICO** |
| S-02 | JWT forjado si `JWT_SECRET` es débil o placeholder | Backend/Auth | Firma JWT débil | **ALTO** |
| S-03 | Suplantación de servicio Reports si token de sesión es predecible | Reports→Backend | Token hardcodeado en código | **ALTO** |
| S-04 | Spoofing de IP en `LocalOnlyGuard` via headers forjados (X-Forwarded-For) | Backend | Headers HTTP manipulados | **MEDIO** |
| S-05 | Suplantación de admin via rol `VIEWER` hardcodeado en guard temporal | Backend | `req.user = { role: 'VIEWER' }` fijo | **ALTO** |

**Evidencia — S-01 y S-05:**
```typescript
// backend/src/auth/guards/jwt-auth.guard.ts — Líneas 54-60
if (AUTH_MODE === 'development') {
  const request = context.switchToHttp().getRequest<Request>();
  request.user = {
    userId: 9999999,        // ← ID fijo, no real
    email: 'dev@local.dev', // ← Email fijo
    role: 'VIEWER',         // ← Rol fijo — si cambia a 'ADMIN' en el placeholder, toda la app es admin
  };
  return true; // ← Siempre autoriza
}
```

**Mitigación S-04 — Corrección en `LocalOnlyGuard`:**
```typescript
// backend/src/common/guards/local-only.guard.ts — PROBLEMA ACTUAL (línea 10)
// req.ip puede ser manipulado si no se configura trust proxy correctamente
const ip: string = req.ip ?? req.connection.remoteAddress ?? '';

// CORRECCIÓN RECOMENDADA: Confiar solo en la IP de la conexión TCP real
// En app.ts o main.ts, configurar:
app.set('trust proxy', false); // Solo confiar en Nginx como proxy

// Y en el guard usar el IP del socket directo:
const ip: string = req.socket.remoteAddress ?? '';
```

#### T — Tampering (Manipulación de Datos)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| T-01 | Inyección SQL en Reports si parámetros no se sanitizan | Reports→DB | Parámetros de query no validados | **ALTO** |
| T-02 | Mass Assignment en DTOs de registro | Backend/Auth | Body extra ignorado por class-validator | **MEDIO** |
| T-03 | CSRF en endpoints de mutación | Backend | SameSite=Strict mitiga pero no hay token CSRF explícito | **MEDIO** |
| T-04 | Manipulación de cookies de sesión | Frontend/Backend | httpOnly=true mitiga XSS, pero falta __Host- prefix | **BAJO** |
| T-05 | Tampering en tokens JWT sin blacklist | Backend | Token robado válido hasta expiración | **ALTO** |

**Evidencia — T-02 (Mass Assignment):**
```typescript
// backend/src/auth/dto/register.dto.ts
// Revisar que todos los campos tienen @IsNotEmpty() o similares
// y que no hay campos no declarados que TypeORM mapee automáticamente.
// RIESGO: si la entidad User tiene campos como 'isAdmin: boolean',
// un body { email, password, isAdmin: true } podría escalada de privilegios
// si TypeORM hace el mapeo automático sin whitelist explícita.

// MITIGACIÓN — En el service, usar siempre desestructuración explícita:
const user = this.userRepository.create({
  email: dto.email,           // ← BIEN: solo campos explícitos
  passwordHash: hashed,       // ← BIEN: no se mapea directamente del DTO
  role: UserRole.VIEWER,      // ← BIEN: rol hardcodeado, no del DTO
  // NO: ...dto                // ← MAL: spread del DTO completo
});
```

#### R — Repudiation (Repudio)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| R-01 | Sin auditoría de acciones críticas (login, cambio de password, cambio de rol) | Backend | Logs sin estructuración de eventos de seguridad | **MEDIO** |
| R-02 | Request ID no correlacionado entre servicios en todas las rutas | Todos | Trazabilidad parcial | **MEDIO** |
| R-03 | Sin registro de intentos fallidos de autenticación | Backend | No hay logging de brute force attempts | **ALTO** |

**Evidencia — R-03:**
```typescript
// backend/src/auth/auth.service.ts — refreshTokens()
// Solo se registra el error genérico. No hay logging de:
// - IP del cliente que intentó el refresh
// - Número de intentos fallidos
// - Timestamp del intento
// - User-Agent

// CORRECCIÓN:
async refreshTokens(refreshToken: string, clientIp: string): Promise<...> {
  try {
    payload = this.jwtService.verify(refreshToken, { secret: this.jwtSecret });
  } catch (err) {
    // ← Agregar logging de seguridad aquí
    this.logger.warn({
      event: 'REFRESH_TOKEN_INVALID',
      ip: clientIp,
      timestamp: new Date().toISOString(),
      reason: err.message,
    });
    throw new UnauthorizedException('Refresh token inválido o expirado');
  }
}
```

#### I — Information Disclosure (Divulgación de Información)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| I-01 | Swagger habilitado en producción (`SWAGGER_ENABLED=true`) | Backend | Documentación API pública expone estructura interna | **ALTO** |
| I-02 | Métricas Prometheus expuestas con Basic Auth débil | Backend | Telemetría interna con usuarios activos, queries DB | **ALTO** |
| I-03 | Stack trace en respuestas de error en desarrollo expuesto por error de configuración | Backend | `GlobalExceptionFilter` bien implementado — riesgo bajo si NODE_ENV correcto | **BAJO** |
| I-04 | Variables de entorno en logs de Docker | Docker | `docker compose logs` puede exponer valores de env | **MEDIO** |
| I-05 | CSP report-uri apuntando a backend externo en desarrollo | Frontend | CSP violations se envían a `http://localhost:4000` — datos de errores internos | **BAJO** |
| I-06 | Nombre del proyecto en `container_name` hardcodeado | Docker Compose | `nombre_del_proyecto_api` revela naming convention interna | **BAJO** |

**Evidencia — I-01:**
```typescript
// backend/src/main.ts — Línea referencia al swagger
const SWAGGER_ENABLED = process.env.SWAGGER_ENABLED === 'true';
// Si SWAGGER_ENABLED=true en producción, toda la API queda documentada públicamente.
// Un atacante puede usar Swagger UI para explorar endpoints, esquemas, y hacer peticiones.

// CORRECCIÓN: Añadir doble barrera
if (SWAGGER_ENABLED && !IS_PRODUCTION) {
  // Swagger solo en desarrollo
  setupSwagger(app);
} else if (SWAGGER_ENABLED && IS_PRODUCTION) {
  throw new Error('[Bootstrap] SWAGGER_ENABLED=true no está permitido en producción.');
}
```

#### D — Denial of Service (Denegación de Servicio)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| D-01 | Rate limiting en memoria (reiniciable) | Backend | Restart del contenedor elimina contadores | **CRÍTICO** |
| D-02 | Sin límite de tamaño en body de CSP report | Backend/CSP | `CspReportController` acepta bodies arbitrariamente grandes | **MEDIO** |
| D-03 | Sin timeouts en conexiones a PostgreSQL | Backend | Pool sin `idleTimeoutMillis` ni `connectionTimeoutMillis` | **MEDIO** |
| D-04 | Sin circuit breaker entre Reports y Backend | Reports | Caída del Backend bloquea Reports indefinidamente | **MEDIO** |
| D-05 | Single point of failure — un solo VPS | Infraestructura | Sin redundancia ni failover | **BAJO** (aceptado en escala actual) |

**Evidencia — D-01:**
```typescript
// backend/src/app.module.ts — ThrottlerModule sin Redis store
ThrottlerModule.forRoot([
  { name: 'short',  ttl: 1000,  limit: 10 },
  { name: 'medium', ttl: 60000, limit: 100 },
]),
// ← Sin ThrottlerStorageRedisService → almacenamiento en memoria
// Reiniciar el contenedor = resetear todos los contadores de rate limiting

// CORRECCIÓN — Instalar y configurar Redis store:
// pnpm add @nestjs-throttler/redis ioredis
ThrottlerModule.forRootAsync({
  inject: [getConfigToken()],
  useFactory: (config: ConfigService) => ({
    throttlers: [
      { name: 'short',  ttl: 1000,  limit: 10 },
      { name: 'medium', ttl: 60000, limit: 100 },
    ],
    storage: new ThrottlerStorageRedisService(
      new Redis({ host: config.get('REDIS_HOST'), port: 6379 })
    ),
  }),
}),
```

**Evidencia — D-02:**
```typescript
// backend/src/common/controllers/csp-report.controller.ts
// El endpoint /api/csp-report acepta bodies sin límite de tamaño explícito.
// Aunque NestJS tiene límite por defecto (100kb), se debe configurar explícitamente.

// En main.ts, añadir límite específico para este endpoint:
app.use('/api/csp-report', express.json({ limit: '10kb' })); // Antes del router global
```

#### E — Elevation of Privilege (Escalada de Privilegios)

| ID | Amenaza | Componente | Vector | Severidad |
|----|---------|-----------|--------|-----------|
| E-01 | Sin implementación de `@Roles()` en todos los endpoints sensibles | Backend | Endpoints de admin sin decorador @Roles | **ALTO** |
| E-02 | `RolesGuard` sin @Roles() → acceso libre para cualquier usuario autenticado | Backend | Lógica correcta pero riesgo si se omite @Roles en endpoints nuevos | **MEDIO** |
| E-03 | Proceso del contenedor puede ser root | Docker | Dockerfiles bien configurados, verificar usuario no-root | **BAJO** |
| E-04 | Sin MFA implementado ni planificado | Backend/Auth | Auth de un solo factor | **MEDIO** |

**Evidencia — E-01:**
```typescript
// backend/src/common/guards/roles.guard.ts — Línea 14-16
// Sin @Roles() → acceso libre para cualquier usuario autenticado
if (!requiredRoles || requiredRoles.length === 0) return true;

// RIESGO: Si se añade un endpoint GET /api/admin/users SIN @Roles('ADMIN'),
// cualquier usuario con rol VIEWER puede acceder.
// CORRECCIÓN: Cambiar el comportamiento por defecto a DENY si no hay @Roles():
if (!requiredRoles || requiredRoles.length === 0) {
  // Opción 1: Denegar por defecto (zero trust)
  throw new ForbiddenException('Acceso denegado: endpoint sin roles definidos');
  // Opción 2 (menos restrictiva): permitir solo si hay usuario autenticado
  // return !!user;
}
```

---

## 3. Arquitectura de Seguridad — Zero Trust

### 3.1 Principios Zero Trust Aplicados

El modelo Zero Trust se basa en: **"Nunca confiar, siempre verificar"**. Cada componente debe verificar la identidad de quien le contacta, independientemente de si viene de la red interna.

### 3.2 Estado Actual vs. Estado Objetivo

```
ESTADO ACTUAL (Confianza Implícita en Red Interna):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Internet → Nginx → [Red Docker Privada]
                         │
                   Todos los servicios
                   confían entre sí
                   sin autenticación
                   adicional

ESTADO OBJETIVO (Zero Trust):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Internet → Nginx (TLS 1.3 únicamente) → [Edge Layer]
                                              │
                                    Frontend (autenticado por JWT)
                                              │
                           Backend (verifica JWT en CADA request)
                           ├── Reports debe presentar token de servicio
                           ├── Cada operación tiene audit log
                           └── DB tiene usuarios separados con mínimos privilegios
```

### 3.3 Segmentación de Servicios

```yaml
# Segmentación de red propuesta
networks:
  public-dmz:          # Solo Nginx accede desde internet
    internal: false
  
  frontend-tier:       # Frontend ↔ Nginx
    internal: true
    
  backend-tier:        # Backend ↔ Frontend, Backend ↔ DB
    internal: true
    
  reports-tier:        # Reports ↔ Backend, Reports ↔ DB (read-only)
    internal: true
    
  data-tier:           # PostgreSQL + Redis — solo acceso desde backend/reports
    internal: true
```

### 3.4 Control de Identidad y Acceso (IAM)

```
Capas de autenticación por servicio:

Frontend:   → JWT en cookie httpOnly (acceso_token, 15min)
            → Refresh token en cookie httpOnly (7 días)
            → Nonce CSP por request

Backend:    → JwtAuthGuard (verifica token en cada request)
            → RolesGuard (RBAC: VIEWER | ADMIN | SUPERADMIN)
            → MetricsAuthGuard (Basic Auth en /metrics)
            → LocalOnlyGuard (IP allowlist para rutas internas)

Reports:    → Token de servicio presentado al Backend para validación
            → Usuario DB de solo lectura (db_read_only_user)
            → Sin acceso a endpoints de escritura del Backend

PostgreSQL: → Usuario admin (backend): lectura + escritura
            → Usuario readonly (reports): SELECT únicamente
            → auth-method: scram-sha-256

Redis:      → Autenticación por contraseña (redis_secret)
            → Sin acceso desde fuera de la red Docker
```

---

## 4. Matriz de Riesgos

### 4.1 Escala de Evaluación

| Nivel | Probabilidad | Impacto | Score |
|-------|-------------|---------|-------|
| 🔴 CRÍTICO | Alta (>70%) | Catastrófico | 9-10 |
| 🟠 ALTO | Media-Alta (40-70%) | Severo | 6-8 |
| 🟡 MEDIO | Media (20-40%) | Moderado | 4-5 |
| 🟢 BAJO | Baja (<20%) | Menor | 1-3 |

### 4.2 Tabla de Riesgos Identificados

| ID | Riesgo | Componente | Prob. | Impacto | Score | Prioridad |
|----|--------|-----------|-------|---------|-------|-----------|
| R-CRIT-01 | AUTH_MODE=development en producción por accidente | Backend | Media | Catastrófico | **9** | Sprint actual |
| R-CRIT-02 | Rate limiting en memoria — brute force post-restart | Backend | Alta | Severo | **8** | Sprint actual |
| R-CRIT-03 | Refresh token robado sin rotación ni revocación | Backend | Media | Catastrófico | **9** | Sprint actual |
| R-CRIT-04 | JWT_SECRET débil/placeholder en producción | Backend | Baja-Media | Catastrófico | **8** | Sprint actual |
| R-HIGH-01 | Swagger habilitado en producción | Backend | Media | Severo | **7** | Sprint siguiente |
| R-HIGH-02 | Métricas internas expuestas (Basic Auth débil) | Backend | Media | Severo | **6** | Sprint siguiente |
| R-HIGH-03 | Sin audit log de eventos de seguridad | Backend | Alta | Severo | **7** | Sprint siguiente |
| R-HIGH-04 | Mass Assignment en entidades ORM | Backend | Baja | Severo | **6** | Sprint siguiente |
| R-HIGH-05 | Sin TLS mutuo entre servicios internos (mTLS) | Infraestructura | Baja | Severo | **6** | Mediano plazo |
| R-HIGH-06 | Reports sin autenticación de servicio al Backend | Reports | Media | Severo | **7** | Sprint siguiente |
| R-HIGH-07 | Sin rotación automática de secretos | Infraestructura | Baja | Severo | **6** | Mediano plazo |
| R-MED-01 | LocalOnlyGuard vulnerable a X-Forwarded-For manipulation | Backend | Baja | Moderado | **5** | Sprint siguiente |
| R-MED-02 | Sin límite de tamaño en CSP report body | Backend | Media | Moderado | **4** | Sprint siguiente |
| R-MED-03 | Sin timeouts en pool de PostgreSQL | Backend | Baja | Moderado | **4** | Sprint siguiente |
| R-MED-04 | Sin circuit breaker Reports→Backend | Reports | Baja | Moderado | **4** | Mediano plazo |
| R-MED-05 | RBAC: endpoints sin @Roles() accesibles por cualquier auth user | Backend | Media | Moderado | **5** | Sprint siguiente |
| R-MED-06 | Sin MFA | Backend/Auth | N/A | Moderado | **4** | Largo plazo |
| R-MED-07 | Sin SAST/DAST automatizado en CI | CI/CD | Media | Moderado | **5** | Sprint siguiente |
| R-MED-08 | Logs sin centralización (ELK/Loki) en producción mínima | Infraestructura | Alta | Moderado | **4** | Mediano plazo |
| R-MED-09 | Imagen Docker base sin actualización automática | Docker | Media | Moderado | **4** | Mediano plazo |
| R-LOW-01 | Cookies sin prefijo `__Host-` | Backend | Baja | Menor | **2** | Hardening |
| R-LOW-02 | NGINX sin rate limiting en rutas de autenticación específicas | Nginx | Baja | Menor | **3** | Hardening |
| R-LOW-03 | Sin cabeceras de seguridad en respuestas de error | Backend | Baja | Menor | **2** | Hardening |
| R-LOW-04 | `docker-compose.yml` container_name revela naming interno | Docker | Baja | Menor | **1** | Cosmético |
| R-LOW-05 | Sin análisis de dependencias transitivas (SBOM) | Infraestructura | Baja | Menor | **3** | Largo plazo |
| R-LOW-06 | Sin política de retención de logs definida | Infraestructura | N/A | Menor | **2** | Largo plazo |

---

## 5. Análisis Técnico Profundo

### 5.1 Backend NestJS

#### 5.1.1 Autenticación (auth/)

**Archivo:** `backend/src/auth/guards/jwt-auth.guard.ts`

**Hallazgo CRÍTICO — R-CRIT-01:** El guard de autenticación opera en modo simulado. No hay verificación real de JWT en el entorno de desarrollo.

```typescript
// PROBLEMA — jwt-auth.guard.ts, líneas 54-61
if (AUTH_MODE === 'development') {
  const request = context.switchToHttp().getRequest<Request>();
  request.user = {
    userId: 9999999,
    email: 'dev@local.dev',
    role: 'VIEWER',  // ← Cambiar a 'ADMIN' aquí rompería toda la app en producción si olvidamos revertir
  };
  return true;
}
```

La protección en tiempo de arranque (`if (IS_PRODUCTION && AUTH_MODE !== 'real') throw Error`) es excelente y evita despliegues accidentales. Sin embargo, no es suficiente si alguien usa `NODE_ENV=development` en un servidor real.

**Corrección adicional — Doble barrera:**
```typescript
// backend/src/auth/guards/jwt-auth.guard.ts — Añadir validación de entorno
// Verificar también el hostname o una variable de entorno de entorno explícita
const IS_TRULY_LOCAL = process.env.DEPLOYMENT_ENV === 'local'; // Nueva var

if (AUTH_MODE === 'development' && !IS_TRULY_LOCAL) {
  throw new InternalServerErrorException(
    '[JwtAuthGuard] AUTH_MODE=development requiere DEPLOYMENT_ENV=local'
  );
}
```

**Archivo:** `backend/src/auth/auth.service.ts`

**Hallazgo CRÍTICO — R-CRIT-03:** La rotación de refresh tokens está documentada pero no implementada. El método actual `refreshTokens()` emite un nuevo access token sin invalidar el refresh token usado.

```typescript
// PROBLEMA — auth.service.ts, líneas 31-50
async refreshTokens(refreshToken: string): Promise<{ access_token: string }> {
  // ← Verifica el token (bien)
  payload = this.jwtService.verify(refreshToken, { secret: this.jwtSecret });
  
  // ← PROBLEMA: No invalida el refresh token usado
  // Si el token fue robado, el atacante puede seguir usándolo indefinidamente
  
  return { access_token: this.jwtService.sign(...) };
  // ← No emite nuevo refresh token (rotación ausente)
}
```

**Corrección — Implementación mínima de revocación:**
```typescript
// backend/src/auth/auth.service.ts — Implementación con Redis blacklist
// (alternativa más rápida que la BD para el corto plazo)
import { InjectRedis } from '@nestjs-modules/ioredis';
import { Redis } from 'ioredis';

async refreshTokens(refreshToken: string): Promise<TokenPair> {
  // 1. Verificar token
  const payload = this.jwtService.verify(refreshToken, { secret: this.jwtSecret });
  
  // 2. Verificar que no está en blacklist
  const isRevoked = await this.redis.get(`rt:revoked:${payload.jti}`);
  if (isRevoked) {
    // Posible token replay attack → revocar TODA la familia del usuario
    await this.revokeAllUserTokens(payload.sub);
    throw new UnauthorizedException('Token revocado. Por favor inicia sesión de nuevo.');
  }
  
  // 3. Revocar el token actual (invalidarlo en Redis hasta su expiración)
  const ttl = payload.exp - Math.floor(Date.now() / 1000);
  await this.redis.setex(`rt:revoked:${payload.jti}`, ttl, '1');
  
  // 4. Emitir nuevos tokens
  return this.issueTokenPair(payload.sub, payload.email, payload.role);
}
```

**Archivo:** `backend/src/auth/password.service.ts`

**Evaluación POSITIVA:** El uso de argon2id con 64MB de memoria, 3 iteraciones, y pepper es correcto y supera los mínimos de OWASP. 

**Hallazgo MEDIO:** El pepper se lee en tiempo de carga del módulo. Si el archivo de secreto no está disponible en ese momento, el módulo falla silenciosamente en algunos escenarios.

```typescript
// password.service.ts — Línea 9
const PEPPER = readSecret('PEPPER_SECRET_FILE', 'PEPPER_SECRET') ?? '';
// ← El ?? '' hace que PEPPER sea string vacío si no existe
// En desarrollo esto es correcto, pero asegurar que en producción se lanza error

// CORRECCIÓN: Forzar error en producción:
const PEPPER = readSecret('PEPPER_SECRET_FILE', 'PEPPER_SECRET', process.env.NODE_ENV === 'production');
if (!PEPPER && process.env.NODE_ENV === 'production') {
  throw new Error('[PasswordService] PEPPER_SECRET es requerido en producción');
}
```

#### 5.1.2 Configuración (config/)

**Archivo:** `backend/src/config/secrets.ts`

**Evaluación POSITIVA:** El patrón de lectura de secretos (archivo > variable de entorno > error) es correcto y alineado con las mejores prácticas de Docker Secrets.

**Archivo:** `backend/src/config/database.config.ts`

**Hallazgo MEDIO — R-MED-03:** El pool de conexiones no tiene timeouts configurados.

```typescript
// database.config.ts — TypeORM options sin timeouts
// CORRECCIÓN — Añadir opciones de conexión robustas:
return {
  type: 'postgres',
  host, port, database, username, password,
  // ← Añadir estas opciones:
  connectTimeoutMS: 5000,       // Timeout de conexión inicial
  extra: {
    idleTimeoutMillis: 30000,   // Cerrar conexiones inactivas tras 30s
    connectionTimeoutMillis: 5000,
    max: 10,                    // Máximo de conexiones en el pool
    min: 2,                     // Mínimo de conexiones mantenidas
  },
  retryAttempts: 3,
  retryDelay: 3000,
  // SSL en producción:
  ssl: IS_PRODUCTION ? { rejectUnauthorized: true } : false,
};
```

**Archivo:** `backend/src/app.module.ts`

**Hallazgo ALTO — R-HIGH-02:** El orden de guards es correcto (`Throttler → JWT → Roles → Metrics`), pero el `MetricsAuthGuard` con Basic Auth debe tener contraseñas fuertes y rotación.

```typescript
// app.module.ts — Guard order (bien configurado)
providers: [
  { provide: APP_GUARD, useClass: UserThrottlerGuard },  // ← 1. Rate limit
  { provide: APP_GUARD, useClass: JwtAuthGuard },        // ← 2. Autenticación
  { provide: APP_GUARD, useClass: RolesGuard },          // ← 3. Autorización
  { provide: APP_GUARD, useClass: MetricsAuthGuard },    // ← 4. Métricas
],
```

**Hallazgo:** El orden de evaluación de APP_GUARD en NestJS es secuencial, pero `MetricsAuthGuard` no debe estar DESPUÉS de `JwtAuthGuard` si `/metrics` necesita autenticación diferente. Verificar que MetricsAuthGuard tiene acceso antes que JwtAuthGuard para la ruta `/metrics`.

```typescript
// VERIFICACIÓN RECOMENDADA en MetricsAuthGuard:
// Asegurarse que primero verifica si la ruta es /metrics
// y aplica Basic Auth ANTES de que JwtAuthGuard la rechace
canActivate(context: ExecutionContext): boolean {
  const request = context.switchToHttp().getRequest();
  if (!request.path.startsWith('/metrics')) {
    return true; // No es /metrics, dejar pasar al siguiente guard
  }
  // Aplicar Basic Auth aquí
}
```

#### 5.1.3 main.ts

**Archivo:** `backend/src/main.ts`

**Evaluación POSITIVA:**
- `validateAppConfig()` al inicio (fail-fast)
- helmet() configurado
- cookieParser con secret
- CORS configurado con ALLOWED_ORIGINS
- ValidationPipe con whitelist y forbidNonWhitelisted

**Hallazgo ALTO — I-01:** Verificar que la condición de Swagger es robusta:
```typescript
// main.ts — Añadir doble barrera para Swagger
const SWAGGER_ENABLED = process.env.SWAGGER_ENABLED === 'true';
if (SWAGGER_ENABLED) {
  if (IS_PRODUCTION) {
    // Línea X: NUNCA permitir en producción
    throw new Error('[Bootstrap] SWAGGER no puede habilitarse en NODE_ENV=production');
  }
  // Solo en desarrollo — añadir autenticación Basic también:
  app.use('/api-docs', basicAuth({
    users: { [process.env.SWAGGER_USER ?? 'dev']: process.env.SWAGGER_PASS ?? 'devpass' },
    challenge: true,
  }));
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api-docs', app, document);
}
```

**Hallazgo MEDIO:** El `GlobalPrefix` y `ValidationPipe` están bien configurados, pero falta `transform: true` para coercionar tipos automáticamente:

```typescript
// main.ts — ValidationPipe mejorado
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,              // ← Bien: elimina campos no declarados
  forbidNonWhitelisted: true,   // ← Bien: rechaza campos extra
  transform: true,              // ← AÑADIR: convierte tipos automáticamente
  transformOptions: {
    enableImplicitConversion: true,
  },
  disableErrorMessages: IS_PRODUCTION, // ← AÑADIR: no revelar mensajes de validación en prod
}));
```

---

### 5.2 Frontend Next.js

#### 5.2.1 Content Security Policy (middleware.ts)

**Evaluación POSITIVA:** La implementación de CSP con nonces por request es de nivel enterprise. La estrategia es correcta:
- Nonce único por request (`crypto.randomUUID()` → base64)
- Sin `'unsafe-inline'` en script-src ni style-src
- `frame-ancestors 'none'` y `frame-src 'none'`
- `upgrade-insecure-requests` solo en producción

**Hallazgo MEDIO — I-05:** El `report-uri` envía a `/api/csp-report`. Verificar que en desarrollo esto apunta al backend local, no a un servidor externo.

```typescript
// middleware.ts — Líneas de connectSrc
const connectSrcOrigins = [
  process.env.NEXT_PUBLIC_API_URL,      // ← Si está indefinida en dev, el URL es vacío
  process.env.NEXT_PUBLIC_REPORTS_URL,  // ← Ídem
]
.filter(Boolean)
// RIESGO: Si ambas son undefined, connectSrc = "'self'" (bien por defecto)
// Pero verificar que las vars están definidas en el entorno de CI

// CORRECCIÓN — Validación explícita:
if (process.env.NODE_ENV === 'production') {
  const requiredVars = ['NEXT_PUBLIC_API_URL', 'NEXT_PUBLIC_REPORTS_URL'];
  for (const v of requiredVars) {
    if (!process.env[v]) throw new Error(`[CSP] ${v} es requerida en producción`);
  }
}
```

**Hallazgo BAJO — T-04:** Las cookies no usan el prefijo `__Host-` que añade una capa de protección adicional.

```typescript
// backend/src/auth/auth.controller.ts — COOKIE_OPTIONS
const COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict' as const,
  // AÑADIR: path explícito para habilitar __Host- prefix
  path: '/',
};

// Y al enviar la cookie usar el prefijo __Host-:
res.cookie('__Host-access_token', token, {
  ...COOKIE_OPTIONS,
  // __Host- requiere: secure=true, path='/', sin domain attribute
});
// Nota: solo funciona con HTTPS, por lo que en desarrollo se usa sin prefijo
const cookieName = IS_PRODUCTION ? '__Host-access_token' : 'access_token';
```

#### 5.2.2 next.config.ts

**Evaluación POSITIVA:** Los security headers en `next.config.ts` están bien configurados:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy` restrictivo
- `Strict-Transport-Security` solo en producción

**Hallazgo BAJO:** El comentario en el archivo menciona `'unsafe-eval'` y `'unsafe-inline'` como alternativas. Asegurarse de que estos comentarios no sean descomentados accidentalmente en producción.

---

### 5.3 Servicio de Reports Python

**Hallazgo ALTO — R-HIGH-06:** Según la arquitectura descrita, el servicio de Reports valida sesiones mediante tokens con el Backend, luego accede directamente a la DB con permisos de solo lectura. No se observa código del servicio Reports en el repositorio analizado, pero el patrón de autenticación de servicio debe verificarse.

**Patrón requerido:**
```python
# reports/auth.py — Validación de sesión antes de acceder a DB
import httpx
import os

BACKEND_URL = os.getenv("BACKEND_INTERNAL_URL", "http://backend:4000")
SERVICE_TOKEN = open("/run/secrets/reports_service_token").read().strip()

async def validate_session(user_token: str) -> dict:
    """
    El servicio Reports NUNCA debe confiar en el token del usuario directamente.
    Debe validarlo contra el Backend primero.
    """
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{BACKEND_URL}/api/internal/validate-session",
            headers={
                "Authorization": f"Bearer {user_token}",
                "X-Service-Token": SERVICE_TOKEN,  # ← Autenticación de servicio
            },
            timeout=5.0,  # ← Timeout explícito — circuit breaker básico
        )
        if response.status_code != 200:
            raise HTTPException(status_code=401, detail="Sesión inválida")
        return response.json()
```

**Hallazgo ALTO — T-01:** Verificar que todas las queries al PostgreSQL en Reports usan parámetros vinculados (parameterized queries), no interpolación de strings.

```python
# BIEN — Consulta parametrizada
async def get_report_data(user_id: int, date_from: str, date_to: str):
    query = "SELECT * FROM reports WHERE user_id = $1 AND created_at BETWEEN $2 AND $3"
    return await db.fetch(query, user_id, date_from, date_to)

# MAL — Interpolación directa (SQL Injection)
query = f"SELECT * FROM reports WHERE user_id = {user_id}"  # ← NUNCA hacer esto
```

---

### 5.4 Base de Datos PostgreSQL

#### 5.4.1 init-db.sh

**Archivo:** `config/init-db.sh`

**Evaluación POSITIVA:** El script crea un usuario de solo lectura separado para el servicio Reports. Esto cumple con el principio de mínimo privilegio.

**Hallazgo ALTO:** Verificar que el script aplica `REVOKE` explícito de permisos por defecto:

```bash
# config/init-db.sh — Reforzar restricciones del usuario readonly
# Añadir después de crear el usuario readonly:

# Revocar permisos por defecto del schema public al usuario readonly
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- Crear usuario readonly
  CREATE USER ${DB_READ_ONLY_USER} WITH PASSWORD '${DB_READ_ONLY_PASSWORD}';
  
  -- Revocar capacidad de crear objetos
  REVOKE CREATE ON SCHEMA public FROM ${DB_READ_ONLY_USER};
  
  -- Otorgar solo lectura en tablas existentes
  GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${DB_READ_ONLY_USER};
  GRANT USAGE ON SCHEMA public TO ${DB_READ_ONLY_USER};
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_READ_ONLY_USER};
  
  -- Aplicar para tablas futuras automáticamente
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO ${DB_READ_ONLY_USER};
    
  -- IMPORTANTE: Sin esto, tablas nuevas no son accesibles para readonly
EOSQL
```

#### 5.4.2 pg_hba.conf

**Archivo:** `config/pg_hba.conf`

**Evaluación POSITIVA:** Se usa `scram-sha-256` como método de autenticación (el más seguro disponible en PostgreSQL). La configuración rechaza acceso desde IPs externas.

**Hallazgo MEDIO:** Verificar que en producción (PostgreSQL en el host) el `pg_hba.conf` también esté configurado para aceptar solo conexiones desde la IP del host Docker (gateway), no desde `0.0.0.0`.

```conf
# pg_hba.conf — PRODUCCIÓN (PostgreSQL en el host)
# Rechazar todo por defecto
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
# Solo aceptar conexiones desde la red Docker (para los contenedores)
host    nombre_del_proyecto_db   backend_user   172.16.0.0/12   scram-sha-256
host    nombre_del_proyecto_db   readonly_user  172.16.0.0/12   scram-sha-256
# Denegar todo lo demás
host    all             all             0.0.0.0/0               reject
```

---

### 5.5 Redis

**Archivo:** `config/redis-entrypoint.sh`

**Evaluación POSITIVA:** Redis está configurado para requerir autenticación con una contraseña. El script verifica que el secreto existe antes de iniciar.

**Hallazgo MEDIO:** Verificar que Redis no está expuesto en ningún puerto del host en producción. El `docker-compose.prod.yml` no debe incluir `ports` para Redis.

```yaml
# docker-compose.prod.yml — Redis sin exposición de puertos
redis:
  # ← Verificar que NO hay sección 'ports' aquí
  # Solo accesible desde la red Docker interna
  networks:
    - nombre_del_proyecto-private
  # ← Solo la red privada, sin public-dmz
```

**Hallazgo MEDIO:** Redis debería tener `maxmemory` y `maxmemory-policy` configurados para evitar que un ataque de DoS llene la memoria del servidor.

```bash
# config/redis-entrypoint.sh — Añadir configuración de memoria
exec redis-server \
  --requirepass "$REDIS_SECRET" \
  --maxmemory 256mb \
  --maxmemory-policy allkeys-lru \
  --save "" \           # ← Deshabilitar persistencia si solo se usa para sesiones
  --appendonly no \
  --loglevel warning
```

---

### 5.6 Nginx (Proxy Inverso)

**Archivo:** `docs/guides/NGINX.md`

**Evaluación POSITIVA:**
- TLS 1.2/1.3 con ciphers modernos
- Headers de seguridad (HSTS, X-Frame-Options, X-Content-Type-Options)
- Rate limiting por zona
- Health checks bloqueados (`/health`, `/ready`)
- Request ID correlacionado entre servicios

**Hallazgo ALTO:** Verificar la configuración de rate limiting en las rutas de autenticación:

```nginx
# /etc/nginx/sites-available/nombre_del_proyecto
# ─── Rate limiting específico para auth ───
limit_req_zone $binary_remote_addr zone=auth_zone:10m rate=5r/m;

location /api/auth/login {
    limit_req zone=auth_zone burst=3 nodelay;
    limit_req_status 429;
    # Añadir header Retry-After
    add_header Retry-After 60;
    
    proxy_pass http://127.0.0.1:4000;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    # IMPORTANTE: Nginx no debe incluir X-Forwarded-For del cliente externo
    # para rutas de autenticación (previene spoofing de IP en logs)
}

location /api/auth/register {
    limit_req zone=auth_zone burst=2 nodelay;
    limit_req_status 429;
    proxy_pass http://127.0.0.1:4000;
}
```

**Hallazgo MEDIO:** La guía no menciona configuración de `client_max_body_size` para el endpoint de CSP reports. Establecer un límite bajo:

```nginx
# Para el endpoint de CSP reports
location /api/csp-report {
    client_max_body_size 10k;  # Máximo 10KB para CSP reports
    limit_req zone=general_zone burst=5 nodelay;
    proxy_pass http://127.0.0.1:4000;
}
```

---

### 5.7 Docker y Contenedores

#### 5.7.1 Dockerfile (desarrollo)

**Archivo:** `backend/.docker/Dockerfile`

**Evaluación POSITIVA:**
- Imagen fijada por hash SHA256 (`node:24-slim@sha256:...`) — excelente práctica
- `tini` como proceso init (manejo correcto de señales)
- Multi-stage build
- `curl` instalado para healthchecks

**Hallazgo MEDIO:** El Dockerfile de desarrollo no ejecuta el proceso como usuario no-root. Verificar:

```dockerfile
# backend/.docker/Dockerfile — Añadir usuario no-root
# Después de instalar dependencias del sistema:
RUN groupadd -r appgroup && useradd -r -g appgroup -s /sbin/nologin appuser
# ...
# Al final, antes del CMD:
USER appuser
# WORKDIR ya configurado como /usr/src/app
# La app no necesita escribir en el filesystem (logs van a stdout)
```

#### 5.7.2 Dockerfile.prod (producción)

**Archivo:** `backend/.docker/Dockerfile.prod`

**Evaluación POSITIVA:**
- Multi-stage build correcto (builder → runner)
- Imagen final sin herramientas de build
- pnpm con versión fijada via ARG

**Hallazgo ALTO:** Verificar que la imagen de producción:
1. No incluye el código fuente TypeScript (solo el JS compilado)
2. Ejecuta como usuario no-root
3. El filesystem es de solo lectura con excepciones explícitas

```dockerfile
# backend/.docker/Dockerfile.prod — Fase runner
FROM node:24-slim@sha256:a81a03dd965b4052269a57fac857004022b522a4bf06e7a739e25e18bce45af2 AS runner

# Usuario no-root
RUN groupadd -r appgroup && useradd -r -g appgroup -s /sbin/nologin appuser

WORKDIR /usr/src/app

# Solo copiar artefactos compilados (no .ts, no node_modules de dev)
COPY --from=builder --chown=appuser:appgroup /usr/src/app/dist ./dist
COPY --from=builder --chown=appuser:appgroup /usr/src/app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /usr/src/app/package.json ./

USER appuser

# Health check usando el usuario de la app
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:${PORT:-4000}/health/ready || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "dist/main.js"]
```

#### 5.7.3 docker-compose.prod.yml

**Evaluación POSITIVA:**
- Docker Secrets sin Swarm (archivos en `/run/secrets/`)
- `mem_limit` y `cpus` configurados por servicio
- `restart: always` en producción
- Red privada (`nombre_del_proyecto-private`)

**Hallazgo ALTO — Filesystem read-only en producción:**

```yaml
# docker-compose.prod.yml — Añadir seguridad de filesystem
services:
  backend:
    read_only: true             # ← Filesystem de solo lectura
    tmpfs:
      - /tmp:mode=1777,size=100m  # ← Directorio temporal en memoria
    security_opt:
      - no-new-privileges:true  # ← Previene escalada de privilegios
    cap_drop:
      - ALL                     # ← Eliminar todas las capabilities de Linux
    cap_add:
      - NET_BIND_SERVICE        # ← Solo la necesaria (si el puerto < 1024)
```

---

### 5.8 CI/CD y GitHub Actions

**Archivo:** `.github/workflows/security.yml`

**Evaluación POSITIVA:** El workflow de seguridad incluye:
- `pnpm audit` para dependencias
- Análisis SAST
- Escaneo de secrets con herramientas

**Hallazgo MEDIO — R-MED-07:** Asegurarse que el workflow de seguridad se ejecuta en CADA PR, no solo en ramas principales:

```yaml
# .github/workflows/security.yml — Trigger en todos los PRs
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]  # ← IMPORTANTE: en PRs también
  schedule:
    - cron: '0 6 * * 1'  # Escaneo semanal adicional
```

**Hallazgo ALTO:** Agregar Semgrep o CodeQL para análisis SAST más profundo:

```yaml
# .github/workflows/security.yml — Añadir CodeQL
jobs:
  codeql:
    name: CodeQL Analysis
    runs-on: ubuntu-latest
    permissions:
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: javascript, typescript
          queries: security-extended
      - uses: github/codeql-action/analyze@v3
```

---

### 5.9 Gestión de Secretos

**Estado actual:** Sistema de dos capas (Docker Secrets en prod, variables de entorno en dev). La utilidad `readSecret()` en `secrets.ts` implementa correctamente el patrón de lectura.

**Evaluación POSITIVA:**
- Secretos de producción en archivos (`/run/secrets/`)
- `.gitignore` excluye `.env` y `secrets/`
- El README documenta `make secrets-init`

**Hallazgo ALTO — R-HIGH-07:** Sin rotación automática de secretos. En caso de compromiso, los secretos deben rotarse manualmente.

**Plan de rotación de secretos (a implementar):**
```bash
# Makefile — Añadir target de rotación de secretos
secrets-rotate:
	@echo "Rotando secretos..."
	@# 1. Generar nuevos valores
	openssl rand -base64 64 > ./secrets/jwt_secret_new.txt
	openssl rand -base64 64 > ./secrets/cookie_secret_new.txt
	
	@# 2. Desplegar con nuevos secretos (mantener anterior activo brevemente para tokens en vuelo)
	@echo "ADVERTENCIA: Rotar JWT invalidará todas las sesiones activas"
	@read -p "¿Continuar? [y/N] " confirm && [ "$$confirm" = "y" ]
	
	@# 3. Reemplazar archivos
	mv ./secrets/jwt_secret_new.txt ./secrets/jwt_secret.txt
	
	@# 4. Reiniciar servicios
	docker compose -f docker-compose.yml -f docker-compose.prod.yml restart backend
```

**Hallazgo MEDIO:** Para escalabilidad empresarial, migrar a HashiCorp Vault o AWS Secrets Manager:

```yaml
# docker-compose.prod.yml — Integración futura con Vault
services:
  backend:
    environment:
      VAULT_ADDR: "http://vault:8200"
      VAULT_TOKEN_FILE: /run/secrets/vault_token
    # El backend leería secretos de Vault en tiempo de arranque
    # en lugar de Docker Secrets (o ambos, con Vault como fuente primaria)
```

---

### 5.10 Código Comentado y Plantillas

**Hallazgo GENERAL:** El repositorio contiene código comentado de alta calidad que representa la implementación futura. Se evalúa en tres categorías:

#### Código comentado de bajo riesgo (correcto, listo para activar)
- `jwt.strategy.ts` — Estrategia JWT completa, bien implementada
- `auth.controller.ts` — Endpoint de login/register con cookie httpOnly
- `password.service.ts` — Completamente implementado

#### Código comentado que requiere revisión antes de activar
- `auth.service.ts` — El esqueleto de rotación de refresh tokens necesita tabla en BD primero
- `app.module.ts` — El ThrottlerModule necesita Redis store antes de ser útil en producción
- `guards/jwt-auth.guard.ts` — Requiere que `jwt.strategy.ts` esté registrado en `AuthModule`

#### Configuración comentada en next.config.ts
```typescript
// RIESGO: La CSP comentada en next.config.ts incluye 'unsafe-inline' y 'unsafe-eval'
// Si alguien descomenta esta sección sin entenderla, se debilita la CSP del middleware.
// RECOMENDACIÓN: Eliminar estos comentarios del código o añadir una advertencia clara:

// ⚠️ NO DESCOMENTAR — La CSP real está en middleware.ts con nonces.
// Esta sección es solo referencia histórica y está retenida solo para documentación.
```

---

## 6. Políticas de Seguridad

### 6.1 RBAC — Role-Based Access Control

#### Definición de Roles

```typescript
// backend/src/common/decorators/roles.decorator.ts — Política RBAC completa
export enum UserRole {
  VIEWER    = 'VIEWER',    // Solo lectura — datos propios
  EDITOR    = 'EDITOR',    // Crear/editar — datos propios
  MANAGER   = 'MANAGER',   // Gestionar usuarios de su equipo
  ADMIN     = 'ADMIN',     // Gestión completa del sistema
  SUPERADMIN = 'SUPERADMIN', // Solo operaciones de sistema
}
```

#### Matriz de Permisos

| Recurso | VIEWER | EDITOR | MANAGER | ADMIN | SUPERADMIN |
|---------|--------|--------|---------|-------|------------|
| Leer datos propios | ✅ | ✅ | ✅ | ✅ | ✅ |
| Editar datos propios | ❌ | ✅ | ✅ | ✅ | ✅ |
| Leer datos de equipo | ❌ | ❌ | ✅ | ✅ | ✅ |
| Gestionar usuarios | ❌ | ❌ | Parcial | ✅ | ✅ |
| Configuración sistema | ❌ | ❌ | ❌ | ✅ | ✅ |
| Rotación de secretos | ❌ | ❌ | ❌ | ❌ | ✅ |
| Acceso a métricas | ❌ | ❌ | ❌ | ✅ | ✅ |
| Generar reportes | ✅ | ✅ | ✅ | ✅ | ✅ |

#### Aplicación en el código

```typescript
// Ejemplo de uso correcto de RBAC con el sistema actual
@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)  // Guards explícitos en el controlador
export class AdminController {
  
  @Get('users')
  @Roles(UserRole.ADMIN, UserRole.SUPERADMIN)  // ← SIEMPRE declarar @Roles en endpoints sensibles
  getUsers() { ... }
  
  @Delete('users/:id')
  @Roles(UserRole.SUPERADMIN)  // ← Solo SUPERADMIN puede eliminar usuarios
  deleteUser(@Param('id') id: string) { ... }
  
  // MAL EJEMPLO — Sin @Roles → accesible por cualquier usuario autenticado:
  // @Get('dashboard')    // ← EVITAR: sin @Roles, cualquier user autenticado accede
  // getDashboard() { ... }
}
```

### 6.2 IAM — Identity and Access Management

#### Identidades del Sistema

| Identidad | Tipo | Autenticación | Permisos |
|-----------|------|--------------|----------|
| Usuario final | Humano | JWT cookie httpOnly | Según rol RBAC |
| Servicio Reports | Máquina | Token de servicio compartido | Leer sesión en Backend |
| Prometheus | Máquina | Basic Auth | Leer `/metrics` |
| CI/CD | Máquina | GitHub OIDC | Deploy solo a ambientes específicos |
| DBA | Humano | PostgreSQL auth | Gestión de BD (solo desde VPN) |

#### Tokens y Ciclo de Vida

```
Access Token:
  - Duración: 15 minutos (JWT_EXPIRES_IN=15m)
  - Almacenamiento: cookie httpOnly, secure, sameSite=strict
  - Renovación: via refresh token

Refresh Token:
  - Duración: 7 días (JWT_REFRESH_EXPIRES_IN=7d)  
  - Almacenamiento: cookie httpOnly, secure, sameSite=strict
  - Rotación: EN CADA USO (implementar — ver R-CRIT-03)
  - Revocación: Redis blacklist con TTL = exp del token

Service Token (Reports):
  - Duración: Sin expiración (secreto compartido)
  - Almacenamiento: Docker Secret /run/secrets/reports_service_token
  - Rotación: Manual — al menos cada 90 días
```

### 6.3 Seguridad Interna entre Servicios

```
Autenticación de servicio a servicio:

Frontend → Backend:
  Header: Cookie: access_token=<JWT>
  Verificación: JwtAuthGuard en cada request

Reports → Backend (validación):
  Header: Authorization: Bearer <user_token>
  Header: X-Service-Token: <reports_service_token>
  Verificación: Backend valida ambos antes de responder

Backend → PostgreSQL:
  Conexión TLS en producción
  Usuario: backend_user (lectura/escritura)
  
Reports → PostgreSQL:
  Conexión TLS en producción
  Usuario: readonly_user (solo SELECT)
  Sin acceso a tablas sensibles (users, tokens)

Backend → Redis:
  Autenticación por contraseña
  Solo desde red Docker interna
```

### 6.4 Gestión de Secretos — Política Formal

| Secreto | Entorno Dev | Entorno Prod | Rotación | Responsable |
|---------|------------|-------------|----------|-------------|
| `jwt_secret` | `.env` (placeholder) | `/run/secrets/jwt_secret` | Cada 90 días o ante compromiso | SUPERADMIN |
| `cookie_secret` | `.env` (placeholder) | `/run/secrets/cookie_secret` | Cada 90 días | SUPERADMIN |
| `db_password` | `.env` | `/run/secrets/db_password` | Cada 6 meses | DBA |
| `pepper_secret` | `.env` | `/run/secrets/pepper_secret` | **NUNCA** (invalida todos los hashes) | N/A |
| `redis_secret` | `.env` | `/run/secrets/redis_secret` | Cada 6 meses | SUPERADMIN |
| `metrics_password` | `.env` | `/run/secrets/metrics_password` | Cada 90 días | ADMIN |

> ⚠️ El `pepper_secret` NUNCA debe rotarse. Si se pierde, TODOS los passwords quedan inválidos. Hacer backup seguro (Vault, HSM, o caja fuerte física).

---

## 7. Recomendaciones de Implementación

### 7.1 CRÍTICAS — Implementar de inmediato

#### RC-01: Implementar JWT real (desactivar AUTH_MODE=development)

```bash
# 1. Instalar dependencias (si no están)
cd backend && pnpm add @nestjs/passport passport passport-jwt
pnpm add -D @types/passport-jwt

# 2. Descomentar jwt.strategy.ts completo

# 3. Registrar en auth.module.ts:
# providers: [JwtStrategy, ...]
# exports: [JwtStrategy]

# 4. En jwt-auth.guard.ts, reemplazar la clase:
# export class JwtAuthGuard extends AuthGuard('jwt') {

# 5. Cambiar en .env.production:
# AUTH_MODE=real

# 6. Implementar login en auth.service.ts y auth.controller.ts
```

#### RC-02: Migrar ThrottlerModule a Redis store

```bash
cd backend && pnpm add @nestjs-throttler/redis ioredis @nestjs-modules/ioredis
```

```typescript
// backend/src/app.module.ts
import { ThrottlerStorageRedisService } from '@nestjs-throttler/redis';
import { Redis } from 'ioredis';

ThrottlerModule.forRootAsync({
  inject: [ConfigService],
  useFactory: (config: ConfigService) => ({
    throttlers: [
      { name: 'short',  ttl: 1000,  limit: 10 },
      { name: 'medium', ttl: 60000, limit: 100 },
    ],
    storage: new ThrottlerStorageRedisService(new Redis({
      host: config.get('REDIS_HOST', 'redis'),
      port: 6379,
      password: readSecret('REDIS_SECRET_FILE', 'REDIS_SECRET'),
    })),
  }),
}),
```

#### RC-03: Implementar blacklist de refresh tokens con Redis

```typescript
// backend/src/auth/auth.service.ts — Método completo con revocación
// (Ver sección 5.1.1 de este documento para el código completo)
```

#### RC-04: Proteger JWT_SECRET contra valores débiles en producción

```typescript
// backend/src/main.ts — Añadir validación de fortaleza del JWT_SECRET
if (IS_PRODUCTION) {
  const jwtSecret = readSecret('JWT_SECRET_FILE', 'JWT_SECRET');
  if (!jwtSecret || jwtSecret.length < 64) {
    throw new Error(
      '[Bootstrap] JWT_SECRET debe tener al menos 64 caracteres en producción. ' +
      'Genera uno con: openssl rand -base64 64'
    );
  }
  if (/CAMBIAR|placeholder|example|secret|password/i.test(jwtSecret)) {
    throw new Error('[Bootstrap] JWT_SECRET contiene valor placeholder. ' +
      'Reemplaza con: make secrets-init'
    );
  }
}
```

### 7.2 ALTAS — Implementar antes de producción

#### RA-01: Audit log de eventos de seguridad

```typescript
// backend/src/common/audit/audit.service.ts — Nuevo archivo
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';

@Injectable()
export class AuditService {
  async logEvent(event: AuditEvent): Promise<void> {
    await this.auditRepository.save({
      eventType: event.type,       // 'LOGIN_SUCCESS', 'LOGIN_FAILED', 'ROLE_CHANGED', etc.
      userId: event.userId,
      ipAddress: event.ip,
      userAgent: event.userAgent,
      metadata: JSON.stringify(event.metadata),
      createdAt: new Date(),
    });
    // También emitir a log estructurado para Loki/CloudWatch
    this.logger.log({
      event: event.type,
      userId: event.userId,
      ip: event.ip,
      severity: event.severity,    // 'INFO', 'WARNING', 'CRITICAL'
    });
  }
}
```

#### RA-02: Endpoint de validación de servicio para Reports

```typescript
// backend/src/internal/internal.controller.ts — Nuevo controlador interno
@Controller('internal')
@UseGuards(LocalOnlyGuard)  // Solo accesible desde red Docker
export class InternalController {
  
  @Post('validate-session')
  @HttpCode(200)
  async validateSession(
    @Headers('authorization') authHeader: string,
    @Headers('x-service-token') serviceToken: string,
  ): Promise<SessionValidationResult> {
    // 1. Validar token de servicio
    const expectedToken = readSecret('REPORTS_SERVICE_TOKEN_FILE', 'REPORTS_SERVICE_TOKEN');
    if (serviceToken !== expectedToken) {
      throw new UnauthorizedException('Token de servicio inválido');
    }
    // 2. Validar JWT del usuario
    const userToken = authHeader?.replace('Bearer ', '');
    const payload = await this.jwtService.verify(userToken);
    return { userId: payload.sub, role: payload.role, valid: true };
  }
}
```

#### RA-03: Filesystem read-only en producción

```yaml
# docker-compose.prod.yml — Para todos los servicios
services:
  backend:
    read_only: true
    tmpfs:
      - /tmp:size=50m,mode=1777
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
```

#### RA-04: Timeouts en pool de PostgreSQL

```typescript
// backend/src/config/database.config.ts — Línea donde se retorna la config
extra: {
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  max: IS_PRODUCTION ? 20 : 5,
  min: IS_PRODUCTION ? 2 : 1,
  statement_timeout: 30000,      // Queries > 30s son abortadas
  query_timeout: 30000,
},
ssl: IS_PRODUCTION ? {
  rejectUnauthorized: true,
  // ca: readFileSync('/run/secrets/db_ca_cert'),  // Si se usa TLS en la DB
} : false,
```

### 7.3 MEDIAS — Sprint siguiente

#### RM-01: Configurar trust proxy correctamente en Express

```typescript
// backend/src/main.ts — Después de crear la app
// Confiar solo en el proxy de Nginx (una capa)
app.set('trust proxy', 1); // Confiar en el primer proxy (Nginx)
// Esto hace que req.ip sea la IP real del cliente (X-Forwarded-For del primer hop)
// y que LocalOnlyGuard lea la IP correcta
```

#### RM-02: Validación de tamaño en CSP report endpoint

```typescript
// backend/src/common/controllers/csp-report.controller.ts
// Añadir en main.ts antes del middleware global:
app.use('/api/csp-report', express.json({ 
  limit: '10kb',
  type: ['application/json', 'application/csp-report']
}));
```

#### RM-03: Eliminar comentarios con alternativas inseguras en next.config.ts

```typescript
// frontend/next.config.ts — ELIMINAR o marcar claramente:
// TODOS los comentarios que mencionan 'unsafe-inline' o 'unsafe-eval'
// deben ser eliminados o reemplazados por:
// ⚠️ NO USAR — Débil. La CSP real está en middleware.ts
```

#### RM-04: Configurar Renovate para actualizaciones automáticas de imagen Docker

```json
// .github/renovate.json — Añadir configuración para Docker
{
  "dockerfileManager": {
    "enabled": true
  },
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchPackagePatterns": ["node"],
      "schedule": ["every week"],
      "automerge": false,  // Requiere review manual para imágenes base
      "labels": ["security", "dependencies"]
    }
  ]
}
```

---

## 8. Plan de Implementación por Fases

### Fase 1 — Corto Plazo (Semanas 1-2) — Quick Wins Críticos

**Objetivo:** Eliminar riesgos que bloquean cualquier despliegue en producción.

| Tarea | Archivo(s) a modificar | Esfuerzo |
|-------|----------------------|---------|
| RC-01: Activar JWT real | `jwt-auth.guard.ts`, `jwt.strategy.ts`, `auth.module.ts` | 1 día |
| RC-02: Throttler con Redis | `app.module.ts`, `package.json` | 2 horas |
| RC-03: Blacklist refresh tokens | `auth.service.ts`, nueva entidad DB | 1 día |
| RC-04: Validar fortaleza JWT_SECRET | `main.ts` | 1 hora |
| RA-04: Timeouts en DB pool | `database.config.ts` | 30 min |
| Activar login/register real | `auth.controller.ts`, `auth.service.ts` | 2 días |

**Checklist de validación:**
```bash
# Ejecutar antes de considerar completa la Fase 1
make test                     # Todos los tests pasan
AUTH_MODE=real NODE_ENV=production make health-check  # App arranca en modo prod
make secrets-check            # Todos los secretos están configurados
pnpm audit --audit-level=high # Sin vulnerabilidades altas en dependencias
```

### Fase 2 — Mediano Plazo (Semanas 3-6) — Hardening y Observabilidad

**Objetivo:** Alcanzar nivel de seguridad adecuado para usuarios reales en producción.

| Tarea | Descripción | Esfuerzo |
|-------|-------------|---------|
| Audit log service | Registrar eventos de seguridad en BD + logs | 2 días |
| Internal validate-session | Endpoint para Reports | 4 horas |
| Filesystem read-only | docker-compose.prod.yml | 1 hora |
| Rate limit en Nginx para auth | nginx.conf | 2 horas |
| Cookie prefix __Host- | auth.controller.ts | 1 hora |
| SAST en CI (CodeQL) | .github/workflows/security.yml | 2 horas |
| RBAC completo documentado | Roles en todos los endpoints | 1 día |
| Limit CSP report body | main.ts + nginx.conf | 1 hora |

**Definición de "hecho" para Fase 2:**
- Todos los endpoints de admin tienen `@Roles(UserRole.ADMIN)` o más restrictivo
- Audit log registra: login, logout, cambio de rol, refresh de token, acceso fallido
- CI rechaza cualquier commit que introduzca `'unsafe-eval'` o `'unsafe-inline'`

### Fase 3 — Largo Plazo (Meses 2-6) — Arquitectura Enterprise

**Objetivo:** Escalar el sistema para equipos múltiples y entornos de alta disponibilidad.

| Tarea | Descripción | Esfuerzo |
|-------|-------------|---------|
| HashiCorp Vault | Migrar secretos de Docker Secrets a Vault | 1 semana |
| mTLS entre servicios | TLS mutuo en red Docker interna | 1 semana |
| MFA (TOTP) | Autenticación de doble factor | 1 semana |
| Centralización de logs | Loki + Grafana (ya documentado en monitoring/) | 3 días |
| Circuit breaker Reports→Backend | Resiliencia en Reports | 2 días |
| SBOM (Software Bill of Materials) | Syft/Grype en CI | 1 día |
| Política de retención de logs | Cumplimiento regulatorio | 2 días |
| Disaster Recovery drill | Simulacro trimestral | Proceso |
| Penetration testing externo | Contratar pentest profesional | Externo |

**Arquitectura objetivo para múltiples desarrolladores:**
```
Equipo:
  - Desarrolladores: No acceso directo a producción. Deploy via CI/CD.
  - DevOps: Acceso a infraestructura vía VPN + MFA.
  - SUPERADMIN: Rotación de secretos, gestión de accesos.
  - Auditores: Solo lectura de audit logs (rol dedicado).

Entornos:
  - local:    Docker Compose local, datos sintéticos
  - staging:  VPS dedicado, secretos reales (rotación independiente de prod)
  - prod:     VPS prod, DR configurado, backup verificado semanalmente

Flujo de código:
  feature-branch → PR → Review (mínimo 1 aprobador) → CI/CD → staging → prod
```

---

## Conclusión

El proyecto demuestra una base arquitectónica sólida con decisiones de seguridad bien documentadas y justificadas. Los principales riesgos son **de implementación, no de diseño**: el sistema está correctamente diseñado para operar de forma segura, pero varios componentes están en estado de plantilla (AUTH_MODE=development, rotación de tokens pendiente, etc.).

La prioridad inmediata es completar la implementación de autenticación JWT real (Fase 1) antes de cualquier exposición pública, y llevar el rate limiting a un backend persistente (Redis). Con la Fase 1 completa, el sistema alcanza un nivel de seguridad adecuado para una primera versión productiva.

---

*Documento generado con base en análisis del código fuente, configuraciones de Docker Compose, archivos de infraestructura, y documentación del proyecto. Revisado contra OWASP Top 10 2021, OWASP ASVS 4.0, NIST CSF 2.0, ISO 27001:2022, y CIS Docker Benchmark 1.6.0.*

*Próxima revisión recomendada: Al completar Fase 1, o ante cualquier cambio arquitectónico significativo.*
