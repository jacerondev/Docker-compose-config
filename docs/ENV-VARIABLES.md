# ENV-VARIABLES.md — Guía de variables de entorno

> Este archivo documenta cada variable de entorno del proyecto: su propósito,
> valores válidos y en qué archivo/entorno se usa.
>
> **Para configurar el proyecto:**
>
> - Desarrollo: `make setup` (copia `.env.example` → `.env` automáticamente)
> - Producción: `make prod` (copia `.env.prod.example` → `.env.production` automáticamente)

---

## Mapa de archivos

| Archivo             | ¿Versionado? | Entorno    | Propósito                              |
| ------------------- | ------------ | ---------- | -------------------------------------- |
| `.env.example`      | ✅ Sí        | Desarrollo | Plantilla — copiar a `.env`            |
| `.env`              | ❌ No        | Desarrollo | Valores reales dev (gitignored)        |
| `.env.prod.example` | ✅ Sí        | Producción | Plantilla — copiar a `.env.production` |
| `.env.production`   | ❌ No        | Producción | Valores reales prod (gitignored)       |
| `secrets/`          | ❌ No        | Producción | Credenciales sensibles (gitignored)    |

---

## Variables de base de datos

### `DB_HOST`

| Campo                 | Valor                                                                              |
| --------------------- | ---------------------------------------------------------------------------------- |
| **Descripción**       | Hostname o IP donde corre PostgreSQL                                               |
| **Dev**               | `host-gateway` (Docker 20.10+ resuelve a la IP del host)                           |
| **Prod**              | `host-gateway` (misma razón — PostgreSQL en el host, no en Docker)                 |
| **Alternativa Linux** | `172.17.0.1` (IP del gateway Docker en Linux sin Docker Desktop)                   |
| **Nunca usar**        | `localhost` desde dentro de un contenedor — apunta al contenedor mismo, no al host |

> **¿Por qué `host-gateway`?**
> Los contenedores corren en una red Docker interna. Para llegar a PostgreSQL (que está en el host),
> necesitan la IP del gateway de esa red. `host-gateway` es un alias especial de Docker 20.10+
> que siempre resuelve a esa IP, independientemente del servidor.

---

### `DB_PORT`

| Campo                 | Valor                                        |
| --------------------- | -------------------------------------------- |
| **Descripción**       | Puerto de PostgreSQL                         |
| **Valor por defecto** | `5432`                                       |
| **Cuándo cambiar**    | Si PostgreSQL corre en un puerto no estándar |

---

### `DB_NAME`

| Campo           | Valor                      |
| --------------- | -------------------------- |
| **Descripción** | Nombre de la base de datos |
| **Dev**         | `nombre_del_proyecto_db`   |
| **Prod**        | `nombre_del_proyecto_prod` |

---

### `DB_USER` (solo desarrollo)

| Campo           | Valor                                                       |
| --------------- | ----------------------------------------------------------- |
| **Descripción** | Usuario de PostgreSQL                                       |
| **Dev**         | `user_dev` (definido en `.env`)                             |
| **Prod**        | ❌ No va en `.env.production` — va en `secrets/db_user.txt` |

> En producción, la app lee el usuario desde `/run/secrets/db_user` (Docker Secret).
> La variable `DB_USER_FILE=/run/secrets/db_user` indica a la app dónde leer el valor.

---

### `DB_PASSWORD` (solo desarrollo)

| Campo           | Valor                                                           |
| --------------- | --------------------------------------------------------------- |
| **Descripción** | Contraseña de PostgreSQL                                        |
| **Dev**         | Definida en `.env` (nunca commiteada)                           |
| **Prod**        | ❌ No va en `.env.production` — va en `secrets/db_password.txt` |

> En producción, la app lee la contraseña desde `/run/secrets/db_password`.

---

### `DB_READ_ONLY_USER` (solo desarrollo)

