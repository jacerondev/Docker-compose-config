# filepath: reports/gunicorn.conf.py

import os

# ── Binding ──────────────────────────────────────────────────────────────────
bind = f"0.0.0.0:{os.environ.get('PORT_REPORTS', '5000')}"
forwarded_allow_ips = "127.0.0.1"  # Solo confiar en X-Forwarded-For de Nginx

# ── Workers ───────────────────────────────────────────────────────────────────
workers = min(os.cpu_count() or 2, 4)
worker_class = "gthread"
threads = 4

# ── Timeouts y límites ────────────────────────────────────────────────────────
timeout = 300               # 5 min — reportes Excel/CSV pesados
max_requests = 200          # Reinicio preventivo contra memory leaks de Pandas
max_requests_jitter = 40    # Desfasa reinicios para evitar picos simultáneos
worker_tmp_dir = "/dev/shm" # Heartbeats en RAM — más rápido que disco

# ── Seguridad HTTP ────────────────────────────────────────────────────────────
limit_request_line = 4094
limit_request_fields = 100
limit_request_field_size = 8190

# ── Preload ────────────────────────────────────────────────────────────────────
preload_app = True          # Carga la app UNA vez en master, forkea workers

# ── Logging ───────────────────────────────────────────────────────────────────
accesslog = "-"   # stdout → visible con docker logs
errorlog = "-"    # stdout

# ── Hook de Gunicorn post-fork ────────────────────────────────────────────────
# IMPORTANTE: Este hook SOLO se activa con --preload en el CMD de Gunicorn.
# Sin --preload, Gunicorn no usa este hook porque
# cada worker crea su propio engine independiente desde cero.
#
# Referencia: https://docs.sqlalchemy.org/en/20/core/connections.html#using-connection-pools-with-multiprocessing
# Cuando se usa --preload, el master process carga el código y crea el engine,
# luego forkea los workers. Sin --preload, cada worker carga el código y crea su propio engine,
# por lo que no hay conexiones heredadas que limpiar.
def post_fork(server, worker):
    """
    Limpia el pool de conexiones SQLAlchemy heredado del proceso master.
    Necesario con preload_app=True: el master crea el engine antes del fork.
    PostgreSQL no es fork-safe — dispose() fuerza a cada worker a crear conexiones propias.
    """
    # Importar app para acceder al engine registrado en extensions
    from main import app    # Con --preload, main ya está en sys.modules
    engine = app.extensions.get('db_engine')
    if engine:
        engine.dispose()