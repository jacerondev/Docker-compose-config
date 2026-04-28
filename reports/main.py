# filepath: reports/main.py

"""
main.py — Punto de entrada de la API de reportes (Flask)

Orden de inicialización (IMPORTANTE):
  1. configure_logging()   ← PRIMERO, antes de cualquier import que logge
  2. Flask app setup
  3. Registrar blueprints y rutas
"""


# ── 1. Logging estructurado — DEBE ser lo primero ─────────────────────────────
# structlog necesita configurarse antes de que cualquier otra librería
# intente loggear. Si Flask o psycopg2 loggan antes de configurar structlog,
# los primeros mensajes saldrían en formato plano.
from src.logging_config import configure_logging, bind_request_context
configure_logging()


# ── 2. Imports después del logging ────────────────────────────────────────────
import uuid
import os
import structlog

from flask import Flask, request, g
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_caching import Cache

from src.config import get_settings
from src.utils import read_secret
from src.db import create_db_engine

from src.routes import health_bp, register_routes, reports_bp


# Logger del módulo principal
logger = structlog.get_logger(__name__)
alert_logger = structlog.get_logger("redis_health")


# ── 3. Configuración de Redis ─────────────────────────────────────────

# Leer la URL base y la contraseña por separado, construir URL completa
_REDIS_URL_BASE = os.environ.get('REDIS_URL')  # redis://nombre_del_proyecto_redis:6379/0
_REDIS_PASSWORD = read_secret('REDIS_PASSWORD_FILE', 'REDIS_PASSWORD')  # Del Docker Secret o variable de entorno

if _REDIS_URL_BASE and _REDIS_PASSWORD:
    # Insertar contraseña: redis://:PASSWORD@host:port/db
    # El : antes del password es el formato estándar de URI Redis
    from urllib.parse import urlparse, urlunparse
    parsed = urlparse(_REDIS_URL_BASE)
    REDIS_URL = urlunparse(parsed._replace(netloc=f":{_REDIS_PASSWORD}@{parsed.hostname}:{parsed.port}"))
elif _REDIS_URL_BASE:
    REDIS_URL = _REDIS_URL_BASE  # Sin contraseña (desarrollo)
else:
    REDIS_URL = None


# ── 4. Alertas redis ─────────────────────────────────────────
class AlertingLimiter(Limiter):
    """Limiter que alerta cuando Redis no responde en vez de bloquear la app."""
    
    def _check_request_limit(self, *args, **kwargs):
        try:
            return super()._check_request_limit(*args, **kwargs)
        except Exception as exc:
            # Redis caído: loggear como alerta crítica
            alert_logger.critical(
                "redis_unavailable_rate_limiting_disabled",
                error=str(exc),
                action="fail_open"  # permitir el request, no bloquear
            )
            # fail-open: el request pasa, pero queda registrado
            return None

# ── 5. Crear la app Flask ─────────────────────────────────────────────────────
app = Flask(__name__)
settings = get_settings()

# CORS: solo permite orígenes definidos en ALLOWED_ORIGINS (ver ADR-020)
CORS(app, origins=os.environ.get('ALLOWED_ORIGINS', 'http://localhost:3000').split(','))
REDIS_URL = os.environ.get('REDIS_URL')
is_production = os.environ.get('APP_ENV', 'development') == 'production'

if is_production and not REDIS_URL:
    raise RuntimeError(
        "[main] REDIS_URL es obligatorio en producción.\n"
        "  Añade REDIS_URL en .env.production y\n"
        "  asegúrate de que el servicio redis está corriendo."
    )

# Rate limiting: 200 req/min por IP (ajustable según necesidades)
limiter = AlertingLimiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per minute"],
    # En producción, /tmp es un tmpfs (ver docker-compose.prod.yml)
    # Mejor que in-memory: sobrevive a recargas de código (APP_ENV=development reload)
    # No sobrevive a reinicios del contenedor — para eso necesitas Redis
    # storage_uri="redis://redis:6379/0",
    storage_uri=REDIS_URL if REDIS_URL else "memory://",
    # storage_uri="memory://",  # No se usa porque con workers múltiples y recargas de código, el almacenamiento
    # en memoria no se comparte entre procesos, lo que hace que el rate limit sea ineficaz.
    # NOTA: El estado se pierde en reinicios. Para producción con SLA,
    # Considerar añadir rate limiting adicional en el host con fail2ban
    # para complementar la capa de aplicación.
    storage_options={"socket_connect_timeout": 1},
)

# Configurar caché de sesiones (TTL de 60s — la sesión del backend expira en 15m)
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache' if REDIS_URL else 'SimpleCache',
    'CACHE_REDIS_URL': REDIS_URL,
    'CACHE_DEFAULT_TIMEOUT': 60,   # 60 segundos — balance seguridad/performance
    'CACHE_KEY_PREFIX': 'session_cache:',
}

# ── 6. Contexto de request — añade request_id a todos los logs ────────────────

@app.before_request
def set_request_context() -> None:
    """Vincula un ID único a cada request para correlación de logs."""
    request_id = request.headers.get('X-Request-Id', str(uuid.uuid4()))
    g.request_id = request_id
    bind_request_context(
        request_id=request_id,
        method=request.method,
        path=request.path,
    )


@app.teardown_request
def clear_request_context(exc: Exception | None) -> None:
    """Limpia el contexto de structlog al terminar cada request."""
    structlog.contextvars.clear_contextvars()


# ── 7. Inicializar SQLAlchemy engine ──────────────────────────────────────────
engine = create_db_engine()
cache = Cache(app, config=CACHE_CONFIG)

app.extensions['db_engine'] = engine
app.extensions['limiter'] = limiter
app.extensions['session_cache'] = cache


if app.extensions.get('session_cache') is None:
    logger.warning("session_cache_not_registered",
                   impact="auth calls to backend on every request")

limiter.limit("30 per minute")(health_bp)  # Health endpoints: límite generoso para Docker healthchecks
limiter.limit("5 per minute")(reports_bp)  # Reportes pesados: muy restrictivo
# limiter.limit("5 per minute")(auth_bp)  # Endpoints de auth: Entre backend y reports, no expone auth directamente al frontend

register_routes(app)


# ── 8. Arranque directo (desarrollo) ─────────────────────────────────────────
# En producción el servidor lo levanta Gunicorn (ver Dockerfile.prod):
#   CMD ["gunicorn", "--bind", "0.0.0.0:5000", "main:app"]
#
# APP_ENV es la única variable que controla el modo del stack Python:
#   'development' → logs con colores (ConsoleRenderer), debug Flask activo
#   'production'  → logs JSON estructurados (JSONRenderer), debug desactivado

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app_env = os.environ.get('APP_ENV', 'development')
    flask_debug = os.environ.get('FLASK_DEBUG', '0') == '1'
    logger.info("app_starting", port=port, app_env=app_env)
    is_development = app_env == 'development'
    app.run(host='0.0.0.0', port=port, debug=flask_debug and is_development)
