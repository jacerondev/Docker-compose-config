# REPORTS-PYTHON.md — Guía de Desarrollo del Servicio de Reportes

> **Referencia técnica viva.** Actualizar al añadir rutas, servicios o decisiones.
>
> Stack: Python 3.12 · Flask · Gunicorn (gthread) · PostgreSQL · pandas · reportlab · openpyxl

---

## Índice

1. [Arquitectura del servicio](#1-arquitectura-del-servicio)
2. [Configuración con Pydantic (equivalente a class-validator)](#2-configuración-con-pydantic-equivalente-a-class-validator)
3. [Conexión a la base de datos — Docker Secrets vs env vars](#3-conexión-a-la-base-de-datos--docker-secrets-vs-env-vars)
4. [Healthcheck — proceso + conectividad DB](#4-healthcheck--proceso--conectividad-db)
5. [Añadir una nueva ruta (blueprint)](#5-añadir-una-nueva-ruta-blueprint)
6. [Generación de PDFs con reportlab](#6-generación-de-pdfs-con-reportlab)
7. [Generación de Excel con openpyxl](#7-generación-de-excel-con-openpyxl)
8. [Dependencias — cómo añadir paquetes correctamente](#8-dependencias--cómo-añadir-paquetes-correctamente)
9. [Tests con pytest](#9-tests-con-pytest)
10. [Gunicorn en producción — por qué gthread y no gevent](#10-gunicorn-en-producción--por-qué-gthread-y-no-gevent)
11. [Monkey patching — cuándo y por qué NO](#11-monkey-patching--cuándo-y-por-qué-no)
12. [RabbitMQ para reportes pesados — decisión futura](#12-rabbitmq-para-reportes-pesados--decisión-futura)
13. [SAST con Bandit — análisis estático del código Python](#13-sast-con-bandit--análisis-estático-del-código-python)
14. [Logging estructurado y Grafana Loki](#14-logging-estructurado-y-grafana-loki)
14. [Gunicorn y proxies — forwarded-allow-ips](#gunicorn-y-proxies--forwarded-allow-ips)
14. [Rate Limiting](#rate-limiting)

---

## 1. Arquitectura del servicio

```
reports/
├── main.py                     ← Bootstrap Flask + registro de blueprints + /health
├── src/
│   ├── __init__.py
│   ├── config.py               ← Pydantic: valida env vars al arrancar (fail-fast)
│   ├── routes/
│   │   ├── __init__.py
│   │   └── reports.py          ← Blueprints con los endpoints de reportes
│   ├── services/
│   │   ├── __init__.py
│   │   └── report_service.py   ← Lógica: pandas, reportlab, openpyxl
│   └── middleware/             ← Auth, logging, etc.
│
├── tests/
│   ├── __init__.py
│   ├── conftest.py             ← Fixtures de pytest (app test client)
│   └── test_health.py
│
├── requirements.in             ← SOLO editar este — dependencias directas
└── requirements.txt            ← Generado por: make update-requirements (NO editar)
```

**Flujo de un request:**
```
HTTP Request → Flask → Blueprint (routes/) → Service (services/) → PostgreSQL
                                                    ↓
                              pandas / reportlab / openpyxl
                                                    ↓
                              Response (JSON / PDF / Excel)
```

---

## 2. Configuración con Pydantic (equivalente a class-validator)

`src/config.py` valida todas las variables de entorno al arrancar. Si falta cualquiera, el servicio falla inmediatamente con un error claro — en lugar de fallar silenciosamente en el primer request.

```python
# src/config.py — ya implementado
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator
from functools import lru_cache


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file='.env',
        extra='ignore',      # ignorar vars no declaradas (no lanzar error)
    )

    # Base de datos — obligatorias
    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: str

    # Servicio
    port: int = 5000
    APP_ENV: str = 'development'
    nestjs_auth_url: str

    @field_validator('db_port', 'port')
    @classmethod
    def validate_port(cls, v: int) -> int:
        if not (1024 <= v <= 65535):
            raise ValueError(f'Puerto {v} fuera de rango (1024–65535)')
        return v

    @property
    def is_development(self) -> bool:
        return self.APP_ENV == 'development'


@lru_cache     # singleton — misma instancia en toda la app
def get_settings() -> Settings:
    return Settings()
```

**Usar en cualquier archivo:**
```python
from src.config import get_settings

settings = get_settings()
port = settings.db_port        # ← tipado, validado, siempre disponible
```

---

## 3. Conexión a la base de datos — Docker Secrets vs env vars

`get_db_connection()` en `main.py` ya implementa la lógica de lectura dual:

```python
# main.py — ya implementado
import psycopg2, os

def get_db_connection():
    """
    Producción: lee de /run/secrets/db_password (Docker Secret via DB_PASSWORD_FILE)
    Desarrollo: lee de DB_PASSWORD en .env
    """
    password_file = os.environ.get('DB_PASSWORD_FILE')
    password = (
        open(password_file).read().strip()
        if password_file
        else os.environ.get('DB_PASSWORD')
    )

    user_file = os.environ.get('DB_USER_FILE')
    user = (
        open(user_file).read().strip()
        if user_file
        else os.environ.get('DB_USER')
    )

    return psycopg2.connect(
        host=os.environ['DB_HOST'],
        port=os.environ['DB_PORT'],
        database=os.environ['DB_NAME'],
        user=user,
        password=password,
        connect_timeout=3,       # falla rápido si PostgreSQL no responde
    )
```

**Patrón de uso en services:**
```python
# src/services/report_service.py
from main import get_db_connection

def get_orders_by_month(year: int, month: int) -> list[dict]:
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM orders "
                "WHERE EXTRACT(year  FROM created_at) = %s "
                "  AND EXTRACT(month FROM created_at) = %s",
                (year, month)
            )
            columns = [desc[0] for desc in cur.description]
            return [dict(zip(columns, row)) for row in cur.fetchall()]
    finally:
        conn.close()             # siempre cerrar — no usar context manager aquí
```

---

## 4. Healthcheck — proceso + conectividad DB

Ya implementado en `main.py`. Docker marca el contenedor como `unhealthy` si responde 503, lo que activa alertas en Prometheus/Grafana.

```python
# main.py — ya implementado
@app.route('/health')
def health():
    """
    Healthcheck con verificación real de PostgreSQL.
    Retorna 200 si la DB responde, 503 si no.
    """
    try:
        conn = None
        try:
            conn = get_db_connection()
            conn = conn.cursor()
            conn.execute('SELECT 1')
        finally:
            if conn:
                conn.close()
        logger.debug("health_check_ok")
        return {'status': 'ok'}, 200
    except psycopg2.OperationalError as e:
        logger.warning("health_check_db_error", exc_info=True)  # log interno completo
        # logger.warning("health_check_db_error", error=str(e))
        return {'status': 'degraded'}, 503
    except Exception as e:
        logger.error("health_check_unexpected_error", exc_info=True)
        return {'status': 'error'}, 503
```

---

## 5. Añadir una nueva ruta (blueprint)

**Patrón: un Blueprint por grupo de endpoints relacionados.**

```python
# src/routes/reports.py
from flask import Blueprint, request, jsonify, send_file
from src.services.report_service import ReportService

reports_bp = Blueprint('reports', __name__, url_prefix='/reports')
_service   = ReportService()


@reports_bp.route('/monthly', methods=['GET'])
def monthly_report():
    """GET /reports/monthly?year=2026&month=3 → JSON con datos del mes"""
    year  = request.args.get('year',  type=int)
    month = request.args.get('month', type=int)

    if not year or not month:
        return jsonify({'error': 'year y month son obligatorios'}), 400
    if not (1 <= month <= 12):
        return jsonify({'error': 'month debe estar entre 1 y 12'}), 400

    data = _service.get_orders_by_month(year, month)
    return jsonify(data)


@reports_bp.route('/monthly/excel', methods=['GET'])
def monthly_excel():
    """GET /reports/monthly/excel?year=2026&month=3 → descarga .xlsx"""
    year  = request.args.get('year',  type=int)
    month = request.args.get('month', type=int)

    if not year or not month:
        return jsonify({'error': 'year y month son obligatorios'}), 400

    file_path = _service.generate_excel(year, month)
    return send_file(
        file_path,
        mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        as_attachment=True,
        download_name=f'reporte_{year}_{month:02d}.xlsx',
    )
```

**Registrar el blueprint en `main.py`:**
```python
from src.routes.reports import reports_bp
app.register_blueprint(reports_bp)
```

---

## 6. Generación de PDFs con reportlab

```python
# src/services/report_service.py
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors
import tempfile


def generate_pdf(data: list[dict], title: str) -> str:
    """
    Genera un PDF con una tabla de datos.
    Devuelve la ruta del archivo temporal — Flask lo sirve con send_file().
    """
    tmp  = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
    doc  = SimpleDocTemplate(tmp.name, pagesize=A4)
    stls = getSampleStyleSheet()
    elements = [Paragraph(title, stls['Title'])]

    if data:
        headers    = list(data[0].keys())
        table_data = [headers] + [[str(row[col]) for col in headers] for row in data]
        table      = Table(table_data)
        table.setStyle(TableStyle([
            ('BACKGROUND',    (0, 0), (-1, 0),  colors.HexColor('#2563EB')),
            ('TEXTCOLOR',     (0, 0), (-1, 0),  colors.white),
            ('FONTNAME',      (0, 0), (-1, 0),  'Helvetica-Bold'),
            ('GRID',          (0, 0), (-1, -1), 0.5, colors.grey),
            ('ROWBACKGROUNDS',(0, 1), (-1, -1), [colors.white, colors.HexColor('#F8FAFC')]),
        ]))
        elements.append(table)

    doc.build(elements)
    return tmp.name
```

---

## 7. Generación de Excel con openpyxl

```python
# src/services/report_service.py
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment
import tempfile


def generate_excel(data: list[dict], sheet_name: str = 'Reporte') -> str:
    """
    Genera un Excel con los datos recibidos.
    Devuelve la ruta del archivo temporal — Flask lo sirve con send_file().
    """
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = sheet_name

    if not data:
        path = tempfile.mktemp(suffix='.xlsx')
        wb.save(path)
        return path

    headers     = list(data[0].keys())
    header_fill = PatternFill('solid', fgColor='2563EB')
    header_font = Font(bold=True, color='FFFFFF')

    for col, header in enumerate(headers, 1):
        cell       = ws.cell(row=1, column=col, value=header)
        cell.fill  = header_fill
        cell.font  = header_font
        cell.alignment = Alignment(horizontal='center')
        ws.column_dimensions[cell.column_letter].width = max(len(header) + 4, 12)

    for row_num, row_data in enumerate(data, 2):
        for col, key in enumerate(headers, 1):
            ws.cell(row=row_num, column=col, value=row_data.get(key))

    path = tempfile.mktemp(suffix='.xlsx')
    wb.save(path)
    return path
```

---

## 8. Dependencias — cómo añadir paquetes correctamente

**Regla: editar siempre `requirements.in`, nunca `requirements.txt` directamente.**

```bash
# 1. Añadir la dependencia en requirements.in
echo "flask-login" >> reports/requirements.in

# 2. Regenerar requirements.txt con hashes SHA256
make update-requirements

# 3. Revisar el diff antes del commit
git diff reports/requirements.txt

# 4. Commit de ambos archivos
git add reports/requirements.in reports/requirements.txt
git commit -m "deps(reports): add flask-login"
```

**¿Por qué este flujo?**
`requirements.txt` es generado por `pip-compile --generate-hashes`. Si lo editas manualmente, la próxima `make update-requirements` sobreescribe tus cambios. Los hashes SHA256 protegen contra ataques de supply chain — pip verifica que el paquete descargado es exactamente el que se compiló.

---

## 9. Tests con pytest

```bash
# Ejecutar todos los tests
cd reports
pytest tests/ -v

# Con reporte de cobertura
pytest tests/ --cov=src --cov-report=html
# Abrir: reports/htmlcov/index.html
```

**Template de test con mock de DB:**
```python
# tests/test_reports.py
import pytest
from unittest.mock import patch, MagicMock


@pytest.fixture
def app():
    """App Flask en modo testing."""
    # Descomentar cuando main.py sea importable:
    # from main import app as flask_app
    # flask_app.config['TESTING'] = True
    # return flask_app
    pass


@pytest.fixture
def client(app):
    if app:
        return app.test_client()


def test_health_ok(client):
    """El /health responde 200 cuando PostgreSQL está disponible."""
    import psycopg2
    mock_conn = MagicMock()
    mock_conn.cursor.return_value.__enter__ = MagicMock()
    mock_conn.cursor.return_value.__exit__  = MagicMock(return_value=False)

    with patch('main.get_db_connection', return_value=mock_conn):
        response = client.get('/health')

    assert response.status_code == 200
    assert response.json['status'] == 'ok'


def test_health_db_error(client):
    """El /health responde 503 cuando PostgreSQL no responde."""
    import psycopg2
    with patch('main.get_db_connection', side_effect=psycopg2.OperationalError('refused')):
        response = client.get('/health')
    assert response.status_code == 503


def test_config_validates_ports():
    """Pydantic rechaza puertos fuera de rango."""
    import pytest
    from src.config import Settings
    with pytest.raises(Exception):
        Settings(db_host='localhost', db_name='test', db_user='u', db_password='p',
                 nestjs_auth_url='http://backend:4000', db_port=80)  # puerto inválido
```

---

## 10. Gunicorn en producción — por qué gthread y no gevent

El servicio usa `worker-class gthread` con 4 threads (ver `reports/.docker/Dockerfile.prod`).

| Worker | Mejor para | Por qué no aquí |
|---|---|---|
| `sync` | Apps simples | Un reporte lento bloquea todos los demás |
| `gthread` | **I/O mixto (DB + archivos)** ✅ | Python libera el GIL en I/O, 4 threads = verdadera concurrencia |
| `gevent` | I/O masivo, async puro | Pandas no libera el GIL correctamente con gevent |
| `uvicorn` | FastAPI / ASGI | Requeriría migrar de Flask |

**Con gthread + 4 threads y 2 CPUs:**
- Mientras un thread espera a PostgreSQL (I/O), los otros 3 procesan requests
- Reportes lentos no bloquean el `/health` ni otros requests
- No requiere cambiar nada del código (a diferencia de gevent)

---

## 11. Monkey patching — cuándo y por qué NO

> **Para este proyecto: NO usar monkey patching.**

El monkey patching de `gevent` solo es necesario con `worker-class gevent`:

```python
# ❌ NO usar — solo necesario con gevent, no con gthread
from gevent import monkey
monkey.patch_all()
```

Con `gthread`, Python maneja I/O en threads reales. El monkey patching no aporta nada y puede causar incompatibilidades con pandas, psycopg2 y reportlab.

**Si en el futuro se migra a gevent** (solo cuando el volumen justifique el cambio), añadir `monkey.patch_all()` como primera línea de `main.py`, antes de cualquier import.

---

## 12. RabbitMQ para reportes pesados — decisión futura

> **Estado:** No implementado. Ver ADR cuando sea necesario.

**El problema que resuelve:**  
Reportes de 50,000+ filas pueden tardar >30 segundos. Nginx hace timeout y el usuario ve un error aunque el reporte esté generándose.

**Flujo con cola (cuando aplique):**
```
POST /reports/generate
  → responde 202: { jobId: "abc", status: "queued" }
  → encola el trabajo en RabbitMQ/Redis

(en paralelo)
  → worker lee la cola
  → genera el reporte
  → guarda en disco/S3
  → notifica vía webhook/email

GET /reports/status/abc
  → { status: "completed", downloadUrl: "/reports/download/abc" }
```

**Dependencias a añadir en `requirements.in` cuando sea necesario:**
```
celery[redis]
redis
```

**¿Cuándo implementarlo?**  
Cuando el tiempo promedio de generación supere 10-15 segundos con usuarios reales, o cuando aparezcan timeouts en producción. Antes añade complejidad operacional sin beneficio real.

---

## 13. SAST con Bandit — análisis estático del código Python

> **Estado:** No configurado en CI — añadir junto con Semgrep en `security.yml`.

### Qué detecta Bandit en código Python/Flask

Bandit analiza el código fuente buscando patrones inseguros conocidos. No busca vulnerabilidades en dependencias (eso ya lo hace Trivy), sino errores que escribe el propio equipo.

| Categoría | Ejemplo de lo que detecta |
|---|---|
| Inyecciones | `query = "SELECT * FROM users WHERE id = " + id` (SQL injection) |
| Ejecución de código | `eval(user_input)`, `exec()`, `subprocess.call(shell=True)` |
| Deserialización | `pickle.loads(data)`, `yaml.load(data)` sin `Loader=yaml.SafeLoader` |
| Criptografía débil | `hashlib.md5()`, `random.random()` para generar tokens |
| Secretos hardcodeados | `password = "abc123"` en el código fuente |
| Flask específico | `DEBUG=True` en producción, `render_template_string(user_input)` |

### Instalación y uso local

```bash
# Instalar (solo desarrollo/CI — no añadir a requirements.in)
pip install bandit

# Escanear el código fuente
bandit -r reports/src/ -ll
# -r: recursivo
# -ll: solo reporta MEDIUM y HIGH (ignora LOW — demasiado ruido)

# Con reporte JSON (para CI)
bandit -r reports/src/ -ll -f json -o bandit-results.json

# Ver el resultado
cat bandit-results.json | python3 -m json.tool
```

**Ejemplo de output:**
```
>> Issue: [B608:hardcoded_sql_expressions] Possible SQL injection via string-based query construction.
   Severity: Medium   Confidence: Medium
   Location: src/services/report_service.py:42
   42    query = "SELECT * FROM orders WHERE user_id = " + str(user_id)
```

### Cómo corregir los findings más comunes

**SQL injection → usar parámetros preparados:**
```python
# ❌ Vulnerable — nunca interpolar directamente
query = f"SELECT * FROM orders WHERE user_id = {user_id}"
cur.execute(query)

# ✅ Seguro — psycopg2 escapa los parámetros automáticamente
cur.execute("SELECT * FROM orders WHERE user_id = %s", (user_id,))
```

**yaml.load sin SafeLoader:**
```python
# ❌ Vulnerable — yaml.load puede ejecutar código arbitrario
import yaml
data = yaml.load(config_string)

# ✅ Seguro
data = yaml.safe_load(config_string)
# o explícito:
data = yaml.load(config_string, Loader=yaml.SafeLoader)
```

**subprocess con shell=True:**
```python
# ❌ Peligroso si el comando incluye input del usuario
import subprocess
subprocess.call(f"convert {filename} output.pdf", shell=True)

# ✅ Usar lista de argumentos
subprocess.call(["convert", filename, "output.pdf"])
```

**random para tokens:**
```python
# ❌ random no es criptográficamente seguro
import random
token = str(random.random())

# ✅ secrets es el módulo correcto para valores criptográficos
import secrets
token = secrets.token_urlsafe(32)
```

### Falsos positivos — cómo ignorarlos

Bandit tiene falsos positivos. Para ignorar un finding justificado:

```python
# Ignorar una línea específica con comentario obligatorio
result = subprocess.call(safe_command)  # nosec B603 — input validado previamente

# Ignorar un bloque completo (usar con precaución)
# nosec
```

> **Regla del equipo:** nunca añadir `# nosec` sin explicar por qué el código es seguro en ese contexto. Un `# nosec` sin explicación se rechaza en code review.

### CI/CD — ya documentado en `BACKEND-NESTJS.md` sección 16

El job de Bandit en `security.yml` está en `BACKEND-NESTJS.md` §16 junto con Semgrep. Ambos se configuran en el mismo workflow para mantener el CI ordenado.

---

## 14. Logging estructurado y Grafana Loki

> **Estado:** No implementado — añadir cuando Grafana Loki esté configurado en el stack de monitoreo.

### El problema con `print()` y los logs de Flask por defecto

Flask escribe en texto plano:
```
127.0.0.1 - - [10/Mar/2026 10:30:15] "GET /health HTTP/1.1" 200 -
127.0.0.1 - - [10/Mar/2026 10:30:20] "POST /reports/monthly HTTP/1.1" 500 -
ERROR: KeyError 'db_host'
```

No hay estructura, no hay nivel de log uniforme, no hay contexto (¿qué usuario? ¿qué parámetros?). Imposible de buscar o agregar automáticamente.

### La solución: structlog o logging estándar con formato JSON

Python tiene dos caminos buenos para JSON estructurado:

**Opción A — `structlog` (recomendada para proyectos nuevos):**
```bash
# Añadir a requirements.in:
structlog>=24.0
```

```python
# src/logging_config.py — configuración centralizada
import structlog
import logging
import json
import os

def configure_logging() -> None:
    """Configura structlog una sola vez al arrancar la app."""
    is_production = os.environ.get('APP_ENV') == 'production'

    processors = [
        structlog.contextvars.merge_contextvars,    # añade contexto del request
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        # Producción: JSON puro para Loki
        # Desarrollo: formato legible con colores
        structlog.dev.ConsoleRenderer() if not is_production
        else structlog.processors.JSONRenderer(),
    ]

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.DEBUG if not is_production else logging.INFO
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )
```

```python
# main.py — activar al arrancar
from src.logging_config import configure_logging
configure_logging()  # ← antes de crear la app Flask

import structlog
logger = structlog.get_logger()

@app.route('/reports/monthly')
def monthly_report():
    year  = request.args.get('year', type=int)
    month = request.args.get('month', type=int)

    # ✅ Campos estructurados como kwargs
    logger.info("report_requested", year=year, month=month, user_ip=request.remote_addr)

    try:
        data = report_service.get_orders_by_month(year, month)
        logger.info("report_generated", year=year, month=month, rows=len(data))
        return jsonify(data)
    except Exception as e:
        logger.error("report_failed", year=year, month=month, error=str(e), exc_info=True)
        return jsonify({"error": "Error generando el reporte"}), 500
```

**Output en desarrollo (legible):**
```
2026-03-10T10:30:15Z [info     ] report_requested   year=2026 month=3 user_ip=192.168.1.1
2026-03-10T10:30:15Z [info     ] report_generated   year=2026 month=3 rows=1250
```

**Output en producción (JSON para Loki):**
```json
{"event":"report_requested","year":2026,"month":3,"user_ip":"192.168.1.1","level":"info","timestamp":"2026-03-10T10:30:15Z"}
{"event":"report_generated","year":2026,"month":3,"rows":1250,"level":"info","timestamp":"2026-03-10T10:30:15Z"}
```

**Opción B — logging estándar de Python con formatter JSON (sin dependencias extra):**
```python
# Para quien prefiere no añadir structlog
import logging
import json

class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_obj = {
            "time":    self.formatTime(record, self.datefmt),
            "level":   record.levelname.lower(),
            "name":    record.name,
            "msg":     record.getMessage(),
        }
        if record.exc_info:
            log_obj["exc"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logging.getLogger().addHandler(handler)
logging.getLogger().setLevel(logging.INFO)
```

### Grafana Loki — cómo encaja con este servicio

Loki es el agregador de logs del stack de Grafana. Promtail (el agente) lee los logs de todos los contenedores Docker y los envía a Loki. Grafana los visualiza con queries.

```
reports-api container → stdout (JSON)
          ↓
  Promtail (lee /var/lib/docker/containers/*.log)
          ↓
  Loki (almacena indexando solo las etiquetas: service, level, job)
          ↓
  Grafana → query: {service="reports"} | json | level="error"
```

**La configuración de Loki/Promtail está en `MONITORING-ROADMAP.md`** — cuando ese documento se actualice con el stack de Loki, la única acción en el servicio de reports es asegurarse de que los logs van a stdout en formato JSON (lo que configura structlog con `JSONRenderer` en producción).

### Qué NO loguear nunca

```python
# ❌ NUNCA — datos personales
logger.info("user_login", email=dto.email, password=dto.password)

# ❌ NUNCA — tokens ni credenciales
logger.debug("auth_header", token=request.headers.get("Authorization"))

# ✅ Solo IDs y eventos, nunca valores sensibles
logger.info("user_login_attempt", user_id=user.id, ip=request.remote_addr)
logger.info("auth_success", user_id=user.id)
logger.warning("auth_failed", ip=request.remote_addr, attempts=failed_count)
```

---

## Limitación conocida: Rate Limiting en memoria

El rate limiting actual de Flask-Limiter usa almacenamiento en memoria.
Los contadores se reinician cuando el contenedor se reinicia.
Para rate limiting persistente, añadir Redis (ver ROADMAP.md).
La mitigación actual es el rate limiting de Nginx (ver docs/guides/NGINX.md).

---

## Gunicorn y proxies — forwarded-allow-ips

El Dockerfile.prod configura Gunicorn con:
```
--forwarded-allow-ips=127.0.0.1
```

Esto significa que Gunicorn solo confía en los headers `X-Forwarded-For` y
`X-Real-IP` cuando vienen de `127.0.0.1` (Nginx en el mismo host).

**Si la arquitectura cambia**, este valor debe actualizarse:

| Escenario | Valor correcto |
|---|---|
| Nginx en el mismo host (actual) | `127.0.0.1` |
| Nginx en contenedor Docker | IP del contenedor Nginx o rango de red |
| Load balancer externo (AWS ALB, etc.) | IP del LB o `*` (con cuidado) |
| Múltiples proxies en cadena | Lista separada por comas |

Para actualizar sin rebuild, exponer como variable de entorno en el Dockerfile:
```dockerfile
ENV GUNICORN_FORWARDED_IPS="127.0.0.1"
CMD ["sh", "-c", "gunicorn --forwarded-allow-ips=${GUNICORN_FORWARDED_IPS} ..."]
```

---

## Rate Limiting

| Capa | Herramienta | Límite | Estado |
|------|-------------|--------|--------|
| Red | Nginx limit_req | 100 req/s burst 20 | ⚙️ Configurar en Nginx |
| Aplicación | Flask-Limiter | 200 req/min por IP | ✅ Activo |
| Sistema | fail2ban | Configurable | ⚙️ Recomendado en producción |

**Nota sobre Gunicorn:** Gunicorn gestiona workers y threads pero no hace rate limiting.