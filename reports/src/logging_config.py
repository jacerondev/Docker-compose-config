# filepath: reports/src/logging_config.py
"""
src/logging_config.py — Configuración centralizada de logging estructurado

Por qué structlog en vez de logging estándar de Python:
  - logging estándar emite texto plano → imposible de parsear automáticamente
  - structlog emite JSON en producción → Loki/Promtail lo indexa por campo
  - En desarrollo emite formato legible con colores (ConsoleRenderer)
  - Los campos extra se pasan como kwargs: logger.info("event", user_id=1, duration_ms=45)
  - Compatible 100% con el logging estándar de Python (stdlib bridge)

Uso en el resto del código:
  import structlog
  logger = structlog.get_logger()

  logger.info("report_requested", year=2026, month=3, user_ip="1.2.3.4")
  logger.warning("db_slow_query", duration_ms=850, query="SELECT...")
  logger.error("report_failed", exc_info=True, report_type="monthly")
"""

import logging
import os
import structlog
import uuid


def _add_trace_id(logger, method, event_dict):
    """Añade trace_id para correlación cross-service."""
    from flask import g
    trace_id = getattr(g, 'trace_id', None)
    if trace_id:
        event_dict['trace_id'] = trace_id
    return event_dict


def _redact_sensitive_fields(
    logger: logging.Logger,
    method: str,
    event_dict: dict,
) -> dict:
    """Redacta campos sensibles antes de enviar a Loki."""
    sensitive_keys = {'password', 'secret', 'token', 'authorization', 'cookie'}
    for key in list(event_dict.keys()):
        if any(s in key.lower() for s in sensitive_keys):
            event_dict[key] = '[REDACTED]'
    return event_dict


def configure_logging() -> None:
    """
    Configura structlog una sola vez al arrancar la app.

    Llamar ANTES de crear la instancia Flask:
        from src.logging_config import configure_logging
        configure_logging()
        app = Flask(__name__)

    Entornos:
      - development : ConsoleRenderer (colores, legible en terminal)
      - production  : JSONRenderer   (JSON por línea, indexable por Loki)
    """
    is_production = os.environ.get('APP_ENV', 'development') == 'production'

    # ── 1. Configurar el logging estándar de Python ──────────────────────────
    # structlog actúa como wrapper sobre stdlib logging.
    # Esto asegura que librerías externas (flask, gunicorn, psycopg2)
    # también emitan sus logs en el mismo formato.
    log_level = logging.INFO if is_production else logging.DEBUG

    logging.basicConfig(
        format="%(message)s",           # structlog gestiona el formato final
        level=log_level,
    )

    # Silenciar logs demasiado verbosos de librerías externas en producción
    if is_production:
        logging.getLogger("werkzeug").setLevel(logging.WARNING)
        logging.getLogger("urllib3").setLevel(logging.WARNING)

    # ── 2. Pipeline de procesadores ──────────────────────────────────────────
    # Cada procesador recibe el evento y devuelve el evento modificado.
    # El último procesador determina el formato de salida final.
    shared_processors = [
        # Añade contexto de la variable de contexto (request_id, user_id, etc.)
        # Se limpia automáticamente entre requests si se usa con Flask
        structlog.contextvars.merge_contextvars,

        # Añade el nivel de log como campo: {"level": "info", ...}
        structlog.stdlib.add_log_level,

        # Añade el nombre del logger como campo: {"logger": "src.routes.reports", ...}
        structlog.stdlib.add_logger_name,

        # Añade timestamp ISO: {"timestamp": "2026-03-11T10:30:00.123456Z", ...}
        structlog.processors.TimeStamper(fmt="iso"),

        # Si se pasa exc_info=True, formatea la excepción como campo
        structlog.processors.format_exc_info,

        # Si se pasa stack_info=True, añade el stack trace
        structlog.processors.StackInfoRenderer(),

        # Redacta campos sensibles antes de enviar a Loki
        _redact_sensitive_fields,

        # Añade trace_id para correlación cross-service (si está disponible)
        _add_trace_id
    ]

    structlog.configure(
        processors=shared_processors + [
            # Producción: JSON puro, una línea por evento → Loki/Promtail lo indexa
            # Desarrollo: formato con colores y alineación → legible en terminal
            structlog.processors.JSONRenderer()
            if is_production
            else structlog.dev.ConsoleRenderer(colors=True),
        ],
        # make_filtering_bound_logger filtra por nivel ANTES de procesar
        # Más eficiente que filtrar al final
        wrapper_class=structlog.make_filtering_bound_logger(log_level),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
        # Cachea el logger la primera vez que se llama get_logger()
        # Mejora rendimiento en producción (no recrea el logger en cada request)
        cache_logger_on_first_use=True,
    )


def bind_request_context(request_id: str, method: str, path: str) -> None:
    """
    Vincula contexto del request actual para que aparezca en TODOS los logs
    generados durante ese request, sin necesidad de pasarlo manualmente.

    Uso en Flask (añadir en before_request):
        @app.before_request
        def set_request_context():
            import uuid
            bind_request_context(
                request_id=request.headers.get('X-Request-Id', str(uuid.uuid4())),
                method=request.method,
                path=request.path,
            )

    Uso en Flask (limpiar en teardown_request):
        @app.teardown_request
        def clear_request_context(exc):
            structlog.contextvars.clear_contextvars()
    """
    structlog.contextvars.bind_contextvars(
        request_id=request_id,
        method=method,
        path=path,
    )
