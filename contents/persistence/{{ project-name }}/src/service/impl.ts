import { randomUUID } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { ServerError, Status } from 'nice-grpc';
import type { FastifyInstance } from 'fastify';
import { items } from '../persistence/schema';
import type { {{ PrefixName }}{{ SuffixName }}Implementation } from '../generated/{{ prefix_name }}_{{ suffix_name }}';

// Sample scaffold implementation persisting the proto CRUD into the items table — the
// round trip a black-box test can drive. Replace alongside src/persistence/schema.ts when
// you add your real model. Writes generate ids in JS and read back after the write so the
// implementation stays dialect-portable (MySQL has no RETURNING clause).
export function create{{ PrefixName }}{{ SuffixName }}Impl(
  db: FastifyInstance['db'],
): {{ PrefixName }}{{ SuffixName }}Implementation {
  const mustFind = async (id: string) => {
    const [row] = await db.select().from(items).where(eq(items.id, id));
    if (!row) {
      throw new ServerError(Status.NOT_FOUND, `{{ PrefixName }} ${id} not found`);
    }
    return row;
  };

  return {
    async create{{ PrefixName }}(request) {
      const id = randomUUID();
      await db.insert(items).values({ id, displayName: request.displayName });
      const row = await mustFind(id);
      return { id: row.id, displayName: row.displayName };
    },

    async get{{ PrefixName }}(request) {
      const row = await mustFind(request.id);
      return { id: row.id, displayName: row.displayName };
    },

    async list{{ PrefixName }}s() {
      const rows = await db.select().from(items).orderBy(items.createdAt);
      return {
        items: rows.map((row) => ({ id: row.id, displayName: row.displayName })),
        nextPageToken: '',
      };
    },

    async update{{ PrefixName }}(request) {
      const id = request.id;
      if (!id) {
        throw new ServerError(Status.INVALID_ARGUMENT, 'id is required');
      }
      await mustFind(id);
      await db.update(items).set({ displayName: request.displayName }).where(eq(items.id, id));
      const row = await mustFind(id);
      return { id: row.id, displayName: row.displayName };
    },

    async delete{{ PrefixName }}(request) {
      await mustFind(request.id);
      await db.delete(items).where(eq(items.id, request.id));
      return {};
    },
  };
}
