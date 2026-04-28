# filepath: reports/src/routes/health.py
import os
import structlog
from flask import abort, Blueprint, current_app
from src.middleware.local_only import _is_internal_request

logger = structlog.get_logger(__name__)
health_bp = Blueprint('health', __name__)

def _local_only() -> None:
    """Restringe acceso a red interna — delega a middleware central."""
    if not _is_internal_request():
        abort(403)

# Límite aplicado desde main.py: limiter.limit("30 per minute")(health_bp)
@health_bp.route('/health')
def health():
    """
    Healthcheck con verificación real de PostgreSQL.
    Retorna 200 si la DB responde, 503 si no.

    Petición publica (Nginx puede acceder sin autenticación) para monitoreo externo (UptimeRobot, etc).
    
    Uso:
    - Monitoreo (Uptime)
    - Verifica que la app está viva (NO dependencias)

    No incluir:
    - Estado de base de datos
    - Servicios externos
    """

    return {'status': 'ok'}, 200

# Límite aplicado desde main.py: limiter.limit("30 per minute")(health_bp)
@health_bp.route('/health/ready')
def health_ready():
    """
    Healthcheck INTERNO — solo para Docker healthcheck (curl dentro del contenedor).
    Verifica conexión real a PostgreSQL. Nginx NO debe exponer esta ruta.
    Retorna 200 + detalle de BD si responde, 503 si no.

    Petición privada (solo desde dentro del contenedor) para monitoreo interno de Docker.
    Bloqueado el acceso externo (Nginx) actualmente.
    
    Uso:
    - Monitoreo (Uptime)
    - Verifica que la app está viva (NO dependencias)

    Incluir:
    - Estado de base de datos
    - Servicios externos
    """
    _local_only()

    # engine = current_app.extensions['db_engine']
    # try:
    #     with engine.connect() as conn:
    #         conn.execute(engine.text('SELECT 1'))
    #     logger.debug("readiness_check_ok")
    #     return {'status': 'ok', 'db': 'connected'}, 200
    # except Exception as exc:
    #     is_production = os.environ.get('APP_ENV', 'development') == 'production'
    #     logger.warning(
    #         "readiness_check_db_error",
    #         error_type=type(exc).__name__,
    #         error_summary=str(exc).split('\n')[0],
    #         exc_info=not is_production,
    #     )
    #     return {'status': 'degraded', 'db': 'unavailable'}, 503

    engine = current_app.extensions['db_engine']
    limiter = current_app.extensions.get('limiter')
    
    status = {'db': 'unknown', 'rate_limiter': 'unknown'}
    degraded = False
    
    # Check DB
    try:
        with engine.connect() as conn:
            conn.execute(engine.text('SELECT 1'))
        status['db'] = 'connected'
    except Exception:
        status['db'] = 'unavailable'
        degraded = True
    
    # Check Redis (si está configurado)
    redis_url = os.environ.get('REDIS_URL')
    if redis_url:
        try:
            import redis as redis_client
            r = redis_client.from_url(redis_url, socket_connect_timeout=1)
            r.ping()
            status['rate_limiter'] = 'redis_connected'
        except Exception:
            status['rate_limiter'] = 'redis_unavailable_using_memory_fallback'
            # No es degraded — el rate limiter sigue funcionando con fallback
            logger.warning("redis_health_check_failed")
    else:
        status['rate_limiter'] = 'memory_mode'
    
    http_status = 503 if degraded else 200
    return {'status': 'degraded' if degraded else 'ok', **status}, http_status