# ONBOARDING.md — Guía de Incorporación — NOMBRE_DEL_PROYECTO

> Bienvenido al proyecto. Esta guía te lleva de cero a entorno funcionando en ~30 minutos.

---

## Índice

- [Requisitos del sistema](#requisitos-del-sistema)
- [Checklist de instalación](#checklist-de-instalación)
- [Setup paso a paso](#setup-paso-a-paso)
- [Verificar que todo funciona](#verificar-que-todo-funciona)
- [Mapa del proyecto](#mapa-del-proyecto)
- [Flujo de trabajo diario](#flujo-de-trabajo-diario)
- [Comandos que usarás más](#comandos-que-usarás-más)
- [Recursos y documentación](#recursos-y-documentación)
- [Checklist final](#checklist-final)

---

## Requisitos del sistema

| Herramienta | Versión mínima | Instalación |
|---|---|---|
| Docker Engine | >= 20.10 | [docs.docker.com](https://docs.docker.com/engine/install/) |
| Docker Compose | >= 2.0 (plugin) | Incluido con Docker Desktop |
| GNU Make | >= 4.0 | `sudo apt install make` |
| Git | cualquier | `sudo apt install git` |
| PostgreSQL client | cualquier | `sudo apt install postgresql-client` |
| Node.js | >= 20 (opcional) | Solo si editas backend/frontend fuera de Docker |
| Python | >= 3.12 (opcional) | Solo si editas reports fuera de Docker |

Verificar todo de una vez:
```bash
make doctor
```

---

## Checklist de instalación

```
[ ] Docker Engine instalado y corriendo (docker ps no da error)
[ ] docker compose version >= 2.0
[ ] make --version >= 4.0
[ ] Acceso de escritura en /var/run/docker.sock (usuario en grupo docker)
[ ] PostgreSQL instalado en el host (no en Docker — ver ADR-006)
[ ] psql --version disponible
[ ] Puerto 5432 disponible (PostgreSQL host)
[ ] Puertos 3000, 4000, 5000 disponibles (servicios Docker)
```

Verificar puertos:
```bash
ss -tlnp | grep -E '3000|4000|5000|5432'
# Si salen resultados, hay algo ocupando esos puertos
```

---

## Setup paso a paso

### Paso 1 — Clonar el repositorio

```bash
git clone git@github.com:tu-org/nombre_del_proyecto.git
cd nombre_del_proyecto/docker-compose-config
```

### Paso 2 — Configurar variables de entorno

```bash
# Copiar la plantilla
cp .env.example .env

# Editar con tus valores locales (DB_PASSWORD, DB_USER, etc.)
nano .env
```

Variables mínimas que debes cambiar en `.env`:
```bash
DB_PASSWORD=tu_password_local     # cualquier valor para desarrollo
DB_USER=tu_usuario_local          # ej: nombre_del_proyecto_dev
DB_NAME=nombre_del_proyecto_dev               # nombre de la BD local
DB_HOST=host-gateway              # o 172.17.0.1 si host-gateway no funciona
```

### Paso 3 — Crear la base de datos local

```bash
# Asegurarse de que PostgreSQL está corriendo
sudo systemctl status postgresql

# Crear usuario y base de datos
sudo -u postgres psql -c "CREATE USER nombre_del_proyecto_dev WITH PASSWORD 'tu_password';"
sudo -u postgres psql -c "CREATE DATABASE nombre_del_proyecto_dev OWNER nombre_del_proyecto_dev;"

# Verificar
psql -U nombre_del_proyecto_dev -d nombre_del_proyecto_dev -h localhost -c "SELECT 1;"
```

### Paso 4 — Setup del proyecto

```bash
make setup
```

Esto realiza automáticamente:
- Valida que `.env` tiene todas las variables requeridas
- Construye las imágenes Docker de los 3 servicios
- Verifica que Docker Compose es válido

Si hay errores, leer el output y corregir antes de continuar.

### Paso 5 — Arrancar los servicios

```bash
make dev
```

Los servicios tardan ~30-60 segundos en arrancar la primera vez.

### Paso 6 — Verificar que funciona

```bash
make health-check
```

Deberías ver los 3 servicios en estado `healthy`.

---

## Verificar que todo funciona

Después del setup, verificar cada servicio:

```bash
# Backend (NestJS)
curl http://localhost:4000/health
# Esperado: {"status":"ok"} o similar

# Frontend (Next.js)
curl -I http://localhost:3000
# Esperado: HTTP/1.1 200 OK

# Reports (Python/Flask)
curl http://localhost:5000/health
# Esperado: {"status":"ok"}

# Swagger (solo en desarrollo)
# Abrir en navegador: http://localhost:4000/api/docs
```

Logs en tiempo real:
```bash
make logs              # Todos los servicios
make logs-backend      # Solo backend
make logs-frontend     # Solo frontend
make logs-reports      # Solo reports
```

---

## Mapa del proyecto

```
docker-compose-config/
│
├── 📋 DECISIONES DE ARQUITECTURA
│   └── DECISIONS.md           ← Leer primero — explica el "por qué" de cada decisión
│
├── 🐳 DOCKER COMPOSE
│   ├── docker-compose.yml          ← Base (todos los entornos)
│   ├── docker-compose.override.yml ← Desarrollo (auto-aplicado con make dev)
│   └── docker-compose.prod.yml     ← Producción (make prod)
│
├── ⚙️  SERVICIOS
│   ├── backend/                    ← NestJS API — Puerto 4000
│   │   ├── .docker/
│   │   │   ├── Dockerfile          ← Desarrollo
│   │   │   └── Dockerfile.prod     ← Producción (multi-stage)
│   │   └── src/
│   │       ├── main.ts             ← Punto de entrada, configuración global
│   │       ├── auth/               ← Autenticación JWT (esqueleto)
│   │       ├── health/             ← Endpoint /health
│   │       └── config/             ← TypeORM, secrets
│   │
│   ├── frontend/                   ← Next.js — Puerto 3000
│   │   ├── .docker/
│   │   │   ├── Dockerfile
│   │   │   └── Dockerfile.prod
│   │   └── src/app/                ← App Router de Next.js
│   │
│   └── reports/                    ← Python Flask — Puerto 5000
│       ├── .docker/
│       │   ├── Dockerfile
│       │   └── Dockerfile.prod
│       ├── main.py                 ← Punto de entrada Flask
│       └── src/
│           ├── config.py           ← pydantic-settings (validación al arrancar)
│           └── logging_config.py   ← structlog configurado
│
├── 🔧 INFRAESTRUCTURA
│   ├── Makefile                    ← Interfaz de todos los comandos
│   ├── .env.example                ← Plantilla de variables (versionar)
│   ├── .env.prod.example           ← Plantilla producción (versionar)
│   └── secrets/                    ← Credenciales producción (NO versionar)
│
├── 📊 MONITOREO (opcional)
│   ├── monitoring/
│   │   ├── prometheus.yml
│   │   ├── alertmanager.yml
│   │   └── alerts.yml
│   └── docker-compose.monitoring.yml
│
└── 📚 DOCUMENTACIÓN
    ├── README.md                   ← Desarrollo
    ├── README.prod.md              ← Producción
    ├── CONTRIBUTING.md             ← Cómo contribuir
    ├── CHANGELOG.md                ← Historial de cambios
    └── docs/
        ├── ARCHITECTURE.md         ← Diagrama de arquitectura
        ├── ENV-VARIABLES.md        ← Todas las variables documentadas
        ├── DISASTER-RECOVERY.md    ← Recuperación ante desastres
        ├── guides/                 ← Guías detalladas por servicio
        └── auditorias/             ← Reportes de auditoría
```

---

## Flujo de trabajo diario

### Al empezar el día

```bash
cd docker-compose-config

# Actualizar código
git pull origin develop

# Si cambiaron Dockerfiles o package.json
make rebuild       # Reconstruye imágenes

# Si solo cambió código fuente
make dev           # Arranca (hot reload activo)
```

### Durante el desarrollo

Hot reload está activo en todos los servicios:
- **Backend:** NestJS reinicia automáticamente al cambiar `.ts`
- **Frontend:** Next.js recarga el navegador al cambiar componentes
- **Reports:** Flask reinicia al cambiar `.py`

No necesitas reconstruir la imagen para cambios de código.

### Al terminar el día

```bash
make stop          # Para los contenedores (conserva datos)
# O
make down          # Para y elimina contenedores (BD conservada en host)
```

### Antes de hacer un commit

Ver `CONTRIBUTING.md` para el checklist completo.

---

## Comandos que usarás más

```bash
# ── Desarrollo ──────────────────────────────────────────────────
make dev            # Arranca los 3 servicios con logs
make stop           # Para los servicios
make restart        # Para + arranca
make logs           # Ver logs de todos los servicios
make shell-backend  # Shell dentro del contenedor backend
make shell-reports  # Shell dentro del contenedor reports

# ── Base de datos ───────────────────────────────────────────────
make backup-db      # Backup de PostgreSQL
make rollback-db    # Restaurar último backup
make db-migrate     # Ejecutar migraciones pendientes (cuando estén configuradas)

# ── Verificación ────────────────────────────────────────────────
make validate       # Valida docker-compose files
make validate-env   # Verifica que .env tiene todas las variables
make health-check   # Estado de los 3 servicios
make doctor         # Estado del entorno completo

# ── Seguridad ───────────────────────────────────────────────────
make audit-full     # Pipeline completo de auditoría
make lint-docker    # Hadolint en todos los Dockerfiles

# ── Limpieza ────────────────────────────────────────────────────
make clean          # Elimina contenedores y logs locales
make prune          # Elimina imágenes no usadas (libera disco)
```

Ver todos los comandos disponibles:
```bash
make help
```

---

## Recursos y documentación

| Documento | Qué encontrarás |
|---|---|
| `DECISIONS.md` | **Leer primero.** Por qué PostgreSQL en el host, por qué pnpm, por qué multi-stage, etc. |
| `README.md` | Guía de desarrollo completa |
| `README.prod.md` | Guía de deploy en producción |
| `docs/ARCHITECTURE.md` | Diagrama de arquitectura y flujo de datos |
| `docs/ENV-VARIABLES.md` | Todas las variables de entorno documentadas |
| `docs/guides/BACKEND-NESTJS.md` | NestJS: auth, validación, Swagger, testing |
| `docs/guides/FRONTEND-NEXTJS.md` | Next.js: App Router, variables públicas, standalone |
| `docs/guides/REPORTS-PYTHON.md` | Flask: pydantic-settings, gunicorn, structlog |
| `CONTRIBUTING.md` | Convención de commits, branches, flujo de PRs |
| `TESTING.md` | Estrategia de testing y cobertura |
| `MIGRATION-GUIDE.md` | Migraciones TypeORM paso a paso |

---

## Checklist final

Antes de tu primer commit, verificar que completaste:

```
ENTORNO
[ ] make doctor → todo verde
[ ] make dev → los 3 servicios healthy
[ ] curl localhost:4000/health → {"status":"ok"}
[ ] curl localhost:3000 → HTTP 200
[ ] curl localhost:5000/health → {"status":"ok"}

CONOCIMIENTO
[ ] Leí DECISIONS.md (especialmente ADR-001 a ADR-006)
[ ] Leí CONTRIBUTING.md (convención de commits y branches)
[ ] Entendí la estructura de docker-compose (base + override + prod)
[ ] Sé usar make help para ver todos los comandos disponibles

GIT
[ ] git config user.email configurado con tu email corporativo
[ ] git config user.name configurado
[ ] Acceso al repositorio verificado (git fetch)
[ ] Entiendo el flujo: feature/xxx → develop → main

PRIMER CAMBIO
[ ] Crear rama: git checkout -b feature/onboarding-test
[ ] Hacer un cambio trivial (ej: añadir un comentario)
[ ] make validate → pasa sin errores
[ ] git commit -m "chore: verificar onboarding"
[ ] PR abierto como borrador
```

Si algún punto falla o no está claro, consultar `docs/` o abrir un issue con la etiqueta `onboarding`.
