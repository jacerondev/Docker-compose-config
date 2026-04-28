# filepath: reports/tests/test_config.py
"""Tests de la configuración de Pydantic (src/config.py)."""
import pytest
import os
from unittest.mock import patch


def test_settings_carga_correctamente():
    """Settings carga sin error con variables mínimas válidas."""
    env = {
        'DB_HOST': 'localhost',
        'DB_NAME': 'test_db',
        'DB_PORT': '5432',
    }
    with patch.dict(os.environ, env, clear=False):
        from src.config import get_settings
        get_settings.cache_clear()
        settings = get_settings()
        assert settings.db_host == 'localhost'
        assert settings.db_name == 'test_db'


def test_settings_rechaza_puerto_invalido():
    """Pydantic debe rechazar puertos fuera de rango."""
    env = {
        'DB_HOST': 'localhost',
        'DB_NAME': 'test_db',
        'DB_PORT': '80',  # inválido para la app
    }
    with patch.dict(os.environ, env, clear=False):
        from src.config import get_settings
        get_settings.cache_clear()
        with pytest.raises(Exception):
            get_settings()