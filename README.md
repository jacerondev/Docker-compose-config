# NOMBRE_DEL_PROYECTO

> Las imágenes base se actualizan automáticamente vía Renovate. Revisa y aprueba los PRs generados antes de mergear.

---

# 🚀 DEPLOY A PRODUCCIÓN — NOMBRE_DEL_PROYECTO

**Última actualización:** 17 de Marzo de 2026
**Mantenedor1:** Nombre desarrollador
**Soporte2:** devopsNombreEmpresa@gmail.com

---

## ⚠️ ESTADO ACTUAL — PLANTILLA EMPRESARIAL

Este repositorio es una **plantilla base**. La infraestructura está lista para producción. La lógica de negocio está pendiente de implementar:

| Componente                     | Estado               | Notas                                  |
| ------------------------------ | -------------------- | -------------------------------------- |
| Docker / CI/CD / Monitoring    | ✅ Production Ready  | Listo para usar                        |
| Auth endpoints (`/api/auth/*`) | 🔶 Temporal          | Guard activo, devuelve usuario mock    |
| JWT real con base de datos     | 🔶 Temporal          | Implementar `AuthService` logica       |
| Reports endpoints              | 🔶 Esqueleto         | Añadir lógica en `reports/src/routes/` |
| Frontend UI                    | 🔶 Página de ejemplo | Reemplazar `frontend/src/app/page.tsx` |

**Para activar la autenticación real:** ver `backend/src/auth/auth.controller.ts` — todos los TODOs están documentados.

---

## ¿Qué es este sistema?

NOMBRE_DEL_PROYECTO es una plataforma de [descripción del negocio]:

- **Backend (NestJS):** gestiona [funcionalidad de negocio]
- **Frontend (Next.js):** interfaz de usuario para [usuarios]
- **Reports API (Flask):** genera reportes Excel/PDF de [datos]
- **Base de datos (Postgresql):** Maneja el sistema de datos [Explicación de diseño]

---

## 📋 REQUISITOS PREVIOS

En tu servidor:

- Ubuntu 20.04+ o Debian 11+
- Docker 20.10+
- Docker Compose v2
- PostgreSQL 15+
- Nginx
- Dominio configurado con DNS apuntando al servidor

---

## ⚠️ LEER ANTES DEL DEPLOY: Control de Recursos

Los límites de CPU y RAM se definen con `mem_limit` y `cpus` (nivel raíz del servicio), **no** con `deploy.resources`. Esto es importante porque `deploy.resources` solo funciona en Docker Swarm y se ignora completamente en Compose standalone.

**Valores configurados actualmente:**

| Servicio    | CPU     | RAM      | Justificación                    |
| ----------- | ------- | -------- | -------------------------------- |
| backend     | 1.0     | 1G       | NestJS estable con 1 core        |
| frontend    | 0.5     | 512M     | Next.js standalone es liviano    |
| reports-api | 2.0     | 2G       | Pandas/Excel consume CPU + RAM   |
| **Total**   | **3.5** | **3.5G** | Pensado para servidor de 4 cores |

Verificar cores del servidor:

```bash
nproc               # Número de cores lógicos
lscpu | grep CPU    # Detalle completo
```

Ejemplo para servidor de 2 cores — ajustar en `docker-compose.prod.yml`:

```yaml
backend:
  mem_limit: 512m
  cpus: "0.5"
frontend:
  mem_limit: 256m
  cpus: "0.3"
reports-api:
  mem_limit: 1g
  cpus: "0.9"
```

---

## 🔧 PREPARACIÓN DEL SERVIDOR

