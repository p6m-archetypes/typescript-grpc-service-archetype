import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildManagementApp } from '../src/management';
import type { FastifyInstance } from 'fastify';

describe('health endpoints', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = buildManagementApp();
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health/readiness returns 200', async () => {
    const response = await app.inject({ method: 'GET', url: '/health/readiness' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
  });

  it('GET /health/liveness returns 200', async () => {
    const response = await app.inject({ method: 'GET', url: '/health/liveness' });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
  });
});
