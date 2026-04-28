# MIGRATION-GUIDE.md — Guía de Migraciones TypeORM — NOMBRE_DEL_PROYECTO

> **Por qué migraciones y no `synchronize: true`:** TypeORM con `synchronize: true` puede ejecutar `ALTER TABLE ... DROP COLUMN` silenciosamente si renombras una propiedad en una entidad. En producción eso es pérdida de datos irreversible. Las migraciones te dan control explícito, historial auditado y rollback.

---

## Índice

- [Setup inicial](#setup-inicial)
- [Crear una migración](#crear-una-migración)
- [Ejecutar migraciones](#ejecutar-migraciones)
- [Revertir una migración](#revertir-una-migración)
- [Flujo de trabajo completo](#flujo-de-trabajo-completo)
- [Targets de Make](#targets-de-make)
- [Convenciones de nombres](#convenciones-de-nombres)
- [Errores frecuentes](#errores-frecuentes)

---

## Setup inicial

### 1. Instalar dependencias

```bash
cd backend
pnpm add typeorm @nestjs/typeorm pg
pnpm add -D ts-node
```

### 2. Crear `backend/ormconfig.ts` (para el CLI de TypeORM)

```typescript
// backend/ormconfig.ts
// Usado SOLO por el CLI de TypeORM (make db-migrate, make db-generate, etc.)
// La app usa getDatabaseConfig() en database.config.ts
import { DataSource } from 'typeorm';
import * as dotenv from 'dotenv';

dotenv.config();  // Carga .env en desarrollo

export default new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST ?? 'localhost',
  port: parseInt(process.env.DB_PORT ?? '5432'),
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,

  // Entidades — TypeORM las necesita para generar migraciones
  entities: ['src/**/*.entity.ts'],

  // Directorio donde se guardan las migraciones
  migrations: ['src/migrations/*.ts'],

  // NUNCA true en esta configuración
  synchronize: false,
});
```

### 3. Añadir scripts al `backend/package.json`

```json
{
  "scripts": {
    "migration:generate": "ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:generate -d ormconfig.ts",
    "migration:create":   "ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:create",
    "migration:run":      "ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:run -d ormconfig.ts",
    "migration:revert":   "ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:revert -d ormconfig.ts",
    "migration:show":     "ts-node -r tsconfig-paths/register node_modules/.bin/typeorm migration:show -d ormconfig.ts"
  }
}
```

### 4. Crear el directorio de migraciones

```bash
mkdir -p backend/src/migrations
touch backend/src/migrations/.gitkeep
```

### 5. Deshabilitar `synchronize` en desarrollo

En `backend/src/config/database.config.ts`, cambiar:

```typescript
// ANTES (peligroso)
synchronize: !isProduction,

// DESPUÉS (seguro)
synchronize: false,  // Siempre false — usar migraciones
```

---

## Crear una migración

### Opción A: Generación automática (recomendada)

TypeORM compara el estado actual de las entidades con el esquema real de la BD y genera la migración automáticamente.

```bash
# Asegurarse de que la BD de desarrollo está corriendo
make dev

# Dentro del contenedor backend:
docker compose exec backend pnpm migration:generate src/migrations/NombreDescriptivo

# Ejemplo:
docker compose exec backend pnpm migration:generate src/migrations/CrearTablaUsuarios
```

Esto genera `src/migrations/1703123456789-CrearTablaUsuarios.ts`.

**Revisar SIEMPRE el archivo generado antes de ejecutarlo.** TypeORM a veces genera `DROP COLUMN` inesperados si hay diferencias de nombre entre entidad y columna existente.

### Opción B: Migración manual (para cambios complejos)

```bash
docker compose exec backend pnpm migration:create src/migrations/AjusteEspecial
```

Genera una migración vacía con los métodos `up()` y `down()` para rellenar a mano:

```typescript
// src/migrations/1703123456789-AjusteEspecial.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class AjusteEspecial1703123456789 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    // Cambios a aplicar
    await queryRunner.query(`
      ALTER TABLE "users" ADD COLUMN "phone" VARCHAR(20)
    `);
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    // Cómo deshacer los cambios (OBLIGATORIO)
    await queryRunner.query(`
      ALTER TABLE "users" DROP COLUMN "phone"
    `);
  }
}
```

---

## Ejecutar migraciones

### En desarrollo

```bash
# Ver migraciones pendientes
docker compose exec backend pnpm migration:show

# Ejecutar todas las migraciones pendientes
docker compose exec backend pnpm migration:run

# Via Make (si el target está definido)
make db-migrate
```

### En producción

Las migraciones en producción se ejecutan **antes del healthcheck**, como parte del proceso de deploy:

```bash
# En el servidor de producción (llamado desde deploy.yml)
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec -T backend \
  pnpm migration:run
```

O configurando `migrationsRun: true` en `database.config.ts` solo para producción:

```typescript
// database.config.ts
migrationsRun: isProduction,  // Ejecuta automáticamente al arrancar en producción
```

> ⚠️ Con `migrationsRun: true`, las migraciones corren automáticamente al iniciar el contenedor. Asegurarse de que el backup esté hecho antes de un deploy en producción.

---

## Revertir una migración

Revierte **la última migración aplicada**:

```bash
docker compose exec backend pnpm migration:revert

# Via Make:
make db-rollback
```

Para revertir varias migraciones, ejecutar el comando varias veces. TypeORM ejecuta el método `down()` de la migración más reciente cada vez.

---

## Flujo de trabajo completo

### Añadir una columna nueva

```bash
# 1. Modificar la entidad
# backend/src/users/user.entity.ts
@Column({ nullable: true })
phone?: string;

# 2. Generar la migración
docker compose exec backend pnpm migration:generate src/migrations/AnadirTelefonoUsuarios

# 3. Revisar el archivo generado en src/migrations/
# Verificar que solo hay ADD COLUMN, no DROP COLUMN inesperados

# 4. Ejecutar en desarrollo
docker compose exec backend pnpm migration:run

# 5. Verificar en BD
docker compose exec postgres psql -U $DB_USER -d $DB_NAME -c "\d users"

# 6. Commit con nombre descriptivo
git add src/migrations/
git commit -m "feat(db): añadir columna phone a tabla users"
```

### Renombrar una columna (caso peligroso)

TypeORM NO detecta renombrado automáticamente — lo ve como DROP + ADD. **Usar migración manual:**

```typescript
async up(queryRunner: QueryRunner): Promise<void> {
  await queryRunner.query(
    `ALTER TABLE "users" RENAME COLUMN "old_name" TO "new_name"`
  );
}

async down(queryRunner: QueryRunner): Promise<void> {
  await queryRunner.query(
    `ALTER TABLE "users" RENAME COLUMN "new_name" TO "old_name"`
  );
}
```

---

## Targets de Make

Añadir al `Makefile`:

```makefile
db-migrate: ## Ejecuta migraciones pendientes
	@$(PRINT) "$(BLUE)🗄️  Ejecutando migraciones...$(RESET)"
	$(DC) exec -T backend pnpm migration:run
	@$(PRINT) "$(GREEN)✅ Migraciones aplicadas$(RESET)"

db-rollback: ## Revierte la última migración
	@$(PRINT) "$(YELLOW)⚠️  Revirtiendo última migración...$(RESET)"
	$(DC) exec -T backend pnpm migration:revert
	@$(PRINT) "$(GREEN)✅ Migración revertida$(RESET)"

db-migration-show: ## Muestra estado de las migraciones
	@$(PRINT) "$(CYAN)🔍 Estado de migraciones:$(RESET)"
	$(DC) exec -T backend pnpm migration:show

db-migration-generate: ## Genera migración desde cambios en entidades (uso: make db-migration-generate NAME=NombreMigracion)
	@[ -n "$(NAME)" ] || { $(PRINT) "$(RED)❌ Falta NAME: make db-migration-generate NAME=AnadirCampo$(RESET)"; exit 1; }
	$(DC) exec -T backend pnpm migration:generate src/migrations/$(NAME)
	@$(PRINT) "$(GREEN)✅ Migración generada en src/migrations/$(RESET)"
```

Uso:
```bash
make db-migrate
make db-rollback
make db-migration-show
make db-migration-generate NAME=AnadirCampoTelefono
```

---

## Convenciones de nombres

| Tipo de cambio | Nombre de migración |
|---|---|
| Crear tabla | `CrearTabla[Entidad]` |
| Añadir columna | `Anadir[Campo]A[Tabla]` |
| Modificar columna | `Modificar[Campo]En[Tabla]` |
| Eliminar columna | `Eliminar[Campo]De[Tabla]` |
| Crear índice | `AnadirIndice[Campo]En[Tabla]` |
| Datos iniciales (seed) | `SeedDatos[Descripcion]` |

Ejemplos:
- `CrearTablaUsuarios`
- `AnadirTelefonoAUsuarios`
- `AnadirIndiceEmailEnUsuarios`
- `SeedDatosRolesIniciales`

---

## Errores frecuentes

### Error: "No migrations pending"

La BD ya tiene todas las migraciones. Verificar con `migration:show`.

### Error: "Table already exists"

La BD tiene datos del tiempo de `synchronize: true`. Solución:

```bash
# Opción 1: Resetear BD de desarrollo (solo desarrollo, NUNCA producción)
make reset-db

# Opción 2: Marcar migraciones como ejecutadas sin correrlas
docker compose exec backend pnpm migration:run --fake
```

### Error: "column X of relation Y does not exist"

La migración hace referencia a una columna que no existe. Revisar que el `down()` de la migración anterior fue ejecutado correctamente, o editar la migración.

### Error: "relation X already exists" en el up()

La migración intenta crear algo que ya existe. Usar `IF NOT EXISTS`:

```typescript
await queryRunner.query(`
  CREATE TABLE IF NOT EXISTS "categories" (...)
`);
```

### Producción: migración fallida a mitad

1. No entrar en pánico.
2. Verificar desde el backup cuál fue el último estado consistente.
3. Ejecutar `migration:revert` si el `down()` es seguro.
4. Si no, restaurar desde backup con `make rollback-db`.
5. Corregir la migración y volver a intentar.

> **Regla de oro:** Siempre hacer `make backup-db` antes de ejecutar migraciones en producción.
