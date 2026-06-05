import './otel';
import { settings } from './settings';
import { serveManagement } from './management';
import { serveGrpc } from './servicer';
{% if persistence ~= 'None' %}import { initResource as initDb, closeResource as closeDb } from './resources/persistence';
{% endif %}{% if cache ~= 'None' %}import { initResource as initCache, closeResource as closeCache } from './resources/cache';
{% endif %}{% if messaging ~= 'None' %}import { initResource as initMessaging, closeResource as closeMessaging } from './resources/messaging';
{% endif %}{% if has_s3 %}import { initS3 } from './resources/storage-s3';
{% endif %}{% if has_azure_blob %}import { initAzureBlob } from './resources/storage-azure';
{% endif %}
async function main() {
{% if persistence ~= 'None' %}  await initDb();
{% endif %}{% if cache ~= 'None' %}  await initCache();
{% endif %}{% if messaging ~= 'None' %}  await initMessaging();
{% endif %}{% if has_s3 %}  initS3();
{% endif %}{% if has_azure_blob %}  initAzureBlob();
{% endif %}
  try {
    await Promise.all([serveGrpc(), serveManagement()]);
  } finally {
{% if persistence ~= 'None' %}    await closeDb();
{% endif %}{% if cache ~= 'None' %}    await closeCache();
{% endif %}{% if messaging ~= 'None' %}    await closeMessaging();
{% endif %}  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
