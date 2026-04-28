import type { NextConfig } from 'next';

const securityHeaders = [
  { key: 'X-Content-Type-Options',  value: 'nosniff' },
  { key: 'X-Frame-Options',         value: 'DENY' },
  { key: 'Referrer-Policy',         value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy',      value: 'camera=(), microphone=(), geolocation=()' },
  // Solo en producción:
  ...(process.env.NODE_ENV === 'production'
    ? [{ key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' }]
    : []),
  // { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
  // ── Content Security Policy ────────────────────────────────────────────────
  // Ajustar 'connect-src' con los dominios reales del backend y reports en prod.
  // 'self' = solo tu propio dominio. Añadir CDNs/APIs externos según los uses.
  // {
  //   key: 'Content-Security-Policy',
  //   value: [
  //     "default-src 'self'",
  //     // Scripts: solo de tu dominio + 'unsafe-inline' necesario para Next.js
  //     // En producción considera nonces (ver Next.js docs) para eliminar unsafe-inline
  //     // "script-src 'self' 'unsafe-inline'",
  //     // La CSP incluye 'unsafe-eval' en producción esto permite ejecución de código JS
  //     // dinámico (eval(), Function()), ampliando la superficie de ataque XSS. Next.js en
  //     // modo standalone generalmente no lo necesita
  //     // "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  //     // Estilos: 'unsafe-inline' necesario para Tailwind en modo desarrollo
  //     "style-src 'self' 'unsafe-inline'",
  //     // Imágenes: tu dominio + data URIs para iconos inline
  //     "img-src 'self' data: blob:",
  //     // Fuentes: solo tu dominio (si añades Google Fonts, agregar fonts.gstatic.com)
  //     "font-src 'self'",
  //     // Fetch/XHR: donde puede llamar el frontend
  //     // ⚠️ Actualizar con la URL real de tu API y reports en producción
  //     `connect-src 'self' ${process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4000'} ${process.env.NEXT_PUBLIC_REPORTS_URL ?? 'http://localhost:5000'}`,
  //     // Frames: ninguno (DENY en X-Frame-Options ya cubre esto)
  //     "frame-src 'none'",
  //     // Objetos multimedia: ninguno
  //     "object-src 'none'",
  //     // Base URI: solo tu dominio (previene ataques de base-uri injection)
  //     "base-uri 'self'",
  //     // Form submissions: solo tu dominio
  //     "form-action 'self'",
  //   ].join('; '),
  // },
];

const nextConfig: NextConfig = {
  output: 'standalone',
  async headers() {
    return [{ source: '/(.*)', headers: securityHeaders }];
  },
  logging: { fetches: { fullUrl: process.env.NODE_ENV === 'development' } },
};

export default nextConfig;