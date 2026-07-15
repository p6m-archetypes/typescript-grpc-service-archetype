// Sample scaffold entity proving the persistence round trip end-to-end.
// Replace with your real domain tables (and rename the RPC implementation in
// src/service/impl.ts to match).
{% if persistence == 'PostgreSQL' %}
import { pgTable, timestamp, varchar } from 'drizzle-orm/pg-core';

export const items = pgTable('items', {
  id: varchar('id', { length: 36 }).primaryKey(),
  displayName: varchar('display_name', { length: 255 }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});
{% else %}
import { mysqlTable, timestamp, varchar } from 'drizzle-orm/mysql-core';

export const items = mysqlTable('items', {
  id: varchar('id', { length: 36 }).primaryKey(),
  displayName: varchar('display_name', { length: 255 }).notNull(),
  createdAt: timestamp('created_at').notNull().defaultNow(),
});
{% endif %}
