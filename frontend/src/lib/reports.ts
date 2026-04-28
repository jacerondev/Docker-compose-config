// filepath: frontend/src/lib/reports.ts
// ══════════════════════════════════════════════════════════════════════════════
// Cliente HTTP para Reports API (Python/Flask)
//
// Arquitectura: el frontend llama directamente a reports-api desde el navegador.
// En producción, Nginx enruta:
//   /api/*       → backend:4000  (NestJS)
//   /reports/*   → reports-api:5000 (Flask)
//
// Autenticación: igual que con el backend — cookies httpOnly gestionadas
// automáticamente por el navegador (credentials: 'include').
//
// X-Request-Id: se propaga desde el frontend para correlacionar logs entre
// los tres servicios (frontend → backend → reports-api → Loki).
// ══════════════════════════════════════════════════════════════════════════════

const REPORTS_BASE = process.env.NEXT_PUBLIC_REPORTS_URL ?? 'http://localhost:5000';

export class ReportsApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ReportsApiError';
  }
}

function getReportsErrorMessage(status: number): string {
  switch (status) {
    case 401: return 'Sesión expirada. Por favor inicia sesión nuevamente.';
    case 403: return 'No tienes permiso para acceder a este reporte.';
    case 404: return 'El reporte solicitado no existe.';
    case 429: return 'Demasiadas solicitudes de reportes. Espera un momento.';
    case 503: return 'El servicio de reportes no está disponible. Intenta más tarde.';
    default:  return 'Error al generar el reporte. Por favor intenta de nuevo.';
  }
}

async function reportsRequest<T>(
  endpoint: string,
  options: RequestInit = {},
  // Permite propagar el mismo requestId de una llamada previa al backend
  requestId?: string,
): Promise<T> {
  const id = requestId ?? crypto.randomUUID();

  const response = await fetch(`${REPORTS_BASE}${endpoint}`, {
    credentials: 'include',    // Envía cookies httpOnly automáticamente
    headers: {
      'Content-Type': 'application/json',
      'X-Request-Id': id,      // Correlación de logs entre frontend ↔ reports-api
      ...options.headers,
    },
    ...options,
  });

  if (!response.ok) {
    throw new ReportsApiError(response.status, getReportsErrorMessage(response.status));
  }

  // Reports puede devolver JSON o un blob (PDF, Excel)
  const contentType = response.headers.get('Content-Type') ?? '';
  if (contentType.includes('application/json')) {
    return response.json() as Promise<T>;
  }

  // Para descargas binarias (PDF, Excel): devolver el blob
  return response.blob() as unknown as Promise<T>;
}

export const reportsApi = {
  get: <T>(endpoint: string, requestId?: string) =>
    reportsRequest<T>(endpoint, { method: 'GET' }, requestId),

  post: <T>(endpoint: string, body: unknown, requestId?: string) =>
    reportsRequest<T>(
      endpoint,
      { method: 'POST', body: JSON.stringify(body) },
      requestId,
    ),
};