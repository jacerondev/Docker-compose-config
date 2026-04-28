# filepath: reports/src/db.py
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL as SaURL
from src.utils import read_secret
import os
import structlog

logger = structlog.get_logger(__name__)

def create_db_engine():
    """
    Factory del engine — llamar UNA vez en bootstrap desde main.py.

    Construye la URL de conexión a PostgreSQL leyendo credenciales desde
    Docker Secrets (producción) o variables de entorno (desarrollo).

    Flujo:
        Producción: DB_USER_FILE=/run/secrets/db_user        → lee del archivo
                    DB_PASSWORD_FILE=/run/secrets/db_password → lee del archivo
        Desarrollo: DB_USER=user_dev (desde .env)             → usa la variable directa
                    DB_PASSWORD=password_dev (desde .env)     → usa la variable directa
    """

    # NOTA: Este engine usa las credenciales del usuario principal (DB_USER/DB_PASSWORD).
    # reports-api en producción usa DB_READ_ONLY_USER/DB_READ_ONLY_PASSWORD via docker-compose.prod.yml.
    # El docker-compose.prod.yml inyecta DB_USER_FILE=/run/secrets/db_read_only_user para reports.
    user = read_secret('DB_USER_FILE', 'DB_USER')
    password = read_secret('DB_PASSWORD_FILE', 'DB_PASSWORD')
    
    if not user:
        raise RuntimeError(
            "Usuario de BD no disponible. "
            "En dev: define DB_USER en .env. "
            "En prod: ejecuta 'make secrets-init'."
        )
    if not password:
        raise RuntimeError(
            "Contraseña de BD no disponible. "
            "En dev: define DB_PASSWORD en .env. "
            "En prod: ejecuta 'make secrets-init'."
        )

    url = SaURL.create(
        drivername="postgresql+psycopg2",
        username=user,
        password=password,   # SQLAlchemy oculta en repr()
        host=os.environ['DB_HOST'],
        port=int(os.environ['DB_PORT']),
        database=os.environ['DB_NAME'],
    )

    logger.info("db_connecting", url=url.render_as_string(hide_password=True))

    connect_args = {
        "connect_timeout": 10,  # Si PostgreSQL no responde en 10s(margen para picos de carga) → error rápido
        # Cuando SSL esté activo, el handshake también necesita timeout
        # psycopg2 >= 2.9.3 hereda connect_timeout para SSL
        "options": "-c statement_timeout=30000",  # 30s máx por query
    }

    # En producción con BD remota, activar SSL obligatorio
    if os.environ.get('DB_SSL_REQUIRED', 'false') == 'true':
        # connect_args["sslmode"] = "require"
        connect_args["sslmode"] = "verify-full"
        connect_args["sslrootcert"] = os.environ.get(
            "DB_SSL_CA", "/run/secrets/db_ssl_ca"
        )

    return create_engine(
        url,
        pool_size=5,
        max_overflow=10,
        pool_timeout=10,
        pool_recycle=1800,
        pool_pre_ping=True,
        connect_args=connect_args,
    )