### 1. Actualizar sistema

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Instalar Docker

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
docker --version && docker compose version
```

### 3. Instalar PostgreSQL (PostgreSQL en el host)

Este proyecto **no** incluye PostgreSQL como contenedor. La base de datos corre directamente en tu máquina.

```bash
sudo apt install postgresql postgresql-contrib -y
sudo systemctl status postgresql
```

### 4. Instalar Nginx

```bash
sudo apt install nginx -y
sudo systemctl status nginx
```

### 5. Instalar Make

```bash
sudo apt install make -y
make --version
```

### 6. Instalar Hadolint (Producción)

```bash
wget -O hadolint https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64
chmod +x hadolint && sudo mv hadolint /usr/local/bin/
```

### 7. Instalar Trivy (Producción)

```bash
sudo apt install trivy
```

> Tu usuario debe tener **UID 1000** para que los volúmenes de Docker funcionen sin problemas de permisos.
> Verifica con: `id -u`

---

## 📦 DEPLOY

## Arrancar el proyecto

```bash
make help     # Lista completa de comandos disponibles
make dev      # Desarrollo con logs en pantalla
make dev-bg   # Desarrollo en segundo plano
```

| Comando       | Logs        | Terminal | Contenedores al cerrar terminal |
| ------------- | ----------- | -------- | ------------------------------- |
| `make dev`    | En pantalla | Ocupada  | Se detienen                     |
| `make dev-bg` | `make logs` | Libre    | Siguen corriendo                |

### PASO 1: Clonar proyecto

```bash
sudo mkdir -p /opt/
sudo chown $USER:$USER /opt/nombre_del_proyecto
cd /opt && git clone https://github.com/tu-usuario/nombre_del_proyecto.git
cd nombre_del_proyecto
```

### PASO 2: Configurar variables de entorno

## Desarrollo

```bash
make setup
```

`make setup` se encarga automáticamente de:

- Crear el archivo `.env` desde `.env.example`
- Crear la base de datos en PostgreSQL
- Construir las imágenes de Docker
- Crear las carpetas `logs/backend` y `logs/reports`

## Producción

```bash
make prod-setup
```

`make prod-setup` se encarga automáticamente de:

- Crear el archivo `.env.production` desde `.env.prod.example`
- Crear la base de datos en PostgreSQL
- Construir las imágenes de Docker
- Crear las carpetas `logs/backend` y `logs/reports`

Cambiar:

- `NEXT_PUBLIC_API_URL` → https://api.tudominio.com
- `NEXT_PUBLIC_REPORTS_URL` → https://reports.tudominio.com
- `ALLOWED_ORIGINS` → https://tudominio.com,https://www.tudominio.com
- `DB_HOST`, `DB_PORT`, `DB_NAME` → valores reales (sin contraseña aquí)

### PASO 3: Configurar secretos (Producción)

Los secretos sensibles (contraseñas, tokens) van en archivos separados, nunca en `.env.production`:

```bash
make secrets-init                  # Crea la carpeta secrets/ con archivos template
nano secrets/db_password.txt       # Escribir la contraseña real
nano secrets/db_user.txt           # Escribir el usuario real
nano secrets/grafana_password.txt  # Escrbirir la contraseña real
nano secrets/metrics_user.txt      # 
nano secrets/metrics_password.txt  # Escrbirir la contraseña real
# secrets/jwt_secret.txt           # Actualmente se realiza con make secrets-init autogenerado
# secrets/pepper_secret.txt        # Actualmente se realiza con make secrets-init autogenerado
# chmod 600 secrets/*.txt          # Actualmente se realiza con make secrets-init el comando
make secrets-check                 # Verifica que todo está configurado
```
> La carpeta `secrets/` está en `.gitignore`. Nunca se versiona.

Dentro del contenedor, la app lee los secretos desde `/run/secrets/<nombre>`:

```javascript
// Node.js — leer secreto desde archivo
const password = fs.readFileSync("/run/secrets/db_password", "utf8").trim();
```

```python
# Python — leer secreto desde archivo
password = open('/run/secrets/db_password').read().strip()
```

### PASO 4: Configurar PostgreSQL (Producción)

```bash
sudo -u postgres psql << EOF
CREATE DATABASE nombre_del_proyecto_db;
CREATE USER user_prod WITH PASSWORD 'TuPasswordReal';
GRANT ALL PRIVILEGES ON DATABASE nombre_del_proyecto_db TO user_prod;
\q
EOF

# Permitir conexiones desde Docker
sudo nano /etc/postgresql/15/main/postgresql.conf
# listen_addresses = 'localhost'

sudo nano /etc/postgresql/15/main/pg_hba.conf
# host    nombre_del_proyecto_db    user_prod    172.16.0.0/12    scram-sha-256

sudo systemctl restart postgresql
```

Para procedimientos avanzados (migraciones, backups, disaster recovery, secrets management),
ver [DATABASE.md](docs/guides/DATABASE.md).

Para procedimientos avanzados (migraciones, backups, disaster recovery, secrets management, gestión de credenciales),
ver [DATABASE.md](docs/guides/DATABASE.md).

### PASO 5: Deploy

```bash
make prod          # Deploy directo (validaciones + migraciones + up)
```

### PASO 6: Verificar

```bash
make logs                                    # Ver logs en tiempo real
docker ps --filter "health=healthy"          # Deben aparecer los 3 servicios
curl http://localhost:4000/health            # Backend
curl http://localhost:3000                   # Frontend
curl http://localhost:5000/health            # Reports
```

---

## Seguridad y Validación

### Linting de Dockerfiles (Hadolint)

**Uso:**

```bash
make lint-docker          # Escanea todos los Dockerfiles

