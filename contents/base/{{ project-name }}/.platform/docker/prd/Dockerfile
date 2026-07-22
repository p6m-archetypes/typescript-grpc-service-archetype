FROM node:22-alpine AS builder
WORKDIR /app
# protobuf-compiler for grpc-tools proto compilation; bash for scripts/proto.sh
RUN apk add --no-cache protobuf bash
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* .npmrc* ./
# The lockfile is authoritative when present (any committed checkout — what CI builds); a fresh
# render ships none yet, so fall back to a plain install for the first build after rendering.
RUN npm install -g pnpm && \
    if [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile; else pnpm install; fi
COPY . .
RUN pnpm proto && pnpm build

FROM node:22-alpine
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
USER appuser
EXPOSE {{ service_port }} {{ management_port }}
ENTRYPOINT ["node", "dist/index.js"]
