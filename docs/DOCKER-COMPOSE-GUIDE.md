# DOCKER-COMPOSE-GUIDE.md — Guía de Arquivos Docker Compose

> **Última actualización:** Marzo 2026

---

## Estructura de capas

```
docker-compose.yml            ← BASE: servicios comunes a todos los entornos
docker-compose.override.yml   ← DEV: se aplica automáticamente en desarrollo
docker-compose.prod.yml       ← PROD: se aplica manualmente en producción
docker-compose.monitoring.yml ← OPCIONAL: stack Prometheus + Grafana
```

**Cómo se combinan:**

```bash
# Desarrollo (automático — Docker aplica override.yml sin pedirlo)
docker compose up
# = docker-compose.yml + docker-compose.override.yml

# Producción (manual — hay que especificar los dos archivos)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up
# = docker-compose.yml + docker-compose.prod.yml
# (override.yml NO se aplica)

# Monitoreo (archivo adicional separado)
docker compose -f docker-compose.monitoring.yml up
```

> Usar siempre `make dev`, `make prod`, `make monitoring-up` en lugar de los comandos
> largos — el Makefile gestiona las combinaciones correctas automáticamente.

---

## docker-compose.yml — Base

Contiene lo que es **igual en todos los entornos**:
- Definición de los 3 servicios (backend, frontend, reports-api)
- Build context y Dockerfile de desarrollo
- Variables de entorno no sensibles
- Healthchecks (Nivel 1)
- Red `nombre_del_proyecto-private`

**Lo que NO incluye:**
- `depends_on` hacia postgres (solo en dev, via override)
- Puertos (definidos por el entorno)
- Secretos (solo en producción)
- Límites de recursos (solo en producción)

---

## docker-compose.override.yml — Desarrollo

Se aplica **automáticamente** cuando ejecutas `docker compose up` sin especificar archivo.

Añade en desarrollo:
- Servicio `postgres` con PostgreSQL 17
- `depends_on: postgres` para backend y reports-api
- Puertos expuestos (`0.0.0.0:PORT:PORT`)
- Volúmenes para hot reload
- Variables de entorno de desarrollo (`DB_PASSWORD`, `LOG_LEVEL=debug`)
- Logs con menos retención

**Lo que NO incluye:**
- `restart` (en dev queremos ver los errores)
- `read_only` (en dev necesitamos escribir para hot reload)
- `mem_limit` / `cpus` (en dev no limitamos recursos)
- `secrets` (en dev usamos variables de entorno directas)

---

## docker-compose.prod.yml — Producción

Requiere especificarse **explícitamente**: `docker compose -f docker-compose.yml -f docker-compose.prod.yml up`

Añade en producción:
- Imagen con tag (no build local)
- Puertos bound a `127.0.0.1:PORT:PORT`
- Docker Secrets (`/run/secrets/`)
- Hardening: `read_only`, `cap_drop: ALL`, `no-new-privileges`, `pids_limit`
- Límites de recursos: `mem_limit`, `memswap_limit`, `cpus`
- Log rotation
- Red `internal: true`
- `extra_hosts: host-gateway` para acceder a PostgreSQL en el host
- `depends_on: backend: condition: service_healthy` para reports-api

---

## docker-compose.monitoring.yml — Monitoreo

Stack **completamente separado** y opcional.

Servicios:
- **Prometheus** — recolecta métricas (backend, reports, node-exporter, cadvisor)
- **Grafana** — dashboards visuales
- **Node Exporter** — métricas del servidor host (CPU, RAM, disco)
- **cAdvisor** — métricas de contenedores Docker
- **Alertmanager** (solo con `--profile prod-alerting`)

```bash
# Levantar sin Alertmanager (desarrollo/staging)
make monitoring-up

# Levantar con Alertmanager (producción)
make monitoring-up-prod

# Ver dashboards
# Acceder por SSH tunnel: ssh -L 3001:127.0.0.1:3001 usuario@servidor
# Luego abrir: http://localhost:3001
```

---

## Redes

| Red | Configuración | Propósito |
|---|---|---|
| `nombre_del_proyecto-private` | `internal: true` en prod | Comunicación entre servicios sin acceso a internet |
| `nombre_del_proyecto-private` | `bridge` en dev | Sin `internal: true` para facilitar debugging |
| `monitoring` | `bridge` | Red separada para el stack de monitoreo |

**¿Por qué `internal: true` en prod?**
Los contenedores no deben hacer requests a internet en runtime. Sus dependencias
se instalan en build time. Si un contenedor es comprometido, `internal: true`
previene la exfiltración de datos a internet.

---

## Secretos (solo producción)

```yaml
# Definición global
secrets:
  db_password:
    file: ./secrets/db_password.txt

# Montaje en el servicio
services:
  backend:
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password  # la app lee este archivo
```

La app lee el secreto con:
```javascript
fs.readFileSync(process.env.DB_PASSWORD_FILE, 'utf8').trim()
```

---

## Variables de entorno vs secretos

```yaml
# ✅ Variable de entorno: no sensible
environment:
  NODE_ENV: production
  DB_HOST: host-gateway
  PORT: 4000

# ✅ Secreto: sensible (montado como archivo)
secrets:
  - db_password    # → /run/secrets/db_password
  - db_user        # → /run/secrets/db_user

# ❌ NUNCA: credencial en variable de entorno
environment:
  DB_PASSWORD: mi_password  # visible en docker inspect
```

---

## Comandos útiles

```bash
make config          # Ver configuración resuelta de todos los compose files
make validate        # Validar YAML y detectar errores de sintaxis
make doctor          # Verificar entorno y archivos críticos

# Desarrollo
make dev             # Levantar con logs en pantalla
make dev-bg          # Levantar en segundo plano
make stop            # Detener
make clean           # Eliminar contenedores + volúmenes

# Producción
make prod            # Deploy (validaciones + migraciones + up)
make secrets-init    # Crear archivos de secretos (primera vez)
make secrets-check   # Verificar que los secretos están configurados
```
