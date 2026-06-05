FROM node:22-alpine AS builder
WORKDIR /app
# protobuf-compiler required for grpc-tools proto compilation
RUN apk add --no-cache protobuf
COPY package.json pnpm-workspace.yaml .npmrc* ./
RUN npm install -g pnpm && pnpm install --frozen-lockfile
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
