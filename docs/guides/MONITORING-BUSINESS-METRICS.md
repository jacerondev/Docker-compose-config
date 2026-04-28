# docs/guides/MONITORING-BUSINESS-METRICS.md
# Métricas de Negocio — Guía de Implementación

**Estado:** Plantilla lista para copiar y adaptar  
**Prerequisito:** Stack de Prometheus + Grafana corriendo (`make monitoring-up`)  
**Referencia:** `docs/guides/BACKEND-NESTJS.md §9` (métricas básicas de Counter)

---

## ¿Por qué métricas de negocio?

Prometheus ya mide la **infraestructura**: CPU, RAM, latencia HTTP, tasa de errores.  
Las métricas de negocio miden **qué hace tu sistema para los usuarios**:

| Infraestructura (ya tienes) | Negocio (esta guía) |
|---|---|
| `http_requests_total` — total de requests | `users_registered_total` — usuarios nuevos |
| `http_request_duration_seconds` — latencia | `report_generation_duration_seconds` — tiempo de reportes |
| `node_cpu_seconds_total` — CPU del servidor | `reports_rows_processed_total` — volumen de datos |

Si la CPU está al 90%, sabes que hay un problema. Con métricas de negocio sabes *cuál*:  
¿están generándose demasiados reportes grandes? ¿hay un spike de registros?

---

## Los tres tipos de métrica

### Counter — solo sube, nunca baja
Para contar eventos: registros, logins, errores, reportes generados.  
La función de Prometheus `rate()` calcula eventos por segundo sobre un rango.

```
Pregunta: "¿Cuántos usuarios se registraron en la última hora?"
rate(users_registered_total[1h])
```

### Gauge — sube y baja
Para valores que fluctúan: usuarios activos ahora mismo, tamaño de cola, conexiones DB.  
Se lee directamente sin `rate()`.

```
Pregunta: "¿Cuántos usuarios están conectados ahora?"
users_active_sessions
```

### Histogram — distribución de valores
Para medir duraciones, tamaños de archivo, número de filas. Permite calcular percentiles.  
Usa `histogram_quantile()` para P50, P95, P99.

```
Pregunta: "¿Qué latencia tienen el 95% de los reportes?"
histogram_quantile(0.95, rate(report_generation_duration_seconds_bucket[5m]))
```

---

## Implementación en NestJS (Backend)

### Paso 0: Instalar dependencias

```bash
cd backend
pnpm add @willsoto/nestjs-prometheus prom-client
```

```typescript
// src/app.module.ts — registrar PrometheusModule globalmente
import { PrometheusModule } from '@willsoto/nestjs-prometheus';

@Module({
  imports: [
    PrometheusModule.register({
      defaultMetrics: { enabled: true },  // CPU, memoria, event loop automáticos
      path: '/metrics',                    // GET /metrics — scrapeado por Prometheus
    }),
    // ... resto de módulos
  ],
})
export class AppModule {}
```

Después de esto, `GET http://localhost:4000/metrics` ya devuelve métricas del sistema.

---

### Counter: usuarios registrados

```typescript
// src/auth/auth.module.ts — registrar las métricas del módulo
import { makeCounterProvider } from '@willsoto/nestjs-prometheus';

@Module({
  providers: [
    AuthService,
    JwtStrategy,
    makeCounterProvider({
      name: 'users_registered_total',
      help: 'Total de usuarios registrados exitosamente',
      labelNames: ['method'],   // cómo se registraron: 'email', 'google', 'github'
    }),
    makeCounterProvider({
      name: 'auth_login_attempts_total',
      help: 'Total de intentos de login',
      labelNames: ['result', 'reason'],
      // result: 'success' | 'failure'
      // reason: 'invalid_credentials' | 'account_locked' | 'email_not_verified'
    }),
  ],
})
export class AuthModule {}
```

```typescript
// src/auth/auth.service.ts — usar las métricas
import { InjectMetric } from '@willsoto/nestjs-prometheus';
import { Counter } from 'prom-client';

@Injectable()
export class AuthService {
  constructor(
    @InjectMetric('users_registered_total')
    private readonly registeredCounter: Counter<string>,

    @InjectMetric('auth_login_attempts_total')
    private readonly loginCounter: Counter<string>,
  ) {}

  async register(dto: RegisterDto): Promise<User> {
    const user = await this.usersService.create(dto);

    // Incrementar con label del método de registro
    this.registeredCounter.inc({ method: 'email' });

    return user;
  }

  async login(dto: LoginDto): Promise<TokenPair> {
    const user = await this.usersService.findByEmail(dto.email);

    if (!user || !(await argon2.verify(user.password, dto.password))) {
      // Contar fallo con razón específica
      this.loginCounter.inc({ result: 'failure', reason: 'invalid_credentials' });
      throw new UnauthorizedException('Credenciales inválidas');
    }

    this.loginCounter.inc({ result: 'success', reason: '' });
    return this.generateTokens(user);
  }
}
```