# O manualmente (comandos individuales):
hadolint backend/.docker/Dockerfile
hadolint frontend/.docker/Dockerfile
hadolint reports/.docker/Dockerfile
find . -name "Dockerfile*" -exec hadolint {} \;
```

> Los comandos manuales anteriores son equivalentes a `make lint-docker`, que los ejecuta todos internamente con manejo de errores.

---

### Escaneo de vulnerabilidades (Trivy)

**Uso:**

```bash
make scan-security           # Escanea imágenes de producción (trivy image)
make trivy-config-scan       # Trivy: escanea Dockerfiles (misconfigurations)

# Escaneo de configuración de Dockerfiles:
trivy config frontend/.docker/Dockerfile.prod
trivy config backend/.docker/Dockerfile.prod
trivy config reports/.docker/Dockerfile.prod

# Escaneo de filesystem (dependencias del código fuente):
trivy fs backend/
trivy fs frontend/
trivy fs reports/
```

> `make scan-security` ejecuta `trivy image` contra las imágenes construidas, que es más completo que `trivy config` o `trivy fs`. Los comandos manuales son útiles para diagnósticos específicos.

---

### Pipeline de auditoría completo

```bash
make install-tools    # Instala syft y grype (una sola vez)
make doctor           # Verifica entorno, herramientas y archivos críticos
make audit-full       # Ejecuta el pipeline completo:
                      #   1. lint-docker (hadolint)
                      #   2. audit-requirements (pip-audit)
                      #   3. scan-security (trivy image)
                      #   4. sbom (syft — genera SBOMs en scripts/tests/)
                      #   5. system-check (estado del sistema)
```

**Evidencia generada en `scripts/tests/`:**

```
scripts/tests/
├── alerts.log           Resultado de escaneos hadolint y trivy (lint Dockerfiles)
├── trivy-config.log     trivy config (misconfiguraciones)
├── security-scan.log    Resultado de Trivy (vulnerabilidades en imágenes)
├── pnpm-audit.log       pnpm audit (CVEs en dependencias Node.js)
├── pip-audit.log        pip-audit (CVEs en dependencias Python)
├── sbom-backend.log     SBOM CycloneDX backend
├── sbom-report.json     SBOM en formato CycloneDX (inventario de paquetes)
├── sbom-frontend.json   SBOM CycloneDX frontend
└── system-check.log     Estado del sistema en producción
```

---

### SBOM (Software Bill of Materials)

El SBOM es un inventario completo de todos los paquetes dentro de cada imagen Docker.

```bash
make sbom              # Genera SBOMs usando syft instalado localmente
make sbom-docker       # Genera SBOMs vía Docker (no requiere instalar syft)
```

**¿Para qué sirve sbom-report.json?**

- Lista exacta de cada paquete y versión dentro de la imagen
- Permite detectar vulnerabilidades futuras sin rebuild
- Requerido en auditorías empresariales y estándares como ISO 27001
- Usado por grype para escanear vulnerabilidades

---

### Grype — Escáner de vulnerabilidades en imágenes

```bash
make grype-scan        # Falla si encuentra HIGH o CRITICAL (comportamiento CI)
make grype-scan-docker # Misma funcionalidad vía Docker
```

---

### Integración en CI/CD

El proyecto incluye escaneos automáticos en GitHub Actions:

- ✅ Hadolint valida todos los Dockerfiles en cada PR
- ✅ Trivy escanea vulnerabilidades en cada push a main
- ✅ SARIF sube a la pestaña Security de GitHub
- ✅ El build falla si hay vulnerabilidades CRITICAL/HIGH

Ver: `.github/workflows/security.yml` y `.github/workflows/ci.yml`

---
### Configurar Branch Protection en GitHub

Para que `hadolint` y `trivy` sean **obligatorios** antes de mergear:

1. GitHub → Settings → Branches → Add branch protection rule
2. Branch: `main`
3. Activar: **Require status checks to pass before merging**
4. Añadir checks: `Lint Dockerfiles (hadolint)` y `Vulnerability Scan (trivy)`
5. Activar: **Require branches to be up to date before merging**

---

## 🔐 ROTACIÓN DE SECRETOS

**Política de rotación recomendada:**

- Contraseñas de DB: cada 90 días
- Si hay sospecha de compromiso: inmediata

Para procedimiento completo de rotación de secretos (auditoría, logging, política de 90 días),
ver [SECRETS-MANAGEMENT.md](docs/SECRETS-MANAGEMENT.md#procedimiento-estándar).

En resumen: `make secrets-init` → editar `/opt/backups/.backup_key` → `make prod`

---

## Actualización de dependencias Python (reports)

No necesitas Python instalado localmente. Todo corre en Docker.

```bash
make audit-requirements      # Verifica CVEs en dependencias actuales

