# filepath: reports/src/utils.py
"""Utilidades para validación de request en Flask con Pydantic."""
import functools
from typing import Type
from pydantic import BaseModel, ValidationError
from flask import request, jsonify
import os
import warnings

_PLACEHOLDER_PREFIXES = ('cambiar_', 'placeholder', 'changeme', 'your_', 'todo_')

def validate_request(schema: Type[BaseModel], source: str = "json"):
    """
    Decorador que valida el cuerpo (JSON) o query params de un request con Pydantic.

    Args:
        schema: Clase Pydantic a usar para validación.
        source: 'json' para body, 'query' para query params (?key=val).

    Uso:
        @app.route('/reports/excel', methods=['POST'])
        @validate_request(ExcelReportSchema, source='json')
        @require_auth
        def generate_excel():
            data: ExcelReportSchema = g.validated_data
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            from flask import g
            try:
                if source == "json":
                    raw = request.get_json(silent=True) or {}
                else:  # query params
                    raw = request.args.to_dict()

                g.validated_data = schema.model_validate(raw)
            except ValidationError as e:
                # Devolver errores de validación sin exponer estructura interna
                errors = [
                    {"field": ".".join(str(loc) for loc in err["loc"]), "message": err["msg"]}
                    for err in e.errors()
                ]
                return jsonify({"error": "Datos de entrada inválidos", "details": errors}), 422
            return func(*args, **kwargs)
        return wrapper
    return decorator


def read_secret(
    file_env: str,
    plain_env: str | None,
    required: bool = True,
    min_length: int = 0,
    allow_placeholder_in_dev: bool = True,
) -> str | None:
    """
    Lee un secreto desde archivo (Docker Secret) o variable de entorno.

    Equivalente a readSecret() en backend/src/config/database.config.ts.

    Args:
        file_env:  Variable que apunta al archivo, ej: 'DB_PASSWORD_FILE'
        plain_env: Variable con el valor directo,  ej: 'DB_PASSWORD'
        required: Si True, lanza error si no se encuentra el secreto.
        min_length: Longitud mínima del secreto (si se encuentra).
        allow_placeholder_in_dev: Si True, permite valores de placeholder en desarrollo.

    Returns:
        El valor del secreto, o None si ninguno está disponible.

    Raises:
        RuntimeError: Si el archivo existe pero no se puede leer.
    """
    is_production = os.environ.get('APP_ENV', 'development') == 'production'
    file_path = os.environ.get(file_env) if file_env else None
    value: str | None = None

    if file_path:
        try:
            with open(file_path) as f:
                return f.read().strip()
        except FileNotFoundError:
            raise RuntimeError(
                f"Docker Secret no encontrado: {file_path}\n"
                f"¿Ejecutaste 'make secrets-init' y 'make secrets-check'?\n"
                f"Variable referenciada: {file_env}"
            )
        except PermissionError:
            raise RuntimeError(
                f"Sin permisos para leer {file_path}. "
                f"Verifica que el secreto está montado correctamente."
            )
    elif plain_env:
        value = os.environ.get(plain_env)

    if not value:
        if required:
            raise RuntimeError(
                f"Secreto requerido no disponible: "
                f"ni {file_env} ni {plain_env} están definidos."
            )
        return None
    
    # Validación de longitud mínima
    if min_length > 0 and len(value) < min_length:
        raise RuntimeError(
            f"Secreto demasiado corto ({len(value)} chars, mínimo {min_length})."
        )

    # Detección de placeholders
    if value.lower().startswith(_PLACEHOLDER_PREFIXES):
        if is_production or not allow_placeholder_in_dev:
            raise RuntimeError(
                f"El secreto contiene un valor placeholder. "
                f"Ejecuta 'make secrets-init' para generar secretos reales."
            )
        warnings.warn(
            f"Secreto con valor placeholder detectado. Ejecuta 'make setup'.",
            stacklevel=2,
        )

    # Fallback: variable de entorno directa (desarrollo)
    return value