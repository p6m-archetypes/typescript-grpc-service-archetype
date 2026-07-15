import './otel';
import { buildManagementApp, serveManagement } from './management';
import { serveGrpc } from './servicer';
{% if cache ~= 'None' %}
import { initResource as initCache } from './resources/cache';
{% endif %}
{% if messaging ~= 'None' %}
import { initResource as initMessaging } from './resources/messaging';
{% endif %}
{% if has_s3 %}
import { initS3 } from './resources/storage-s3';
{% endif %}
{% if has_azure_blob %}
import { initAzureBlob } from './resources/storage-azure';
{% endif %}

async function main() {
  const app = buildManagementApp();
{% if persistence ~= 'None' %}
  // Sample scaffold: connect the database (the plugin decorates `app.db`) and create the
  // items schema (src/persistence/schema.ts, src/persistence/init.ts). Replace with real
  // migrations (drizzle-kit) as your domain solidifies.
  const { default: persistencePlugin } = await import('./plugins/persistence');
  await app.register(persistencePlugin);
  await app.ready();
  const { ensureSchema } = await import('./persistence/init');
  await ensureSchema(app.db);
{% endif %}
{% if cache ~= 'None' %}
  await initCache();
{% endif %}
{% if messaging ~= 'None' %}
  await initMessaging();
{% endif %}
{% if has_s3 %}
  initS3();
{% endif %}
{% if has_azure_blob %}
  initAzureBlob();
{% endif %}
  try {
    // Both listens resolve once bound; the running servers keep the process alive.
    await Promise.all([serveGrpc({% if persistence ~= 'None' %}app.db{% endif %}), serveManagement(app)]);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