# Para actualizar requirements.txt con nuevas versiones:
# 1. Editar reports/requirements.in con las nuevas versiones
# 2. Regenerar con hashes:
make update-requirements
# 3. Revisar el diff:
git diff reports/requirements.txt
```

---

## Actualizar digests SHA256 de imágenes base

Las imágenes base están fijadas a digests SHA256 para builds reproducibles.
Renovate actualiza los digests automáticamente vía PR semanal.

Para actualizar manualmente:

```bash
make show-digests   # Muestra los digests actuales
```

Luego editar los `FROM` en:

- `backend/.docker/Dockerfile.prod` (2 referencias)
- `frontend/.docker/Dockerfile.prod` (3 referencias)
- `reports/.docker/Dockerfile.prod` (2 referencias)

---

## Comandos disponibles

### ▶ INICIO Y CONFIGURACIÓN

```bash
make help                  # Ver todos los comandos disponibles
make setup                 # Configuración inicial (primera vez)
make prod-setup            # Configuración inicial producción (primera vez)
make pre-commit-setup      # Configura git hooks (una sola vez)
make check-setup           # Verifica que make setup fue ejecutado (antes de dev/prod)
make check-secrets         # Verifica que los secrets de producción están configurados
make doctor                # Verifica entorno, herramientas y archivos críticos
make validate              # Valida docker-compose sin build (rápido)
make validate-build        # Construye todas las imágenes desde cero (para CI)
make validate-env          # Verifica .env contra .env.example
make validate-env-prod     # Verifica .env.production contra .env.prod.example
make validate-all          # ⭐ Validación COMPLETA antes de deploy
make troubleshoot          # Muestra tips de solución para problemas comunes
```

### 🔧 DESARROLLO

```bash
make dev                   # Arranca servicios (logs en pantalla, terminal ocupada)
make dev-bg                # Arranca servicios en background (terminal libre)
make build                 # Construye imágenes de desarrollo sin arrancar
make stop                  # Detiene todos los servicios
make clean                 # Elimina contenedores y volúmenes
make prune                 # Limpia imágenes y recursos huérfanos (libera disco)
make health-check          # Verifica el estado de salud de los 3 servicios
make wait-healthy          # Espera a que los 3 servicios estén healthy (timeout: 5 min)
make stats                 # Muestra uso de CPU y RAM de los contenedores (una lectura)
```

### 🔧 MONITOREO AVANZADO

```bash
make monitoring-config     # Genera alertmanager.yml y prometheus.yml desde templates
make monitoring-up         # Levanta Prometheus + Grafana (desarrollo)
make monitoring-up-prod    # Levanta Prometheus + Grafana + Alertmanager (producción)
make monitoring-alert-test # Dispara alerta de prueba al Alertmanager → verifica Slack
make monitoring-down       # Detiene el stack de monitoreo
make monitoring-logs       # Ver logs del stack de monitoreo en tiempo real
make monitoring-ps         # Estado de contenedores del stack de monitoreo
```

### 🚀 PRODUCCIÓN/BACKUP

```bash
make prod                  # Deploy a producción (validaciones + migraciones + up)
make backup-db             # Backup manual cifrado de PostgreSQL → /opt/backups/
make backup-db-decrypt     # Descifra un backup para inspección o restauración
make rollback-db           # Restaura el backup más reciente de PostgreSQL
make setup-cron            # Instala backup automático diario (cron)
make check-cron            # Verifica si el cron job está activo
make remove-cron           # Elimina el cron job de backup
```

### 🔐 SECRETOS

```bash
make secrets-init          # Crea carpeta secrets/ con archivos template
make secrets-check         # Verifica que los secretos existen y son válidos
```

### 🛡️ SEGURIDAD Y AUDITORÍA

```bash
make install-tools         # Instala syft y grype con verificación de integridad
make lint-docker           # Valida Dockerfiles con hadolint
make trivy-config-scan     # Trivy: escanea Dockerfiles (misconfigurations)
make scan-security         # Trivy: escanea imágenes construidas
make audit-requirements    # Audita dependencias Python con pip-audit
make audit-pnpm            # Audita dependencias pnpm (backend + frontend)
make sbom                  # Genera SBOM con syft (local)
make sbom-docker           # Genera SBOM con syft (vía Docker)
make grype-scan            # Escanea vulnerabilidades con grype (falla en HIGH/CRITICAL)
make grype-scan-docker     # Escanea vulnerabilidades con grype (vía Docker)
make audit-full            # ★ Pipeline completo de auditoría (todos los escaneos)
```

### 📋 LOGS Y DIAGNÓSTICO

```bash
make logs                  # Ver logs de todos los servicios en tiempo real
make logs-backend          # Ver logs del backend
make logs-frontend         # Ver logs del frontend
make logs-reports          # Ver logs del reports-api
make config                # Muestra la configuración resuelta de docker-compose
```

### 🔨 MANTENIMIENTO

```bash
make test                  # Corre tests del backend con reporte de cobertura
make lint                  # Linter del backend
make update-requirements   # Regenera requirements.txt con hashes SHA256
make show-digests          # Muestra digests SHA256 de imágenes base actuales
```

### 🔨 BASES DE DATOS

```bash
make db-migrate            # Ejecuta las migraciones de TypeORM pendientes
make db-migration-generate # Genera migración desde cambios en entidades (uso: make db-migration-generate NAME=NombreCambio)
make db-migration-create   # Crea migración vacía para editar manualmente (uso: make db-migration-create NAME=AjusteEspecial)
make db-migration-show     # Muestra el estado de las migraciones (pendientes y aplicadas)
make db-rollback           # Revierte la última migración de TypeORM
make db-seed               # Carga datos iniciales en la base de datos (seed)
```

### 🐚 TERMINALES INTERACTIVAS

```bash
make shell-backend         # Abre terminal interactiva en el contenedor backend
make shell-frontend        # Abre terminal interactiva en el contenedor frontend
make shell-reports         # Abre terminal interactiva en el contenedor reports-api
```

## Ambientes

Para referencia completa de archivos `.env` y variables soportadas, 
ver [ENV-VARIABLES.md](docs/ENV-VARIABLES.md).

**En desarrollo:** `make setup` copia `.env.example` → `.env`
Editar `.env` manualmente en desarrollo, nunca commitearlo

**En producción:** `make prod-setup` copia `.env.prod.example` → `.env.production`
Editar `.env.production` manualmente en servidor, nunca commitearlo

---

## 🌐 CONFIGURAR NGINX

Para la guía completa de configuración de Nginx (instalación, SSL con Certbot, headers de 
seguridad, rate limiting, troubleshooting), consulta la [Guía de Nginx](docs/guides/NGINX.md).

**En breve — Resumen rápido:**

```bash
# 1. Crear archivo de configuración
sudo nano /etc/nginx/sites-available/nombre_del_proyecto

