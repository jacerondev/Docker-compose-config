# docs/guides/DATABASE.md — Guía de PostgreSQL

**Proyecto:** NOMBRE_DEL_PROYECTO
**Audiencia:** DevOps / desarrollador que configura el servidor o trabaja con la DB
**Última actualización:** Marzo 2026

> PostgreSQL corre en el HOST, fuera de Docker, tanto en desarrollo como en producción.
> Ver `DECISIONS.md ADR-006` para la justificación completa.
> En desarrollo se usa un contenedor PostgreSQL gestionado por `docker-compose.override.yml`.

> ⚠️ **El usuario `postgres` es el superusuario del sistema.**
> Nunca usar `postgres` como usuario de aplicación en producción.
> Tiene permisos para eliminar cualquier base de datos, crear roles,
> leer datos de todos los schemas y modificar la configuración del servidor.
> 
> La aplicación siempre usa `nombre_del_proyecto_user` (backend) o
> `reports_reader` (reports), ambos sin privilegios de superusuario.

---

## Índice

- [Crear la primera migración](#crear-la-primera-migración)
- [Desarrollo vs Producción](#desarrollo-vs-producción)
- [Instalación en producción (host)](#instalación-en-producción-host)
- [Configuración inicial de la base de datos](#configuración-inicial-de-la-base-de-datos)
- [Usuarios y privilegios](#usuarios-y-privilegios)
- [Permitir conexiones desde Docker](#permitir-conexiones-desde-docker)
- [Migraciones con TypeORM](#migraciones-con-typeorm)
- [Backup y restore](#backup-y-restore)
- [Gestión de contraseñas (rotación de secretos)](#gestión-de-contraseñas-rotación-de-secretos)
- [Monitoreo y mantenimiento](#monitoreo-y-mantenimiento)
- [Troubleshooting](#troubleshooting)
- [SSL de base de datos](#ssl-de-base-de-datos)

---

## Crear la primera migración

Cuando añadas la primera entidad (ej: User), genera la migración:
```bash
# 1. Compilar TypeScript
pnpm run build

# 2. Generar migración (TypeORM lee las entidades compiladas)
make db-migration-create NAME=InitialSchema

# Equivalente a:
# pnpm typeorm migration:generate src/migrations/InitialSchema -d ormconfig.ts

# 3. Revisar el archivo generado en src/migrations/
# 4. Aplicar:
make db-migrate
```

**Nunca cambiar `synchronize: true` en producción.** Si se necesita sincronización automática en desarrollo, se puede activar condicionalmente:
```typescript
synchronize: !isProduction && process.env.ALLOW_SYNC === 'true',
```

---

## Desarrollo vs Producción

| Aspecto | Desarrollo | Producción |
|---|---|---|
| Dónde corre | Contenedor Docker (`docker-compose.override.yml`) | Host (instalado con apt) |
| Cómo conectan los servicios | Por nombre de servicio Docker `postgres` | Por `host-gateway` (IP del host) |
| Credenciales | Variables de entorno en `.env` | Docker Secrets en `./secrets/` |
| Arranque | Automático con `make dev` | Servicio systemd `postgresql` |
| Datos | Volumen Docker `postgres_dev_data` | Directorio `/var/lib/postgresql/` |
| Backups | No necesarios (datos de prueba) | Automáticos con `make setup-cron` |

---

## Instalación en producción (host)

```bash
# Ubuntu 22.04 / 24.04
sudo apt update
sudo apt install -y postgresql postgresql-contrib

# Verificar que está corriendo
sudo systemctl status postgresql
sudo systemctl enable postgresql     # Arranque automático al reiniciar

# Verificar versión
psql --version
```

---

## Configuración inicial de la base de datos

Estos pasos se hacen **una sola vez** al preparar el servidor de producción.

```bash
# Conectar como superusuario de PostgreSQL
sudo -u postgres psql

-- Crear el rol de la aplicación (sin superuser, sin createdb)
CREATE ROLE nombre_del_proyecto_user WITH
  LOGIN
  PASSWORD 'contraseña_segura_aquí'    -- usar openssl rand -base64 32
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE;

-- Crear la base de datos de producción
CREATE DATABASE nombre_del_proyecto_prod
  OWNER nombre_del_proyecto_user
  ENCODING 'UTF8'
  LC_COLLATE 'es_CO.UTF-8'   -- ajustar según idioma del proyecto
  LC_CTYPE   'es_CO.UTF-8'
  TEMPLATE template0;

-- Verificar
\l                             -- lista todas las bases de datos
\du                            -- lista todos los roles
\q                             -- salir
```

**Guardar las credenciales como Docker Secrets:**
```bash
echo "nombre_del_proyecto_user"               > secrets/db_user.txt
echo "contraseña_segura_aquí"     > secrets/db_password.txt
chmod 600 secrets/db_user.txt secrets/db_password.txt
make secrets-check
```

---

## Usuarios y privilegios

El proyecto usa dos usuarios de PostgreSQL con principio de mínimo privilegio:

| Usuario | Privilegios | Usado por | Creado en |
|---|---|---|---|
| `nombre_del_proyecto_user` | `ALL PRIVILEGES` en la DB | Backend (NestJS) | Manual en prod / `make setup` en dev |
| `reports_reader` | Solo `SELECT` en todas las tablas | Reports-API (Flask) | Automático via `config/init-db.sh` |

### Crear el usuario read-only en producción

En producción PostgreSQL corre en el host. Ejecutar **una sola vez** como superusuario:
```bash
sudo -u postgres psql -d nombre_del_proyecto_prod <<EOF
CREATE USER reports_reader WITH PASSWORD 'contraseña_desde_secrets';
GRANT CONNECT ON DATABASE nombre_del_proyecto_prod TO reports_reader;
GRANT USAGE ON SCHEMA public TO reports_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reports_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO reports_reader;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO reports_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO reports_reader;
EOF
```

Guardar las credenciales:
```bash
echo "reports_reader" > secrets/db_read_only_user.txt
echo "contraseña_generada" > secrets/db_read_only_password.txt
chmod 600 secrets/db_read_only_user.txt secrets/db_read_only_password.txt
```

> En desarrollo, `config/init-db.sh` crea este usuario automáticamente al hacer
> `make dev` la primera vez (o `docker compose down -v && make dev` para recrear).

---

## Permitir conexiones desde Docker

Los contenedores Docker necesitan llegar a PostgreSQL usando `host-gateway`.
Por defecto PostgreSQL solo acepta conexiones locales. Hay que configurar dos archivos:

### 1. `postgresql.conf` — escuchar en todas las interfaces

```bash
# Encontrar el archivo de configuración
sudo -u postgres psql -c "SHOW config_file;"

# Editar (la ruta puede variar según la versión)
sudo nano /etc/postgresql/16/main/postgresql.conf

# Cambiar (o añadir):
listen_addresses = 'localhost'    # Mantener localhost — Docker accede via host-gateway
# NO poner '*' — innecesario y menos seguro
```

> En la práctica, `host-gateway` resuelve a la IP del bridge de Docker (ej: `172.17.0.1`),
> que a su vez llega a `localhost` del host. Con `listen_addresses = 'localhost'` funciona.
> Si no funciona, cambiar a la IP específica del bridge: `172.17.0.1`.

### 2. `pg_hba.conf` — autorizar conexiones del rol de la app

```bash
sudo nano /etc/postgresql/16/main/pg_hba.conf

# Añadir al final (antes de las líneas existentes de IPv6):
# Permite al usuario nombre_del_proyecto_user conectar desde la red Docker (172.17.0.0/16)
# sin usar SSL (la red es local — el tráfico no sale del servidor)
host  nombre_del_proyecto_prod  nombre_del_proyecto_user  172.17.0.0/16  scram-sha-256
```

```bash
# Aplicar cambios
sudo systemctl reload postgresql

# Verificar desde el host que acepta conexiones
psql -U nombre_del_proyecto_user -h 127.0.0.1 -d nombre_del_proyecto_prod -c "SELECT version();"
```

---

## Migraciones con TypeORM

El proyecto usa `synchronize: false` en producción (ver `backend/src/config/database.config.ts`).
Los cambios de schema deben hacerse con migraciones explícitas.

La primera migración, la que TypeORM genera al comparar entidades con una base de datos vacía debe llamarse convencionalmente InitialSchema. Esto es importante porque:

1. TypeORM ordenará y ejecutará migraciones en orden alfanumérico-cronológico.
2. El nombre InitialSchema establece que no hay estado previo a este punto.
3. Si se usa un nombre genérico (Migration1, Test, etc.) el historial de migraciones queda ilegible.

```bash
# Generar una migración automáticamente (compara entidades con la DB actual)
cd backend
pnpm run migration:generate -- src/migrations/NombreDeLaMigracion

# Ver qué migraciones están pendientes
pnpm run migration:show

# Aplicar todas las migraciones pendientes
make db-migrate

# Revertir la última migración (en emergencias)
make db-rollback

make db-migration-generate NAME=InitialSchema
# genera: backend/src/migrations/1710000000000-InitialSchema.ts
```

**Flujo de trabajo de migraciones:**
1. Modificar la entidad TypeORM en `backend/src/`
2. `pnpm run migration:generate` en local → genera archivo en `src/migrations/`
3. Revisar el SQL generado antes de hacer commit
4. El CI ejecuta las migraciones automáticamente en el deploy (si `migrationsRun: true`)
   o manualmente con `make db-migrate` después del deploy

> **NUNCA** usar `synchronize: true` en producción. Puede borrar columnas o datos.

---

## Backup y restore

### Backup manual
```bash
# Backup completo con compresión y cifrado
make backup-db

# El backup se guarda en: backups/nombre_del_proyecto_prod_YYYY-MM-DD_HH-MM-SS.sql.gz.enc
# Ver Makefile para la clave de cifrado (GPG o openssl)
```

### Backup automático con cron
```bash
# Configurar backup diario a las 2am
make setup-cron

# Verificar que el cron está activo
make check-cron

# Ver los últimos backups
ls -lh backups/
```

### Restore
```bash
# Descifrar el backup
make backup-db-decrypt BACKUP_FILE=backups/nombre_del_proyecto_prod_2026-03-10_02-00-00.sql.gz.enc

# Restaurar (ATENCIÓN: reemplaza la base de datos actual)
make rollback-db BACKUP_FILE=backups/nombre_del_proyecto_prod_2026-03-10_02-00-00.sql.gz

# Ver escenario completo en docs/DISASTER-RECOVERY.md → Escenario 3
```

---

## Gestión de contraseñas (rotación de secretos)

```bash
# 1. Generar nueva contraseña
NEW_PASS=$(openssl rand -base64 32)

# 2. Cambiar en PostgreSQL
sudo -u postgres psql -c "ALTER ROLE nombre_del_proyecto_user PASSWORD '$NEW_PASS';"

# 3. Actualizar el secret de Docker
echo "$NEW_PASS" > secrets/db_password.txt
chmod 600 secrets/db_password.txt

# 4. Reiniciar los contenedores para que lean el nuevo secret
make prod

# 5. Verificar que los servicios arrancan correctamente
make wait-healthy
make health-check
```

---

## Monitoreo y mantenimiento

```bash
# Ver conexiones activas
sudo -u postgres psql -c "SELECT pid, usename, application_name, state, query_start FROM pg_stat_activity WHERE datname = 'nombre_del_proyecto_prod';"

# Ver tamaño de la base de datos
sudo -u postgres psql -c "SELECT pg_size_pretty(pg_database_size('nombre_del_proyecto_prod'));"

# VACUUM ANALYZE — limpiar y actualizar estadísticas (programar mensual)
sudo -u postgres psql -d nombre_del_proyecto_prod -c "VACUUM ANALYZE;"

# Verificar índices no utilizados (candidatos a eliminar)
sudo -u postgres psql -d nombre_del_proyecto_prod -c "
  SELECT schemaname, tablename, indexname, idx_scan
  FROM pg_stat_user_indexes
  WHERE idx_scan = 0
  ORDER BY schemaname, tablename;"
```

---

## Troubleshooting

### Error: `ECONNREFUSED` desde los contenedores

```bash
# 1. Verificar que PostgreSQL está corriendo
sudo systemctl status postgresql

# 2. Verificar que escucha en la interfaz correcta
sudo -u postgres psql -c "SHOW listen_addresses;"

# 3. Verificar que host-gateway resuelve a la IP del host
docker exec nombre_del_proyecto_api ping host-gateway -c 2
# Si no funciona, usar la IP directa:
docker exec nombre_del_proyecto_api nc -zv 172.17.0.1 5432

# 4. Verificar pg_hba.conf
sudo grep nombre_del_proyecto /etc/postgresql/*/main/pg_hba.conf
```

### Error: `password authentication failed`

```bash
# Verificar que el secret tiene el valor correcto
cat secrets/db_password.txt

# Verificar que PostgreSQL tiene la misma contraseña
sudo -u postgres psql -c "\du nombre_del_proyecto_user"
# Intentar login manual:
psql -U nombre_del_proyecto_user -h 127.0.0.1 -d nombre_del_proyecto_prod
```

### El pool de conexiones se agota (`too many connections`)

El pool está configurado con `max: 10` en `database.config.ts`. Si tienes múltiples
servicios (backend + reports), la DB puede recibir hasta 20 conexiones concurrentes.
Ajustar según el `max_connections` de PostgreSQL:

```bash
sudo -u postgres psql -c "SHOW max_connections;"
# Default: 100 — más que suficiente para este stack Single VPS
```

---

## SSL de base de datos

### Comportamiento de `DB_SSL_REQUIRED` en cada servicio

**Backend (NestJS/TypeORM):** Si `DB_SSL_REQUIRED=true` y `DB_SSL_CA` no está
definido, el servidor falla al arrancar con un error explícito:
`[database.config] DB_SSL_REQUIRED=true pero DB_SSL_CA no está definido.`

**Reports API (Python/psycopg2):** Si `DB_SSL_REQUIRED=true`, psycopg2 busca
el archivo en la ruta definida por `DB_SSL_CA` (por defecto `/run/secrets/db_ssl_ca`).
Si ese archivo **no existe**, psycopg2 lanza `psycopg2.OperationalError: could not
open certificate file "/run/secrets/db_ssl_ca"` al primer intento de conexión.

> ⚠️ **Diferencia de comportamiento:**
> - NestJS falla al **arrancar** si falta el certificado (fail-fast)
> - Python falla en el **primer request** que necesite BD (fail-late)
>
> Para hacer Python también fail-fast, añadir validación en `src/db.py`:
>
> ```python
> if os.environ.get('DB_SSL_REQUIRED', 'false') == 'true':
>     ssl_ca = os.environ.get('DB_SSL_CA', '/run/secrets/db_ssl_ca')
>     if not os.path.exists(ssl_ca):
>         raise RuntimeError(
>             f"DB_SSL_REQUIRED=true pero el certificado CA no existe: {ssl_ca}\n"
>             f"Proporciona el archivo o desactiva DB_SSL_REQUIRED."
>         )
>     connect_args["sslmode"] = "verify-full"
>     connect_args["sslrootcert"] = ssl_ca
> ```