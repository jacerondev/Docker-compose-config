# filepath: reports/tests/test_db_readonly.py

"""
Verifica que el usuario de BD de reports-api NO puede ejecutar
operaciones de escritura (INSERT/UPDATE/DELETE/DROP).

Este test requiere una BD PostgreSQL real — se salta en CI sin BD.
En CI con BD: ejecutar con make test-reports-integration.
"""
import pytest
import os
from sqlalchemy import create_engine, text
from sqlalchemy.exc import ProgrammingError

# Salta si no hay variables de BD disponibles (CI sin integración real)
pytestmark = pytest.mark.skipif(
    not os.environ.get('DB_HOST'),
    reason="Requiere conexión real a PostgreSQL (DB_HOST no definida)"
)


@pytest.fixture(scope='module')
def db_engine():
    """Engine con credenciales de solo lectura (como en producción de reports)."""
    from src.db import create_db_engine
    engine = create_db_engine()
    yield engine
    engine.dispose()


def test_usuario_puede_hacer_select(db_engine):
    """El usuario de reports SÍ debe poder leer datos."""
    with db_engine.connect() as conn:
        result = conn.execute(text("SELECT 1 AS test"))
        assert result.fetchone()[0] == 1


def test_usuario_no_puede_hacer_insert(db_engine):
    """El usuario de reports NO debe poder insertar datos."""
    with pytest.raises(ProgrammingError, match="permission denied"):
        with db_engine.connect() as conn:
            conn.execute(text(
                "INSERT INTO information_schema.tables VALUES (1)"
            ))


def test_usuario_no_puede_hacer_update(db_engine):
    """El usuario de reports NO debe poder modificar datos."""
    with pytest.raises(ProgrammingError, match="permission denied"):
        with db_engine.connect() as conn:
            conn.execute(text("UPDATE pg_tables SET tablename='hack' WHERE 1=0"))


def test_usuario_no_puede_hacer_delete(db_engine):
    """El usuario de reports NO debe poder eliminar datos."""
    with pytest.raises(ProgrammingError, match="permission denied"):
        with db_engine.connect() as conn:
            conn.execute(text("DELETE FROM pg_tables WHERE 1=0"))


def test_usuario_no_puede_hacer_drop(db_engine):
    """El usuario de reports NO debe poder eliminar tablas."""
    with pytest.raises(ProgrammingError, match="permission denied"):
        with db_engine.connect() as conn:
            conn.execute(text("DROP TABLE IF EXISTS test_hack"))


def test_usuario_no_puede_hacer_create(db_engine):
    """El usuario de reports NO debe poder crear objetos."""
    with pytest.raises(ProgrammingError, match="permission denied"):
        with db_engine.connect() as conn:
            conn.execute(text("CREATE TABLE test_hack (id INT)"))