# 2. Activar
sudo ln -s /etc/nginx/sites-available/nombre_del_proyecto /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 3. SSL (Certbot configura automáticamente)
sudo certbot --nginx -d tudominio.com -d api.tudominio.com

# 4. Firewall
sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable
```

Para configuración completa de Nginx (instalación, SSL, headers, rate limiting y troubleshooting),
ver [Guía de Nginx](docs/guides/NGINX.md).

---

### Rate Limiting — Dos capas de protección

El proyecto implementa rate limiting en **dos niveles complementarios**:
1. **Nginx** (nivel de red) — bloquea antes de llegar a Node.js ([ver Guía](docs/guides/NGINX.md#rate-limiting-en-nginx))
2. **NestJS** (`@nestjs/throttler`) — protege la lógica de negocio

**Capa 2 — NestJS (aplicación):**

```typescript
// app.module.ts — protección global
ThrottlerModule.forRoot([
  { name: 'short', ttl: 1000, limit: 10 },    // 10 req/seg por IP
  { name: 'medium', ttl: 60000, limit: 100 }, // 100 req/min por IP
])

// auth.controller.ts — login con límite estricto
@Throttle({ short: { limit: 5, ttl: 60000 } })  // 5 intentos/min
@Post('login')
async login() { ... }
```

Cuando se supera el límite: **HTTP 429 Too Many Requests**

**¿Por qué dos capas?**

- **Nginx** bloquea sin consumir recursos de Node.js — protege contra DDoS básico
- **NestJS** puede limitar por usuario autenticado (no solo por IP) — protege la lógica de negocio
- Son complementarios: Nginx es la muralla exterior, NestJS es la guardia interior

### Verificar que rate limiting funciona

```bash
# Probar rate limiting del backend (30 req/min → después del burst, bloquea)
for i in {1..15}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://api.tudominio.com/health)
    echo "Request $i: HTTP $STATUS"
done
# Esperado: 200 200 200 ... 200 (burst) ... 503 (bloqueado por Nginx)

# Probar rate limiting del login (5 intentos/min)
for i in {1..7}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST http://api.tudominio.com/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{"email":"test@test.com","password":"wrong"}')
    echo "Login intento $i: HTTP $STATUS"
