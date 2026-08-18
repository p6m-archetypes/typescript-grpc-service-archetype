import { sql } from 'drizzle-orm';
import type { FastifyInstance } from 'fastify';

// Bootstrap the scaffold schema at startup (the EnsureCreated equivalent).
// Replace with real migrations (drizzle-kit) as your domain solidifies.
export async function ensureSchema(db: FastifyInstance['db']): Promise<void> {
{% if persistence == 'PostgreSQL' %}
  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS {{ entity_name }}s (
      id varchar(36) PRIMARY KEY,
      display_name varchar(255) NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    )
  `);
{% else %}
  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS {{ entity_name }}s (
      id varchar(36) PRIMARY KEY,
      display_name varchar(255) NOT NULL,
      created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  `);
{% endif %}
}
