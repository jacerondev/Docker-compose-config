# SECURITY.md — Política de seguridad

**Proyecto:** NOMBRE_DEL_PROYECTO
**Última actualización:** Marzo 2026

---

## Versiones soportadas

| Versión              | Soporte de seguridad |
| -------------------- | -------------------- |
| `main` (última)      | ✅ Activo            |
| Versiones anteriores | ❌ No soportadas     |

Este proyecto sigue un modelo de rama única (`main`). Solo la última versión en `main` recibe correcciones de seguridad.

---

## Cómo reportar una vulnerabilidad

**No abras un issue público** para reportar vulnerabilidades de seguridad.
Los issues públicos son visibles para todos antes de que el problema esté resuelto.

### Canal preferido

Envía un email a: `devopsNombreEmpresa@gmail.com`

Con el asunto: `[SECURITY] Descripción breve del problema`

### Qué incluir en el reporte

Para ayudarnos a reproducir y evaluar el problema, incluye:

- Descripción clara de la vulnerabilidad
- Componente afectado (backend, frontend, reports-api, docker-compose, CI/CD)
- Pasos para reproducirlo
- Impacto potencial (qué datos o accesos quedarían expuestos)
- Versión del commit o tag afectado
- Si tienes un fix propuesto, es bienvenido (pero no requerido)

---

## Tiempo de respuesta

| Etapa                                         | Tiempo objetivo  |
| --------------------------------------------- | ---------------- |
| Acuse de recibo                               | 48 horas hábiles |
| Confirmación de si es válida o no             | 5 días hábiles   |
| Corrección para vulnerabilidades críticas     | 14 días          |
| Corrección para vulnerabilidades medias/bajas | 30 días          |

Si no recibes respuesta en 48 horas hábiles, reenvía el email con `[SEGUIMIENTO]` en el asunto.

---

## Divulgación coordinada

Nuestro proceso es:

1. Recibes el reporte → confirmamos recepción
2. Reproducimos y evaluamos la severidad (CVSS)
3. Desarrollamos y probamos el fix
4. Hacemos deploy del fix
5. Publicamos un aviso en el CHANGELOG con los detalles técnicos
6. Si lo deseas, te mencionamos como descubridor (con tu permiso)

Pedimos que no divulgues públicamente la vulnerabilidad hasta que hayamos publicado el fix (máximo 90 días desde el reporte inicial).

---

## Controles de seguridad implementados

Para contexto al evaluar reportes, estos son los controles activos:

**Contenedores:**

- `read_only: true` — filesystem de solo lectura
- `cap_drop: ALL` — sin capacidades Linux
- `no-new-privileges: true` — procesos no pueden escalar privilegios
- `pids_limit` — límite de procesos por contenedor
- Usuario no-root en todos los contenedores

**Secretos:**

- Docker Secrets sin Swarm (archivos en `./secrets/`, nunca en variables de entorno)
- Credenciales de DB nunca en logs ni en `.env.production`

**Red:**

- Puertos bound a `127.0.0.1` en producción (solo accesibles via Nginx)
- Red Docker con `internal: true` (sin acceso a internet desde los contenedores)

**CI/CD:**

- Escaneo de imágenes con Trivy (CRITICAL/HIGH bloquean el pipeline)
- SAST con Semgrep y Bandit
- SBOM generado con Syft en cada build
- `pnpm audit` para dependencias Node.js
- Renovate para actualización automática de digests SHA256

**Aplicación:**

- Helmet.js con headers de seguridad HTTP
- CORS restringido a orígenes declarados
- Rate limiting con ThrottlerModule (NestJS) y Nginx
- Validación de inputs con class-validator (whitelist + forbidNonWhitelisted)
- GlobalExceptionFilter: no expone stack traces al cliente

**Autenticación (estado actual):**

- Guard global activo: `JwtAuthGuard` aplicado a todos los endpoints
- Modo temporal: inyecta usuario mock (no requiere token real)
- Endpoints públicos: `/api/auth/login`, `/api/auth/register`, `/health` (decorator `@Public()`)

---

## Vulnerabilidades conocidas / en seguimiento

_(Ninguna actualmente)_

---

## Reconocimientos

_(Nadie reportado aún — sé el primero)_

---

## Mapeo de controles OWASP Top 10 (2021)

| OWASP | Categoría | Control implementado | Estado |
|-------|-----------|----------------------|--------|
| A01 | Broken Access Control | `JwtAuthGuard` global + `@Public()` explícito; `RolesGuard` con RBAC | 🟡 Parcial — AUTH_MODE=development |
| A02 | Cryptographic Failures | HSTS en producción; cookies `Secure`+`HttpOnly`+`SameSite=Strict`; secretos via Docker Secrets nunca en env vars | ✅ Activo |
| A03 | Injection | `ValidationPipe` con `whitelist`+`forbidNonWhitelisted`; TypeORM con parámetros (no concatenación SQL); Pydantic en Python | ✅ Activo |
| A04 | Insecure Design | Rate limiting por endpoint (Throttler + flask-limiter); CSP con nonce; red Docker `internal:true` | 🟡 Parcial — ver ADR-024 |
| A05 | Security Misconfiguration | Helmet.js; `read_only:true`; `cap_drop:ALL`; Swagger bloqueado en producción; `no-new-privileges:true` | ✅ Activo |
| A06 | Vulnerable Components | Trivy (SARIF → GitHub Security); Semgrep OWASP rules; Bandit; Renovate con SHA256 | ✅ Activo |
| A07 | Auth Failures | Throttling en login (5/min) y registro (3/hora); httpOnly cookies; fail-fast si `AUTH_MODE!=real` en prod | 🟡 Parcial — auth sin implementar |
| A08 | Software Integrity | Imágenes con digest SHA256; `pnpm --frozen-lockfile`; SBOM con Syft | ✅ Activo |
| A09 | Logging Failures | structlog con JSON en producción; `GlobalExceptionFilter` sin stack en prod; `X-Request-Id` para trazabilidad | ✅ Activo |
| A10 | SSRF | Red Docker `internal:true` — contenedores no acceden a internet; `NESTJS_AUTH_URL` restringida a red interna | ✅ Activo |

### Herramientas de verificación activas

| Herramienta | Tipo | Cuándo corre | Qué detecta |
|-------------|------|-------------|-------------|
| Trivy | SCA + DAST image | Cada PR y push a main | CVEs en dependencias e imágenes |
| Semgrep | SAST | Cada PR | Vulnerabilidades en TypeScript/Python; OWASP Top 10 |
| Bandit | SAST Python | Cada PR | Vulnerabilidades específicas de Python/Flask |
| Hadolint | Linting | Cada PR | Malas prácticas en Dockerfiles |
| Renovate | Dependencias | Cada fin de semana | Actualizaciones con SHA256 |
| docker-bench-security | CIS Benchmark | Manual (ver más abajo) | Configuración del daemon Docker |
| Lynis | OS Hardening | Manual (ver más abajo) | Configuración del sistema operativo |
| pip-audit | SCA Python | Cada PR (audit.yml) | CVEs en dependencias Python |
| pnpm audit | SCA Node.js | Cada PR (audit.yml) | CVEs en dependencias Node.js |
| OSV Scanner | SCA multi-ecosistema | Manual / opcional | CVEs cruzados entre ecosistemas |
| Grype | SCA + imágenes | Manual / opcional | Alternativa a Trivy para SBOMs |