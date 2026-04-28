# docs/DATA-DICTIONARY.md — Diccionario de Datos

**Proyecto:** NOMBRE_DEL_PROYECTO
**Estado:** Plantilla base — completar secciones marcadas con `TODO` al definir el modelo de negocio
**Última actualización:** Marzo 2026

```markdown
## ⚠️ Estado de Este Documento

**Esquema de BD:** Ejemplo ilustrativo (ver TODO abajo)  
**Contratos API:** Plantilla empresarial (endpoints no implementados)  
**Clasificación de datos:** ✅ Vigente y aplicable
```

> **Cómo usar este archivo:**
> Este documento tiene dos tipos de contenido:
> - Secciones **ya completas**: secretos, clasificación de datos, compliance.
> - Secciones **TODO**: schema de DB y contratos de API — completar cuando se definan las entidades.
>
> Para exportar el schema real de PostgreSQL:
> ```bash
> psql -U $DB_USER -d $DB_NAME -c "\dt"          # lista tablas
> pg_dump -U $DB_USER -d $DB_NAME --schema-only   # schema SQL completo
> ```

---

## Índice

- [Variables de entorno y secretos](#variables-de-entorno-y-secretos)
- [Secretos de Docker](#secretos-de-docker)
- [Esquema de base de datos](#esquema-de-base-de-datos)
- [Contratos de API](#contratos-de-api)
- [Clasificación de datos](#clasificación-de-datos)
- [Notas de compliance](#notas-de-compliance)

---

## Variables de entorno y secretos

> La documentación detallada de cada variable de entorno está en `docs/ENV-VARIABLES.md`.
> Esta sección cubre solo los secretos sensibles y su ciclo de vida.

---

## Secretos de Docker

Todos los secretos se gestionan con Docker Secrets (archivos en `./secrets/`, excluidos del repo).
Ver `DECISIONS.md ADR-009` para la justificación de este enfoque.

| Archivo | Contenido | Usado por | Cómo generarlo | Rotación |
|---|---|---|---|---|
| `secrets/db_password.txt` | Contraseña de PostgreSQL | Backend + Reports | `openssl rand -base64 32` | Manual, recomendado mensual en prod |
| `secrets/db_user.txt` | Usuario de PostgreSQL | Backend + Reports | Definir al crear el rol en postgres | Raro — solo si cambia el rol |
| `secrets/db_read_only_password.txt` | Contraseña de PostgreSQL | Backend + Reports | `openssl rand -base64 32` | Manual, recomendado mensual en prod |
| `secrets/db_read_only_user.txt` | Usuario de PostgreSQL | Backend + Reports | Definir al crear el rol en postgres | Raro — solo si cambia el rol |
| `secrets/jwt_secret.txt` | Clave de firma JWT — 48 bytes base64 | Backend NestJS | `openssl rand -base64 48` | Inmediata si se compromete — invalida **todos** los tokens activos |
| `secrets/cookie_secret.txt` | Secreto para firma de cookies httpOnly (express cookie-parser) | Backend NestJS | `openssl rand -hex 48` | Inmediata si se compromete — invalida todas las sesiones activas |
| `secrets/pepper_secret.txt` | Pepper para hashing de contraseñas (Argon2id) — no es un JWT | Backend NestJS | `openssl rand -base64 32` | ⚠️ Rotar invalida TODOS los hashes: todos los usuarios deben cambiar contraseña |
| `secrets/grafana_password.txt` | Contraseña admin de Grafana | Stack de monitoreo | Definir manualmente | Manual, recomendado trimestral |
| `secrets/metrics_password.txt` | Contraseña HTTP Basic para endpoint /metrics (Prometheus) | Backend NestJS + Stack monitoreo | `openssl rand -base64 24` *(auto en secrets-init)* | Manual, recomendado trimestral |

```bash
make secrets-init   # Crea ./secrets/ con archivos vacíos para rellenar
make secrets-check  # Verifica que todos los archivos tienen contenido
```

**Antes de rotar `jwt_secret`:** todos los usuarios activos perderán su sesión. Planificar en ventana de mantenimiento.

---

## Esquema de base de datos

> **TODO — Completar cuando se definan las entidades del modelo de negocio.**
>
> Instrucciones:
> 1. Definir entidades en `backend/src/` como clases TypeORM (`@Entity()`)
> 2. TypeORM genera el schema en dev (`synchronize: true`)
> 3. Exportar: `pg_dump -U $DB_USER -d $DB_NAME --schema-only -f schema.sql`
> 4. Documentar cada tabla en el formato de abajo

### Tabla: `users` *(ejemplo — reemplazar con entidades reales)*

```sql
CREATE TABLE users (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  email       VARCHAR(255) NOT NULL UNIQUE,
  password    VARCHAR(255) NOT NULL,    -- argon2 hash, NUNCA texto plano
  role        VARCHAR(50)  NOT NULL DEFAULT 'user',
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
```

| Campo | Tipo | Nulo | Default | Descripción | PII | Índice |
|---|---|---|---|---|---|---|
| `id` | UUID | No | `gen_random_uuid()` | Identificador único | ❌ | PRIMARY KEY |
| `email` | VARCHAR(255) | No | — | Email del usuario | ✅ | UNIQUE |
| `password` | VARCHAR(255) | No | — | Hash argon2 (no texto plano) | ✅ | — |
| `role` | VARCHAR(50) | No | `'user'` | Rol: `user`, `admin` | ❌ | — |
| `is_active` | BOOLEAN | No | `TRUE` | Cuenta activa o deshabilitada | ❌ | — |
| `created_at` | TIMESTAMP | No | `NOW()` | Fecha de creación | ❌ | — |
| `updated_at` | TIMESTAMP | No | `NOW()` | Fecha de última modificación | ❌ | — |

### Tabla: `audit_logs` *(recomendada para compliance)*

```sql
CREATE TABLE audit_logs (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     UUID         REFERENCES users(id) ON DELETE SET NULL,
  action      VARCHAR(100) NOT NULL,
  entity      VARCHAR(100),
  entity_id   VARCHAR(255),
  ip_address  INET,
  user_agent  TEXT,
  metadata    JSONB,
  created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC);
```

> **TODO:** Añadir las demás tablas del modelo de negocio siguiendo este formato.

---

## Contratos de API

> Los contratos completos con ejemplos de request/response están en Swagger:
> - **Desarrollo:** `http://localhost:4000/api/docs` (solo con `NODE_ENV=development`)
> - **Producción:** Swagger deshabilitado por seguridad (ver `backend/src/main.ts`)

### Backend (NestJS) — endpoints actuales

| Método | Ruta | Auth | Estado | Descripción |
|---|---|---|---|---|
| GET | `/api/health` | ❌ | ✅ Activo | Estado del servicio y conexión a DB |
| GET | `/metrics` | ❌ | ✅ Activo | Métricas Prometheus (solo red interna) |
| POST | `/api/auth/register` | ❌ | 🚧 Stub | **Lanza HTTP 501** — AuthService pendiente |
| POST | `/api/auth/login` | ❌ | 🚧 Stub | **Lanza HTTP 501** — AuthService pendiente |
| POST | `/api/auth/refresh` | ❌ | 🚧 Stub | **Lanza HTTP 501** — AuthService pendiente |
| GET | `/api/auth/me` | ✅ JWT | 🚧 Stub | Perfil del usuario — requiere JWT real |
| POST | `/api/auth/logout` | ✅ JWT | ✅ Activo | Logout stateless (limpia en cliente) |

> **TODO:** Añadir endpoints de negocio al implementar los módulos de aplicación.

### Reports API (Flask) — endpoints actuales

| Método | Ruta | Auth | Estado | Descripción |
|---|---|---|---|---|
| GET | `/health` | ❌ | ✅ Activo | Estado del servicio y conexión a DB |

> **TODO:** Documentar endpoints de generación de reportes al implementarlos.

---

## Clasificación de datos

| Clasificación | Ejemplos en este proyecto | Protección requerida |
|---|---|---|
| **PÚBLICO** | Versión de API, status de `/health` | Ninguna especial |
| **INTERNO** | Emails, nombres, roles | TLS en tránsito, acceso restringido a logs |
| **CONFIDENCIAL** | Contraseñas hash, tokens JWT | Nunca en logs, encriptación en reposo recomendada |
| **RESTRINGIDO** | Datos de reportes financieros o personales | MFA + audit logging + retención limitada |

---

## Notas de compliance

### GDPR — Derecho al olvido
```sql
-- Anonimizar usuario (no borrar para mantener integridad en audit_logs)
UPDATE users SET
  email     = 'deleted_' || id || '@deleted.local',
  password  = 'DELETED',
  is_active = FALSE
WHERE id = $1;
```

### Retención de logs
Los logs de Docker tienen rotación en `docker-compose.prod.yml`:
- Backend / Frontend: 10MB × 3 archivos ≈ 30MB por servicio
- Reports API: 20MB × 5 archivos ≈ 100MB

Para retención de 90+ días, configurar Loki (ver `docs/guides/MONITORING-LOKI-PROMTAIL.md`).

### Datos de prueba
- **Nunca** usar datos reales en desarrollo.
- Usar [Faker.js](https://fakerjs.dev/) (Node) o [Faker](https://faker.readthedocs.io/) (Python).
- Los seeds de dev (`make db-seed`) deben usar datos completamente ficticios.
