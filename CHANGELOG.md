# CHANGELOG

Todos los cambios notables del proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.0.0/),
y el proyecto usa [Calendar Versioning — CalVer](https://calver.org/) (`YYYY.MM.DD`).

---

## [Sin lanzar] — Pendiente

### Por añadir
- Completar implementación de métricas de negocio (ver `docs/guides/MONITORING-BUSINESS-METRICS.md`)
- Implementar `AuthService.register()` y `AuthService.login()` completos
- Activar umbral de cobertura Python al 20% (`reports/setup.cfg`) cuando se añada lógica de negocio real
- Migrar `refresh()` a lectura de cookie httpOnly cuando `login()` esté implementado (ADR-022)

---

## [2026.03.19] — Auditoría v5

### Añadido
- `DECISIONS.md` — ADR-019: Logging estructurado con structlog y json-file
- `DECISIONS.md` — ADR-020: Estrategia de CORS con lista explícita de orígenes
- `DECISIONS.md` — ADR-021: Política de cobertura de tests progresiva
- `DECISIONS.md` — ADR-022: Almacenamiento de tokens JWT con httpOnly Cookies (migración desde localStorage)
- `DECISIONS.md` ADR-001 — escalation path documentado para Gunicorn: APScheduler → ARQ → FastAPI+Granian

### Cambiado
- `DECISIONS.md` — índice actualizado con ADR-018 a ADR-022 (ADR-018 faltaba desde su creación)
- `DECISIONS.md` — `Última actualización` actualizada a 19 de marzo de 2026 — Auditoría v5
- `CHANGELOG.md` — declaración de versionado corregida de SemVer a CalVer
- `scripts/setup.sh` — generación automática de `JWT_SECRET` con `openssl rand -base64 48` al crear `.env` dev
- `scripts/setup.sh` — verificación de `make` instalado antes de usarlo (paso 2)
- `scripts/setup.sh` — `DB_PASSWORD` se pasa via `PGPASSWORD` en lugar de interpolarse en el heredoc SQL (previene fallo con contraseñas con comillas o caracteres especiales)
- `scripts/setup.sh` — fallback de editor cambiado de `nano` a `vi` (disponible en todos los sistemas POSIX)
- `scripts/setup.sh` — añadido `make db-migrate` al resumen de comandos útiles en modo desarrollo
- `scripts/deploy-prod.sh` — añadido `jwt_secret.txt` al loop de verificación de secretos (A-02)
- `frontend/middleware.ts` — `style-src` usa nonce en lugar de `'unsafe-inline'` — elimina vector de CSS injection (M-01)
- `frontend/middleware.ts` — añadido `upgrade-insecure-requests` en producción
- `frontend/src/lib/api.ts` — mensajes de error genéricos al cliente via `getErrorMessage(status)` — elimina exposición de `statusText` (M-02)
- `frontend/src/lib/api.ts` — migración completa de `localStorage` a `credentials: 'include'` para auth via cookies httpOnly (C-02 / ADR-022)
- `frontend/src/lib/api.ts` — añadida clase `ApiError` con código HTTP para manejo específico por status
- `frontend/src/lib/api.ts` — añadidos métodos `put`, `patch`, `delete` al objeto `api`
- `backend/src/auth/auth.controller.ts` — `login()` y `register()` lanzan `NotImplementedException` consistente (A-04)
- `backend/src/auth/auth.controller.ts` — preparado para emitir/limpiar cookies httpOnly en login/logout/refresh (C-02 / ADR-022)
- `backend/src/auth/auth.controller.ts` — `@ApiBearerAuth()` reemplazado por `@ApiCookieAuth()` donde aplica
- `backend/src/auth/auth.service.ts` — eliminado código muerto (implementación comentada duplicada al inicio del archivo) (A-03)
- `backend/src/auth/guards/jwt-auth.guard.ts` — protección contra deploy en producción: lanza `InternalServerErrorException` si `NODE_ENV=production` y `AUTH_MODE≠real` (A-01)
- `backend/src/app.module.ts` — eliminado comentario de ejemplo huérfano después del `export class AppModule {}` (M-06)
- `reports/main.py` — renombrado `get_engine_connection()` a `build_database_url()` — refleja que retorna una URL, no una conexión (M-04)
- `reports/main.py` — corregida numeración de secciones: segunda sección `# ── 7.` renombrada a `# ── 8.` (M-03)
- `reports/main.py` — separación de `APP_ENV` (modo de la app) y `APP_ENV` (debug mode de Flask): ya no se confunden (A-05)

### Corregido
- `CONTRIBUTING.md` — typo en anchor del índice: `#colitica-de-cobertura` → `#política-de-cobertura-de-tests`
- `backend/src/auth/auth.controller.ts` — inconsistencia: `refresh()` llamaba a `authService` real mientras `login()` devolvía placeholder; ahora ambos son consistentemente `NotImplementedException` hasta implementación completa (A-04)

---

## [2026.03.12] — Auditoría v4

### Añadido
- `backend/src/common/decorators/public.decorator.ts` — decorator `@Public()` faltante (referenciado en 2 archivos pero nunca creado, rompía compilación)
- `backend/src/auth/strategies/jwt.strategy.ts` — estrategia JWT movida a ubicación correcta dentro del módulo auth
- `docs/guides/MONITORING-BUSINESS-METRICS.md` — guía completa con Counter, Histogram, Gauge para NestJS y Flask, dashboard Grafana y alertas
- `reports/src/logging_config.py` — configuración centralizada de structlog (JSON en prod, colores en dev)

### Cambiado
- `backend/tsconfig.json` — corregido `moduleResolution: "Node16"` (elimina deprecation warning de node10)
- `Makefile` — `audit-npm` renombrado a `audit-pnpm`; `audit-npm` queda como alias de retrocompatibilidad
- `Makefile` — `secrets-init` genera `secrets/jwt_secret.txt` automáticamente con `openssl rand -base64 48`
- `Makefile` — `secrets-check` verifica también `secrets/jwt_secret.txt`
- `reports/main.py` — integración de structlog con contexto de request (request_id en todos los logs)
- `docs/MONITORING-ROADMAP.md` — estado actualizado de "Pendiente" a implementado por componente
- `docs/ENV-VARIABLES.md` — añadidas secciones `JWT_SECRET`, `JWT_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN`, `SLACK_WEBHOOK_URL`
- `.env.prod.example` — añadidas variables JWT y SLACK_WEBHOOK_URL
- `docs/DATA-DICTIONARY.md` — tabla de secretos actualizada con `grafana_password.txt` y `jwt_secret.txt`
- `docs/DISASTER-RECOVERY.md` — añadidos escenarios 5 (Alertmanager/Slack) y 6 (JWT inválido tras deploy)
- `monitoring/alerts.yml` — `severity` movido dentro de `labels:` (routing de Alertmanager no funcionaba)
- `Makefile` — añadidos targets `monitoring-up-prod`, `monitoring-alert-test`, `validate-env-prod`
- `Makefile` — `validate-env` lee dinámicamente de `.env.example` en lugar de lista hardcodeada de 16 vars

### Corregido
- `@Public()` decorator referenciado en `auth.controller.ts` y `jwt-auth.guard.ts` pero el archivo fuente no existía — rompía compilación
- `jwt.strategy.ts` vivía en `src/extender/strategies/` pero era importado desde `src/auth/strategies/` — rutas inconsistentes
- `alerts.yml` tenía `severity` al mismo nivel que `annotations` — Alertmanager no podía hacer routing por severidad
- `validate-env` no detectaba nuevas variables añadidas a `.env.example` (lista hardcodeada desactualizada)
- `tsconfig.json` tenía `moduleResolution: "node"` (alias deprecado de node10) — genera advertencia desde TS 5.x

---

## [2026.03.11] — Auditoría v3

### Añadido
- `docs/guides/MONITORING-ALERTMANAGER.md` — documentación completa de Alertmanager
- `docs/guides/MONITORING-LOKI-PROMTAIL.md` — documentación de Loki, Promtail y ELK como alternativa
- `frontend/src/app/error.tsx` — error boundary global del App Router
- `frontend/src/app/loading.tsx` — skeleton de carga global del App Router
- `backend/src/auth/auth.module.ts` — módulo auth completo (plantilla sin lógica)
- `backend/src/auth/dto/login.dto.ts` y `register.dto.ts` — DTOs con validación
- `backend/src/auth/guards/jwt-auth.guard.ts` — guard JWT template
- `backend/src/auth/strategies/jwt.strategy.ts` — estrategia JWT template

### Cambiado
- `monitoring/prometheus.yml` — añadidos rule_files y alerting hacia Alertmanager
- `reports/tests/test_health.py` — reemplazado placeholder `assert True` con tests reales
- `.github/workflows/ci.yml` — migrado de npm a pnpm, añadido pnpm audit para backend y frontend
- `docker-compose.monitoring.yml` — Alertmanager con profile `prod-alerting`

### Corregido
- CI usaba `npm ci` en proyecto con `pnpm-lock.yaml` — corregido a `pnpm install --frozen-lockfile`
- `monitoring/prometheus.yml` no conectaba con Alertmanager ni cargaba `alerts.yml`
- `SLACK_WEBHOOK_URL` faltaba en `.env.example`

---

## [2026.02.27] — Auditoría v2

### Añadido
- `docs/` — carpeta de documentación técnica del proyecto
- `docs/ENV-VARIABLES.md` — guía completa de todas las variables de entorno y secretos
- `docs/ARCHITECTURE.md` — diagrama oficial de arquitectura con Mermaid
- `CHANGELOG.md` — este archivo
- `CONTRIBUTING.md` — guía de contribución al proyecto
- `DECISIONS.md` — 17 ADRs completamente documentados con justificación y alternativas
- `docker-compose.override.yml` mejorado con documentación exhaustiva y soporte WSL2

### Cambiado
- `.env.example` — añadidos `DB_USER` y `DB_PASSWORD` (faltaban, rompían CI)
- `.env.prod.example` — eliminado `DB_HOST` duplicado
- `docker-compose.prod.yml` — añadido `extra_hosts: host-gateway` en backend y reports-api
- `ci.yml` — scan y SARIF para los 3 servicios (antes solo backend)
- `Makefile` — añadido target `validate-env` para verificar variables requeridas

### Corregido
- `security.yml` — sintaxis YAML correcta en job `trivy` (las llaves `name:` y `uses:` estaban desalineadas)
- `grype-scan` — ahora incluye frontend (antes solo backend y reports)

---

## [2026.02.26] — Auditoría v1

### Añadido
- `DECISIONS.md` — primeros 5 ADRs
- Sección `## 🔧 Troubleshooting` en `README.md` (9 escenarios)
- `make validate-build` — build desde cero para CI
- `make grype-scan-docker` — escaneo via Docker sin instalar grype localmente

### Cambiado
- `README.md` — corregidas referencias a `make check-tools` → `make doctor`
- `docker-compose.prod.yml` — `version: "3.8"` eliminado (deprecated en Compose v2)

---

## [2026.02.24] — Configuración inicial de producción

### Añadido
- `docker-compose.prod.yml` — configuración de producción con Docker Secrets
- `docker-compose.override.yml` — configuración de desarrollo con hot reload
- `README.prod.md` — guía completa de deploy en servidor
- `.env.prod.example` — plantilla de variables de producción
- `scripts/deploy-prod.sh` — script de deploy
- `.github/workflows/deploy.yml` — deploy automático en push de tags

### Cambiado
- `docker-compose.prod.yml` — `mem_limit`/`cpus` en lugar de `deploy.resources` (que solo funciona en Swarm)
- Backend y reports-api: `extra_hosts: host-gateway:host-gateway`

---

## [2026.02.20] — CI/CD y seguridad

### Añadido
- `.github/workflows/ci.yml` — pipeline completo: validate → build → test × 3 → scan × 3 → sbom × 3
- `.github/workflows/security.yml` — hadolint + trivy en PRs
- `.hadolint.yaml` — configuración de hadolint
- `.github/renovate.json` — actualización automática de digests SHA256
- `Makefile` — dashboard, modo estricto, `make audit-full`, `make doctor`, `make troubleshoot`
- `scripts/setup.sh` — setup interactivo dev y prod

### Seguridad añadida
- Hardening de contenedores prod: `read_only`, `cap_drop: ALL`, `no-new-privileges`
- `pids_limit`, `ulimits`, `tmpfs` en todos los servicios de producción
- Puertos bound a `127.0.0.1` en producción

---

## [2026.02.15] — Estructura inicial

### Añadido
- `docker-compose.yml` — configuración base con 3 servicios
- `backend/.docker/Dockerfile` + `Dockerfile.prod`
- `frontend/.docker/Dockerfile` + `Dockerfile.prod`
- `reports/.docker/Dockerfile` + `Dockerfile.prod`
- `.env.example` — plantilla de variables de entorno
- `README.md` — documentación inicial
- `reports/requirements.in` + `requirements.txt`
- `.gitignore` — exclusiones estándar Node.js + secretos + env production
