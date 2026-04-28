# filepath: reports/src/routes/__init__.py

from .health import health_bp
from .reports import reports_bp
from .auth import auth_bp

def register_routes(app):
    app.register_blueprint(health_bp)
    app.register_blueprint(reports_bp)
    app.register_blueprint(auth_bp)