done
# Esperado: 401 401 401 401 401 429 429 (bloquea al 6to intento)
```

---

## 🔒 CONFIGURAR SSL (HTTPS)

Para instalación, certificados con Certbot y troubleshooting de SSL,
ver [Guía de Nginx — SSL con Certbot](docs/guides/NGINX.md#ssl-con-certbot).

---

## 🔥 FIREWALL

```bash
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
sudo ufw status
```

---

## 🚨 SEGURIDAD ADICIONAL

### Fail2ban

```bash
sudo apt install fail2ban -y
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd   # Ver IPs baneadas
```

### SSH key-only

```bash
sudo nano /etc/ssh/sshd_config
# PasswordAuthentication no
# PubkeyAuthentication yes
sudo systemctl restart ssh
```

---

## 🔄 ACTUALIZACIÓN

```bash
cd /opt/nombre_del_proyecto
git pull origin main
make prod
```

---

## 💾 BACKUPS

### Base de datos

**Uso:**

```bash
make backup-db   # Backup cifrado automáticamente con AES-256-CBC

# O manualmente (comandos individuales):
# Backup manual
sudo -u postgres pg_dump nombre_del_proyecto_db > /opt/backups/nombre_del_proyecto_$(date +%Y%m%d_%H%M).sql
```

```bash
make rollback-db   # Restaura backup más reciente de forma segura

# O manualmente (comandos individuales):
# Restore
sudo -u postgres psql nombre_del_proyecto_db < /opt/backups/nombre_del_proyecto_20260224_1400.sql
```

**Backup automatizado (crontab):**

```bash
make setup-cron   # Instala backup automático diario
make check-cron   # Verifica si está activo
make remove-cron  # Desactiva el cron job

# O manualmente (comandos individuales):
sudo crontab -e
# Backup diario a las 2am, retener 30 días:
0 2 * * * pg_dump -U postgres nombre_del_proyecto_db > /opt/backups/nombre_del_proyecto_$(date +\%Y\%m\%d).sql && find /opt/backups -name "*.sql" -mtime +30 -delete
```

### Backups — Cifrado de seguridad

Los backups se cifran automáticamente con AES-256-CBC:

```bash
make backup-db          # Backup cifrado → /opt/backups/*.sql.gz.enc
make backup-db-decrypt  # Descifrar para restaurar o inspeccionar
```

**Cómo funciona el cifrado:**

1. `pg_dump` genera el SQL
2. `gzip` lo comprime (~10x menos tamaño)
3. `openssl enc -aes-256-cbc -pbkdf2` lo cifra con la clave en `/opt/backups/.backup_key`

**⚠️ IMPORTANTE — La clave de cifrado:**

- Se genera automáticamente en el primer backup en `/opt/backups/.backup_key`
- **Copia esta clave a un lugar seguro** (gestor de contraseñas, Vault, etc.)
- Sin la clave, los backups cifrados son irrecuperables
- Permisos: `chmod 600 /opt/backups/.backup_key`

**Restaurar desde backup cifrado:**

```bash
make backup-db-decrypt   # Descifra el archivo seleccionado
# Luego restaurar el .sql.gz descomprimido:
gunzip backup.sql.gz
sudo -u postgres psql nombre_db < backup.sql
```

**Verificar integridad del backup:**

```bash
# Probar que el cifrado es correcto sin restaurar:
openssl enc -d -aes-256-cbc -pbkdf2 \
  -pass file:/opt/backups/.backup_key \
  -in /opt/backups/nombre_del_proyecto_prod_20260310.sql.gz.enc \
  | gunzip | head -5
# Debe mostrar las primeras líneas del SQL
```

---

## 📊 AUDITORÍA Y EVIDENCIA

**Generar toda la evidencia en una sola ejecución:**

```bash
make audit-full    # Genera toda la evidencia en scripts/tests/
```

**Archivos generados y cómo interpretarlos:**

```
scripts/tests/
├── alerts.log              Lint de Dockerfiles (hadolint)
├── trivy-config.log        Misconfiguraciones en Dockerfiles  
├── security-scan.log       Vulnerabilidades en imágenes construidas
├── pnpm-audit.log          CVEs en node_modules (backend + frontend)
├── pip-audit.log           CVEs en dependencias Python (reports)
├── sbom-backend.log        Inventario de paquetes del backend
├── sbom-frontend.log       Inventario de paquetes del frontend
├── sbom-report.json        SBOM CycloneDX (formato estándar)
└── system-check.log        Health check del sistema
```

**Interpretación de resultados:**

```bash
# Sin vulnerabilidades (PASSED)
grep "PASSED" scripts/tests/security-scan.log

# Vulnerabilidades encontradas
grep -E "CRITICAL|HIGH" scripts/tests/security-scan.log

# Problemas en Dockerfiles
cat scripts/tests/alerts.log | grep -i "error"