| Campo           | Valor                                                                 |
| --------------- | --------------------------------------------------------------------- |
| **Descripción** | Usuario PostgreSQL de solo lectura — exclusivo para reports-api       |
| **Dev**         | `user_dev_readonly` (definido en `.env`)                              |
| **Prod**        | ❌ No va en `.env.production` — va en `secrets/db_read_only_user.txt` |

> Solo tiene `SELECT` sobre todas las tablas. Creado automáticamente en el contenedor
> de desarrollo por `config/init-db.sh` al hacer `make dev` la primera vez.

> En producción, la app lee la contraseña desde `/run/secrets/db_read_only_user`.

---

### `DB_READ_ONLY_PASSWORD` (solo desarrollo)

| Campo           | Valor                                                                     |
| --------------- | ------------------------------------------------------------------------- |
| **Descripción** | Contraseña del usuario de solo lectura                                    |
| **Dev**         | Definida en `.env`                                                        |
| **Prod**        | ❌ No va en `.env.production` — va en `secrets/db_read_only_password.txt` |

> En producción, la app lee la contraseña desde `/run/secrets/db_read_only_password`.

---

## Variables de puertos

### `PORT_BACKEND` / `PORT_FRONTEND` / `PORT_REPORTS`

| Campo                   | Valor                                                      |
| ----------------------- | ---------------------------------------------------------- |
| **Descripción**         | Puerto en el que corre cada servicio dentro del contenedor |
| **Valores por defecto** | `4000` / `3000` / `5000`                                   |
| **Cuándo cambiar**      | Si otro proceso en tu máquina usa esos puertos             |

> En desarrollo, estos puertos se mapean directamente (`0.0.0.0:PORT:PORT`).
> En producción, se mapean solo a localhost (`127.0.0.1:PORT:PORT`) — solo Nginx puede acceder.

---

## Variables de URLs públicas

### `NEXT_PUBLIC_API_URL`

| Campo             | Valor                                                                                                     |
| ----------------- | --------------------------------------------------------------------------------------------------------- |
| **Descripción**   | URL que el **navegador del usuario** usa para llamar al backend                                           |
| **Dev**           | `http://localhost:4000`                                                                                   |
| **Prod**          | `https://api.tudominio.com`                                                                               |
| **⚠️ Importante** | Se "bake" en el bundle de Next.js durante `next build`. Cambiarla requiere rebuild de la imagen frontend. |

> Esta URL sale del servidor y llega al navegador del cliente. Por eso usa `localhost` en dev
> (el navegador accede directamente) y el dominio público en prod.
> NO es la URL interna de Docker (`http://backend:4000`).

---

### `NEXT_PUBLIC_REPORTS_URL`

| Campo             | Valor                                                                       |
| ----------------- | --------------------------------------------------------------------------- |
| **Descripción**   | URL que el **navegador del usuario** usa para llamar al servicio de reports |
| **Dev**           | `http://localhost:5000`                                                     |
| **Prod**          | `https://reports.tudominio.com`                                             |
| **⚠️ Importante** | Mismo comportamiento que `NEXT_PUBLIC_API_URL` — se bake en el build.       |

---

### `NESTJS_AUTH_URL`

| Campo             | Valor                                                                                 |
| ----------------- | ------------------------------------------------------------------------------------- |
| **Descripción**   | URL **interna de Docker** que reports-api usa para validar tokens llamando al backend |
| **Dev**           | `http://backend:4000`                                                                 |
| **Prod**          | `http://backend:4000`                                                                 |
| **⚠️ Importante** | Usa el nombre del servicio `backend` (Docker DNS interno), NO `localhost`             |

> `backend` es el nombre del servicio en `docker-compose.yml`. Docker lo resuelve
> automáticamente a la IP del contenedor del backend dentro de la red `nombre_del_proyecto-network`.

---

## Variables de runtime

### `NODE_ENV`

| Campo               | Valor                                                              |
| ------------------- | ------------------------------------------------------------------ |
| **Descripción**     | Modo de ejecución de Node.js / NestJS                              |
| **Dev**             | `development` — habilita hot reload, más logs, errores detallados  |
| **Prod**            | `production` — optimizaciones de V8, menos logs, errores genéricos |
| **Valores válidos** | `development` \| `production` \| `test`                            |

