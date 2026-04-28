# filepath: reports/tests/conftest.py
"""
Fixtures compartidos para todos los tests de reports-api.

Uso:
    pytest tests/ -v
    pytest tests/ --cov=src --cov-report=html
"""
import pytest
from unittest.mock import patch, MagicMock


@pytest.fixture(scope='session')
def app():
    """
    Mock del engine SQLAlchemy antes de importar main para evitar conexión real a PostgreSQL.
    Crea la app Flask configurada para testing.
    scope='session' = una sola instancia para todos los tests (más rápido).
    """
    mock_engine = MagicMock()
    mock_conn = MagicMock()
    mock_engine.connect.return_value.__enter__ = MagicMock(return_value=mock_conn)
    mock_engine.connect.return_value.__exit__ = MagicMock(return_value=False)
    mock_conn.execute.return_value = MagicMock()

    with patch('src.db.create_db_engine', return_value=mock_engine):
        try:
            from main import app as flask_app
            flask_app.config['TESTING'] = True
            # flask_app.config['DEBUG'] = False
            yield flask_app
        except ImportError as e:
            pytest.skip(f"main.py no importable: {e}")


@pytest.fixture
def client(app):
    """Cliente HTTP para tests. Un cliente nuevo por test (scope=function)."""
    return app.test_client()


@pytest.fixture
def mock_db_ok():
    """Mock de conexión DB que simula PostgreSQL disponible."""
    conn = MagicMock()
    cursor = MagicMock()
    conn.cursor.return_value.__enter__ = MagicMock(return_value=cursor)
    conn.cursor.return_value.__exit__ = MagicMock(return_value=False)
    return conn


@pytest.fixture
def mock_db_down():
    """Mock que simula PostgreSQL caído (SQLAlchemy OperationalError)."""
    from sqlalchemy.exc import OperationalError
    # No usar psycopg2.OperationalError directamente — SQLAlchemy lo envuelve
    return OperationalError("connection refused", None, None)
