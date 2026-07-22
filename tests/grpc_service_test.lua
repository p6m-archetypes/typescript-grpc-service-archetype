--- Render-verification suite for the TypeScript gRPC service archetype (nice-grpc + ts-proto +
--- pnpm + Vitest): each persistence variant lays out correctly and is fully rendered, and the
--- hollow (None) rendering stays hollow.
---
--- The BEHAVIORAL bar — CRUD through the production image (driven via server reflection), the
--- platform env contract, health/metrics/structured logs, both name shapes — lives in
--- tests/standards_test.lua (the shared p6m standards suite), fully containerized: docker is the
--- only requirement. The `build_steps` here are gated on a host toolchain (pnpm) and skip
--- cleanly where it's absent.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

local SRC = "."

local BASE_ANSWERS = {
  author_name    = "Test Author",
  author_email   = "test@example.com",
  org_name       = "acme",
  solution_name  = "platform",
  prefix_name    = "Example",
  suffix_name    = "Service",
  image_registry = "ghcr.io/acme",
}

local function answers_with(extra)
  local out = {}
  for k, v in pairs(BASE_ANSWERS) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end

-- `pnpm install` is idempotent, and on some node builds (e.g. nix nodejs 24 on macOS) pnpm
-- crashes in libuv at process exit (kqueue.c EINTR assert) *after* the install has completed.
-- Retry once: the second run is a fast no-op that confirms success; a genuine install failure
-- fails both attempts.
local PNPM_INSTALL = "pnpm install || pnpm install"

-- Files the persistence scaffold must produce (relative to the rendered project root).
local SCAFFOLD_FILES = {
  "src/persistence/schema.ts",
  "src/persistence/init.ts",
  "src/service/impl.ts",
  "src/plugins/persistence.ts",
}

for _, persistence in ipairs({ "PostgreSQL", "MySQL" }) do
  local label = "typescript-grpc[" .. persistence .. "]"

  local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  archetect.verify(project, {
    name = label,
    project_dir = "example-service",
    expected_files = {
      "package.json",
      "tsconfig.json",
      "vitest.config.ts",
      "pnpm-workspace.yaml",
      ".npmrc",
      "proto/example_service.proto",
      "proto/grpc/health/v1/health.proto",
      "scripts/proto.sh",
      "src/index.ts",
      "src/servicer.ts",
      "src/logging.ts",
      "src/management.ts",
      "src/otel.ts",
      "src/settings.ts",
      "tests/health.test.ts",
      "drizzle.config.ts",
      ".dockerignore",
      ".github/workflows/build.yaml",
      ".platform/docker/local/Dockerfile",
      ".platform/docker/prd/Dockerfile",
      SCAFFOLD_FILES[1], SCAFFOLD_FILES[2], SCAFFOLD_FILES[3], SCAFFOLD_FILES[4],
    },
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
    requires = { "pnpm" },
    build_steps = { PNPM_INSTALL, "pnpm proto", "pnpm exec tsc --noEmit" },
  })
end

-- The hollow rendering stays hollow: no persistence, no scaffold files. Its own Vitest suite
-- (management health endpoints) runs here — in-process, no generated stubs required.
archetect.verify{
  name = "typescript-grpc[None]",
  source = SRC,
  answers = answers_with{ persistence = "None" },
  project_dir = "example-service",
  expected_files = {
    "package.json",
    "proto/example_service.proto",
    "src/index.ts",
    "src/servicer.ts",
    "src/logging.ts",
    "src/management.ts",
    ".dockerignore",
    ".platform/docker/local/Dockerfile",
    ".platform/docker/prd/Dockerfile",
  },
  absent_files = SCAFFOLD_FILES,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
  requires = { "pnpm" },
  build_steps = { PNPM_INSTALL, "pnpm test" },
}
