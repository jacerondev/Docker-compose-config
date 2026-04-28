// filepath: frontend/src/lib/api.ts
// ══════════════════════════════════════════════════════════════════════════════
// Cliente HTTP del frontend — Estrategia de auth: httpOnly Cookies (ADR-022)
//
// Por qué cookies en lugar de localStorage:
//   - localStorage es accesible desde JS → vulnerable a XSS
//   - Cookies httpOnly son inaccesibles desde JS → XSS no puede robar tokens
//   - El navegador gestiona el envío de cookies automáticamente
//   Ver: docs/DECISIONS.md ADR-022
// ══════════════════════════════════════════════════════════════════════════════

const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';

interface ApiOptions extends RequestInit {
  // `token` ya no se usa — la cookie httpOnly se envía automáticamente.
  // Se mantiene por compatibilidad con llamadas desde SSR donde las cookies
  // no viajan automáticamente (se pasa el header manualmente desde el servidor).
  token?: string;
}

// Clase de error con código HTTP para permitir manejo específico por status
// sin exponer detalles internos del servidor al cliente.
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

async function apiRequest<T>(endpoint: string, options: ApiOptions = {}): Promise<T> {
  const { token, ...fetchOptions } = options;

  // Generar un ID para esta request (permite correlacionar frontend ↔ backend ↔ reports)
  const requestId = crypto.randomUUID();

  const response = await fetch(`${API_BASE}${endpoint}`, {
    // credentials: 'include' — el navegador envía las cookies httpOnly automáticamente.
    // Requiere que el backend tenga CORS configurado con origen exacto (no wildcard)
    // y credentials: true. Ver ADR-020 (CORS) y ADR-022 (cookies).
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
      'X-Request-Id': requestId,
      // Soporte opcional para SSR: si se pasa token explícito (ej: desde getServerSideProps),
      // se usa el Authorization header. En el navegador, la cookie tiene prioridad.
      ...(token && { Authorization: `Bearer ${token}` }),
      ...fetchOptions.headers,
    },
    ...fetchOptions,
  });

  if (!response.ok) {
    // Mensaje genérico al cliente — el detalle del error se registra server-side.
    // No exponer response.statusText porque puede revelar estructura interna del backend.
    const userMessage = getErrorMessage(response.status);
    throw new ApiError(response.status, userMessage);
  }

  return response.json() as Promise<T>;
}

/**
 * Traduce códigos HTTP a mensajes amigables para el usuario.
 * El detalle técnico nunca sale del servidor.
 */
function getErrorMessage(status: number): string {
  switch (status) {
    case 400: return 'La solicitud contiene datos inválidos.';
    case 401: return 'Sesión expirada. Por favor inicia sesión nuevamente.';
    case 403: return 'No tienes permiso para realizar esta acción.';
    case 404: return 'El recurso solicitado no existe.';
    case 409: return 'El recurso ya existe o hay un conflicto.';
    case 429: return 'Demasiadas solicitudes. Espera un momento e intenta de nuevo.';
    case 500:
    case 502:
    case 503: return 'El servicio no está disponible en este momento. Intenta más tarde.';
    default:  return 'Ocurrió un error inesperado. Por favor intenta de nuevo.';
  }
}

// ─── API pública ──────────────────────────────────────────────────────────────

export const api = {
  get: <T>(endpoint: string, options?: ApiOptions) =>
    apiRequest<T>(endpoint, { ...options, method: 'GET' }),
  post: <T>(endpoint: string, body: unknown, options?: ApiOptions) =>
    apiRequest<T>(endpoint, { ...options, method: 'POST', body: JSON.stringify(body) }),
  put: <T>(endpoint: string, body: unknown, options?: ApiOptions) =>
    apiRequest<T>(endpoint, { ...options, method: 'PUT', body: JSON.stringify(body) }),
  patch: <T>(endpoint: string, body: unknown, options?: ApiOptions) =>
    apiRequest<T>(endpoint, { ...options, method: 'PATCH', body: JSON.stringify(body) }),
  delete: <T>(endpoint: string, options?: ApiOptions) =>
    apiRequest<T>(endpoint, { ...options, method: 'DELETE' }),
};

// ─── Cliente con manejo de 401 y renovación de sesión ─────────────────────────
// Con cookies httpOnly, el refresh es transparente:
//   1. La request falla con 401 (cookie de access_token expirada)
//   2. Se llama a /auth/refresh (que lee la cookie de refresh_token)
//   3. El backend emite una nueva cookie de access_token
//   4. Se reintenta la request original
//
// Si el refresh falla (cookie de refresh también expirada), redirigir a /login.

export const apiClient = {
  async fetch(url: string, options?: RequestInit): Promise<Response> {
    let response: Response;

    // try/catch para errores de red (sin respuesta del servidor):
    // DNS no resuelve, conexión rechazada, timeout de red, servidor caído, etc.
    // Estos errores NO tienen status HTTP — el Promise rechaza directamente.
    try {
      response = await fetch(url, {
        ...options,
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          ...options?.headers,
        },
      });
    } catch {
      throw new ApiError(0, 'No se pudo conectar al servidor. Verifica tu conexión a internet.');
    }

    if (response.status === 401) {
      // Intentar renovar la sesión via cookie de refresh_token
      // El backend lee la cookie httpOnly — el frontend no necesita enviar nada en el body
      let refreshResponse: Response;
      try {
        refreshResponse = await fetch(`${API_BASE}/api/auth/refresh`, {
          method: 'POST',
          credentials: 'include',
        });
      } catch {
        // Error de red durante el refresh → redirigir al login
        if (typeof window !== 'undefined') {
          window.location.href = '/login';
        }
        throw new ApiError(0, 'No se pudo renovar la sesión. Por favor inicia sesión nuevamente.');
      }

      if (refreshResponse.ok) {
        // El backend emitió una nueva cookie de access_token — reintentar la request original
        try {
          return await fetch(url, {
            ...options,
            credentials: 'include',
            headers: {
              'Content-Type': 'application/json',
              ...options?.headers,
            },
          });
        } catch {
          throw new ApiError(0, 'No se pudo completar la solicitud. Intenta de nuevo.');
        }
      }

      // Refresh falló (refresh_token expirado) → redirigir al login
      // No hay tokens que limpiar — las cookies las limpia el backend en /auth/logout
      if (typeof window !== 'undefined') {
        window.location.href = '/login';
      }
      throw new ApiError(401, getErrorMessage(401));
    }

    return response;
  },
};
