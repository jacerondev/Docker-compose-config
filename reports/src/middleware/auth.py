# filepath: reports/src/middleware/auth.py
"""
Middleware de autenticación para reports-api.

Flujo:
  1. Extrae el access_token de la cookie httpOnly (enviada automáticamente
     por el navegador via credentials: 'include' en el frontend).
  2. Llama a GET /api/auth/me en el backend NestJS con esa cookie.
  3. Si el backend responde 200 → inyecta el usuario en flask.g y continúa.
  4. Si el backend responde 401/403 → devuelve 401 al cliente.
  5. Si el backend no responde (timeout, red) → devuelve 503.

Uso:
  from src.middleware.auth import require_auth
  @app.route('/reports/excel')
  @require_auth
  def generate_excel():
      user = g.current_user  # {'userId': 1, 'email': '...', 'role': 'ADMIN'}
"""

import os
import functools
import structlog
import httpx                      # pip: httpx (ya en requirements.in vía httpx)
import pybreaker
import hashlib

from pydantic import BaseModel, Field
from flask import request, g, jsonify, current_app

from src.utils import read_secret

logger = structlog.get_logger(__name__)

# Tiempo máximo para esperar respuesta del backend (segundos).
# Suficiente para una red Docker interna en el mismo host.
_AUTH_TIMEOUT = float(os.environ.get("NESTJS_AUTH_TIMEOUT", "1.0"))

# URL interna del backend — resuelve por DNS Docker
_NESTJS_AUTH_URL: str = os.environ.get("NESTJS_AUTH_URL", "http://backend:4000")

_AUTH_ME_ENDPOINT = f"{_NESTJS_AUTH_URL}/api/auth/me"

_AUTH_BREAKER = pybreaker.CircuitBreaker(
    fail_max=5,        # 5 fallos consecutivos abren el circuito
    reset_timeout=30,  # 30 segundos antes de intentar de nuevo (half-open)
    name="nestjs_auth",
    listeners=[],      # se pueden añadir listeners para alertas
)



class UserPayload(BaseModel):
    userId: int = Field(gt=0, description="ID de usuario (debe ser positivo)")
    email: str = Field(min_length=1, pattern=r'^[^@]+@[^@]+\.[^@]+$')
    role: str = Field(min_length=1)


@_AUTH_BREAKER
def _call_auth_backend(cookies: dict, headers: dict):
    """Llama al backend para validar la sesión. Protegida por circuit breaker."""
    with httpx.Client(timeout=_AUTH_TIMEOUT) as client:
        return client.get(_AUTH_ME_ENDPOINT, cookies=cookies, headers=headers)


def _get_auth_cookies() -> dict[str, str]:
    """Extrae las cookies de autenticación del request entrante."""
    cookies: dict[str, str] = {}
    if "access_token" in request.cookies:
        cookies["access_token"] = request.cookies["access_token"]
    return cookies


def _validate_session() -> dict | None:
    """
    Llama al backend para validar la sesión.

    Returns:
        dict con el usuario si la sesión es válida, None en caso contrario.

    Raises:
        httpx.TimeoutException: si el backend no responde en _AUTH_TIMEOUT segundos.
        httpx.RequestError: si hay error de red (backend caído, DNS, etc.)
    """
    cookies = _get_auth_cookies()

    if not cookies:
        logger.debug("auth_no_cookie", path=request.path)
        return None
    
    # Clave de caché basada en el hash del token (no almacenar el token en la clave)
    token = cookies.get('access_token', '')
    cache_key = f"sess:{hashlib.sha256(token.encode()).hexdigest()[:32]}"

    # Intentar obtener del caché
    cache = current_app.extensions.get('session_cache')

    if cache is None:
        logger.debug("session_cache_unavailable", fallback="calling_backend_directly")

    if cache:
        cached = cache.get(cache_key)
        if cached is not None:
            return cached  # Hit: sin llamada al backend

    # Propagar X-Request-Id para trazabilidad en los logs del backend
    headers = {}
    if request_id := getattr(g, "request_id", None):
        headers["X-Request-Id"] = request_id

    response = _call_auth_backend(cookies, headers)

    if response.status_code == 200:
        try:
            user = UserPayload(**response.json()).model_dump()

            # Guardar en caché con TTL de 60s
            if cache:
                cache.set(cache_key, user, timeout=60)
                # TTL de 60s: el caché expira antes que el access_token (15m).
                # Al hacer logout, el token queda inválido en el backend.
                # Reports invalidará el caché por TTL en máximo 60s.
                # Para invalidación inmediata: implementar POST /internal/cache/invalidate
                # llamado por el backend al hacer logout, pasando el hash del token para eliminar la clave específica del caché.
            return user
        except Exception:
            # logger.error("auth_invalid_payload", body=response.text[:200])
            logger.error("auth_invalid_payload", response_length=len(response.text))
            return None

    logger.debug(
        "auth_rejected_by_backend",
        status=response.status_code,
        path=request.path,
    )
    return None


def require_auth(func):
    """
    Decorador que exige sesión válida en el backend.

    Si la sesión es válida, inyecta el usuario en g.current_user y
    continúa con la función decorada.

    Ejemplo:
        @app.route('/reports/excel')
        @limiter.limit('5 per minute')
        @require_auth
        def generate_excel():
            user = g.current_user
            ...
    """

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        try:
            user = _validate_session()
        except pybreaker.CircuitBreakerError:
            # Circuito abierto — backend no responde hace >30s
            logger.error(
                "auth_circuit_open",
                backend=_AUTH_ME_ENDPOINT,
                action="denying_all_requests"
            )
            return jsonify({
                "error": "Servicio de autenticación temporalmente no disponible.",
                "retry_after": 30
            }), 503
        except httpx.TimeoutException:
            logger.warning(
                "auth_backend_timeout",
                url=_AUTH_ME_ENDPOINT,
                timeout=_AUTH_TIMEOUT,
                path=request.path,
            )
            return jsonify({"error": "Servicio de autenticación no disponible. Intenta de nuevo."}), 503
        except httpx.RequestError as exc:
            logger.error(
                "auth_backend_unreachable",
                error=str(exc),
                path=request.path,
            )
            return jsonify({"error": "No se pudo verificar la sesión. Intenta de nuevo."}), 503

        if user is None:
            return jsonify({"error": "Sesión inválida o expirada."}), 401

        g.current_user = user
        logger.debug("auth_ok", user_id=user.get("userId"), role=user.get("role"))
        return func(*args, **kwargs)

    return wrapper