import { settings } from './settings';
{% if persistence ~= 'None' %}
import type { FastifyInstance } from 'fastify';
{% endif %}

export async function serveGrpc({% if persistence ~= 'None' %}db: FastifyInstance['db']{% endif %}): Promise<void> {
  // Import generated code inside the function — run 'pnpm proto' to generate src/generated/ first
  const { createServer } = await import('nice-grpc');
  const { {{ PrefixName }}{{ SuffixName }}Definition } = await import('./generated/{{ prefix_name }}_{{ suffix_name }}');
  const { HealthDefinition, HealthCheckResponse_ServingStatus } = await import('./generated/grpc/health/v1/health');
  const { ServerReflectionService, ServerReflection } = await import('nice-grpc-server-reflection');
  const { readFileSync } = await import('node:fs');
  const { join } = await import('node:path');
{% if cache ~= 'None' %}
  const { getCache } = await import('./resources/cache');
{% endif %}
{% if messaging ~= 'None' %}
  const { getProducer } = await import('./resources/messaging');
{% endif %}

  const server = createServer();

{% if persistence ~= 'None' %}
  // Sample scaffold: the proto CRUD persisted into the items table (src/persistence/schema.ts)
  // through Drizzle. Replace src/service/impl.ts with your real domain implementation.
  const { create{{ PrefixName }}{{ SuffixName }}Impl } = await import('./service/impl');
  server.add({{ PrefixName }}{{ SuffixName }}Definition, create{{ PrefixName }}{{ SuffixName }}Impl(db));
{% else %}
  server.add({{ PrefixName }}{{ SuffixName }}Definition, {
    async create{{ PrefixName }}(request) {
      return { id: '', displayName: request.displayName ?? '' };
    },
    async get{{ PrefixName }}(request) {
      return { id: request.id, displayName: '' };
    },
    async list{{ PrefixName }}s(request) {
      return { items: [], nextPageToken: '' };
    },
    async update{{ PrefixName }}(request) {
      return { id: request.id, displayName: request.displayName ?? '' };
    },
    async delete{{ PrefixName }}(request) {
      return {};
    },
  });
{% endif %}

  // gRPC health checks (grpc.health.v1.Health) for probes and load balancers.
  server.add(HealthDefinition, {
    async check() {
      return { status: HealthCheckResponse_ServingStatus.SERVING };
    },
    async *watch() {
      yield { status: HealthCheckResponse_ServingStatus.SERVING };
    },
  });

  // gRPC server reflection (so dynamic clients — grpcurl, test harnesses — can
  // discover the API without the .proto files). Serves the descriptor set that
  // scripts/proto.sh emits alongside the generated code.
  server.add(
    ServerReflectionService,
    ServerReflection(readFileSync(join(__dirname, 'generated', 'protoset.bin')), [
      {{ PrefixName }}{{ SuffixName }}Definition.fullName,
      HealthDefinition.fullName,
    ]),
  );

  await server.listen(`${settings.host}:${settings.port}`);
}
