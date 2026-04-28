// filepath: backend/src/config/database.config.ts
import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { readSecret } from '@config/secrets';

/**
 * Configuración de TypeORM para NestJS.
 *
 * Se usa con TypeOrmModule.forRootAsync() para que ConfigModule ya esté
 * disponible cuando esta función se ejecuta.
 *
 * Variables necesarias en .env (desarrollo) o Docker Secrets (producción):
 *   DB_HOST     — hostname de PostgreSQL (ej: postgres, host-gateway)
 *   DB_PORT     — puerto (defecto: 5432)
 *   DB_NAME     — nombre de la base de datos
 *   DB_USER     — usuario (o DB_USER_FILE=/run/secrets/db_user en producción)
 *   DB_PASSWORD — contraseña (o DB_PASSWORD_FILE=/run/secrets/db_password en producción)
 */
export function getDatabaseConfig(): TypeOrmModuleOptions {
  const username = readSecret('DB_USER_FILE', 'DB_USER');
  const password = readSecret('DB_PASSWORD_FILE', 'DB_PASSWORD');

  const host = process.env.DB_HOST;
  const port = parseInt(process.env.DB_PORT ?? '5432', 10);
  const database = process.env.DB_NAME;

  if (!host || !database) {
    throw new Error(
      '"DB_HOST" y "DB_NAME" son obligatorios. Revisa tu .env o .env.production.',
    );
  }

  const isProduction = process.env.NODE_ENV === 'production';
  const sslRequired = process.env.DB_SSL_REQUIRED === 'true';
  if (sslRequired && !process.env.DB_SSL_CA) {
    throw new Error(
      '[database.config] DB_SSL_REQUIRED=true pero DB_SSL_CA no está definido.\n' +
      'Proporciona la ruta al certificado CA del servidor PostgreSQL.'
    );
  }

  return {
    type: 'postgres',
    host,
    port,
    username,
    password,
    database,

    // ── Sincronización automática ─────────────────────────────────────────────
    // true  → TypeORM actualiza el schema en cada arranque  (SOLO desarrollo)
    // false → El schema se gestiona con migraciones         (PRODUCCIÓN siempre)
    // synchronize: !isProduction,
    synchronize: false,

    // ── Migraciones ───────────────────────────────────────────────────────────
    // false → ejecutar manualmente con: make db-migrate
    // Cambiar a true solo si quieres migraciones automáticas en deploy
    migrationsRun: false,

    // ── Entidades ─────────────────────────────────────────────────────────────
    // autoLoadEntities: true recoge todas las entidades registradas con
    // TypeOrmModule.forFeature([Entidad]) sin listarlas aquí manualmente
    autoLoadEntities: true,

    // ── Logging ───────────────────────────────────────────────────────────────
    // En desarrollo: ver todas las queries SQL en consola
    // En producción: solo errores (no exponer queries en logs)
    logging: !isProduction ? ['query', 'error', 'warn'] : ['error'],

    // ── Pool de conexiones ────────────────────────────────────────────────────
    // Evita abrir una conexión nueva por cada request HTTP
    // max: máximo de conexiones simultáneas al pool
    extra: {
      max: 10,
      idleTimeoutMillis: 30_000,   // cerrar conexión inactiva tras 30s
      connectionTimeoutMillis: 5_000, // fallar si no conecta en 5s
    },

    // ── SSL ───────────────────────────────────────────────────────────────────
    
    ssl: sslRequired
      ? { rejectUnauthorized: true, ca: process.env.DB_SSL_CA }
      : false,
  };
}
