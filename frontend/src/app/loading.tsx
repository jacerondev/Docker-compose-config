// filepath: frontend/src/app/loading.tsx
/**
 * loading.tsx — Skeleton de carga global del App Router de Next.js
 *
 * ¿Cuándo se activa?
 *   - Automáticamente mientras un Server Component dentro de este segmento
 *     está haciendo fetch de datos (Suspense automático del App Router)
 *   - Durante la navegación entre rutas en el mismo segmento
 *
 * ¿Cómo funciona?
 *   Next.js envuelve automáticamente page.tsx en un <Suspense> usando este
 *   archivo como fallback. El usuario ve este skeleton mientras espera.
 *
 * Personalización por ruta:
 *   Crear un loading.tsx dentro de cada subcarpeta para skeletons específicos:
 *   app/dashboard/loading.tsx  → skeleton del dashboard
 *   app/(auth)/login/loading.tsx → skeleton del login
 *
 * Docs: https://nextjs.org/docs/app/api-reference/file-conventions/loading
 */

export default function Loading() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-gray-50">
      {/* Spinner principal */}
      <div className="mb-4">
        <div
          className="h-12 w-12 animate-spin rounded-full border-4 border-gray-200 border-t-blue-600"
          role="status"
          aria-label="Cargando"
        />
      </div>

      {/* Texto de estado */}
      <p className="text-sm text-gray-500" aria-live="polite">
        Cargando...
      </p>
    </div>
  );
}

/**
 * VARIANTE — Skeleton de contenido (más apropiada para páginas con datos)
 *
 * Descomenta este componente y comenta el de arriba cuando tengas
 * la estructura visual de tu página definida:
 *
 * export default function Loading() {
 *   return (
 *     <div className="container mx-auto px-4 py-8 max-w-7xl">
 *       {/* Header skeleton *\/}
 *       <div className="mb-8 h-8 w-48 animate-pulse rounded-md bg-gray-200" />
 *
 *       {/* Grid de cards skeleton *\/}
 *       <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
 *         {Array.from({ length: 6 }).map((_, i) => (
 *           <div key={i} className="rounded-lg border border-gray-200 bg-white p-6">
 *             <div className="mb-4 h-4 w-3/4 animate-pulse rounded bg-gray-200" />
 *             <div className="mb-2 h-3 w-full animate-pulse rounded bg-gray-100" />
 *             <div className="h-3 w-5/6 animate-pulse rounded bg-gray-100" />
 *           </div>
 *         ))}
 *       </div>
 *     </div>
 *   );
 * }
 */
