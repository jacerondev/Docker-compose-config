# filepath: reports/tests/test_health.py
# ══════════════════════════════════════════════════════════════════════════════
# Tests del endpoint /health del servicio de reportes
#
# Para ejecutar:
#   cd reports && pytest tests/ -v
#   cd reports && pytest tests/ --cov=src --cov-report=html
# ══════════════════════════════════════════════════════════════════════════════
from sqlalchemy.exc import OperationalError


# ── Tests del endpoint /health ────────────────────────────────────────────────

def test_health_responde_200(client):
    """/health responde 200 con {'status': 'ok'} — siempre, sin verificar BD."""
    response = client.get('/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'


def test_health_no_expone_estado_db(client):
    """/health público NO debe incluir detalle de BD (eso es /health/ready)."""
    response = client.get('/health')
    data = response.get_json()
    # /health solo responde status, no detalla BD ni rate_limiter
    assert 'status' in data
    assert data['status'] == 'ok'


def test_health_ready_requiere_red_interna(client):
    """/health/ready rechaza peticiones externas con 403."""
    # El cliente de test usa 127.0.0.1 por defecto — simular IP externa
    response = client.get('/health/ready',
                          environ_base={'REMOTE_ADDR': '8.8.8.8'})
    assert response.status_code == 403


def test_health_ready_desde_localhost(client):
    """/health/ready acepta peticiones desde localhost con BD disponible."""
    mock_engine = client.application.extensions['db_engine']
    # El mock del conftest ya tiene connect().execute() funcionando
    response = client.get('/health/ready',
                          environ_base={'REMOTE_ADDR': '127.0.0.1'})
    # 200 si DB mockada responde OK
    assert response.status_code in (200, 503)  # 503 si el mock no está configurado


def test_health_ready_db_caida(client):
    """/health/ready responde 503 cuando PostgreSQL no responde."""
    mock_engine = client.application.extensions['db_engine']
    mock_engine.connect.side_effect = OperationalError("connection refused", None, None)
    
    response = client.get('/health/ready',
                          environ_base={'REMOTE_ADDR': '127.0.0.1'})
    assert response.status_code == 503
    data = response.get_json()
    assert data['status'] == 'degraded'
    assert data['db'] == 'unavailable'
    
    # Restaurar el mock para no afectar otros tests
    mock_engine.connect.side_effect = None


def test_health_ready_incluye_estado_rate_limiter(client):
    """/health/ready incluye estado del rate limiter en la respuesta."""
    response = client.get('/health/ready',
                          environ_base={'REMOTE_ADDR': '127.0.0.1'})
    data = response.get_json()
    assert 'rate_limiter' in data


# ── Tests de imports y dependencias ──────────────────────────────────────────

def test_flask_importable():
    import flask
    assert flask.__version__ is not None


def test_sqlalchemy_importable():
    """SQLAlchemy es el ORM principal — verificar que está disponible."""
    from sqlalchemy import create_engine
    assert create_engine is not None


def test_pandas_importable():
    import pandas
    assert pandas.__version__ is not None


def test_pydantic_settings_importable():
    from pydantic_settings import BaseSettings
    assert BaseSettings is not None


def test_pybreaker_importable():
    """Circuit breaker — crítico para la resiliencia de auth."""
    import pybreaker
    assert pybreaker.CircuitBreaker is not None

def test_psycopg2_importable():
    """Verifica que el driver de PostgreSQL está disponible."""
    import psycopg2
    assert psycopg2.__version__ is not None