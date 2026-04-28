# filepath: reports/src/routes/auth.py — endpoint interno (solo accesible desde red Docker)

import structlog
from flask import request, Blueprint, current_app
from src.middleware.local_only import local_only_required

logger = structlog.get_logger(__name__)
auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/internal/cache/invalidate', methods=['POST'])
@local_only_required
def invalidate_session_cache():
    """Llamado por el backend cuando un usuario hace logout."""
    data = request.get_json(silent=True) or {}
    token_hash = data.get('token_hash')
    if not token_hash or not isinstance(token_hash, str) or len(token_hash) < 10:
        return {'error': 'token_hash inválido'}, 400
    
    cache = current_app.extensions.get('session_cache')
    if cache and token_hash:
        cache_key = f"sess:{token_hash[:32]}"  # Usar 32 chars del hash
        cache.delete(cache_key)
        logger.info("session_cache_invalidated", key_prefix=cache_key[:8])
    return {'ok': True}, 200