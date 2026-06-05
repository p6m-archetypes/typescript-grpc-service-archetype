import Fastify from 'fastify';
import { register } from 'prom-client';
import { settings } from './settings';

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

export async function serveManagement(): Promise<void> {
  const app = buildManagementApp();
  await app.listen({ host: settings.host, port: settings.managementPort });
}
