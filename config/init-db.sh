# filepath: config/init-db.sh
#!/bin/bash
# Ejecutado automáticamente por el contenedor postgres en el primer arranque.
# Crea el usuario de solo lectura para reports-api.
# IMPORTANTE: Este script solo corre si el volumen postgres_dev_data está vacío.
# Para re-ejecutar: docker compose down -v && make dev

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- Usuario de solo lectura para reports-api
  CREATE USER ${DB_READ_ONLY_USER} WITH PASSWORD '${DB_READ_ONLY_PASSWORD}';

  -- Acceso a la base de datos (necesario para conectarse)
  GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${DB_READ_ONLY_USER};

  -- Acceso al schema public (necesario para ver tablas)
  GRANT USAGE ON SCHEMA public TO ${DB_READ_ONLY_USER};

  -- Solo SELECT en tablas existentes
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${DB_READ_ONLY_USER};

  -- SELECT en tablas que se creen en el futuro (clave para migraciones)
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO ${DB_READ_ONLY_USER};

  -- Solo SELECT en secuencias (para leer IDs sin poder modificarlos)
  GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_READ_ONLY_USER};

  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON SEQUENCES TO ${DB_READ_ONLY_USER};
EOSQL

echo "✅ Usuario read-only '${DB_READ_ONLY_USER}' creado correctamente"