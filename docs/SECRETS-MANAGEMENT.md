# SECRETS-MANAGEMENT.md — Gestión de Secretos

> **Última actualización:** Marzo 2026  
> Ver ADR-009 en DECISIONS.md para la justificación técnica de esta decisión.

---

## ¿Qué es un secreto vs una variable de entorno?

| Característica | Variable de entorno | Secreto |
|---|---|---|
| **Ejemplo** | `NODE_ENV=production`, `PORT=4000` | `db_password`, `jwt_secret` |
| **Es sensible** | ❌ No | ✅ Sí |
| **Visible en** `docker inspect` | ✅ Sí (texto plano) | ❌ No (es un archivo) |
| **Se versiona** | Como ejemplo en `.env.example` | ❌ Nunca |
| **Cómo se gestiona** | `.env` / `.env.production` | `secrets/*.txt` |
| **Cómo lo lee la app** | `process.env.VAR` / `os.environ` | `fs.readFileSync('/run/secrets/nombre')` |

> [!IMPORTANT]
> `docker inspect <container>` muestra TODAS las variables de entorno en texto plano.
> Los secretos se montan como archivos en `/run/secrets/` — no aparecen en `docker inspect`.

---

## Inventario de secretos del proyecto

| Secreto | Archivo | Descripción | Usada por |
|---|---|---|---|
| `db_password`      | `secrets/db_password.txt` | Contraseña de PostgreSQL (lectura/escritura)    | backend     |
| `db_user`          | `secrets/db_user.txt`     | Usuario de PostgreSQL (lectura/escritura)        | backend     |
| `db_read_only_password`| `secrets/db_read_only_password.txt`  | Contraseña del usuario read-only de PostgreSQL  | reports-api |
| `db_read_only_user`| `secrets/db_read_only_user.txt | Usuario read-only de PostgreSQL      | reports-api |
| `jwt_secret`       | `secrets/jwt_secret.txt` | Clave para firmar tokens JWT | backend |
| `grafana_password` | `secrets/grafana_password.txt` | Contraseña de Grafana (solo si usas monitoring) | grafana |
| `metrics_password` | `secrets/metrics_password.txt` | Contraseña Basic Auth para `/metrics` (Prometheus) | backend |

---

## Configuración inicial (solo la primera vez)

```bash
# 1. Crear la carpeta y archivos template
make secrets-init

# 2. Editar cada archivo con el valor real
nano secrets/db_password.txt    # Contraseña real de PostgreSQL
nano secrets/db_user.txt        # Usuario real de PostgreSQL
nano secrets/jwt_secret.txt     # Se genera automáticamente con make secrets-init

