# filepath: reports/src/routes/reports.py
import structlog

from flask import g, Blueprint, current_app
from src.middleware.auth import require_auth
from src.schemas import ExcelReportSchema
from src.utils import validate_request

logger = structlog.get_logger(__name__)
reports_bp = Blueprint('reports', __name__)

@reports_bp.route('/reports/excel', methods=['POST'])
@require_auth
@validate_request(ExcelReportSchema, source='json')
def generate_excel_report():
    user = g.current_user
    params: ExcelReportSchema = g.validated_data
    # params.date_from, params.date_to, params.format están validados
    return {'error': 'Not implemented'}, 501  # Implementar lógica de generación de reportes aquí
    # return jsonify({"status": "not implemented"}), 501


# Cuando añadas PDF (más costoso que Excel):
# @reports_bp.route('/reports/pdf', methods=['POST'])
# @current_app.extensions['limiter'].limit("2 per minute")  # más restrictivo
# @require_auth
# @validate_request(PdfReportSchema, source='json')
# def generate_pdf_report():
#     ...