--- Render-verification suite for the TypeScript gRPC service archetype (nice-grpc + ts-proto +
--- pnpm + Vitest): each persistence variant lays out correctly and is fully rendered, and the
--- hollow (None) rendering stays hollow.
---
--- The BEHAVIORAL bar — CRUD through the production image (driven via server reflection), the
--- platform env contract, health/metrics/structured logs, both name shapes — lives in
--- tests/standards_test.lua (the shared p6m standards suite), fully containerized: docker is the
--- only requirement. No host toolchain is invoked here either (S8b): compile coverage is
--- containerized — the standards SUT builds each persistence variant's production image, and the
--- hollow (None) rendering is proven by a docker-gated `docker.build` of its production
--- Dockerfile below. The rendered project's own unit tests (Vitest) belong to the rendered
--- project's CI, not to this suite.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

local p6m = require("p6m")

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
  })
end

-- The hollow rendering stays hollow: no persistence, no scaffold files.
local none_project = prova.fixture("typescript-grpc[None]:project", Scope.File, function(ctx)
  return archetect.render{
    source = SRC,
    answers = answers_with{ persistence = "None" },
    destination = ctx:tempdir(),
    defaults = true,
  }
end)

archetect.verify(none_project, {
  name = "typescript-grpc[None]",
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
})

-- Containerized compile proof for the hollow variant (S8b): the persistence variants compile
-- inside the standards SUT image builds; None never boots there, so prove it compiles (proto
-- codegen + tsc included) by building its production image — build success IS the compile check.
prova.group("typescript-grpc[None]:image", { requires = { "docker" } }, function(g)
  g:test("production image builds from a clean render", function(t)
    local root = t:use(none_project):dir("example-service")
    local image = docker.build{
      context = root.path,
      dockerfile = ".platform/docker/prd/Dockerfile",
    }
    t:expect(image, "built image"):never():is_nil()
  end)
end)

-- CI parity (S10): the rendered project's own Build workflow path — js-pnpm-setup/js-pnpm-build's
-- exact command sequence on a fresh clone, in the toolchain image. The Dockerfile and CI are two
-- independent build paths; only the first was held above, and the drift bit on 2026-07-23 (CI's
-- `pnpm build` needed proto codegen only the Dockerfile ran). The hollow render suffices:
-- resource variants change dependencies, not the command path.
prova.group("typescript-grpc[None]:ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, none_project, {
    stack = "pnpm",
    project_dir = "example-service",
    name = "typescript-grpc",
  })
end)
