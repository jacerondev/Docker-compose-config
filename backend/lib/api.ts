// filepath: backend/lib/api.ts  — Cliente HTTP tipado para el backend NestJS
//
// MANEJO DE ERRORES EN DOS CAPAS:
//   1. Errores de red (fetch() falla antes de obtener respuesta):
//      - Backend caído / DNS no resuelve → TypeError: Failed to fetch
//      - Timeout de red                  → AbortError: The user aborted a request
//      - CORS bloqueado                  → TypeError: Failed to fetch (mismo mensaje)
//   2. Errores HTTP (respuesta recibida pero con status de error):
//      - 4xx, 5xx                        → ApiError con status y body del servidor

const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000';

// Timeout por defecto: 10 segundos
// Ajustar por endpoint si necesitas más (ej: uploads grandes)
const DEFAULT_TIMEOUT_MS = 10_000;

// ── Tipos de error ────────────────────────────────────────────────────────────

/**
 * Error HTTP: la request llegó al servidor pero devolvió un status de error.
 * Incluye el status HTTP y el body de la respuesta para mostrar mensajes del servidor.
 */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly statusText: string,
    public readonly body: unknown,
  ) {
    super(`API error ${status}: ${statusText}`);
    this.name = 'ApiError';
  }
}

/**
 * Error de red: no se pudo contactar el servidor.
 * Causas: backend caído, sin internet, DNS falla, CORS bloqueado.
 */
export class NetworkError extends Error {
  constructor(
    message: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'NetworkError';
  }
}

// ── Opciones de request ───────────────────────────────────────────────────────

interface ApiOptions extends RequestInit {
  token?: string;
  timeoutMs?: number;  // Override del timeout por request
}

// ── Función principal ─────────────────────────────────────────────────────────

async function apiRequest<T>(endpoint: string, options: ApiOptions = {}): Promise<T> {
  const { token, timeoutMs = DEFAULT_TIMEOUT_MS, ...fetchOptions } = options;

  // AbortController: permite cancelar la request si tarda demasiado
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(`${API_BASE}${endpoint}`, {
      headers: {
        'Content-Type': 'application/json',
        ...(token && { Authorization: `Bearer ${token}` }),
        ...fetchOptions.headers,
      },
      signal: controller.signal,  // Conecta el timeout al fetch
      ...fetchOptions,
    });

    // Leer el body siempre (incluso en errores) para obtener el mensaje del servidor
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      body = null;  // Respuesta sin body JSON (204 No Content, etc.)
    }

    if (!response.ok) {
      // Error HTTP: status 4xx o 5xx
      throw new ApiError(response.status, response.statusText, body);
    }

    return body as T;

  } catch (error) {
    if (error instanceof ApiError) {
      // Re-lanzar errores HTTP sin envolver
      throw error;
    }

    if (error instanceof DOMException && error.name === 'AbortError') {
      // Timeout: la request tardó más de timeoutMs
      throw new NetworkError(
        `Timeout: el servidor no respondió en ${timeoutMs / 1000}s. ¿Está el backend activo?`,
        error,
      );
    }

    if (error instanceof TypeError) {
      // fetch() lanza TypeError para errores de red (DNS, CORS, backend caído)
      throw new NetworkError(
        'No se pudo conectar con el servidor. Verifica tu conexión o que el backend esté activo.',
        error,
      );
    }

    // Cualquier otro error inesperado — relanzar sin envolver
    throw error;
  } finally {
    clearTimeout(timeoutId);  // Limpiar el timeout aunque el fetch falle
  }
}

// ── API pública ───────────────────────────────────────────────────────────────

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

// ── Helpers para consumir en componentes ─────────────────────────────────────
//
// Uso recomendado en un componente React:
//
//   import { api, ApiError, NetworkError } from '@/lib/api';
//
//   try {
//     const user = await api.get<User>('/api/auth/me', { token });
//   } catch (error) {
//     if (error instanceof ApiError) {
//       if (error.status === 401) router.push('/login');
//       else toast.error(`Error ${error.status}`);
//     } else if (error instanceof NetworkError) {
//       toast.error('Sin conexión con el servidor');
//     }
//   }
