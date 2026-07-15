import Fastify, { type FastifyInstance } from 'fastify';
import { register, collectDefaultMetrics } from 'prom-client';
import { settings } from './settings';

// Register Node.js process & runtime metrics with the default registry.
collectDefaultMetrics();

export function buildManagementApp() {
  const app = Fastify({ logger: { level: settings.logLevel } });

  app.get('/health/readiness', async () => ({ status: 'ok' }));
  app.get('/health/liveness', async () => ({ status: 'ok' }));
  app.get('/metrics', async (_req, reply) => {
    reply.header('Content-Type', register.contentType);
    return register.metrics();
  });

  return app;
}

export async function serveManagement(app?: FastifyInstance): Promise<void> {
  const server = app ?? buildManagementApp();
  await server.listen({ host: settings.host, port: settings.managementPort });
}
