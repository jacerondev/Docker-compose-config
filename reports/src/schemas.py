# filepath: reports/src/schemas.py
"""
Modelos Pydantic para validación de entrada en los endpoints de reports-api.

Principio: validar en la frontera — antes de que los datos lleguen a SQLAlchemy
o a las funciones de generación de archivos.
"""
from datetime import date
from typing import Literal, Optional
from pydantic import BaseModel, Field, field_validator, model_validator


class DateRangeSchema(BaseModel):
    """Rango de fechas para filtrar reportes."""
    date_from: date = Field(..., description="Fecha de inicio (YYYY-MM-DD)")
    date_to: date   = Field(..., description="Fecha de fin (YYYY-MM-DD)")

    @model_validator(mode='after')
    def validate_range(self) -> 'DateRangeSchema':
        if self.date_from > self.date_to:
            raise ValueError("date_from no puede ser posterior a date_to")
        # Limitar rango máximo a 1 año para evitar consultas gigantes
        delta = (self.date_to - self.date_from).days
        if delta > 365:
            raise ValueError("El rango máximo permitido es 365 días")
        return self


class ExcelReportSchema(BaseModel):
    """Parámetros de solicitud para generación de reporte Excel."""
    date_from: date = Field(..., description="Fecha de inicio")
    date_to: date   = Field(..., description="Fecha de fin")
    format: Literal["xlsx", "csv"] = Field(default="xlsx")
    # Limitar filas máximas para prevenir abuso de recursos
    max_rows: int = Field(default=10_000, ge=1, le=50_000)

    @model_validator(mode='after')
    def validate_date_range(self) -> 'ExcelReportSchema':
        if self.date_from > self.date_to:
            raise ValueError("date_from no puede ser posterior a date_to")
        if (self.date_to - self.date_from).days > 365:
            raise ValueError("El rango máximo es 365 días")
        return self