---

### `APP_ENV`

| Campo               | Valor                                                            |
| ------------------- | ---------------------------------------------------------------- |
| **Descripción**     | Modo de ejecución de Flask                                       |
| **Dev**             | `development` — habilita debug mode y auto-reload                |
| **Prod**            | `production` — deshabilita debug (Gunicorn gestiona el servidor) |
| **Valores válidos** | `development` \| `production`                                    |

---

### `SWAGGER_ENABLED`

| Campo           | Valor                                                 |
| --------------- | ----------------------------------------------------- |
| **Descripción** | Activa o desactiva la documentación Swagger de la API |
| **Dev**         | `true`                                                |
| **Prod**        | `false`                                               |
| **Formato**     | Booleano: true o false                                |

---

### `ALLOWED_ORIGINS`

| Campo           | Valor                                                               |
| --------------- | ------------------------------------------------------------------- |
| **Descripción** | Dominios permitidos en las cabeceras CORS del backend y reports-api |
| **Dev**         | `http://localhost:3000`                                             |
| **Prod**        | `https://tudominio.com,https://www.tudominio.com`                   |
| **Formato**     | URLs completas separadas por coma, sin espacios                     |

> Si el frontend intenta llamar al backend desde un dominio no listado aquí,
> el navegador bloqueará la request (CORS error).

---

## Variables de imágenes Docker (opcionales)

### `IMAGE_BACKEND` / `IMAGE_FRONTEND` / `IMAGE_REPORTS`

| Campo                  | Valor                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| **Descripción**        | Imagen Docker a usar, incluyendo tag o digest                                                         |
| **Cuándo usar**        | Para apuntar a un registry privado (GitHub Container Registry, Docker Hub privado, etc.)              |
| **Formato correcto**   | `nombre_del_proyecto/backend:2026.02.20` o `ghcr.io/org/nombre_del_proyecto/backend:sha-abc123`       |
| **Formato incorrecto** | ~~`http://localhost/nombre_del_proyecto/backend:...`~~ — las imágenes Docker no llevan protocolo HTTP |
| **Default**            | Si no se definen, Docker hace build local automáticamente                                             |

> Ejemplo para GitHub Container Registry:
>
> ```bash
> IMAGE_BACKEND=ghcr.io/tu-org/nombre_del_proyecto/backend:2026.02.24
> IMAGE_FRONTEND=ghcr.io/tu-org/nombre_del_proyecto/frontend:2026.02.24
> IMAGE_REPORTS=ghcr.io/tu-org/nombre_del_proyecto/reports:2026.02.24
> ```

---

## Variables de Docker Secrets (producción)

Estas no son variables de entorno — son rutas a archivos de secretos que la app lee directamente:

| Variable                       | Valor fijo                           | Dónde se define                                           |
| ------------------------------ | ------------------------------------ | --------------------------------------------------------- |
| `DB_PASSWORD_FILE`             | `/run/secrets/db_password`           | `docker-compose.prod.yml` → `environment:`                |
| `DB_USER_FILE`                 | `/run/secrets/db_user`               | `docker-compose.prod.yml` → `environment:`                |
| `DB_PASSWORD_FILE` (read-only) | `/run/secrets/db_read_only_password` | `docker-compose.prod.yml` → reports-api                   |
| `DB_USER_FILE` (read-only)     | `/run/secrets/db_read_only_user`     | `docker-compose.prod.yml` → reports-api                   |

> Estos valores son fijos — no se cambian. Lo que cambia es el **contenido** de los archivos
> en `secrets/*.txt`. Ver `make secrets-init` y `make secrets-check`.

---

## Variables de autenticación JWT

### `JWT_SECRET`

