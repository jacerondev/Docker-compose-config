# filepath: reports/src/middleware/local_only.py — NUEVO ARCHIVO
"""
Decorador @local_only_required para restringir acceso a red interna Docker/localhost.
Equivalente al LocalOnlyGuard de NestJS (backend/src/common/guards/local-only.guard.ts).
"""

import os
import ipaddress
import functools
import structlog
from flask import request, abort

logger = structlog.get_logger(__name__)

# Red interna Docker bridge + localhost
_ALLOWED_NETS = [
    ipaddress.ip_network('127.0.0.0/8'),
    ipaddress.ip_network('172.16.0.0/12'),   # Docker bridge estándar Linux
    ipaddress.ip_network('::1/128'),          # IPv6 loopback
]

# Red extra configurable via env var (útil en CI o Docker Desktop)
_extra = os.environ.get('INTERNAL_NETWORK')
if _extra:
    try:
        _ALLOWED_NETS.append(ipaddress.ip_network(_extra, strict=False))
    except ValueError:
        logger.warning("invalid_internal_network_env", value=_extra)


def _is_internal_request() -> bool:
    """Verifica si el request proviene de la red interna."""
    raw = request.remote_addr or '127.0.0.1'
    clean = raw.replace('::ffff:', '')  # Quitar prefijo IPv4-mapped IPv6
    try:
        client_ip = ipaddress.ip_address(clean)
    except ValueError:
        return False
    return any(client_ip in net for net in _ALLOWED_NETS)


def local_only_required(func):
    """
    Decorador que restringe el acceso a requests desde red interna Docker/localhost.
    Uso idéntico al _local_only() de health.py pero como decorador reutilizable.

    Uso:
        from src.middleware.local_only import local_only_required

        @auth_bp.route('/internal/cache/invalidate', methods=['POST'])
        @local_only_required
        def invalidate_session_cache():
            ...
    """
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        if not _is_internal_request():
            logger.warning(
                "local_only_access_denied",
                remote_addr=request.remote_addr,
                path=request.path,
            )
            abort(403)
        return func(*args, **kwargs)
    return wrapper