**Queries Prometheus útiles:**
```promql
# Registros por minuto (últimas 24h)
rate(users_registered_total[5m]) * 60

# Tasa de fallos de login (% de intentos fallidos)
rate(auth_login_attempts_total{result="failure"}[5m])
/ rate(auth_login_attempts_total[5m]) * 100

# Desglose de razones de fallo
sum by(reason) (rate(auth_login_attempts_total{result="failure"}[1h]))
```

---

### Gauge: sesiones activas

```typescript
// src/auth/auth.module.ts — añadir el Gauge
import { makeGaugeProvider } from '@willsoto/nestjs-prometheus';

@Module({
  providers: [
    // ... anteriores
    makeGaugeProvider({
      name: 'users_active_sessions',
      help: 'Número de sesiones de usuario activas ahora mismo',
    }),
  ],
})

// src/auth/auth.service.ts
import { Gauge } from 'prom-client';

@Injectable()
export class AuthService {
  constructor(
    @InjectMetric('users_active_sessions')
    private readonly activeSessions: Gauge<string>,
  ) {}

  async login(dto: LoginDto): Promise<TokenPair> {
    // ...
    this.activeSessions.inc();     // nueva sesión al hacer login
    return tokens;
  }

  async logout(userId: number): Promise<void> {
    await this.invalidateTokens(userId);
    this.activeSessions.dec();     // sesión cerrada al hacer logout
  }
}
```

**Query Prometheus:**
```promql
# Sesiones activas ahora mismo
users_active_sessions

# Alerta si hay más de 1000 sesiones simultáneas
users_active_sessions > 1000
```

---

### Histogram: duración de operaciones críticas

Los histogramas son los más potentes pero también los más costosos.  
Úsalos solo para operaciones que quieras medir con percentiles (P50, P95, P99).

```typescript
// src/auth/auth.module.ts
import { makeHistogramProvider } from '@willsoto/nestjs-prometheus';

@Module({
  providers: [
    // ...
    makeHistogramProvider({
      name: 'auth_token_validation_duration_seconds',
      help: 'Duración de la validación de tokens JWT',
      labelNames: ['result'],
      // Buckets optimizados para operaciones rápidas (ms a segundos)
      buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0],
    }),
  ],
})
```

```typescript
import { Histogram } from 'prom-client';

@Injectable()
export class AuthService {
  constructor(
    @InjectMetric('auth_token_validation_duration_seconds')
    private readonly tokenDuration: Histogram<string>,
  ) {}

  async validateToken(token: string): Promise<JwtPayload> {
    const timer = this.tokenDuration.startTimer();
    try {
      const payload = this.jwtService.verify(token);
      timer({ result: 'valid' });
      return payload;
    } catch (err) {
      timer({ result: 'invalid' });
      throw new UnauthorizedException();
    }
  }
}
```

**Queries Prometheus:**
```promql
# P95 de validación de tokens (últimos 5 min)
histogram_quantile(0.95,
  rate(auth_token_validation_duration_seconds_bucket[5m])
)

# P50 (mediana) — lo que experimenta el usuario "promedio"
histogram_quantile(0.50,
  rate(auth_token_validation_duration_seconds_bucket[5m])
)
```

---

## Implementación en Flask (Reports API)

### Paso 0: Instalar dependencias

```bash
# Añadir a requirements.in
prometheus-client>=0.20
```

```python
# main.py — registrar el endpoint /metrics
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import time

@app.route('/metrics')
def metrics():
    """Endpoint scrapeado por Prometheus cada 30s."""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}
```

---

### Counter: reportes generados

