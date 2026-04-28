# filepath: reports/src/config/config.py
"""
Configuración con validación automática (equivalente a class-validator en NestJS).
Falla al arrancar si falta alguna variable — mejor que fallar en runtime.

DISEÑO DE CREDENCIALES:
  Desarrollo:  db_user / db_password vienen de variables de entorno (.env)
  Producción:  db_user / db_password NO vienen de variables de entorno.
               Vienen de Docker Secrets montados en /run/secrets/.
               main.py los lee directamente con get_db_connection() → read_secret().
               Por eso db_user y db_password son Optional aquí (default None).

  nestjs_auth_url es una URL interna (no sensible): http://backend:4000
  Va en .env / .env.production como variable normal — no necesita Docker Secret.
  Default a 'http://backend:4000' para que los tests no fallen si no está definida.
"""
from typing import Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator, model_validator
from functools import lru_cache
import os


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file='.env',
        extra='ignore',  # ignorar variables no declaradas
    )

    # ── Base de datos ──────────────────────────────────────────────────────────
    # host, port, name: no son sensibles → siempre vienen de variables de entorno
    db_host: str
    db_port: int = 5432
    db_name: str

    # user y password: Optional porque en producción vienen de Docker Secrets
    # (archivos /run/secrets/db_user y /run/secrets/db_password), NO de env vars.
    # main.py → get_db_connection() → read_secret() los lee directamente del archivo.
    # En desarrollo sí vienen del .env y pasan la validación normalmente.
    db_user: Optional[str] = None
    db_password: Optional[str] = None

    # ── Servicio ───────────────────────────────────────────────────────────────
    port: int = 5000
    app_env: str = 'development'
    flask_debug: bool = False  # Controlado por FLASK_DEBUG=0/1

    # URL interna para validar tokens con NestJS.
    # No es sensible → va en .env / .env.production como variable normal.
    # Tiene default para que los tests no fallen si no hay backend activo.
    nestjs_auth_url: str = 'http://backend:4000'

    @field_validator('db_port', 'port')
    @classmethod
    def validate_port(cls, v: int) -> int:
        if not (1024 <= v <= 65535):
            raise ValueError(f'Puerto {v} fuera de rango válido (1024-65535)')
        return v
    
    @model_validator(mode='after')
    def validate_production_secrets(self) -> 'Settings':
        """
        En producción, db_user y db_password NO vienen del .env (son Optional).
        Vienen de Docker Secrets vía main.py → _read_secret().
        
        Este validator verifica que al menos UNO de los dos caminos esté disponible:
          - La variable de entorno directa (desarrollo)
          - El archivo de Docker Secret (producción)
        
        Esto captura el error al arrancar, no en el primer request.
        """
        is_production = self.app_env == 'production'
        
        if is_production:
            # En producción: verificar que los archivos de secrets existen
            db_user_file = os.environ.get('DB_USER_FILE')
            db_password_file = os.environ.get('DB_PASSWORD_FILE')
            
            errors = []
            if not db_user_file:
                errors.append('DB_USER_FILE no definido — falta el Docker Secret para db_user')
            elif not os.path.exists(db_user_file):
                errors.append(f'DB_USER_FILE apunta a {db_user_file} pero el archivo no existe')
                
            if not db_password_file:
                errors.append('DB_PASSWORD_FILE no definido — falta el Docker Secret para db_password')
            elif not os.path.exists(db_password_file):
                errors.append(f'DB_PASSWORD_FILE apunta a {db_password_file} pero el archivo no existe')
            
            if errors:
                raise ValueError(
                    'Configuración de producción inválida:\n' +
                    '\n'.join(f'  - {e}' for e in errors) +
                    '\n  ¿Ejecutaste make secrets-init?'
                )
        else:
            # En desarrollo: al menos db_user debe estar disponible
            if not self.db_user:
                raise ValueError(
                    'DB_USER no definido en desarrollo. '
                    'Verifica tu .env o ejecuta: make setup'
                )
        
        return self


    @model_validator(mode='after')
    def validate_ssl_in_production(self) -> 'Settings':
        if self.app_env == 'production':
            db_ssl = os.environ.get('DB_SSL_REQUIRED', 'false')
            if db_ssl != 'true':
                import warnings
                warnings.warn(
                    'DB_SSL_REQUIRED no está configurado como true en producción. '
                    'La conexión a la BD no está cifrada.',
                    stacklevel=2
                )
                # En caso de que el proyecto maneje SSL obligatorio, cambiar por raise
                # generando un bloqueo en lugar de una advertencia
                # Actualmente no se contempra el uso de SSL, pero esta validación queda
                # como ejemplo de cómo manejar configuraciones críticas en producción.
                # raise ValueError(
                #     "DB_SSL_REQUIRED=true es obligatorio en producción. "
                #     "La conexión a la BD no está cifrada. "
                #     "Configura DB_SSL_REQUIRED=true en .env.production y "
                #     "provee DB_SSL_CA con el certificado del servidor."
                # )

        return self

    @property
    def is_development(self) -> bool:
        return self.app_env == 'development'


@lru_cache  # singleton — misma instancia en toda la app
def get_settings() -> Settings:
    return Settings()
