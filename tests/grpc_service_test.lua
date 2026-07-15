--- Acceptance suite for the TypeScript gRPC service archetype (nice-grpc + ts-proto + pnpm + Vitest).
--- Renders the project, verifies the layout and template substitution, installs it, runs its own
--- Vitest suite, then generates the proto stubs, boots the real gRPC server, and proves over the
--- wire that the RPCs answer — via prova's reflection-based dynamic gRPC client (the render wires
--- nice-grpc-server-reflection plus grpc.health.v1 into every variant).
---
--- The default configuration weaves in no resources (persistence/cache/messaging = None); the RPC
--- handlers are echo/empty stubs. The persistence variants (PostgreSQL/MySQL) each render with a
--- real database container, boot the service against it, and prove gRPC CRUD calls round-trip into
--- that database. This suite defines the archetype's acceptance bar — its job is to fill the gaps
--- and keep them filled.
---
--- The static tier reads renders with no toolchain; the build and live tiers require `pnpm`
--- (which drives Node) and the CRUD tiers additionally `docker`; each skips cleanly without them.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

local postgres = require("postgres")
local mysql    = require("mysql")

local SRC = "."

local ANSWERS = {
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
  for k, v in pairs(ANSWERS) do out[k] = v end
  for k, v in pairs(extra) do out[k] = v end
  return out
end

-- `pnpm install` is idempotent, and on some node builds (e.g. nix nodejs 24 on macOS) pnpm
-- crashes in libuv at process exit (kqueue.c EINTR assert) *after* the install has completed.
-- Retry once: the second run is a fast no-op that confirms success; a genuine install failure
-- fails both attempts.
local PNPM_INSTALL = "pnpm install || pnpm install"

-- prefix Example / suffix Service => project dir `example-service`, proto package `example_service`,
-- gRPC service `ExampleService`.
local PROJECT_DIR = "example-service"
local SVC = "example_service.ExampleService"

local EXPECTED_FILES = {
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
  "src/management.ts",
  "src/otel.ts",
  "src/settings.ts",
  "tests/health.test.ts",
  ".github/workflows/build.yaml",
  ".platform/docker/local/Dockerfile",
  ".platform/docker/prd/Dockerfile",
}

-- Files the persistence scaffold must produce (relative to the rendered project root) —
-- and that the hollow (None) rendering must NOT.
local SCAFFOLD_FILES = {
  "src/persistence/schema.ts",
  "src/persistence/init.ts",
  "src/service/impl.ts",
  "src/plugins/persistence.ts",
}

-- The default (None) rendering, shared by every hollow-variant tier below. No toolchain
-- needed - pure in-process render.
local project = prova.fixture("typescript-grpc:project", Scope.Suite, function(ctx)
  local tree = archetect.render{
    source = SRC,
    answers = ANSWERS,
    destination = ctx:tempdir(),
    defaults = true,
  }
  return tree:dir(PROJECT_DIR)
end)

-- Install once (shared by the build tier and the live-service fixture). Only reached from pnpm-gated
-- groups, so `pnpm` is guaranteed present here.
local installed = prova.fixture("typescript-grpc:installed", Scope.Suite, function(ctx)
  local root = ctx:use(project)
  local install = shell.run(PNPM_INSTALL, { cwd = root.path, timeout = "300s" })
  assert(install:ok(), "pnpm install failed:\n" .. install.stderr .. install.stdout)
  return root
end)

-- Generate the gRPC stubs (`pnpm proto`) then boot the server on free ports. Reflection answering
-- (grpc.wait_for) proves the gRPC server is really up; the management sidecar is probed separately.
-- Only reached from the live group (requires pnpm).
local service = prova.fixture("typescript-grpc:service", Scope.Suite, function(ctx)
  local root = ctx:use(installed)

  local proto = shell.run("pnpm proto", { cwd = root.path, timeout = "180s" })
  assert(proto:ok(), "pnpm proto failed:\n" .. proto.stderr .. proto.stdout)

  local port, mgmt = net.free_port(), net.free_port()
  ctx:manage(shell.spawn("pnpm exec tsx src/index.ts", {
    cwd = root.path,
    env = {
      HOST            = "127.0.0.1",
      GRPC_PORT       = tostring(port),
      MANAGEMENT_PORT = tostring(mgmt),
    },
  }))

  local addr = "127.0.0.1:" .. port
  local mgmt_url = "http://127.0.0.1:" .. mgmt
  grpc.wait_for(addr, { timeout = "60s" })
  http.wait_for(mgmt_url .. "/health/liveness", { timeout = "60s" })
  return { addr = addr, mgmt_url = mgmt_url }
end)

-- Tier 1 - static: layout, template substitution, and generated k8s manifests. No toolchain.
prova.group("typescript-grpc layout", function(g)
  g:test("scaffolds the expected project layout", function(t)
    local root = t:use(project).path
    t:expect_all(function()
      for _, f in ipairs(EXPECTED_FILES) do
        t:expect(fs.exists(root .. "/" .. f), f):is_true()
      end
    end)
  end)

  g:test("wires prefix/suffix and ports through file contents", function(t)
    local root = t:use(project).path
    -- The proto declares package example_service + service ExampleService with full CRUD.
    local proto = fs.read(root .. "/proto/example_service.proto")
    t:expect(proto, "proto package"):contains("package example_service")
    t:expect(proto, "proto service"):contains("service ExampleService")
    t:expect(proto, "proto delete rpc"):contains("rpc DeleteExample")
    -- The servicer implements the stub RPC handlers and wires server reflection.
    local servicer = fs.read(root .. "/src/servicer.ts")
    t:expect(servicer, "servicer handler"):contains("createExample")
    t:expect(servicer, "server reflection"):contains("ServerReflection")
    -- project-name lands in the package identity.
    t:expect(fs.read(root .. "/package.json"), "package name"):contains('"name": "example-service"')
    -- The service reads its ports from GRPC_PORT / MANAGEMENT_PORT.
    local settings = fs.read(root .. "/src/settings.ts")
    t:expect(settings, "grpc port env"):contains("GRPC_PORT")
    t:expect(settings, "management port env"):contains("MANAGEMENT_PORT")
  end)

  g:test("renders valid, non-empty kubernetes manifests", function(t)
    local root = t:use(project).path
    local manifests = fs.glob(root, ".platform/kubernetes/**/*.yaml")
    t:expect(#manifests > 0, "at least one k8s manifest"):is_true()
    t:expect_all(function()
      for _, m in ipairs(manifests) do
        local docs = yaml.parse_all(fs.read(m))
        t:expect(#docs > 0, m .. " has ≥1 document"):is_true()
      end
    end)
  end)

  g:test("leaves no unrendered template markers", function(t)
    t:expect(t:use(project)):is_fully_rendered()
  end)

  g:test("the hollow rendering stays hollow: no persistence scaffold files", function(t)
    local root = t:use(project).path
    t:expect_all(function()
      for _, f in ipairs(SCAFFOLD_FILES) do
        t:expect(fs.exists(root .. "/" .. f), f .. " must be absent"):is_false()
      end
    end)
  end)
end)

-- Tier 2 - build + unit: the generated project's own Vitest suite passes.
prova.group("typescript-grpc build + unit tests", { requires = { "pnpm" } }, function(g)
  g:test("the generated Vitest suite passes", function(t)
    local root = t:use(installed).path
    local vitest = shell.run("pnpm test", { cwd = root, timeout = "180s" })
    t:expect(vitest.code, "vitest exit code"):equals(0)
    t:expect(vitest.stdout .. vitest.stderr, "vitest reports a passing suite"):contains("passed")
  end)
end)

-- Tier 3 - live gRPC: the running server answers real RPC calls through prova's reflection-based
-- dynamic client; the management sidecar answers real HTTP requests.
prova.group("typescript-grpc endpoints", { requires = { "pnpm" } }, function(g)
  g:test("the stub RPCs answer over the wire (via server reflection)", function(t)
    local svc = t:use(service)
    local client = grpc.client(svc.addr)

    -- createExample echoes displayName; listExamples returns an empty page.
    local created = client:call(SVC .. "/CreateExample", { display_name = "widget" })
    t:expect(created.display_name, "createExample echoes displayName"):equals("widget")

    local listed = client:call(SVC .. "/ListExamples", {})
    t:expect(#(listed.items or {}), "listExamples returns an empty page"):equals(0)
  end)

  g:test("the gRPC health service reports SERVING", function(t)
    local svc = t:use(service)
    local client = grpc.client(svc.addr)
    local health = client:call("grpc.health.v1.Health/Check", {})
    t:expect(health.status):equals("SERVING")
  end)

  g:test("the management sidecar reports readiness and liveness", function(t)
    local svc = t:use(service)

    local ready = http.get(svc.mgmt_url .. "/health/readiness")
    t:expect(ready.status, "readiness status code"):equals(200)
    t:expect(ready:json().status, "readiness body"):equals("ok")

    local live = http.get(svc.mgmt_url .. "/health/liveness")
    t:expect(live.status, "liveness status code"):equals(200)
    t:expect(live:json().status, "liveness body"):equals("ok")
  end)

  g:test("the management sidecar exposes Prometheus metrics", function(t)
    local svc = t:use(service)
    local r = http.get(svc.mgmt_url .. "/metrics")
    t:expect(r.status, "metrics status code"):equals(200)
    t:expect(r.body, "Prometheus exposition format"):contains("# HELP")
  end)
end)

-- Persistence variants: one entry per rendering variant. `db` is the container recipe
-- namespace; the SQL strings carry each backend's placeholder syntax (the scaffold table is
-- lowercase `items`, so no identifier quoting is needed).
local VARIANTS = {
  {
    persistence   = "PostgreSQL",
    db            = postgres,
    db_port       = 5432,
    count_by_name = "SELECT count(*) FROM items WHERE display_name = $1",
  },
  {
    persistence   = "MySQL",
    db            = mysql,
    db_port       = 3306,
    count_by_name = "SELECT count(*) FROM items WHERE display_name = ?",
  },
}

for _, v in ipairs(VARIANTS) do
  local label = "typescript-grpc[" .. v.persistence .. "]"

  -- a) render — one fixture per variant, shared by verify and the black-box tests.
  local variant_project = prova.fixture(label .. ":project", Scope.File, function(ctx)
    return archetect.render{
      source = SRC,
      answers = answers_with{ persistence = v.persistence },
      destination = ctx:tempdir(),
      defaults = true,
    }
  end)

  -- b) verify — layout, fully-rendered, and typecheck (needs the generated proto stubs).
  archetect.verify(variant_project, {
    name = label,
    project_dir = PROJECT_DIR,
    expected_files = {
      "package.json",
      "proto/example_service.proto",
      "src/index.ts",
      "src/servicer.ts",
      "src/settings.ts",
      "drizzle.config.ts",
      SCAFFOLD_FILES[1], SCAFFOLD_FILES[2], SCAFFOLD_FILES[3], SCAFFOLD_FILES[4],
      ".github/workflows/build.yaml",
    },
    yaml_globs = { ".platform/kubernetes/**/*.yaml" },
    requires = { "pnpm" },
    build_steps = { PNPM_INSTALL, "pnpm proto", "pnpm exec tsc --noEmit" },
  })

  -- c) black-box — provision the database, boot the rendered service against it.
  local variant_service = prova.fixture(label .. ":service", Scope.File, function(ctx)
    local root = ctx:use(variant_project):dir(PROJECT_DIR)
    local db = v.db.container(ctx)

    local install = shell.run(PNPM_INSTALL, { cwd = root.path, timeout = "300s" })
    assert(install:ok(), label .. " pnpm install failed:\n" .. install.stderr .. install.stdout)

    local proto = shell.run("pnpm proto", { cwd = root.path, timeout = "180s" })
    assert(proto:ok(), label .. " pnpm proto failed:\n" .. proto.stderr .. proto.stdout)

    local port, mgmt = net.free_port(), net.free_port()
    ctx:manage(shell.spawn("pnpm exec tsx src/index.ts", {
      cwd = root.path,
      env = {
        HOST            = "127.0.0.1",
        GRPC_PORT       = tostring(port),
        MANAGEMENT_PORT = tostring(mgmt),
        DB_HOST         = "127.0.0.1",
        DB_PORT         = tostring(db.container:host_port(v.db_port)),
        DB_USERNAME     = "prova",
        DB_PASSWORD     = "prova",
        DB_DBNAME       = "prova",
      },
    }))

    -- Reflection answering proves the whole chain: the persistence plugin connected and
    -- ensureSchema succeeded against the real database before the gRPC server started listening.
    local addr = "127.0.0.1:" .. port
    grpc.wait_for(addr, { timeout = "60s" })
    return { addr = addr, db = db.client }
  end)

  prova.group(label .. " CRUD round-trip", { requires = { "docker", "pnpm" } }, function(g)
    g:test("created entities land in " .. v.persistence, function(t)
      local svc = t:use(variant_service)
      local client = grpc.client(svc.addr)

      -- Create through the public API...
      local created = client:call(SVC .. "/CreateExample", { display_name = "widget" })
      t:expect(created.display_name):equals("widget")
      t:expect(created.id, "created id"):is_truthy()

      -- ...prove the row is in the actual database...
      t:expect(svc.db:query_value(v.count_by_name, { "widget" }), "rows in DB"):equals(1)

      -- ...and read it back through the API (the hollow stub echoed instead of reading).
      local fetched = client:call(SVC .. "/GetExample", { id = created.id })
      t:expect(fetched.display_name):equals("widget")

      local listed = client:call(SVC .. "/ListExamples", {})
      local found = false
      for _, e in ipairs(listed.items or {}) do
        if e.id == created.id then found = true end
      end
      t:expect(found, "created entity present in ListExamples"):is_true()
    end)

    g:test("updates and deletes round-trip into " .. v.persistence, function(t)
      local svc = t:use(variant_service)
      local client = grpc.client(svc.addr)

      local created = client:call(SVC .. "/CreateExample", { display_name = "ephemeral" })

      local updated = client:call(SVC .. "/UpdateExample", { id = created.id, display_name = "renamed" })
      t:expect(updated.display_name):equals("renamed")
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "renamed row in DB"):equals(1)
      t:expect(svc.db:query_value(v.count_by_name, { "ephemeral" }), "old name gone"):equals(0)

      client:call(SVC .. "/DeleteExample", { id = created.id })
      local gone = client:call_status(SVC .. "/GetExample", { id = created.id })
      t:expect(gone.code):equals("NotFound")
      t:expect(svc.db:query_value(v.count_by_name, { "renamed" }), "row deleted from DB"):equals(0)
    end)

    g:test("gRPC health service reports SERVING", function(t)
      local svc = t:use(variant_service)
      local client = grpc.client(svc.addr)
      local health = client:call("grpc.health.v1.Health/Check", {})
      t:expect(health.status):equals("SERVING")
    end)
  end)
end