| Campo            | Valor                                                               |
| ---------------- | ------------------------------------------------------------------- |
| **Descripción**  | Clave secreta para firmar y verificar tokens JWT                    |
| **Dev**          | `genera_con_openssl_rand_base64_48` (valor placeholder, reemplazar) |
| **Prod**         | Generada con `openssl rand -base64 48` — mínimo 48 bytes            |
| **Cómo generar** | `openssl rand -base64 48`                                           |
| **Dónde va**     | Dev: `.env`. Prod: `secrets/jwt_secret.txt` (Docker Secret)         |

> ⚠️ **Nunca** usar el mismo `JWT_SECRET` en desarrollo y producción.
> Si se compromete esta clave, todos los tokens activos deben invalidarse.

---

### `JWT_EXPIRES_IN`

| Campo           | Valor                                                           |
| --------------- | --------------------------------------------------------------- |
| **Descripción** | Tiempo de expiración del access token                           |
| **Dev**         | `8h` (cómodo para desarrollo)                                   |
| **Prod**        | `15m` o `30m` (más seguro — el refresh token renueva la sesión) |
| **Formato**     | `15m`, `1h`, `8h`, `1d` — sigue la sintaxis de la librería `ms` |

> El access token tiene vida corta por diseño. Si se filtra, expira pronto.
> El usuario no nota la diferencia gracias al refresh token automático.

---

### `JWT_REFRESH_EXPIRES_IN`

| Campo            | Valor                                                       |
| ---------------- | ----------------------------------------------------------- |
| **Descripción**  | Tiempo de expiración del refresh token                      |
| **Dev**          | `7d`                                                        |
| **Prod**         | `7d` o `30d` según el negocio                               |
| **Dónde se usa** | `POST /api/auth/refresh` para obtener un nuevo access token |

---

## Variables de Alertmanager (solo producción)

### `SLACK_WEBHOOK_URL`

| Campo              | Valor                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------- |
| **Descripción**    | URL de entrada del webhook de Slack — Alertmanager la usa para enviar notificaciones      |
| **Dev**            | ❌ No se usa (Alertmanager solo corre con `make monitoring-up-prod`)                      |
| **Prod**           | `https://hooks.slack.com/services/T.../B.../XXXX`                                         |
| **Cómo obtenerla** | Slack → Tu workspace → Apps → Incoming Webhooks → Añadir → Copiar URL                     |
| **Dónde va**       | `.env.production` o exportada como variable de entorno antes de `make monitoring-up-prod` |

> **Por qué NO va en `alertmanager.yml` directamente:**
> Docker monta el archivo como volumen — no interpola variables en su contenido.
> La solución es `envsubst` que sustituye `${SLACK_WEBHOOK_URL}` ANTES de que
> Docker lo monte. `make monitoring-up-prod` hace esto automáticamente.
> Ver: `docs/guides/MONITORING-ALERTMANAGER.md`

---

### `COOKIE_SECRET`

| Entorno | Valor |
|---|---|
| **Dev** | `CAMBIAR_genera_con_openssl_rand_hex_48` (placeholder — reemplazar) |
| **Prod** | No va en `.env.production` — usar Docker Secret: `COOKIE_SECRET_FILE` |
| **Cómo generar** | `openssl rand -hex 48` |
| **Docker Secret** | `secrets/cookie_secret.txt` |

Secreto para firma criptográfica de cookies httpOnly (express `cookie-parser`).
Si se compromete, todas las sesiones activas quedan invalidadas.

---

### `PEPPER_SECRET`

| Entorno | Valor |
|---|---|
| **Dev** | `CAMBIAR_genera_con_openssl_rand_base64_32` (placeholder — reemplazar) |
| **Prod** | No va en `.env.production` — usar Docker Secret: `PEPPER_SECRET_FILE` |
| **Cómo generar** | `openssl rand -base64 32` |
| **Docker Secret** | `secrets/pepper_secret.txt` |

Valor secreto adicional combinado con la contraseña antes del hash Argon2id.
⚠️ **Nunca rotar en producción** sin un plan de migración: invalida todos los hashes
existentes en BD y obliga a todos los usuarios a reestablecer su contraseña.