# 3. Permisos estrictos
chmod 700 secrets/
chmod 600 secrets/*.txt

# 4. Verificar que todo está correcto
make secrets-check
```

---

## Cómo la app lee los secretos

### Node.js / NestJS (backend)

```typescript
// backend/src/config/database.config.ts
import * as fs from 'fs';

function readSecret(fileVar: string, plainVar: string): string {
  const filePath = process.env[fileVar];
  if (filePath) {
    return fs.readFileSync(filePath, 'utf8').trim(); // Lee desde Docker Secret
  }
  return process.env[plainVar] ?? ''; // Fallback: variable de entorno (dev)
}

const password = readSecret('DB_PASSWORD_FILE', 'DB_PASSWORD');

// backend/src/auth/guards/metrics-auth.guard.ts
// Mismo patrón aplicado al guard de métricas:
function readMetricsPassword(): string | undefined {
  const filePath = process.env.METRICS_PASSWORD_FILE;
  if (filePath) {
    return fs.readFileSync(filePath, 'utf8').trim();
  }
  return process.env.METRICS_PASSWORD; // dev: viene del .env
}
```

### Python / Flask (reports-api)

```python
# reports/main.py
def _read_secret(file_env: str, plain_env: str) -> str | None:
    file_path = os.environ.get(file_env)
    if file_path:
        with open(file_path) as f:
            return f.read().strip()   # Lee desde Docker Secret
    return os.environ.get(plain_env)  # Fallback: variable de entorno (dev)

password = _read_secret('DB_PASSWORD_FILE', 'DB_PASSWORD')
```

---

## Flujo en producción (docker-compose.prod.yml)

```
secrets/db_password.txt (host, chmod 600)
  ↓ Docker monta como
/run/secrets/db_password (dentro del contenedor, read-only)
  ↓ La app lee via
DB_PASSWORD_FILE=/run/secrets/db_password (variable no sensible)
  ↓ Resulta en
readFileSync('/run/secrets/db_password').trim() → "mi_password_real"
```

---

## Rotación de secretos

### Procedimiento estándar (cada 90 días)

```bash
# 1. Actualizar el secreto
echo "nueva_password_segura" > secrets/db_password.txt
chmod 600 secrets/db_password.txt

# 2. Actualizar en PostgreSQL
sudo -u postgres psql -c "ALTER USER user_prod PASSWORD 'nueva_password_segura';"

# 3. Reiniciar contenedores para que lean el nuevo secreto
make stop && make prod

# 4. Verificar que los servicios están healthy
docker ps --filter "health=healthy"

# 5. Registrar la rotación
echo "$(date): rotación db_password completada por $(whoami)" >> scripts/tests/secrets-rotation.log
```

### Rotación de emergencia (si un secreto fue comprometido)

```bash
# 1. Detener servicios INMEDIATAMENTE
make stop

# 2. Generar nuevo secreto
openssl rand -base64 48 > secrets/jwt_secret.txt
chmod 600 secrets/jwt_secret.txt

# 3. Revocar en el sistema (DB, Slack, etc. según el secreto)
# Para JWT: todos los tokens activos quedan inválidos al reiniciar con la nueva clave

# 4. Redesplegar
make secrets-check && make prod

# 5. Notificar al equipo
echo "$(date): ROTACIÓN DE EMERGENCIA jwt_secret — motivo: posible compromiso" >> scripts/tests/secrets-rotation.log
```

---

## Política de rotación

| Secreto | Frecuencia | Motivo |
|---|---|---|
| `db_password.txt` | 90 días | Política estándar de seguridad |
| `db_read_only_password.txt` | 90 días (junto a `db_password`) | Rotar siempre en paralelo con db_password |
| `jwt_secret.txt` | Al compromiso sospechoso | Invalida todos los tokens activos |
| `grafana_password.txt` | 90 días | Acceso a métricas de producción |
| `metrics_password.txt` | 90 días o al rotar contraseña de Prometheus | Acceso a métricas de infraestructura |

---

## Qué NO hacer

```bash
# ❌ NUNCA poner secretos en variables de entorno del compose
environment:
  DB_PASSWORD: mi_password  # Visible en docker inspect

# ❌ NUNCA committear el directorio secrets/
git add secrets/  # .gitignore lo bloquea pero asegúrate

# ❌ NUNCA poner secretos en logs
console.log(`Conectando con password: ${password}`);  # Expone en logs

# ❌ NUNCA usar el mismo secreto en dev y producción
JWT_SECRET=mismo_en_dev_y_prod  # Si dev se compromete, prod también
```

---

## Verificación de seguridad

```bash
# Verificar que secrets/ no tiene permisos excesivos
ls -la secrets/
# Esperado: drwx------ (700) para el directorio
# Esperado: -rw------- (600) para cada *.txt

# Verificar que los secretos no están en git
git status secrets/  # No debe aparecer nada
git log --all -- secrets/  # No debe tener commits

# Verificar que los secretos están montados en el contenedor
docker compose exec backend ls -la /run/secrets/
# Debe mostrar: db_password, db_user, jwt_secret, metrics_password

# Verificar que NO están en variables de entorno
docker inspect nombre_del_proyecto_api | grep -i password  # No debe aparecer nada
```

---

## Entornos de secretos

| Entorno | Cómo se gestionan | Herramienta |
|---|---|---|
| Desarrollo | Variables de entorno en `.env` | `make setup` |
| Producción | Archivos en `secrets/*.txt` | `make secrets-init` |
| CI/CD | GitHub Secrets (Actions) | Settings → Secrets |

> Para CI/CD, los secretos se inyectan como GitHub Secrets y se pasan como variables de entorno
> al workflow. Las imágenes se construyen sin secretos — los secretos se aplican en deploy.

---

## Rotación de Secrets

### jwt_secret (rotar cada 90 días o ante sospecha de compromiso)
1. Generar nuevo secret: openssl rand -base64 48 > secrets/jwt_secret.txt.new
2. Configurar NestJS para aceptar el secret viejo Y el nuevo durante 1 período de JWT_REFRESH_EXPIRES_IN
3. Desplegar la app
4. Mover .new a .txt y redesplegar
5. Todas las sesiones activas se invalidan al expirar sus refresh tokens

### db_password (rotar cada 180 días)
1. Crear nueva contraseña en PostgreSQL: ALTER USER user_dev PASSWORD 'nueva'
2. Actualizar secret: echo 'nueva' > secrets/db_password.txt
3. Redesplegar backend y reports