# Ver inventario de paquetes
cat scripts/tests/sbom-report.json | jq '.components[] | {name, version}'
```

---

## 📋 CHECKLIST POST-DEPLOY

**Verificaciones críticas (ejecutar en orden):**

```bash
# Paso 1: Contenedores corriendo y saludables
make health-check

# Paso 2: Verificar servicios específicos
curl -s http://localhost:4000/health | jq .    # Backend
curl -s http://localhost:3000 | head -20        # Frontend  
curl -s http://localhost:5000/health | jq .    # Reports

# Paso 3: Base de datos conectada
make db-migrate          # Ejecutar migraciones pendientes
make db-migration-show   # Verificar migraciones aplicadas

# Paso 4: Nginx y SSL
sudo nginx -t            # Syntax check
curl -I https://api.tudominio.com/health

# Paso 5: Seguridad
sudo ufw status          # Firewall habilitado
sudo systemctl status fail2ban
make secrets-check       # Todos los secretos configurados

# Paso 6: Recursos
make stats               # CPU/RAM por servicio
docker stats --no-stream # Ver límites configurados

# Paso 7: Logs
make logs | head -50     # Ver últimos logs (Ctrl+C para salir)
grep -i "error" logs/backend/*.log 2>/dev/null | head -10
```

**Checklist en forma de tickets:**

- [ ] Servicios healthy: `make health-check` ✅
- [ ] Backend responde en `http://localhost:4000`
- [ ] Frontend responde en `http://localhost:3000`
- [ ] Reports responde en `http://localhost:5000`
- [ ] PostgreSQL conectada: `make db-migration-show`
- [ ] Migraciones ejecutadas sin errores
- [ ] Nginx con SSL: `curl -I https://api.tudominio.com`
- [ ] Firewall activo: `sudo ufw status | grep Status`
- [ ] Fail2ban funcionando: `sudo fail2ban-client status`
- [ ] Secretos cargados: `make secrets-check`
- [ ] Límites de memoria activos: `docker stats --no-stream`
- [ ] Logs sin errores CRITICAL: `grep CRITICAL logs/**/*.log`
- [ ] Monitoreo activo: `make monitoring-up-prod`
- [ ] Alertas funcionando: `make monitoring-alert-test`
- [ ] SBOM generado: `make sbom` y `scripts/tests/sbom-report.json` existe

---

## 📞 COMANDOS ÚTILES POST-DEPLOY

**Monitoreo en tiempo real:**

```bash
make logs                    # Ver logs de todos los servicios
make logs-backend            # Solo backend
make logs-frontend           # Solo frontend  
make logs-reports            # Solo reports
make stats                   # CPU/RAM de contenedores (una lectura)
make health-check            # Estado de salud detallado
docker stats --no-stream     # Monitoreo continuo
```

**Stack de monitoreo (Prometheus + Grafana + Alertmanager):**

```bash
make monitoring-up-prod          # Levantar monitoreo completo
make monitoring-alert-test       # Enviar alerta de prueba a Slack
make monitoring-logs             # Ver logs de Prometheus/Grafana
make monitoring-down             # Detener monitoreo

# Acceder a interfaces
# Grafana: http://localhost:3001
# Prometheus: http://localhost:9090
# Alertmanager: http://localhost:9093
```

**Diagnóstico y troubleshooting:**

```bash
make troubleshoot                         # Tips automáticos de solución
make config                               # Ver configuración resuelta
make validate                             # Validar docker-compose sin construir
make doctor                               # Verificar entorno y herramientas
make shell-backend                        # Terminal interactiva en backend
make shell-frontend                       # Terminal interactiva en frontend
make shell-reports                        # Terminal interactiva en reports
```

**Información del sistema:**

```bash
# Ver qué versiones están corriendo
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

# Ver límites de memoria configurados
docker inspect nombre_del_proyecto_api | jq '.[0].HostConfig.Memory'

# Ver variables de entorno en producción
docker inspect nombre_del_proyecto_api | jq '.[0].Config.Env'

# Verificar volúmenes montados
docker inspect nombre_del_proyecto_api | jq '.[0].Mounts'

# Ver histórico de cambios
git log --oneline -10

# Verificar commits no deployados
git status
```

---

### Rollback de emergencia

```bash
# Paso 1: Detener los servicios con problemas
make stop

# Paso 2: Restaurar la base de datos al último backup
make rollback-db   # Pide confirmación antes de ejecutar

# Paso 3: Volver al código anterior
git log --oneline -5   # Ver commits recientes
git checkout <COMMIT_ANTERIOR>

# Paso 4: Redesplegar la versión anterior
make prod

# Paso 5: Verificar que todo está healthy
docker ps --filter "health=healthy"
curl http://localhost:4000/health
curl http://localhost:3000
curl http://localhost:5000/health