```python
# src/metrics.py — definir métricas en un módulo separado
# Importar desde aquí en todos los servicios para evitar crear instancias duplicadas
from prometheus_client import Counter, Histogram, Gauge

# ── Counters ──────────────────────────────────────────────────────────────────

REPORTS_REQUESTED = Counter(
    'reports_requested_total',
    'Total de reportes solicitados',
    ['type', 'format'],
    # type:   'monthly', 'quarterly', 'annual', 'custom'
    # format: 'pdf', 'excel', 'csv'
)

REPORTS_COMPLETED = Counter(
    'reports_completed_total',
    'Total de reportes generados exitosamente',
    ['type', 'format'],
)

REPORTS_FAILED = Counter(
    'reports_failed_total',
    'Total de reportes que fallaron',
    ['type', 'reason'],
    # reason: 'db_timeout', 'no_data', 'memory_exceeded', 'unknown'
)

REPORT_ROWS_PROCESSED = Counter(
    'report_rows_processed_total',
    'Total de filas procesadas en todos los reportes',
    ['type'],
)

# ── Histograms ────────────────────────────────────────────────────────────────

REPORT_DURATION = Histogram(
    'report_generation_duration_seconds',
    'Duración de generación de reportes',
    ['type', 'format'],
    # Buckets para operaciones de segundos a minutos
    buckets=[1, 5, 10, 30, 60, 120, 300, 600],
)

REPORT_FILE_SIZE = Histogram(
    'report_file_size_bytes',
    'Tamaño de los archivos de reporte generados',
    ['type', 'format'],
    # Buckets en bytes: 10KB, 100KB, 1MB, 5MB, 10MB, 50MB, 100MB
    buckets=[10_000, 100_000, 1_000_000, 5_000_000, 10_000_000, 50_000_000, 100_000_000],
)

# ── Gauges ────────────────────────────────────────────────────────────────────

REPORTS_IN_PROGRESS = Gauge(
    'reports_in_progress',
    'Número de reportes siendo generados ahora mismo',
    ['type'],
)
```

```python
# src/services/report_service.py — usar las métricas
import structlog
import time
import os
from src.metrics import (
    REPORTS_REQUESTED, REPORTS_COMPLETED, REPORTS_FAILED,
    REPORT_ROWS_PROCESSED, REPORT_DURATION, REPORT_FILE_SIZE,
    REPORTS_IN_PROGRESS,
)

logger = structlog.get_logger(__name__)


def generate_monthly_report(year: int, month: int, format: str = 'pdf') -> bytes:
    """
    Genera un reporte mensual y registra todas las métricas relevantes.
    """
    report_type = 'monthly'

    # 1. Contar que se solicitó
    REPORTS_REQUESTED.labels(type=report_type, format=format).inc()
    REPORTS_IN_PROGRESS.labels(type=report_type).inc()

    start_time = time.time()

    try:
        logger.info("report_generation_started", type=report_type, year=year, month=month)

        # 2. Obtener datos de la DB
        rows = fetch_orders_by_month(year, month)
        REPORT_ROWS_PROCESSED.labels(type=report_type).inc(len(rows))

        # 3. Generar el archivo
        if format == 'pdf':
            file_bytes = render_pdf(rows)
        elif format == 'excel':
            file_bytes = render_excel(rows)
        else:
            raise ValueError(f"Formato no soportado: {format}")

        # 4. Registrar éxito y métricas
        duration = time.time() - start_time
        REPORT_DURATION.labels(type=report_type, format=format).observe(duration)
        REPORT_FILE_SIZE.labels(type=report_type, format=format).observe(len(file_bytes))
        REPORTS_COMPLETED.labels(type=report_type, format=format).inc()

        logger.info(
            "report_generation_completed",
            type=report_type, year=year, month=month,
            rows=len(rows), duration_seconds=round(duration, 2),
            file_size_bytes=len(file_bytes),
        )

        return file_bytes

    except Exception as e:
        # 5. Registrar fallo con razón específica
        reason = classify_error(e)
        REPORTS_FAILED.labels(type=report_type, reason=reason).inc()
        logger.error(
            "report_generation_failed",
            type=report_type, year=year, month=month,
            reason=reason, exc_info=True,
        )
        raise

    finally:
        # 6. Siempre decrementar el gauge (aunque falle)
        REPORTS_IN_PROGRESS.labels(type=report_type).dec()


def classify_error(e: Exception) -> str:
    """Clasifica el error para la métrica de fallos."""
    import psycopg2
    if isinstance(e, psycopg2.OperationalError):
        return 'db_timeout'
    if isinstance(e, MemoryError):
        return 'memory_exceeded'
    if 'no data' in str(e).lower():
        return 'no_data'
    return 'unknown'
```

