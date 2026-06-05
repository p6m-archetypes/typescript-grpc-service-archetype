import { settings } from './settings';

export async function serveGrpc(): Promise<void> {
  // Import generated code inside the function — run 'pnpm proto' to generate src/generated/ first
  const { createServer } = await import('nice-grpc');
  const { {{ PrefixName }}{{ SuffixName }}Definition } = await import('./generated/{{ prefix_name }}_{{ suffix_name }}');
{% if persistence ~= 'None' %}
  const { getDb } = await import('./resources/persistence');
{% endif %}
{% if cache ~= 'None' %}
  const { getCache } = await import('./resources/cache');
{% endif %}
{% if messaging ~= 'None' %}
  const { getProducer } = await import('./resources/messaging');
{% endif %}
  const server = createServer();

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
  });

  await server.listen(`${settings.host}:${settings.port}`);
}