# Registrar el incidente:
echo "$(date): rollback a $(git rev-parse HEAD) — motivo: deploy fallido" \
  >> scripts/tests/incidents.log
```

---

### Ver qué versiones están corriendo actualmente

```bash
docker inspect nombre_del_proyecto_api    | grep -i "image\|tag"
docker inspect nombre_del_proyecto_web    | grep -i "image\|tag"
docker inspect nombre_del_proyecto_reports | grep -i "image\|tag"

# O más simple:
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

---

## 🚀 DESARROLLO DEL BACKEND (NestJS)

La arquitectura del backend (módulos, DTOs, TypeORM, JWT, Prometheus, logging) está documentada 
en [BACKEND-NESTJS.md](docs/guides/BACKEND-NESTJS.md).

**Guía rápida:**
- [Estructura de módulos](docs/guides/BACKEND-NESTJS.md#1-estructura-de-módulos--15-módulos-planificados)
- [Crear módulo nuevo](docs/guides/BACKEND-NESTJS.md#2-cómo-crear-un-módulo-nuevo)
- [DTOs y validación](docs/guides/BACKEND-NESTJS.md#4-dtos--validación-obligatoria-vs-opcional)
- [Autenticación JWT](docs/guides/BACKEND-NESTJS.md#6-autenticación-jwt)

---

## 🎨 DESARROLLO DEL FRONTEND (Next.js)

El frontend usa Next.js 15 con App Router. Ve la guía completa en 
[FRONTEND-NEXTJS.md](docs/guides/FRONTEND-NEXTJS.md) para estructura, testing y deployment.

---

## 📊 DESARROLLO DE REPORTES (Flask/Python)

La API de reportes (Flask, Gunicorn, Excel/PDF) está documentada en 
[REPORTS-PYTHON.md](docs/guides/REPORTS-PYTHON.md).

---

### 🔧 MONITOREO AVANZADO

**Guías especializadas:**
- [Alertmanager](docs/guides/MONITORING-ALERTMANAGER.md) — Configurar alertas y canales (Slack)
- [Business Metrics](docs/guides/MONITORING-BUSINESS-METRICS.md) — Métricas personalizadas
- [Logs centralizados](docs/guides/MONITORING-LOKI-PROMTAIL.md) — Loki + Promtail

---

## 🛡️ OPERACIONES EN PRODUCCIÓN

**Guías operacionales:**
- [RUNBOOK-OPERACIONAL.md](docs/guides/RUNBOOK-OPERACIONAL.md) — Playbooks, failover, incident response
- [TROUBLESHOOTING.md](docs/guides/TROUBLESHOOTING.md) — Errores comunes y diagnóstico

---

## � DOCUMENTACIÓN COMPLETA

### Despliegue & Configuración
- [DOCKER-COMPOSE-GUIDE.md](docs/DOCKER-COMPOSE-GUIDE.md) — Arquitectura de archivos compose
- [DEPLOYMENT-CHECKLIST.md](docs/DEPLOYMENT-CHECKLIST.md) — Pre/durante/post-deploy
- [ENV-VARIABLES.md](docs/ENV-VARIABLES.md) — Variables de entorno
- [SECRETS-MANAGEMENT.md](docs/SECRETS-MANAGEMENT.md) — Gestión y rotación de secretos

### Mantenimiento & Actualización
- [UPGRADE.md](docs/UPGRADE.md) — Actualizar código, dependencias, imágenes
- [MIGRATION-GUIDE.md](docs/MIGRATION-GUIDE.md) — Migraciones de datos y esquema
- [DISASTER-RECOVERY.md](docs/DISASTER-RECOVERY.md) — Recuperación ante fallos

### Referencias & Arquitectura
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Arquitectura general del sistema
- [API-REFERENCE.md](docs/API-REFERENCE.md) — Referencia completa de endpoints
- [DATA-DICTIONARY.md](docs/DATA-DICTIONARY.md) — Diccionario de datos

### Operacional & Roadmap
- [ONBOARDING.md](docs/ONBOARDING.md) — Guía de inicio rápido
- [TESTING.md](docs/TESTING.md) — Estrategia de testing, E2E, integración
- [PERFORMANCE.md](docs/PERFORMANCE.md) — Optimización y benchmarks
- [MONITORING-ROADMAP.md](docs/MONITORING-ROADMAP.md) — Roadmap de monitoreo
- [ROADMAP.md](docs/ROADMAP.md) — Roadmap del proyecto

---

## Licencia

Este proyecto está bajo la licencia MIT.

- Versión oficial: LICENSE
- Traducción al español: LICENSE.es.md