**Queries Prometheus:**
```promql
# Reportes por minuto (últimos 5 min)
rate(reports_requested_total[5m]) * 60

# Tasa de fallos de reportes
rate(reports_failed_total[5m])
/ rate(reports_requested_total[5m]) * 100

# P95 de duración de reportes mensuales en PDF
histogram_quantile(0.95,
  rate(report_generation_duration_seconds_bucket{type="monthly", format="pdf"}[10m])
)

# Reportes en proceso ahora mismo
sum(reports_in_progress)

# Total de filas procesadas hoy
increase(report_rows_processed_total[24h])
```

---

## Dashboard "Business Health" en Grafana

Una vez que los servicios expongan `/metrics`, añadir este dashboard en Grafana:

### Panel 1: Actividad de usuarios (últimas 24h)
- **Tipo:** Stat
- **Query:** `increase(users_registered_total[24h])`
- **Título:** Nuevos registros hoy

### Panel 2: Salud del login
- **Tipo:** Gauge
- **Query:** `rate(auth_login_attempts_total{result="failure"}[5m]) / rate(auth_login_attempts_total[5m]) * 100`
- **Título:** % Fallos de login (5min)
- **Thresholds:** verde < 5%, amarillo < 15%, rojo ≥ 15%

### Panel 3: Volumen de reportes
- **Tipo:** Time series
- **Query:** `rate(reports_requested_total[5m]) * 60`
- **Título:** Reportes por minuto

### Panel 4: Latencia de reportes P95
- **Tipo:** Stat
- **Query:** `histogram_quantile(0.95, rate(report_generation_duration_seconds_bucket[10m]))`
- **Título:** P95 generación de reportes
- **Unidad:** seconds

### Panel 5: Reportes fallidos por razón
- **Tipo:** Bar chart
- **Query:** `sum by(reason) (increase(reports_failed_total[1h]))`
- **Título:** Fallos en la última hora por razón

---

## Alertas de negocio para alerts.yml

Añadir estas reglas al archivo `monitoring/alerts.yml`:

```yaml
- name: nombre_del_proyecto-business
  rules:

    - alert: HighLoginFailureRate
      expr: >
        rate(auth_login_attempts_total{result="failure"}[5m])
        / rate(auth_login_attempts_total[5m]) * 100 > 20
      for: 3m
      labels:
        severity: warning
        team: backend
      annotations:
        summary: "Tasa alta de fallos de login: {{ $value | printf \"%.1f\" }}%"
        description: "Posible ataque de fuerza bruta o problema de UX."

    - alert: ReportGenerationSlow
      expr: >
        histogram_quantile(0.95,
          rate(report_generation_duration_seconds_bucket[10m])
        ) > 120
      for: 5m
      labels:
        severity: warning
        team: backend
      annotations:
        summary: "Reportes lentos: P95 = {{ $value | printf \"%.0f\" }}s"
        description: "El 95% de los reportes tarda más de 2 minutos."

    - alert: ReportFailureRateHigh
      expr: >
        rate(reports_failed_total[5m])
        / rate(reports_requested_total[5m]) * 100 > 10
      for: 3m
      labels:
        severity: critical
        team: backend
      annotations:
        summary: "Fallos en reportes > 10%: {{ $value | printf \"%.1f\" }}%"
        description: "Más del 10% de los reportes están fallando."
```

---

## Checklist de implementación

- [ ] `pnpm add @willsoto/nestjs-prometheus prom-client` en backend
- [ ] `PrometheusModule.register()` en `app.module.ts`
- [ ] `prometheus-client>=0.20` en `reports/requirements.in`
- [ ] Endpoint `GET /metrics` en Flask (`main.py`)
- [ ] `src/metrics.py` creado con todas las métricas del proyecto
- [ ] Métricas de auth implementadas en `auth.service.ts`
- [ ] Métricas de reports implementadas en `report_service.py`
- [ ] Dashboard "Business Health" creado en Grafana
- [ ] Alertas de negocio añadidas a `monitoring/alerts.yml`
- [ ] Prometheus configurado para scrapear backend:4000/metrics y reports:5000/metrics

> **Nota sobre el scraping:** Verificar que `monitoring/prometheus.yml` incluye los jobs
> para backend y reports apuntando a los puertos correctos. Ver `MONITORING-ROADMAP.md`.
