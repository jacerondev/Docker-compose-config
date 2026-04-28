# DECISIONS.md — Registro de Decisiones de Arquitectura (ADR)

> **¿Qué es un ADR?**
> Un Architecture Decision Record documenta una decisión técnica significativa: el contexto que la originó, las alternativas consideradas, la decisión tomada y las consecuencias. Sirve para que el equipo (y el futuro tú) entienda *por qué* las cosas son como son.

**Proyecto:** NOMBRE_DEL_PROYECTO docker-compose-config
**Última actualización:** 25 de marzo de 2026

---

## Índice

- [ADR-001: Gunicorn con gthread para reports](#adr-001-gunicorn-con-gthread-para-reports)
- [ADR-002: Next.js standalone output en frontend](#adr-002-nextjs-standalone-output-en-frontend)
- [ADR-003: tini como ENTRYPOINT en backend y frontend](#adr-003-tini-como-entrypoint-en-backend-y-frontend)
- [ADR-004: Puertos bound a 127.0.0.1 en producción](#adr-004-puertos-bound-a-127001-en-producción)
- [ADR-005: Wheels precompiladas en reports builder](#adr-005-wheels-precompiladas-en-reports-builder)
- [ADR-006: PostgreSQL y Nginx en el host, fuera de Docker](#adr-006-postgresql-y-nginx-en-el-host-fuera-de-docker)
- [ADR-007: host-gateway para conectar contenedores con PostgreSQL](#adr-007-host-gateway-para-conectar-contenedores-con-postgresql)
- [ADR-008: Separación de archivos .env por entorno](#adr-008-separación-de-archivos-env-por-entorno)
- [ADR-009: Docker Secrets sin Swarm (archivos en ./secrets/)](#adr-009-docker-secrets-sin-swarm-archivos-en-secrets)
- [ADR-010: mem_limit y cpus en lugar de deploy.resources](#adr-010-mem_limit-y-cpus-en-lugar-de-deployresources)
- [ADR-011: Red interna con internal: true en producción](#adr-011-red-interna-con-internal-true-en-producción)
- [ADR-012: No migrar a Kubernetes/K3s (decisión explícita)](#adr-012-no-migrar-a-kubernetesk3s-decisión-explícita)
- [ADR-013: GitHub Actions como plataforma CI/CD](#adr-013-github-actions-como-plataforma-cicd)
- [ADR-014: Pipeline de auditoría local (make audit-full)](#adr-014-pipeline-de-auditoría-local-make-audit-full)
- [ADR-015: Makefile como interfaz única de operación](#adr-015-makefile-como-interfaz-única-de-operación)
- [ADR-016: Estrategia de healthchecks por capas](#adr-016-estrategia-de-healthchecks-por-capas)
- [ADR-017: Renovate para actualización automática de imágenes base](#adr-017-renovate-para-actualización-automática-de-imágenes-base)
- [ADR-018: Express como plataforma HTTP (no Fastify)](#adr-018-express-como-plataforma-http-no-fastify)
- [ADR-019: Logging estructurado con structlog y json-file](#adr-019-logging-estructurado-con-structlog-python-y-json-file-docker)
- [ADR-020: Estrategia de CORS — lista explícita de orígenes](#adr-020-estrategia-de-cors--lista-explícita-de-orígenes)
- [ADR-021: Política de cobertura de tests progresiva](#adr-021-política-de-cobertura-de-tests-progresiva)
- [ADR-022: Almacenamiento de tokens JWT — httpOnly Cookies](#adr-022-almacenamiento-de-tokens-jwt--httponly-cookies-en-lugar-de-localstorage)
- [ADR-023: SSL en conexión a PostgreSQL — desactivado con justificación explícita](#adr-023-ssl-en-conexión-a-postgresql--desactivado-con-justificación-explícita)
- [ADR-024 — Rate limiting granular en Reports API](#adr-024--rate-limiting-granular-en-reports-api)
- [ADR-025 — Gestión de secretos: Docker Secrets vs HashiCorp Vault OSS](#adr-025--gestión-de-secretos-docker-secrets-vs-hashicorp-vault-oss)
- [ADR-026 — Reports-API delega validación de sesión al backend](#adr-026--reports-api-delega-validación-de-sesión-al-backend)
- [ADR-027 — Perfil seccomp: perfil por defecto de Docker en lugar de perfil personalizado](#adr-027--perfil-seccomp-perfil-por-defecto-de-docker-en-lugar-de-perfil-personalizado)
- [ADR-028 — WAF (Web Application Firewall): ausente con justificación explícita](#adr-028--waf-web-application-firewall-ausente-con-justificación-explícita)
- [ADR-029: SameSite en Cookies de Autenticación](#adr-029-samesite-en-cookies-de-autenticación)
- [ADR-030: SPA navegación cross-site: Uso de SameSite](#adr-030-spa-navegación-cross-site-uso-de-samesite)
- [ADR-031: Desactivar DB_SSL_REQUIRED en entornos controlados](#adr-031-desactivar-db_ssl_required-en-entornos-controlados)
- [ADR-032: Desactivar ejecución automática de scripts en gestores de paquetes (ignore-scripts)](#adr-032-desactivar-ejecución-automática-de-scripts-en-gestores-de-paquetes-ignore-scripts)
- [ADR-033: /metrics en el mismo puerto que la API](#adr-033-metrics-en-el-mismo-puerto-que-la-api)
- [ADR-034: Firma de Imágenes de Contenedor con Cosign](#adr-034-firma-de-imágenes-de-contenedor-con-cosign)
- [ADR-035: Lectura del Pepper de Contraseñas — Tiempo de Módulo vs Lazy](#adr-035-lectura-del-pepper-de-contraseñas--tiempo-de-módulo-vs-lazy)
- [ADR-036: Gestión de Secretos en Equipo — Infisical vs Vault vs Docker Secrets](#adr-036-gestión-de-secretos-en-equipo--infisical-vs-vault-vs-docker-secrets)
- [Matriz de riesgos](#matriz-de-riesgos)

---

## ADR-001: Gunicorn con gthread para reports

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

El servicio `reports-api` procesa reportes Excel/CSV con Pandas. Las operaciones mezclan:
- I/O intensivo (lectura de DB, escritura de archivos)
- CPU moderado (transformaciones Pandas)
- Requests concurrentes de múltiples usuarios

Se necesitaba un servidor WSGI para producción (Flask dev server no es apto).

### Decisión

```
gunicorn --worker-class gthread \
         --threads 4 \
         --timeout 300 \
         --max-requests 200 \
         --worker-tmp-dir /dev/shm
```

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| `sync` (1 worker) | Bloqueante — un reporte lento bloquea todos los demás |
| `gevent` | Overhead para operaciones CPU-bound; Pandas no libera el GIL correctamente |
| `uvicorn` + FastAPI | Requiere migrar de Flask a FastAPI — alcance fuera del sprint |
| `multiprocessing` workers | Memory leak con Pandas en procesos de larga duración; `max-requests` no soluciona bien |

### Justificación detallada

- **gthread** usa un único proceso con múltiples hilos (threads). Python libera el GIL durante operaciones I/O (queries DB, escritura de archivos), permitiendo concurrencia real sin el overhead de múltiples procesos.
- **`--threads 4`**: Con `cpus: "2.0"` en docker-compose.prod.yml, 4 threads aprovechan el CPU sin saturarlo.
- **`--max-requests 200`**: Después de 200 requests, el worker se reinicia limpiamente. Previene memory leaks acumulativos de Pandas (objetos DataFrame no liberados correctamente por el GC de Python).
- **`--worker-tmp-dir /dev/shm`**: Gunicorn usa archivos temporales en `/tmp` para heartbeats entre master/worker. `/dev/shm` es RAM pura (no disco), eliminando I/O en el ciclo de monitoring.
- **`--timeout 300`**: Un reporte grande (10.000+ filas, múltiples hojas) puede tardar varios minutos. El default de 30s causaría timeouts prematuros.

### Escalation path — si Gunicorn/gthread genera latencia inaceptable

Si los reportes superan los límites del servidor gthread, escalar en este orden:

| Nivel | Solución | Impacto | Cuándo |
|---|---|---|---|
| 1 | Endpoint de progreso asíncrono | Mínimo | Reportes > 30s bloqueando clientes |
| 2 | **APScheduler** o **ARQ** (job queue sobre Redis) | Medio | Múltiples usuarios concurrentes con reportes largos |
| 3 | Migrar a **FastAPI + Uvicorn** con `BackgroundTasks` | Alto | Se necesita API async nativa |
| 4 | Migrar a **Granian** (servidor ASGI en Rust) | Alto | Máximo rendimiento I/O + CPU en Python |

Para el nivel 2: Flask devuelve inmediatamente un `job_id` y el cliente sondea `/reports/status/<job_id>`. ARQ es asyncio-nativo y mínimo en dependencias.

### Consecuencias
- El servicio puede generar archivos temporales grandes en `/tmp` (configurado con `tmpfs: /tmp:size=128m` en prod).
- Si se agregan endpoints de larga duración (>5min), revisar el timeout.

---

## ADR-002: Next.js standalone output en frontend

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Next.js tiene múltiples modos de output. Por defecto, la imagen Docker necesitaría `pnpm install` de las dependencias completas, resultando en imágenes de 1-2GB.

### Decisión

```js
// next.config.js
module.exports = {
  output: 'standalone',
}
```

Imagen final resultante: ~120-150MB.

### Cómo funciona

El build de Next.js en modo standalone:
1. Genera un `server.js` autocontenido en `.next/standalone/`
2. Copia solo las dependencias de producción necesarias
3. El runtime final solo necesita Node.js + `server.js`

```dockerfile
# Dockerfile.prod — etapa final
FROM node:24-slim
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
CMD ["node", "server.js"]
```

### Consecuencias

- Las URLs públicas (`NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_REPORTS_URL`) se **bakeán en el bundle** durante `next build`. Si cambian, se requiere un rebuild completo de la imagen.
- No hay `node_modules/` en la imagen final — no se puede instalar ni actualizar dependencias sin rebuild.
- El caché de Docker es efectivo: si solo cambia código (no dependencias), la capa de `pnpm install` se reutiliza.

---

## ADR-003: tini como ENTRYPOINT en backend y frontend

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Cuando un contenedor Docker arranca, el proceso con PID 1 tiene responsabilidades especiales en Linux: debe manejar señales del kernel y hacer `wait()` en procesos zombie. Node.js no fue diseñado para ser PID 1.

### Decisión

```dockerfile
# Dockerfile — backend y frontend
RUN apt-get install -y tini
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["pnpm", "run", "dev", "--"]
```

```dockerfile
# Dockerfile.prod — backend y frontend
RUN apt-get install -y tini
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]
```

### Por qué importa

Sin `tini`:
- `docker stop` → Docker envía SIGTERM al proceso → Node.js no lo propaga correctamente a sus hijos → Docker espera 10s → envía SIGKILL → **requests en vuelo se pierden** (graceful shutdown roto)
- Procesos zombie acumulados si Node.js usa `child_process`

Con `tini`:
- `tini` recibe SIGTERM → lo reenvía a Node.js con la señal correcta → Node.js completa requests en vuelo → sale limpiamente
- `tini` hace `wait()` en todos los procesos hijos → no hay zombies

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| Node.js directo como PID 1 | No maneja SIGTERM correctamente en todos los casos |
| `dumb-init` | Funcionalidad equivalente, pero `tini` es más maduro y está en APT |
| Scripts shell como entrypoint | Complejidad innecesaria; los shells tampoco propagan señales bien |

---

## ADR-004: Puertos bound a 127.0.0.1 en producción

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

En producción, los servicios (backend :4000, frontend :3000, reports :5000) solo deben ser accesibles a través de Nginx. Nunca directamente desde internet.

### Decisión

```yaml
# docker-compose.prod.yml
ports:
  - "127.0.0.1:${PORT_BACKEND}:${PORT_BACKEND}"  # Solo localhost
```

En desarrollo (`docker-compose.override.yml`):
```yaml
ports:
  - "${PORT_BACKEND}:${PORT_BACKEND}"  # Accesible desde cualquier interfaz
```

### Por qué `127.0.0.1:` es importante

Sin el prefijo `127.0.0.1:`:
```
0.0.0.0:4000 → cualquier IP del servidor puede acceder al puerto 4000 directamente
```

Con `127.0.0.1:4000`:
```
Solo procesos en el mismo servidor (Nginx, herramientas locales) pueden conectarse
Un atacante externo que intente http://tu-servidor:4000 recibirá "Connection refused"
```

### Flujo de tráfico en producción

```
Internet → Nginx :80/:443
  → http://127.0.0.1:3000 (frontend)
  → http://127.0.0.1:4000 (backend API)
  → http://127.0.0.1:5000 (reports API)
```

---

## ADR-005: Wheels precompiladas en reports builder

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Pandas, psycopg2 y otras dependencias de `reports-api` requieren compilación C durante `pip install`. Esto necesita herramientas como `build-essential`, `libpq-dev`, `gcc`, que añaden ~200MB a la imagen.

### Decisión

Multi-stage build:
1. **Stage builder**: Tiene compiladores C. Compila wheels (`.whl` = paquetes precompilados).
2. **Stage runner**: Solo copia las wheels ya compiladas e instala desde ellas con `--find-links`.

```dockerfile
# Stage 1: Builder (tiene compiladores)
FROM python:3.12-slim AS builder
RUN apt-get install -y build-essential libpq-dev
RUN pip wheel -r requirements.txt -w /wheels

# Stage 2: Runner (sin compiladores)
FROM python:3.12-slim AS runner
COPY --from=builder /wheels /wheels
RUN pip install --find-links=/wheels -r requirements.txt
```

### Beneficios

- La imagen final no tiene `gcc`, `build-essential`, etc. → **~200MB menos**
- Superficie de ataque reducida (sin compiladores = menos vectores de explotación)
- Instalación "offline" garantizada — si PyPI cae, las wheels ya están compiladas en la capa del builder

---

## ADR-006: PostgreSQL y Nginx en el host, fuera de Docker

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

El proyecto gestiona tres servicios de aplicación (backend, frontend, reports). Se debatió si PostgreSQL y Nginx deberían también correr en contenedores.

### Decisión

PostgreSQL y Nginx corren directamente en el sistema operativo del servidor (host), no en contenedores.

### Justificación

**PostgreSQL en el host:**
- Los datos de producción son el activo más crítico. Persistirlos en un volumen Docker añade una capa de abstracción que puede complicar backups, recuperación ante desastres y acceso directo.
- PostgreSQL en el host tiene acceso directo a disco sin overhead de overlay filesystem.
- `make backup-db` y `make rollback-db` usan `pg_dump`/`psql` directamente — más simple y robusto.
- El equipo ya tiene experiencia operativa con PostgreSQL en host.

**Nginx en el host:**
- Nginx gestiona SSL/TLS, certificados Let's Encrypt (certbot), y configuración de dominios. Estas responsabilidades son del servidor, no de la aplicación.
- Nginx en contenedor complicaría la renovación de certificados con certbot.
- Al estar en el host, Nginx puede gestionar múltiples proyectos/dominios en el mismo servidor.

### Consecuencias

- Los contenedores deben conectarse a PostgreSQL vía la IP del host (ver ADR-007).
- Requiere que el equipo de operaciones sepa administrar PostgreSQL y Nginx en el SO.
- El setup inicial es más manual (ver README.md).

### Por qué NO poner PostgreSQL en Docker (riesgos que evitamos)

**Riesgo 1 — Pérdida de datos ante fallo de Docker:**
Si el daemon Docker falla, se reinicia, o se ejecuta `docker compose down -v` 
por error, los volúmenes Docker se eliminan. Con PostgreSQL en el host, 
los datos están en `/var/lib/postgresql/` — completamente fuera del alcance 
de cualquier comando Docker.

**Riesgo 2 — Overlay filesystem = latencia de I/O:**
Docker usa un sistema de archivos overlay para los contenedores. Las operaciones 
de I/O (escrituras de PostgreSQL) pasan por esta capa adicional, añadiendo 
latencia. PostgreSQL en el host tiene acceso directo al disco sin intermediarios.

**Riesgo 3 — Backups más complejos con Docker:**
`pg_dump` desde el host es `sudo -u postgres pg_dump dbname > backup.sql`. 
Desde un contenedor, requeriría: `docker exec postgres_container pg_dump ...`, 
con el riesgo de que el contenedor no esté corriendo cuando el cron intenta 
el backup.

**Riesgo 4 — Volúmenes Docker no son un backup real:**
Un volumen Docker persiste datos, pero vive en `/var/lib/docker/volumes/`. 
Si el servidor se corrompe, el volumen también puede corromperse. No es lo mismo 
que un directorio del host con backups offsite siguiendo la regla 3-2-1.

**Riesgo 5 — Ambigüedad en la persistencia:**
Con `docker compose down` (sin `-v`) los volúmenes persisten. Con 
`docker compose down -v` se eliminan. Esta diferencia sutil ha causado 
pérdidas de datos en producción en proyectos reales. Con PostgreSQL en el host, 
no existe ese riesgo.

**Conclusión:**
Los datos de producción son el activo más crítico. La simplicidad de 
"PostgreSQL en el host" reduce el riesgo a su mínimo expresión.
- Benchmark: PostgreSQL directo en host es ~15-30% más rápido en I/O que en Docker con overlay2 filesystem
- PostgreSQL 15+ tiene WAL archiving nativo — más fácil de configurar fuera de Docker

---

## ADR-007: host-gateway para conectar contenedores con PostgreSQL

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Los contenedores corren en una red Docker interna (`nombre_del_proyecto-private` con `internal: true`). PostgreSQL está en el host. Los contenedores necesitan "salir" de la red Docker para llegar al host, pero sin acceso a internet.

### Problema original

Docker en Linux asigna una IP al gateway del host (típicamente `172.17.0.1`). Esta IP puede variar entre servidores y versiones de Docker. Hardcodear `172.17.0.1` en `.env.production` es frágil.

Además, `internal: true` bloquea el acceso a internet, pero en algunos kernels también puede bloquear el acceso al host gateway.

### Decisión

Usar `extra_hosts: host-gateway:host-gateway` en los servicios que necesitan acceder a PostgreSQL:

```yaml
# docker-compose.prod.yml
backend:
  extra_hosts:
    - "host-gateway:host-gateway"   # Docker 20.10+ resuelve esto a la IP del gateway

reports-api:
  extra_hosts:
    - "host-gateway:host-gateway"
```

```bash
# .env.production
DB_HOST=host-gateway   # Se resuelve automáticamente a la IP del gateway Docker
```

### Por qué funciona

Docker 20.10+ introdujo el alias especial `host-gateway` que siempre resuelve a la IP del gateway del host, independientemente de la configuración de red. Es equivalente a `host.docker.internal` en macOS/Windows pero funciona en Linux.

### Alternativas descartadas

| Opción | Por qué se descartó |
|---|---|
| `172.17.0.1` hardcodeado | IP variable entre servidores y versiones Docker |
| `host.docker.internal` | No funciona en Linux sin Docker Desktop |
| Docker network sin `internal: true` | Expone los contenedores a internet |
| PostgreSQL en contenedor | Ver ADR-006 |

---

## ADR-008: Separación de archivos .env por entorno

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

```
.env               → Dev activo (NO versionado, creado desde .env.example)
.env.example       → Plantilla de dev (SÍ versionado, valores de ejemplo)
.env.production    → Prod activo (NO versionado, solo en servidor)
.env.prod.example  → Plantilla de prod (SÍ versionado, sin secretos)
secrets/           → Credenciales sensibles (NO versionado, solo en servidor)
```

### Separación de responsabilidades

```
.env / .env.example:      Variables de DESARROLLO — credenciales se incluyen (solo dev)
.env.production:          Variables de PRODUCCIÓN — SIN credenciales
secrets/:                 Credenciales de producción — archivos individuales con chmod 600
```

Esta separación permite:
- Compartir `.env.example` con el equipo sin exponer credenciales
- En producción, las credenciales nunca están en el mismo archivo que la configuración
- Los secretos se rotan editando un solo archivo pequeño (no el `.env.production` completo)

---

## ADR-009: Docker Secrets sin Swarm (archivos en ./secrets/)

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Las credenciales de producción (contraseñas DB, tokens) no deben estar en variables de entorno (visibles con `docker inspect`) ni en archivos `.env` (riesgo de exposición accidental).

### Decisión

Usar Docker Secrets en modo standalone (sin Swarm):

```yaml
# docker-compose.prod.yml
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  backend:
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password  # La app lee el archivo
```

Los secretos se montan como archivos read-only en `/run/secrets/<nombre>` dentro del contenedor.

### Lectura en el código de la aplicación

```javascript
// Node.js / NestJS
const password = fs.readFileSync(
  process.env.DB_PASSWORD_FILE || '/run/secrets/db_password',
  'utf8'
).trim();
```

```python
# Python / Flask
import os
password_file = os.environ.get('DB_PASSWORD_FILE', '/run/secrets/db_password')
password = open(password_file).read().strip()
```

### Por qué no variables de entorno para credenciales

- `docker inspect <container>` muestra todas las variables de entorno en texto plano
- Las variables de entorno se pasan a procesos hijos (subshells, scripts)
- Con archivos en `/run/secrets/`: solo el proceso principal puede leerlos (permisos del filesystem)

### Permisos recomendados

```bash
chmod 700 secrets/           # Solo el owner puede listar
chmod 600 secrets/*.txt      # Solo el owner puede leer/escribir
```

---

## ADR-010: mem_limit y cpus en lugar de deploy.resources

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Docker Compose tiene dos formas de limitar recursos:

```yaml
# Forma 1: deploy.resources (solo Swarm)
deploy:
  resources:
    limits:
      memory: 1G
      cpus: '1.0'

# Forma 2: nivel raíz del servicio (Compose standalone)
mem_limit: 1g
cpus: "1.0"
```

### Decisión

Usar `mem_limit` y `cpus` directamente en el servicio. `deploy.resources` se ignora completamente en Docker Compose standalone.

### Verificación

```bash
# Verificar que los límites están aplicados:
docker stats
docker inspect nombre_del_proyecto_api | grep -A5 Memory
```

### Valores configurados y justificación

| Servicio | CPU | RAM | Justificación |
|---|---|---|---|
| backend | 1.0 | 1G | NestJS con TypeORM: estable dentro de estos límites en carga normal |
| frontend | 0.5 | 512M | Next.js standalone es liviano: solo sirve archivos estáticos + SSR |
| reports-api | 2.0 | 2G | Pandas puede consumir varios GB con DataFrames grandes; reportes Excel intensivos |
| **Total** | **3.5** | **3.5G** | Diseñado para servidor de 4 cores y 8GB RAM mínimo |

**Para servidores con menos recursos:**
```yaml
backend:   cpus: "0.5"  mem_limit: 512m
frontend:  cpus: "0.3"  mem_limit: 256m
reports:   cpus: "0.9"  mem_limit: 1g
```

---

## ADR-011: Red interna con internal: true en producción

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

```yaml
networks:
  nombre_del_proyecto-private:
    driver: bridge
    internal: true   # Sin acceso a internet desde los contenedores
    name: nombre_del_proyecto-private
```

### Por qué `internal: true`

Los contenedores de producción no deberían poder hacer requests HTTP arbitrarios a internet. Con `internal: true`:
- Un contenedor comprometido no puede exfiltrar datos a internet
- Las dependencias se resuelven en build time, no en runtime
- Cumple con principio de mínimo privilegio

### Consecuencia: acceso al host

Con `internal: true`, el acceso al host (para PostgreSQL) requiere `extra_hosts: host-gateway:host-gateway` (ver ADR-007).

### Nota sobre `nombre_del_proyecto-public`

La red `nombre_del_proyecto-public` está definida Y comentada en el compose pero actualmente no tiene servicios asignados. Se reserva para una posible migración futura donde Nginx corra en un contenedor y necesite una red pública para recibir tráfico. Hoy, con Nginx en el host, no se usa activamente.

---

## ADR-012: No migrar a Kubernetes/K3s (decisión explícita)

**Estado:** Activo  
**Fecha:** Febrero 2026

### Contexto

Se considero migrar a K3s o Kubernetes como siguiente paso de modernización.

### Decisión

**No migrar a Kubernetes ni K3s.** El proyecto permanece en Docker Compose.

### Justificación

| Factor | Situación actual | Con K8s |
|---|---|---|
| Escala | 3 servicios en 1 servidor | K8s diseñado para decenas de servicios en múltiples nodos |
| Operación | 1-2 personas en el equipo | K8s requiere conocimiento especializado para operar |
| Coste | Servidor único ~$20-50/mes | K8s managed (EKS/GKE) mínimo ~$150-300/mes |
| Complejidad | `make prod` despliega en segundos | K8s: Helm charts, namespaces, RBAC, networking, ingress |
| Overhead | Docker Compose ≈ 0 overhead | K8s control plane consume ~300MB+ RAM |

### Cuándo reconsiderar

- El proyecto crece a 10+ servicios
- Se requiere despliegue en múltiples regiones/nodos
- Se tiene un equipo DevOps dedicado para operar K8s
- El costo de infra justifica la complejidad operacional

### Escalation path — Si se necesita más de 1 servidor sin K8s

Si el proyecto crece a 5-15 contenedores en 2-3 servidores y K8s sigue siendo
demasiado complejo, **Docker Swarm** es el paso intermedio natural:

| Aspecto | Docker Compose (actual) | Docker Swarm | Kubernetes |
|---|---|---|---|
| Nodos soportados | 1 | 1-50 | Ilimitado |
| Secrets nativos | File-based | ✅ Swarm Secrets | ✅ K8s Secrets |
| Rolling updates | Manual | ✅ Automático | ✅ Automático |
| Load balancing | Nginx manual | ✅ Ingress interno | ✅ Ingress + Service Mesh |
| Migración desde Compose | — | `docker stack deploy` | Kompose o Helm |
| Overhead RAM | ~0 MB | ~50 MB | ~300+ MB |

**Cuándo migrar a Swarm:**
- Se necesita alta disponibilidad (2+ servidores)
- Se requieren rolling deployments sin downtime
- El equipo llega a 3+ desarrolladores

**Migración de Compose a Swarm (cuando llegue el momento):**
```bash
# Inicializar Swarm en el servidor principal
docker swarm init --advertise-addr <IP_DEL_SERVIDOR>

# Los secrets nativos de Swarm reemplazan los archivos en secrets/
echo "mi_password" | docker secret create db_password -

# El compose se convierte en stack (casi sin cambios)
docker stack deploy -c docker-compose.yml -c docker-compose.prod.yml nombre_del_proyecto
```

Los archivos `docker-compose.yml` y `docker-compose.prod.yml` son compatibles
con `docker stack deploy` con cambios mínimos (deploy.replicas, deploy.resources).

---

## ADR-013: GitHub Actions como plataforma CI/CD

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

Usar GitHub Actions para CI/CD con los siguientes jobs:

```
CI (ci.yml):
├── validate          → lint, validate compose, build, test healthchecks
├── build-prod-and-sbom → build imágenes prod + generar SBOMs
├── test-backend      → pnpm test + lint
├── test-frontend     → pnpm lint + test
├── test-reports      → flake8 + pytest
└── scan-prod-images  → trivy image scan → SARIF → GitHub Security tab

Security (security.yml):
├── hadolint          → lint Dockerfiles
└── trivy             → fs scan → SARIF → GitHub Security tab

Deploy (deploy.yml):
└── deploy a producción (manual o en push a main)
```

### Branch Protection recomendada

En GitHub → Settings → Branches → Branch protection rules para `main`:
- ✅ Require status checks: `validate`, `Lint Dockerfiles (hadolint)`, `Vulnerability Scan (trivy)`
- ✅ Require branches to be up to date before merging

---

## ADR-014: Pipeline de auditoría local (make audit-full)

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

Mantener un pipeline de auditoría completo ejecutable localmente, independiente del CI:

```bash
make audit-full   # 7 pasos:
# [1/7] lint-docker        → hadolint en todos los Dockerfiles
# [2/7] trivy-config-scan  → misconfigs en Dockerfiles + compose
# [3/7] audit-requirements → pip-audit CVEs en Python
# [4/7] build-prod-images  → build único (reutilizado por pasos 5 y 6)
# [5/7] scan-security      → trivy image scan
# [6/7] sbom               → CycloneDX SBOM por servicio
# [7/7] audit-security     → system-check.log (evidencia operativa)
```

### Por qué local y no solo CI

- Los auditores externos a veces requieren evidencia generada en el servidor de producción, no en el CI.
- Permite auditar antes de hacer un deploy, sin esperar al pipeline.
- `system-check.log` captura el estado real del sistema en ese momento.

### Evidencia generada en `scripts/tests/`

```
alerts.log         → hadolint results
trivy-config.log   → trivy config results
security-scan.log  → trivy image results
pip-audit.log      → pip-audit results
sbom-backend.json  → SBOM CycloneDX backend
sbom-reports.json  → SBOM CycloneDX reports
sbom-frontend.json → SBOM CycloneDX frontend
system-check.log   → docker info + compose ps + logs
grype-backend.log  → grype vulnerabilidades backend
grype-reports.log  → grype vulnerabilidades reports
grype-frontend.log → grype vulnerabilidades frontend
```

---

## ADR-015: Makefile como interfaz única de operación

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

Toda operación del proyecto se hace a través del Makefile. Nadie debería necesitar recordar comandos `docker compose` largos.

### Principios del Makefile

1. **`.SHELLFLAGS := -eu -o pipefail`**: Cualquier comando que falle aborta el target inmediatamente. `-u` hace fallar con variables no definidas. `-o pipefail` hace fallar si cualquier paso de un pipe falla (no solo el último).

2. **`.ONESHELL`**: Todo el target se ejecuta en una sola instancia de shell. Permite usar variables entre líneas sin `&&` y que `set -e` aplique al bloque completo.

3. **`NO_COLOR=1`**: Desactiva colores ANSI para logs de CI (`make audit-full NO_COLOR=1`).

4. **Dashboard manual** en `make help`: Permite secciones, iconos y orden lógico. El alternativo `grep ## | awk` produce lista plana alfabética sin control de agrupación.

5. **`build-prod-images` como target compartido**: Evita builds duplicados cuando `sbom`, `scan-security` y `grype-scan` se ejecutan en secuencia.

---

## ADR-016: Estrategia de healthchecks por capas

**Estado:** Activo (Nivel 1 y Nivel 2 implementados)  
**Fecha:** Febrero 2026 — actualizado Marzo 2026

### Nivel 1: HTTP check público
GET /health → { status: 'ok' } — sin detalle de BD. Usado por Nginx y monitores externos.

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:${PORT}/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

Verifica que el proceso responde HTTP. No verifica conectividad con la base de datos.

### Nivel 2: HTTP check + DB check interno

El endpoint `/health/ready` debe adicionalmente verificar que PostgreSQL está accesible:

**NestJS:** usar `@nestjs/terminus` con `TypeOrmHealthIndicator.pingCheck('database')` → hace `SELECT 1` y devuelve 200/503.

**Flask:** llamar `psycopg2.connect()` + `execute('SELECT 1')` → devuelve `{'status':'ok','db':'connected'}` 200 o `{'status':'error'}` 503.

GET /health/ready → Terminus con TypeOrmHealthIndicator.pingCheck('database').
Solo usado por Docker healthcheck (curl dentro del contenedor).
Nginx bloquea esta ruta externamente (deny all).

### Cuándo el healthcheck importa más

- En CI: `docker ps --filter "health=healthy"` verifica que los 3 servicios están listos antes de declarar el test como exitoso.
- En producción: un servicio "healthy" pero con DB caída causaría errores en todas las requests. Con el Nivel 2, Docker detectaría el problema y podría activar alertas.

---

## ADR-017: Renovate para actualización automática de imágenes base

**Estado:** Activo  
**Fecha:** Febrero 2026

### Decisión

Usar Renovate (`.github/renovate.json`) para actualizar automáticamente:
- Digests SHA256 de imágenes base en `Dockerfile.prod`
- Versiones de actions en `*.github/workflows/*.yml`

### Por qué digests SHA256 en lugar de tags

```dockerfile
# ❌ Sin digest — puede cambiar sin aviso
FROM node:24-slim

# ✅ Con digest — reproducible y verificable
FROM node:24-slim@sha256:abc123...
```

Un tag como `node:24-slim` puede actualizarse upstream y cambiar el comportamiento de tu imagen sin que lo notes. El digest SHA256 es inmutable: si coincide, es exactamente la misma imagen.

### Flujo con Renovate

1. Renovate ejecuta semanalmente (configurado en `renovate.json`)
2. Detecta digests SHA256 nuevos para las imágenes base
3. Abre un PR automático con el diff
4. El equipo revisa y aprueba el PR
5. CI corre tests con la nueva imagen base antes de mergear

---

## ADR-018: Express como plataforma HTTP (no Fastify)

**Estado:** Activo  
**Fecha:** Marzo 2026

### Decisión
Se usa `@nestjs/platform-express` como adaptador HTTP de NestJS.

### Justificación
- Compatibilidad total con ecosystem Express (helmet, passport, etc.)
- Cero fricción con middleware de terceros
- Rendimiento más que suficiente para un Single VPS
- Familiaridad del equipo con Express/Node.js

### Consecuencias
- Si se supera 10k req/seg, evaluar migración a Fastify
- Migrar implicaría reemplazar middleware Express-específico

---

---

## ADR-019: Logging estructurado con structlog (Python) y json-file (Docker)

**Estado:** Activo
**Fecha:** Marzo 2026

### Contexto

El servicio `reports-api` necesitaba logging de producción parseable por herramientas como Loki/Promtail/ELK. El módulo `logging` estándar de Python emite texto libre, difícil de indexar por campo. Se evaluaron tres opciones para el servicio Python.

Para los contenedores Docker (backend y frontend incluidos) también se necesitaba una estrategia de retención de logs que no consumiera disco indefinidamente.

### Decisión

**Python:** usar `structlog` como librería de logging en `reports-api`.

**Docker:** usar el driver `json-file` con rotación en todos los servicios:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| `logging` estándar Python | Emite texto plano — imposible de parsear por campo en Loki/ELK |
| `loguru` | Más simple que structlog, pero contexto de request requiere workarounds complejos |
| `python-json-logger` | No soporta contexto por request (request_id en cada línea) nativamente |
| Driver `local` de Docker | Formato binario — no legible con `docker logs` ni con `tail` directo |
| Driver `syslog` de Docker | Requiere syslog daemon externo; overhead innecesario en single VPS |
| Sin límite de logs | `docker logs` puede llenar disco en producción con tráfico moderado |

### Justificación de structlog

- **Contexto de request** via `structlog.contextvars`: cada línea de log del mismo request incluye automáticamente `request_id`, `method`, `path`. Invaluable para trazar errores en producción.
- **Formato dual**: JSON en producción (parseable por Loki) + colores en desarrollo (legible por humanos). Mismo código, diferente renderer según `APP_ENV`.
- **Compatibilidad con `logging` stdlib**: el bridge `structlog.stdlib` permite que librerías como `sqlalchemy` o `psycopg2` también emitan JSON estructurado sin cambiar su código.

```python
# Mismo logger, diferente output según entorno:
logger.info("report_requested", user_id=42, report_type="monthly", rows=1500)
# Dev  → "report_requested" user_id=42 report_type=monthly rows=1500  (con colores)
# Prod → {"event":"report_requested","user_id":42,"report_type":"monthly","rows":1500}
```

### Justificación de json-file con rotación

- 3 archivos × 10MB = máximo 30MB por servicio → predecible y acotado
- `json-file` es el único driver que admite `docker logs` y retención simultáneos
- Con Loki/Promtail activos, Promtail lee los archivos JSON directamente del sistema de archivos del host en `/var/lib/docker/containers/`

### Consecuencias

- El orden de inicialización en `main.py` es crítico: `configure_logging()` ANTES de cualquier import que logee.
- Los tests deben mockear structlog o usar `structlog.testing.capture_logs()`.
- Si se añade Loki en el futuro, la configuración de Promtail es trivial porque los logs ya son JSON.

---

## ADR-020: Estrategia de CORS — lista explícita de orígenes

**Estado:** Activo
**Fecha:** Marzo 2026

### Contexto

Tanto el backend (NestJS) como `reports-api` (Flask) exponen APIs HTTP que son consumidas desde el frontend Next.js. Sin configuración CORS, los navegadores bloquean estas peticiones cross-origin. Se debatió entre tres estrategias: wildcard, proxy, y lista explícita.

### Decisión

Usar lista explícita de orígenes permitidos via variable de entorno `ALLOWED_ORIGINS`:

```bash
# .env (desarrollo)
ALLOWED_ORIGINS=http://localhost:3000

# .env.production (producción)
ALLOWED_ORIGINS=https://app.tudominio.com
```

**NestJS:**
```typescript
app.enableCors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') ?? [],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  maxAge: 86400,
});
```

**Flask:**
```python
CORS(app, origins=os.environ.get('ALLOWED_ORIGINS', '').split(','))
```

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| `origin: '*'` (wildcard) | Permite cualquier origen — incompatible con `credentials: true`; inaceptable en producción |
| Proxy Next.js (`/api/*` → backend) | Elimina CORS pero añade latencia, complica el routing y rompe la arquitectura de servicios independientes |
| Regex de dominio | Más flexible pero introduce riesgo de bypass por subdominios no previstos |
| CORS deshabilitado + VPN | Operacionalmente complejo para un equipo pequeño; innecesario con 3 servicios en el mismo VPS |

### Por qué lista explícita

- **Principio de mínimo privilegio**: solo los orígenes declarados pueden hacer peticiones autenticadas (`credentials: true`).
- **Compatible con cookies `httpOnly`**: `credentials: true` es obligatorio para que el navegador envíe cookies en peticiones cross-origin. El wildcard lo prohíbe por spec.
- **Auditabilidad**: los orígenes permitidos están en `.env.prod.example` y son revisables en code review.

### Consecuencias

- Añadir un nuevo frontend o dominio requiere actualizar `ALLOWED_ORIGINS` y redesplegar.
- El valor de `ALLOWED_ORIGINS` debe estar en el checklist de deploy (`docs/DEPLOYMENT-CHECKLIST.md`).

---

## ADR-021: Política de cobertura de tests progresiva

**Estado:** Activo
**Fecha:** Marzo 2026

### Contexto

Al iniciar el proyecto como plantilla, la cobertura de tests era mínima: el backend tenía tests de health y configuración (≈30%), el frontend solo lint, y Python tenía 0%. Se debatió si bloquear el CI hasta alcanzar umbrales más altos.

### Decisión

Adoptar una **política de cobertura progresiva**: el CI nunca baja el umbral actual, pero tampoco bloquea el desarrollo por umbrales futuros no alcanzados.

| Servicio | Umbral CI actual | Próximo objetivo | Fecha objetivo |
|---|---|---|---|
| Backend (NestJS) | 30% | 50% | Q3 2026 |
| Frontend (Next.js) | lint solamente | 20% | Q4 2026 |
| Reports (Python) | 0% (activación) | 20% | Q3 2026 |

**Regla de PR:** cualquier PR que introduzca lógica de negocio nueva debe incluir mínimo un test del caso exitoso y un test del caso de error principal.

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| Umbral 80% desde el inicio | Bloquea el desarrollo mientras la plantilla no tiene lógica de negocio real; tests de scaffolding inflados artificialmente |
| Sin umbral (solo lint) | Sin enforcement, la cobertura degrada — no hay fricción positiva |
| Umbral fijo 50% global | Python tiene librerías I/O-heavy difíciles de testear sin DB real; umbral global penaliza el servicio equivocado |

### Cómo activar el umbral en Python

Cuando `reports-api` tenga su primera función de negocio real, editar `reports/setup.cfg`:
```ini
[pytest]
addopts = --cov=src --cov-fail-under=20
```

### Consecuencias

- Los umbrales son deuda técnica explícita — cada trimestre debe revisarse si el objetivo se cumplió.
- La regla del "PR con lógica nueva" depende de la disciplina del equipo y del code review — no está automatizada.

---

## ADR-022: Almacenamiento de tokens JWT — httpOnly Cookies en lugar de localStorage

**Estado:** Activo
**Fecha:** Marzo 2026

### Contexto

La implementación inicial del cliente frontend usaba `localStorage` para almacenar `access_token` y `refresh_token`. Esta es la práctica más común en tutoriales, pero tiene una vulnerabilidad crítica: cualquier código JavaScript en la página puede leer `localStorage`, convirtiendo cualquier XSS (incluso en una dependencia transitiva) en un compromiso completo de tokens.

### Decisión

Almacenar los tokens JWT en **cookies `httpOnly; Secure; SameSite=Strict`** emitidas por el backend:

```typescript
// NestJS — auth.controller.ts — login emite cookies, no tokens en el body
res.cookie('access_token', accessToken, {
  httpOnly: true,       // Inaccesible desde JavaScript
  secure: isProduction, // Solo HTTPS en producción
  sameSite: 'strict' as const,   // Bloquea CSRF cross-site
  maxAge: 15 * 60 * 1000,  // 15 minutos
});
```

```typescript
// Frontend — api.ts — el navegador gestiona las cookies automáticamente
const response = await fetch(`${API_BASE}${endpoint}`, {
  credentials: 'include',  // Envía cookies automáticamente
  headers: { 'Content-Type': 'application/json' },
});
```

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| `localStorage` (estado anterior) | Vulnerable a XSS; cualquier script en la página puede robar tokens |
| `sessionStorage` | Mismo problema — accesible desde JS |
| Memory (variable JS) | Seguro contra XSS pero se pierde en refresh de página; UX deficiente |
| Token en URL / query param | Aparece en logs del servidor, historial, referrer headers |
| `localStorage` + CSP estricta | CSP reduce la superficie pero no elimina el riesgo |

### Por qué httpOnly Cookies son superiores

- **Inaccesibles desde JavaScript**: `httpOnly` impide que XSS robe el token — solo puede hacer peticiones autenticadas con él, no extraerlo.
- **`SameSite=Strict`** previene CSRF: el navegador no envía la cookie desde otros dominios.
- **Rotación automática**: el refresh ocurre via `/auth/refresh` que lee la cookie de refresh — el frontend nunca maneja tokens como strings.

### Implicaciones de arquitectura

- El backend necesita responder con `Set-Cookie` en login y emitir `clearCookie` en logout.
- El frontend usa `credentials: 'include'` en todas las peticiones a la API.
- `ALLOWED_ORIGINS` debe ser un dominio exacto — `credentials: 'include'` requiere origen explícito en CORS (no wildcard).
- El logout DEBE hacer una petición al backend para limpiar la cookie — no es posible desde el cliente solo con cookies `httpOnly`.
- Para clientes no-browser (apps móviles, CLI), mantener soporte paralelo para Bearer token en Authorization header.

---

## ADR-023: SSL en conexión a PostgreSQL — desactivado con justificación explícita

**Estado:** Activo  
**Fecha:** Marzo 2026

### Contexto

PostgreSQL acepta conexiones SSL/TLS para cifrar el tráfico de base de datos en tránsito.
La configuración SSL está disponible en ambos clientes (`database.config.ts` y `main.py`)
pero permanece comentada. Esta decisión documenta el razonamiento explícito para no activarla
en la configuración actual y establece la condición que debe triggear su activación.

### Decisión

**SSL desactivado mientras PostgreSQL y los contenedores estén en el mismo host físico.**

En la arquitectura actual (ADR-006, ADR-007), PostgreSQL corre directamente en el host del
VPS y los contenedores lo alcanzan vía `host-gateway`. Todo el tráfico de base de datos
viaja por la interfaz de loopback (`127.0.0.1`) o por la interfaz virtual de Docker
(`172.17.0.1`), nunca por una interfaz de red pública o entre hosts distintos.

El cifrado SSL en loopback tiene un costo de CPU mensurable (overhead de TLS handshake)
sin beneficio de confidencialidad: un atacante con acceso al sistema de archivos del host
ya tiene acceso a todo — certificados, datos y proceso de PostgreSQL.

### Condición de activación (no negociable)

**SSL DEBE activarse en cualquiera de estos escenarios:**

| Escenario | Acción requerida |
|---|---|
| `DB_HOST` cambia de `host-gateway` / `postgres` a una IP o hostname externo | Activar SSL inmediatamente |
| PostgreSQL migra a un servicio gestionado (RDS, Cloud SQL, Supabase, etc.) | SSL obligatorio — estos servicios lo requieren |
| Arquitectura multi-servidor (BD en VPS separado) | Activar SSL + verificar certificado |
| Requisito de cumplimiento (PCI-DSS, HIPAA, SOC 2) | Activar SSL independientemente de la topología |

### Cómo activar cuando aplique

**NestJS** (`backend/src/config/database.config.ts`):
```typescript
// Descomentar y configurar:
ssl: isProduction
  ? { rejectUnauthorized: true, ca: process.env.DB_SSL_CA ?? undefined }
  : false,
```

**Python** (`reports/main.py`):
```python
# En connect_args de create_engine():
"sslmode": "require",  # O "verify-full" si tienes el CA certificate
```

**Variable de entorno requerida** si el servidor usa un CA personalizado:
```bash
DB_SSL_CA=/run/secrets/db_ssl_ca   # Path al certificado CA en producción
```

### Alternativas consideradas

| Opción | Por qué no se aplicó ahora |
|---|---|
| SSL siempre activado (loopback) | Overhead sin beneficio; PostgreSQL local no tiene CA público |
| `sslmode=prefer` | Degrada silenciosamente a sin SSL si falla; falsa sensación de seguridad |
| Tunnel SSH para BD remota | Alternativa válida pero añade complejidad operacional innecesaria |

### Consecuencias

- La activación de SSL requiere regenerar/proveer un certificado en el servidor PostgreSQL.
- Cualquier cambio en `DB_HOST` en `.env.production` debe ir acompañado de revisión de esta ADR.
- Añadir `DB_SSL_CA` al listado de Docker Secrets cuando se active.
```

---

## 3. Deploy y CI — relación y problema actual

**Estado actual — están desconectados:**
```
ci.yml    → dispara en push a main/develop y PRs
deploy.yml → dispara en push de tags v*.*.*

## ADR-024 — Rate limiting granular en Reports API

**Fecha:** 2026-03-22  
**Estado:** PENDIENTE  
**Categoría de riesgo:** OWASP A04:2021 — Insecure Design

### Contexto
El rate limiting global de reports-api es 200 req/min. Los endpoints de
generación de reportes con Pandas ejecutarán queries pesadas sobre PostgreSQL
y pueden saturar CPU/RAM si no tienen límites propios.

### Decisión
Cada endpoint de reporte define su propio límite via decorador `@limiter.limit()`.
Endpoints de salud: 30 req/min. Reportes ligeros: 20 req/min.
Reportes pesados (Excel, PDF): 5 req/min.

### Consecuencias
Un cliente legítimo con muchos reportes simultáneos recibirá 429. Se documentará
en `docs/API-REFERENCE.md` con los headers `Retry-After` que flask-limiter emite.

---

## ADR-025 — Gestión de secretos: Docker Secrets vs HashiCorp Vault OSS

**Fecha:** 2026-03-22
**Estado:** DECIDIDO — Docker Secrets activo; Vault como siguiente paso documentado
**Categoría:** Seguridad — Gestión de secretos

### Contexto

El proyecto necesita gestionar secretos (contraseñas de BD, JWT secrets, API keys)
de forma segura en un VPS único con Docker Compose standalone (sin Swarm ni Kubernetes).

### Opciones evaluadas

#### Opción A — Variables de entorno directas en `.env.production`
- ❌ Secretos en texto plano en el filesystem del host
- ❌ Visibles en `docker inspect` y en `/proc/<pid>/environ`
- ❌ Se filtran fácilmente en logs o en accidentes de git

#### Opción B — Docker Secrets (archivos en `./secrets/`)
- ✅ Secretos montados como archivos read-only en `/run/secrets/`
- ✅ Solo visibles dentro del contenedor que los declara
- ✅ No aparecen en `docker inspect`
- ⚠️ Rotación requiere reiniciar el contenedor
- ⚠️ Sin audit log nativo (quién leyó qué, cuándo)

#### Opción C — HashiCorp Vault OSS
- ✅ API centralizada para secretos: `vault kv get secret/proyecto/db`
- ✅ Audit log completo (quién, cuándo, qué secreto)
- ✅ Rotación dinámica de secretos sin reiniciar contenedores
- ✅ TTL por secreto (expiración automática)
- ❌ Servicio adicional: ~200MB RAM extra en el VPS
- ❌ Complejidad operacional: Vault necesita ser inicializado, unsealado y respaldado
- ❌ Si Vault cae y no hay unsealing automático, todos los servicios fallan al arrancar

### Decisión

**Se elige Opción B (Docker Secrets)** para la fase actual por estas razones:

1. Proyecto personal con un solo desarrollador — no hay riesgo de acceso no autorizado interno
2. Un solo VPS — no hay necesidad de gestión centralizada multi-servidor
3. Los secretos no rotan frecuentemente — se generan una vez con `make secrets-init`
4. Vault añadiría un punto de falla adicional sin beneficio proporcional

### Cuándo migrar a Vault

La migración a Vault OSS está justificada cuando se cumpla **alguna** de estas condiciones:

| Condición | Señal de que Vault es necesario |
|-----------|--------------------------------|
| Múltiples servidores | Los secretos deben estar disponibles en N hosts |
| Múltiples desarrolladores | Audit log de quién accedió a qué |
| Secretos que rotan frecuentemente | API keys de terceros, certificados de corta vida |
| Compliance (SOC 2, ISO 27001) | Requieren audit trail y rotación forzada |
| Servicios efímeros (CI/CD agents) | Necesitan secretos temporales con TTL |

### Cómo funciona Vault (referencia para la migración futura)
```bash
# 1. Iniciar Vault en dev mode (no para producción)
docker run --cap-add=IPC_LOCK -p 8200:8200 hashicorp/vault server -dev

# 2. Guardar secretos
export VAULT_ADDR='http://127.0.0.1:8200'
vault kv put secret/proyecto/db \
  user=app_user \
  password=$(openssl rand -hex 32)

# 3. En el entrypoint del contenedor, obtener el secreto
export DB_PASSWORD=$(vault kv get -field=password secret/proyecto/db)
```

Para producción, usar el método de autenticación AppRole (el contenedor se autentica
con un `role_id` + `secret_id` para obtener un token temporal y leer sus secretos).

### Consecuencias de la decisión actual

- `./secrets/*.txt` están en `.gitignore` — nunca se versionan
- `make secrets-init` genera los archivos con `openssl rand`
- `make secrets-check` verifica que no contienen placeholders antes del deploy
- La rotación de cualquier secreto requiere: editar el archivo + `make prod-restart`

## ADR-026 — Reports-API delega validación de sesión al backend

**Fecha:** 2026-03-23
**Estado:** DECIDIDO
**Categoría:** Seguridad — Autenticación y autorización

### Contexto
Reports-API accede directamente a PostgreSQL con credenciales de solo lectura.
Para operar, necesita verificar que el usuario que solicita un reporte tiene una
sesión válida. Reports-API recibe cookies httpOnly del navegador.

### Decisión
Reports-API **nunca** verifica ni decodifica cookies JWT directamente.
Toda validación de sesión se delega al backend NestJS mediante `GET /api/auth/me`.
Reports-API reenvía la cookie `access_token` al backend y acepta o rechaza
según el código HTTP de respuesta.

### Justificación
- La clave JWT (`JWT_SECRET`) es un secreto del backend — reports-api no debe
  conocerla. Distribuir el secret aumenta la superficie de ataque.
- Si la lógica de validación de tokens cambia (algoritmo, claims, blacklist),
  solo cambia el backend. Reports-API no requiere cambios.
- Un único punto de verificación de sesión facilita auditoría y revocación.

### Consecuencias
- Reports-API tiene una dependencia de red en el backend para cada request autenticado.
- El timeout de validación es de 3 segundos (`NESTJS_AUTH_TIMEOUT`). Si el backend
  no responde, reports devuelve 503 al cliente.

### Restricción permanente
Nunca añadir `JWT_SECRET` como variable de entorno de reports-api.
Nunca importar `python-jose`, `pyjwt` u otras librerías JWT en reports-api
con el propósito de verificar tokens de sesión.

## ADR-027 — Perfil seccomp: perfil por defecto de Docker en lugar de perfil personalizado

**Fecha:** 2026-03-23
**Estado:** DECIDIDO
**Categoría:** Seguridad — Hardening de contenedores (CIS Docker Benchmark 5.2)

### Contexto

seccomp (Secure Computing Mode) es un mecanismo del kernel Linux que restringe
qué llamadas al sistema (syscalls) puede hacer un proceso dentro de un contenedor.
Cuando un proceso intenta invocar una syscall bloqueada, el kernel la deniega
antes de que el código de la aplicación la ejecute.

Existen tres niveles de configuración en Docker Compose:

| Valor en `security_opt` | Comportamiento |
|---|---|
| No declarado (actual) | Docker aplica su perfil por defecto — bloquea ~44 syscalls peligrosas |
| `seccomp:unconfined` | Desactiva toda restricción seccomp — el contenedor puede hacer cualquier syscall |
| `seccomp:/ruta/perfil.json` | Aplica un perfil personalizado, más o menos restrictivo que el por defecto |

El perfil por defecto de Docker bloquea syscalls como `ptrace`, `reboot`,
`kexec_load`, `mount`, `clone` con flags peligrosos, y otras ~40 más que no
tienen uso legítimo en una aplicación web.

### Opciones evaluadas

**Opción A — No declarar seccomp (actual)**
- ✅ Docker aplica automáticamente su perfil por defecto
- ✅ Cero configuración adicional
- ✅ Se actualiza con cada nueva versión de Docker
- ⚠️ No es visible en el compose — un auditor nuevo podría asumir que no hay restricción

**Opción B — Perfil personalizado más restrictivo**
- ✅ Reduce la superficie de ataque al mínimo estrictamente necesario
- ✅ Visible y auditable en el repositorio
- ❌ Requiere identificar exactamente qué syscalls necesita cada servicio
    (Node.js, Python/Gunicorn y Next.js tienen perfiles de syscalls diferentes)
- ❌ Riesgo de romper funcionalidad si se bloquea una syscall necesaria
- ❌ Mantenimiento: cada actualización de Node.js o Python puede requerir
    revisar el perfil

**Opción C — `seccomp:unconfined`**
- ❌ Desactiva toda protección seccomp — peor que no declarar nada
- ❌ Solo justificado en entornos de debugging o cuando una herramienta de
    profiling lo requiere explícitamente
- ❌ **Nunca usar en producción**

### Decisión

**Opción A — perfil por defecto de Docker, sin declaración explícita.**

El perfil por defecto cubre el caso de uso de una aplicación web estándar
(NestJS, Next.js, Flask/Gunicorn) sin configuración adicional.

La combinación actual ya cumple el CIS Docker Benchmark para hardening:
- `cap_drop: ALL` — elimina todas las capabilities Linux
- `no-new-privileges: true` — impide escalada de privilegios
- `read_only: true` — filesystem de solo lectura
- Perfil seccomp por defecto — bloquea syscalls peligrosas

### Cuándo revisar esta decisión

Migrar a un perfil personalizado (Opción B) cuando se cumpla alguna de estas condiciones:
- Auditoría formal requiere demostrar que las syscalls están explícitamente
  documentadas y restringidas (compliance SOC 2, ISO 27001)
- Se identifica un vector de ataque específico que el perfil por defecto no cubre
- El proyecto escala a múltiples servicios con perfiles de riesgo distintos

### Referencia para implementación futura

Para generar un perfil personalizado basado en las syscalls reales usadas:
```bash
# Capturar syscalls en desarrollo con strace
docker run --security-opt seccomp:unconfined \
  --pid=host nombre_del_proyecto_api \
  strace -f -e trace=all node dist/main.js 2>&1 | \
  grep "^[0-9]" | awk '{print $2}' | cut -d'(' -f1 | sort -u

# O usar el generador de perfiles de Docker:
# https://docs.docker.com/engine/security/seccomp/#significant-syscalls-blocked-by-the-default-profile
```

### Nota sobre AppArmor y SELinux

- **AppArmor** (Ubuntu): requiere perfiles por imagen y mantenimiento manual.
  Evaluado y pospuesto por la misma razón que los perfiles seccomp personalizados.
- **SELinux**: diseñado para RHEL/CentOS. No es el sistema de control de acceso
  obligatorio (MAC) por defecto en Ubuntu — activarlo requiere migrar el sistema
  operativo base o configuración avanzada fuera del alcance actual.

## ADR-028 — WAF (Web Application Firewall): ausente con justificación explícita

**Fecha:** 2026-03-23
**Estado:** DECIDIDO — Sin WAF activo; mitigaciones por capas documentadas
**Categoría:** Seguridad — Defensa en profundidad (OWASP A03:2021 Injection,
               A04:2021 Insecure Design)

### Contexto

Un WAF inspecciona el contenido de las peticiones HTTP (headers, body, query
params) antes de que lleguen a la aplicación, y bloquea patrones conocidos de
ataque: inyección SQL en la URL, intentos de XSS, path traversal, etc.

En esta arquitectura, Nginx actúa como reverse proxy pero no filtra el contenido
de las peticiones — solo hace routing y aplica rate limiting por IP.

### Opciones evaluadas

**Opción A — Sin WAF (actual)**
- ✅ Cero complejidad operacional adicional
- ✅ Sin falsos positivos que bloqueen usuarios legítimos
- ✅ La protección existe en capas de aplicación (ver sección de mitigaciones)
- ❌ Un payload malicioso llega al código de la aplicación sin filtrado previo

**Opción B — ModSecurity v3 + OWASP Core Rule Set (CRS) integrado en Nginx**
- ✅ Bloquea los ataques más comunes antes de que lleguen a Node.js o Python
- ✅ Open source, sin costo de licencia
- ✅ CRS actualizado continuamente por OWASP
- ❌ Falsos positivos frecuentes con APIs modernas que usan JSON en el body
    (el CRS fue diseñado principalmente para form-data y query strings)
- ❌ Requiere tuning extensivo en modo `DetectionOnly` antes de activar bloqueo
- ❌ Añade latencia en cada request (~1-5ms por evaluación de reglas)
- ❌ Módulo `nginx-modsecurity` no está en los repositorios oficiales de Ubuntu —
    requiere compilar Nginx con el módulo o usar paquetes de terceros

**Opción C — Servicio WAF gestionado (Cloudflare WAF, AWS WAF)**
- ✅ Sin mantenimiento de reglas, actualizaciones automáticas
- ✅ Protección DDoS incluida
- ❌ Costo mensual ($20-200/mes según proveedor y tráfico)
- ❌ El tráfico pasa por infraestructura de terceros
- ❌ Overengineering para un proyecto personal en etapa de plantilla

### Decisión

**Opción A — Sin WAF activo.** Las mitigaciones implementadas en capas de
aplicación cubren los vectores de ataque principales para el estado actual
del proyecto.

### Mitigaciones activas que reemplazan al WAF

La protección existe distribuida en varias capas. Ninguna capa por sí sola es
suficiente, pero la combinación cubre los mismos vectores que un WAF básico:

| Vector de ataque | Mitigación implementada | Capa |
|---|---|---|
| Inyección SQL | TypeORM con queries parametrizadas — nunca string interpolation | Backend |
| Inyección SQL en reports | Pydantic valida y tipifica todos los parámetros de entrada | Reports |
| XSS | CSP con nonce por request, `helmet` con directivas estrictas | Backend / Frontend |
| XSS en frontend | `forbidNonWhitelisted: true` en ValidationPipe | Backend |
| CSRF | Cookies `SameSite=strict`, CORS con whitelist explícita | Backend |
| Fuerza bruta / credential stuffing | Rate limiting en 3 capas: Nginx (30 req/s), NestJS Throttler, Flask-Limiter | Nginx / Backend / Reports |
| Ataques de header grande | `--limit-request-line 8190 --limit-request-fields 100` en Gunicorn | Reports |
| Path traversal | Rutas definidas explícitamente, ninguna sirve archivos dinámicos del filesystem | Todos |
| Enumeración de endpoints | `forbidNonWhitelisted`, 404 genérico, sin stack traces en producción | Backend |
| DDoS volumétrico básico | Rate limiting de Nginx (api_limit, login_limit, reports_limit) | Nginx |

### Cuándo añadir WAF

La incorporación de ModSecurity o un WAF gestionado está justificada cuando
se cumpla alguna de estas condiciones:

| Condición | Señal |
|---|---|
| Datos sensibles regulados | PII, datos de salud, datos financieros — compliance lo exige |
| Tráfico público significativo | >10k usuarios activos — el volumen justifica el tuning |
| Múltiples desarrolladores | Necesidad de auditar quién añadió qué regla |
| Ataques activos documentados | Logs muestran intentos repetidos de explotación |
| Requisito de cliente o auditoría | Contrato o certificación lo exige explícitamente |

### Procedimiento para activar ModSecurity en el futuro
```bash
# 1. Instalar módulo dinámico
sudo apt install libnginx-mod-security2

# 2. Descargar OWASP CRS
git clone https://github.com/coreruleset/coreruleset.git /etc/nginx/crs

# 3. Configurar en modo DetectionOnly (NUNCA empezar en bloqueo)
echo "SecRuleEngine DetectionOnly" >> /etc/modsecurity/modsecurity.conf

# 4. Monitorear logs durante 2 semanas y ajustar falsos positivos
sudo tail -f /var/log/nginx/modsec_audit.log

# 5. Activar bloqueo solo después del tuning
# SecRuleEngine On
```

---

## ADR-029: SameSite en Cookies de Autenticación

**Estado:** Activo
**Fecha:** Marzo 2026

---

## Contexto

Inicialmente se consideró usar `SameSite=Lax`, ya que es la configuración más común
y permite flujos de autenticación que incluyen redirecciones externas (por ejemplo,
OAuth o login desde otros dominios).

Sin embargo, este proyecto está diseñado para operar en un entorno controlado:

* Despliegue en un **single VPS**
* Uso en **redes empresariales internas**
* Sin necesidad actual de autenticación cross-site ni redirecciones externas
* Todos los servicios operan bajo el mismo dominio o subdominios controlados

En este contexto, permitir el envío de cookies en navegaciones cross-site introduce
una superficie de ataque innecesaria (principalmente CSRF).

---

## Decisión

Se adopta el uso de cookies de autenticación con la siguiente configuración:

* `httpOnly`
* `Secure` (en producción)
* `SameSite=Strict`

```typescript
// NestJS — emisión de cookie en login
res.cookie('access_token', accessToken, {
  httpOnly: true,       // Inaccesible desde JavaScript (protección contra XSS)
  secure: isProduction, // Solo HTTPS en producción
  sameSite: 'strict' as const, // No se envía en requests cross-site (protección CSRF)
  maxAge: 15 * 60 * 1000,
});
```

El frontend delega el manejo de cookies al navegador:

```typescript
// Frontend — envío automático de cookies
fetch(`${API_BASE}${endpoint}`, {
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
});
```

---

## ADR-030: SPA navegación cross-site: Uso de SameSite

### 🔒 Seguridad

* `httpOnly` evita acceso a cookies desde JavaScript → mitiga robo por XSS
* `SameSite=Strict` bloquea completamente el envío de cookies en contextos cross-site
* Reduce significativamente el riesgo de ataques CSRF sin necesidad de mecanismos adicionales

### 🧱 Alineación con la arquitectura

* El sistema no depende de:

  * OAuth externo
  * SSO federado
  * integraciones cross-domain
* Todas las interacciones ocurren dentro de un dominio controlado

Por tanto, no es necesario permitir comportamiento cross-site.

---

## Alternativas consideradas

| Opción           | Evaluación                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| `SameSite=Lax`   | Permite cookies en navegación top-level (GET). Útil para OAuth, pero innecesario en este sistema |
| `SameSite=None`  | Requiere `Secure` y permite cookies en todos los contextos → mayor superficie de ataque          |
| `localStorage`   | Vulnerable a XSS                                                                                 |
| `sessionStorage` | Vulnerable a XSS                                                                                 |
| Memory (JS)      | Seguro pero pierde persistencia                                                                  |
| Token en URL     | Exposición en logs, historial y headers                                                          |

---

## Consecuencias

### ✅ Positivas

* Protección fuerte contra CSRF sin implementar tokens adicionales
* Reducción de superficie de ataque
* Comportamiento consistente y predecible en entorno controlado

### ⚠️ Limitaciones

* Las cookies no se enviarán en ningún contexto cross-site
* No funcionan directamente:

  * OAuth (Google, Microsoft, etc.)
  * login federado
  * redirecciones desde otros dominios

---

## Decisión futura / extensibilidad

Si en el futuro se requiere:

* autenticación externa (OAuth, SSO)
* integración con terceros
* login desde otro dominio

Se deberá modificar la configuración a:

```typescript
sameSite: 'lax'
```

o evaluar `SameSite=None` junto con medidas adicionales (CSRF tokens, validación de origen, etc.).

Este cambio debe documentarse mediante una actualización de este ADR o uno nuevo.

---

## Implicaciones de arquitectura

* Backend:

  * Debe emitir `Set-Cookie` en login
  * Debe limpiar cookies en logout (`clearCookie`)
* Frontend:

  * Debe usar `credentials: 'include'` en todas las requests
* CORS:

  * `ALLOWED_ORIGINS` debe ser explícito (no se permite `*`)
* Clientes no-browser:

  * Deben usar `Authorization: Bearer` como mecanismo alternativo

---

## Resumen

Se adopta `SameSite=Strict` para maximizar la seguridad en un entorno cerrado,
donde no se requiere compatibilidad cross-site, priorizando la mitigación de CSRF
sobre la flexibilidad de integración externa.

---

## ADR-031: Desactivar DB_SSL_REQUIRED en entornos controlados

## 🧠 Contexto

La plantilla del backend y reports está diseñada para ejecutarse en un **entorno controlado y cerrado**, donde:

- Los servicios (backend, reports, base de datos, etc.) se comunican dentro de una red privada
- No existen conexiones externas directas a la base de datos
- El acceso está restringido a través de contenedores (Docker) o red interna
- No hay exposición pública del puerto de base de datos

Por defecto, muchas configuraciones recomiendan habilitar:

DB_SSL_REQUIRED=true

Esto fuerza el uso de SSL/TLS en las conexiones a la base de datos.

Sin embargo, en este proyecto:

- La comunicación ocurre dentro de una red interna confiable
- El uso de SSL añade complejidad operativa (certificados, configuración, errores)
- No aporta un beneficio significativo en este contexto específico

---

## ⚖️ Decisión

Se define que:

DB_SSL_REQUIRED=false

por defecto en la plantilla.

---

## ✅ Justificación

### 1. Entorno cerrado (Trusted Network)

La arquitectura está diseñada para:

- Docker Compose / redes internas
- Sin exposición pública de la base de datos
- Acceso limitado a servicios autorizados

Esto reduce significativamente el riesgo de:

- Intercepción de tráfico (MITM)
- Acceso no autorizado

---

### 2. Simplicidad operativa

Habilitar SSL implica:

- Gestión de certificados
- Configuración adicional en cliente y servidor
- Posibles errores de conexión (especialmente en desarrollo)

Mantener SSL desactivado:

- Reduce fricción en desarrollo
- Simplifica despliegues locales y CI/CD

---

### 3. Seguridad en capas (Defense in Depth)

La seguridad se garantiza mediante:

- Aislamiento de red (Docker network)
- No exposición de puertos de DB
- Control de acceso a servicios
- Uso de variables de entorno seguras

---

### 4. Preparado para producción externa

El código **YA soporta SSL**, pero está:

- Comentado
- Documentado
- Listo para activarse

Ejemplo:

```typescript
ssl: isProduction
  ? { rejectUnauthorized: true, ca: process.env.DB_SSL_CA ?? undefined }
  : false,
```

---

## 🔄 Alternativa considerada

### ✔ Activar SSL siempre (DB_SSL_REQUIRED=true)

**Ventajas:**
- Mayor seguridad en redes no confiables
- Cumplimiento de estándares corporativos

**Desventajas:**
- Complejidad innecesaria en entornos cerrados
- Sobrecarga de configuración
- Problemas comunes en desarrollo local

---

## ⚠️ Riesgos

Si el entorno deja de ser cerrado y SSL sigue desactivado:

- Posible exposición a ataques MITM
- Intercepción de credenciales de base de datos

---

## 🛡️ Mitigaciones

- Documentar claramente esta decisión (este ADR)
- Requerir SSL en entornos públicos
- Validar configuración en producción

---

## 🚀 Cuándo ACTIVAR SSL

Se debe activar DB_SSL_REQUIRED=true cuando:

- La base de datos esté expuesta fuera de la red interna
- Se utilicen servicios gestionados (RDS, Cloud SQL, etc.)
- Exista acceso desde internet o redes no confiables
- Se requiera cumplimiento (ISO, SOC2, etc.)

---

## 🧩 Implementación

Para activar SSL:

DB_SSL_REQUIRED=true

Y en el código (ya soportado) descomentar

---

## 📌 Consecuencias

### Positivas

- Menor complejidad en desarrollo
- Configuración más simple
- Menos errores de conexión

### Negativas

- Menor seguridad si se usa fuera del entorno previsto
- Requiere disciplina al migrar a producción abierta

---

## 📚 Referencias

- OWASP: Transport Layer Protection
- PostgreSQL SSL Docs
- Docker Networking Best Practices

---

## 🔐 Conclusión

> SSL no se desactiva por descuido, sino por decisión consciente basada en el contexto.

La plantilla prioriza:

- Simplicidad
- Entorno controlado
- Flexibilidad futura

Con soporte completo para endurecimiento cuando sea necesario.

---

## ADR-032: Desactivar ejecución automática de scripts en gestores de paquetes (ignore-scripts)

## 🧠 Contexto

Los gestores de paquetes modernos permiten la ejecución automática de scripts durante la instalación de dependencias, tales como:

- preinstall
- install
- postinstall

En ecosistemas como Node.js, Python y PHP, estos scripts pueden ejecutar código arbitrario en el entorno donde se instalan las dependencias.

Esto introduce riesgos significativos de seguridad, especialmente cuando:

- Se instalan dependencias de terceros
- Existen dependencias transitivas no auditadas
- Se ejecutan instalaciones en entornos sensibles (CI/CD, servidores, contenedores)

---

## ⚠️ Problema

La ejecución automática de scripts puede permitir:

- Ejecución de código malicioso
- Robo de variables de entorno (tokens, credenciales)
- Instalación de puertas traseras (backdoors)
- Persistencia no autorizada en el sistema
- Compromiso de pipelines de CI/CD

---

## ⚖️ Decisión

Se establece como política obligatoria:

**Desactivar la ejecución automática de scripts en todas las instalaciones de dependencias.**

---

## ✅ Implementación

### Node.js / PNPM (estándar del proyecto)

Configuración obligatoria en cada proyecto:

.npmrc
ignore-scripts=true


Instalación:
pnpm install --ignore-scripts

Configuración global recomendada:
pnpm config set ignore-scripts true

---

### NPM

npm install --ignore-scripts
npm config set ignore-scripts true

---

### Yarn

yarn install --ignore-scripts

---

### Python (pip)

Uso de instalación reproducible:

pip install --require-hashes -r requirements.txt

Opcional:
pip install --no-build-isolation --no-cache-dir

---

### Docker (obligatorio)


RUN pnpm install --ignore-scripts

Refuerzo adicional:
RUN pnpm config set ignore-scripts true

---

## ⚠️ Excepciones controladas

Algunos paquetes requieren scripts para funcionar correctamente:

- prisma
- sharp
- playwright

### Procedimiento obligatorio:

1. Instalar sin scripts:
pnpm install --ignore-scripts

2. Ejecutar manualmente solo lo necesario:
pnpm exec <comando>


Ejemplo:
pnpm exec prisma generate

---

## 🔄 Alternativas consideradas

### ❌ Permitir scripts automáticamente (comportamiento por defecto)

**Ventajas:**
- Mayor compatibilidad
- Instalación más simple

**Desventajas:**
- Alto riesgo de ejecución de código malicioso
- Pérdida de control sobre el entorno
- Superficie de ataque ampliada

---

### 🟡 Uso de allowlist (@pnpm/allow-scripts)

**Ventajas:**
- Control granular
- Balance entre seguridad y funcionalidad

**Desventajas:**
- Mayor complejidad operativa
- Requiere mantenimiento continuo

---

## 🧠 Justificación

### 1. Principio de mínimo privilegio

Los paquetes no deben ejecutar código sin autorización explícita.

---

### 2. Zero Trust en dependencias

Ninguna dependencia externa es confiable por defecto.

---

### 3. Seguridad en la cadena de suministro (Supply Chain Security)

Ataques modernos se enfocan en:

- Dependencias comprometidas
- Typosquatting
- Inyección en paquetes populares

---

### 4. Control explícito de ejecución

Separar:

- Instalación de dependencias
- Ejecución de código

---

## ⚠️ Riesgos

- Algunas dependencias pueden fallar sin scripts
- Mayor carga operativa para desarrolladores
- Requiere conocimiento técnico del equipo

---

## 🛡️ Mitigaciones

- Documentación clara (este ADR)
- Procedimientos de excepción definidos
- Automatización en CI/CD
- Uso de lockfiles
- Auditorías periódicas

---

## 📌 Consecuencias

### Positivas

- Reducción significativa de riesgos de seguridad
- Mayor control del entorno de ejecución
- Protección en CI/CD y producción
- Prevención de ataques de cadena de suministro

---

### Negativas

- Instalación más manual
- Posibles errores iniciales en dependencias
- Necesidad de ejecutar pasos adicionales

---

## 🚀 Aplicabilidad

Esta política aplica a:

- Desarrollo local
- Contenedores Docker
- CI/CD
- Entornos de producción

---

## 🔐 Cumplimiento

El incumplimiento de esta política puede resultar en:

- Ejecución de código malicioso
- Compromiso del sistema
- Exposición de credenciales

---

## 📚 Referencias

- OWASP: Software Supply Chain Security
- npm security advisories
- Node.js Security Best Practices

---

## 🔒 Conclusión

> La instalación de dependencias no debe implicar ejecución automática de código.

Este ADR establece un modelo de seguridad basado en:

- Control explícito
- Desconfianza por defecto
- Minimización de superficie de ataque

La ejecución de scripts queda restringida a acciones conscientes y controladas.

---

## ADR-033: /metrics en el mismo puerto que la API

Estado: Activo
Fecha: Marzo 2026

Decisión: el endpoint de métricas de Prometheus se expone en el mismo puerto que 
la API (:4000/metrics) en lugar de un puerto separado.

Justificación: Single VPS, 3 contenedores, complejidad extra de port innecesaria.
Protección: MetricsAuthGuard con HTTP Basic Auth (credenciales en Docker Secrets).

Consecuencia: si MetricsAuthGuard tiene un bug, /metrics queda expuesto.
Escalación: mover a puerto dedicado (ej: :9100) si se añade un proxy externo.

---

## ADR-034: Firma de Imágenes de Contenedor con Cosign

**Estado:** Proyectado (no implementado)
**Fecha:** Marzo 2026

### Contexto

Actualmente, el pipeline de deploy descarga imágenes de Docker por tag o SHA.
No hay verificación criptográfica de que la imagen fue construida por el CI
y no fue alterada en tránsito o en el registry.

Un atacante con acceso al registry podría reemplazar una imagen con código malicioso
y el deploy lo descargaría sin detectarlo.

### Decisión

**Pospuesto.** Implementar cosign cuando se configure un registry privado (GHCR o similar).
La verificación actual por SHA de commit es suficiente para un VPS personal sin registry centralizado.

### Implementación futura (cuando esté el registry)
```bash
# Prerequisito: generar par de claves cosign
cosign generate-key-pair
# → cosign.key (privada, NO al repo), cosign.pub (pública, sí al repo)

# CI — firmar imagen después de push:
cosign sign --key cosign.key ghcr.io/org/backend:$GIT_SHA

# Deploy — verificar firma antes de pull:
cosign verify --key cosign.pub ghcr.io/org/backend:$EXPECTED_SHA
docker pull ghcr.io/org/backend:$EXPECTED_SHA
```

### Alternativas consideradas

| Opción | Por qué se descartó |
|---|---|
| Verificación solo por SHA | Actual — suficiente sin registry |
| Docker Content Trust (Notary) | Complejo, requiere infraestructura adicional |
| **cosign (Sigstore)** | **Elegido para implementación futura — estándar CNCF** |
| Buildkit attestations | Más nuevo, menos adopción |

### Consecuencias

- Sin cosign: un compromiso del registry puede desplegar código malicioso sin detección
- Con cosign: el deploy falla si la imagen no tiene firma válida del CI

**Escalación:** implementar en el sprint siguiente al setup del registry GHCR.

---

## ADR-035: Lectura del Pepper de Contraseñas — Tiempo de Módulo vs Lazy

**Estado:** Activo (tiempo de módulo) / Proyectado cambio a lazy
**Fecha:** Marzo 2026

### Contexto

`password.service.ts` lee el `PEPPER_SECRET` al cargar el módulo (tiempo de importación):
```typescript
// Implementación actual — tiempo de módulo:
const PEPPER = readSecret('PEPPER_SECRET_FILE', 'PEPPER_SECRET') ?? '';
```

Esto significa que el valor se fija cuando Node.js carga el archivo por primera vez
y no puede cambiarse sin reiniciar el servidor.

### Decisión actual

**Mantener lectura en tiempo de módulo.** Para el estado actual de la plantilla
(sin tests unitarios de `hashPassword` ni rotación dinámica de pepper), este
enfoque es más simple y seguro: el valor se valida al arrancar.

### Consecuencias del enfoque actual

- El pepper se valida en el arranque — fail-fast ✅
- No se puede cambiar sin reinicio del servidor (aceptable) ✅
- Los tests unitarios de `hashPassword` requieren manipular `process.env` ⚠️

### Migración futura — Cuando implementar el cambio

Implementar cuando ocurra alguno de estos casos:
1. Se escriben tests unitarios de `hashPassword` o `verifyPassword`
2. Se implementa rotación de pepper sin reinicio del servidor

### Código de migración futura
```typescript
// filepath: backend/src/auth/password.service.ts
// Versión lazy con cache — permite mockear en tests sin manipular process.env

import * as argon2 from 'argon2';
import { readSecret } from '@config/secrets';
import { Logger } from 'nestjs-pino';

let _PEPPER_CACHE: string | null = null;

/**
 * Lee el pepper con lazy initialization y cache.
 * Permite mockear en tests: jest.spyOn(module, 'getPepper').mockReturnValue('test-pepper')
 */
export function getPepper(): string {
  const logger = new Logger('PasswordService');
  if (_PEPPER_CACHE !== null) return _PEPPER_CACHE;

  const pepper = readSecret('PEPPER_SECRET_FILE', 'PEPPER_SECRET') ?? '';

  if (process.env.NODE_ENV !== 'production' && pepper.startsWith('CAMBIAR_')) {
    logger.warn('PEPPER_SECRET usa placeholder. Ejecuta: make setup');
  }
  if (process.env.NODE_ENV === 'production' && (!pepper || pepper.startsWith('CAMBIAR_'))) {
    throw new Error('[password.service] PEPPER_SECRET inválido en producción.');
  }

  _PEPPER_CACHE = pepper;
  return _PEPPER_CACHE;
}

// Función de reset para tests (no exportar en producción):
// export function _resetPepperCache() { _PEPPER_CACHE = null; }

const ARGON2_OPTIONS: argon2.Options = {
  type: argon2.argon2id,
  memoryCost: 65536,
  timeCost: 3,
  parallelism: 4,
};

export async function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain + getPepper(), ARGON2_OPTIONS);
}

export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain + getPepper());
  } catch {
    return false;
  }
}
```

### Uso en tests con la versión lazy
```typescript
// En tests unitarios:
import * as passwordModule from '../auth/password.service';

beforeEach(() => {
  jest.spyOn(passwordModule, 'getPepper').mockReturnValue('test-pepper-seguro-12345');
});

afterEach(() => {
  jest.restoreAllMocks();
});

it('hashPassword genera hash válido', async () => {
  const hash = await hashPassword('MiPassword123!');
  expect(hash).toMatch(/^\$argon2id\$/);
});
```

### Alternativas consideradas

| Opción | Ventaja | Desventaja |
|---|---|---|
| **Tiempo de módulo (actual)** | Simple, fail-fast al arrancar | Tests requieren process.env |
| **Lazy con cache** | Mockeable en tests | Algo más complejo |
| **Inyección de dependencias** | Máxima flexibilidad | Overhead de DI para un valor estático |

---

## ADR-036: Gestión de Secretos en Equipo — Infisical vs Vault vs Docker Secrets

**Estado:** Proyectado (no implementado)
**Fecha:** Marzo 2026

### Contexto

El proyecto actual usa Docker Secrets (archivos en `secrets/`) sin Swarm.
Este enfoque es suficiente para 1 desarrollador en VPS único.
Si el equipo crece (2+ desarrolladores), surge el problema de sincronización
de secretos: ¿cómo comparten los secretos de forma segura sin subirlos al repo?

### Opciones consideradas

| Herramienta | Tipo | Coste | Complejidad | Mejor para |
|---|---|---|---|---|
| Docker Secrets (actual) | File-based | Gratis | Mínima | 1 dev, VPS único |
| SOPS + GPG | Archivos cifrados en repo | Gratis | Media | Equipo pequeño con GPG |
| **Infisical** | SaaS / Self-hosted OSS | Gratis (cloud limitado) | Baja | Equipos, multi-env |
| HashiCorp Vault | Self-hosted | Gratis OSS | Alta | Grandes empresas |
| AWS Secrets Manager | SaaS | ~$0.40/secreto/mes | Media | Proyectos en AWS |

### Decisión

**Pospuesto.** Implementar Infisical cuando el equipo supere 2 desarrolladores
o cuando sea necesario gestionar secretos en múltiples entornos (staging, prod, UAT).

### Por qué Infisical sobre Vault

- **Vault** requiere Alta Disponibilidad para ser confiable, gestión de tokens,
  renovación de leases, y conocimiento operacional elevado.
  Para un equipo pequeño, el overhead operacional supera el beneficio.

- **Infisical** tiene una UI web clara, SDKs para Node.js y Python,
  integración nativa con Docker y GitHub Actions, y puede desplegarse
  como contenedor Docker adicional sin complejidad de cluster.

### Implementación futura con Infisical
```bash
# docker-compose.infisical.yml (cuando sea necesario)
services:
  infisical:
    image: infisical/infisical:latest
    ports:
      - "127.0.0.1:8080:8080"
    env_file: .env.infisical
    volumes:
      - infisical_data:/app/data
```
```typescript
// backend — leer secretos desde Infisical en lugar de Docker Secrets:
import { InfisicalClient } from "@infisical/sdk";
const client = new InfisicalClient({ token: process.env.INFISICAL_TOKEN });
const secret = await client.getSecret({ secretName: "DB_PASSWORD", environment: "prod" });
```

### Consecuencias de no implementar ahora

- Los secretos se comparten manualmente entre desarrolladores (aceptable para 1 persona)
- Sin auditoría de quién accedió a qué secreto
- Sin rotación automática de secretos

**Escalación:** revisar esta decisión cuando el equipo supere 2 personas.

---

## Matriz de riesgos

| Riesgo | Probabilidad | Impacto | Mitigación actual | Estado |
|---|---|---|---|---|
| Credenciales expuestas en repositorio | Baja | Crítico | `.gitignore` + Docker Secrets + `.env.example` sin valores reales | ✅ Mitigado |
| Vulnerabilidad en imagen base | Media | Alto | trivy + grype en CI/CD + Renovate semanal | ✅ Mitigado |
| PostgreSQL inaccesible (contenedores) | Baja | Alto | `host-gateway` + healthchecks Level 2 (pendiente) | ⚠️ Parcial |
| Deploy fallido sin rollback | Baja | Alto | `make rollback-db` + `make backup-db` en crontab | ✅ Mitigado |
| Contenedor consume toda la RAM del servidor | Baja | Alto | `mem_limit` + `memswap_limit` en todos los servicios | ✅ Mitigado |
| Acceso directo a servicios sin pasar por Nginx | Baja | Medio | Puertos bound a `127.0.0.1` | ✅ Mitigado |
| Imagen con dependencias vulnerables (Python) | Media | Medio | pip-audit + trivy en CI | ✅ Mitigado |
| Cambio en imagen base rompe el build | Baja | Medio | Digests SHA256 + Renovate PRs | ✅ Mitigado |
| Sin observabilidad (logs, métricas) | Alta | Medio | Logs con rotación, `make audit-full` | ⚠️ Parcial (sin métricas) |
| Backup manual olvidado | Media | Alto | Crontab en README.md | ⚠️ No automatizado en make |