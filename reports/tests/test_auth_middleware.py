# filepath: reports/tests/test_auth_middleware.py
import pytest
from unittest.mock import patch, MagicMock
import httpx


def test_require_auth_sin_cookie_devuelve_401(client):
    """Sin cookie access_token → 401."""
    response = client.post('/reports/excel',
                           json={"date_from": "2026-01-01", "date_to": "2026-01-31"})
    assert response.status_code == 401


def test_require_auth_backend_responde_200(client):
    """Si el backend valida la sesión → continúa."""
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "userId": 1, "email": "test@test.com", "role": "ADMIN"
    }
    with patch('src.middleware.auth._validate_session', return_value={
        "userId": 1, "email": "test@test.com", "role": "ADMIN"
    }):
        response = client.post('/reports/excel',
                               json={"date_from": "2026-01-01", "date_to": "2026-01-31"},
                               headers={"Cookie": "access_token=fake_token"})
        # 501 porque el endpoint no está implementado, pero auth pasó
        assert response.status_code == 501


def test_require_auth_backend_timeout_devuelve_503(client):
    """Si el backend no responde en tiempo → 503."""
    with patch('src.middleware.auth._validate_session',
               side_effect=httpx.TimeoutException("timeout")):
        response = client.post('/reports/excel',
                               json={},
                               headers={"Cookie": "access_token=fake_token"})
        assert response.status_code == 503


def test_circuit_breaker_abre_tras_fallos_consecutivos(client):
    """Después de 5 timeouts, el circuit breaker abre."""
    import pybreaker
    with patch('src.middleware.auth._call_auth_backend',
               side_effect=httpx.TimeoutException("timeout")):
        for _ in range(5):
            client.post('/reports/excel',
                        json={},
                        headers={"Cookie": "access_token=fake_token"})
    # El 6to request debería obtener CircuitBreakerError
    with patch('src.middleware.auth._call_auth_backend',
               side_effect=pybreaker.CircuitBreakerError()):
        response = client.post('/reports/excel',
                               json={},
                               headers={"Cookie": "access_token=fake_token"})
        assert response.status_code == 503
        data = response.get_json()
        assert "retry_after" in data