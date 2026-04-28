// filepath: frontend/src/app/api/health/route.ts
export async function GET() {
  return Response.json({ status: 'ok' });
}