--- Acceptance suite for the TypeScript gRPC service archetype (nice-grpc + ts-proto + pnpm + Vitest).
--- Renders the project, verifies the layout and template substitution, installs it, runs its own
--- Vitest suite, then generates the proto stubs, boots the real gRPC server, and proves over the wire
--- that the (stub) RPCs answer - createExample echoes its input and listExamples returns an empty
--- page - plus the management sidecar (health probes + Prometheus metrics) responds.
---
--- The default configuration weaves in no resources (persistence/cache/messaging = None); the RPC
--- handlers are echo/empty stubs. The gRPC server binds one port; the management sidecar a second.
---
--- The generated server uses nice-grpc without server reflection, so prova's reflection-based gRPC
--- client cannot introspect it. Instead the live tier writes a tiny nice-grpc client from the
--- project's own generated stubs and runs it with `pnpm exec tsx`, exercising a real RPC round-trip.
---
--- prova's in-process archetect engine renders once per run (prova.toml pins jobs = 1), so the whole
--- suite shares a single rendered tree (the `project` fixture). The static tier reads it with no
--- toolchain; the build tier requires `pnpm`; the live tier additionally generates the proto stubs
--- (`pnpm proto`) and skips cleanly when pnpm is absent.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova

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

-- prefix Example / suffix Service => project dir `example-service`, proto package `example_service`,
-- gRPC service `ExampleService`.
local PROJECT_DIR = "example-service"

-- A reflection-free gRPC client built from the project's own generated stubs. Calls the two stub
-- RPCs and prints the responses as JSON for the live test to assert on. Written into the rendered
-- project root so its `./src/generated/...` import resolves.
local CLIENT_TS = [[
import { createChannel, createClient } from 'nice-grpc';
import { ExampleServiceDefinition } from './src/generated/example_service';

const channel = createChannel(process.env.ADDR as string);
const client = createClient(ExampleServiceDefinition, channel);

(async () => {
  const created = await client.createExample({ displayName: 'widget' });
  const listed = await client.listExamples({ pageSize: 10, pageToken: '' });
  console.log(JSON.stringify({ created, listed }));
  channel.close();
})().catch((e) => { console.error(e); process.exit(1); });
]]

local EXPECTED_FILES = {
  "package.json",
  "tsconfig.json",
  "vitest.config.ts",
  "pnpm-workspace.yaml",
  ".npmrc",
  "proto/example_service.proto",
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

-- Render once for the whole suite (single in-process render; every tier shares this one tree).
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
  local install = shell.run("pnpm install", { cwd = root.path, timeout = "300s" })
  assert(install:ok(), "pnpm install failed:\n" .. install.stderr .. install.stdout)
  return root
end)

-- Generate the gRPC stubs (`pnpm proto`) then boot the server on free ports. Waiting on the
-- management sidecar's /health/liveness proves the whole process (gRPC server + sidecar) came up.
-- Only reached from the live group (requires pnpm).
local service = prova.fixture("typescript-grpc:service", Scope.Suite, function(ctx)
  local root = ctx:use(installed)

  local proto = shell.run("pnpm proto", { cwd = root.path, timeout = "180s" })
  assert(proto:ok(), "pnpm proto failed:\n" .. proto.stderr .. proto.stdout)

  -- Drop the reflection-free client next to the generated stubs it imports.
  fs.write(root.path .. "/_acc_grpc_client.ts", CLIENT_TS)

  local port, mgmt = net.free_port(), net.free_port()
  ctx:manage(shell.spawn("pnpm exec tsx src/index.ts", {
    cwd = root.path,
    env = {
      HOST            = "127.0.0.1",
      GRPC_PORT       = tostring(port),
      MANAGEMENT_PORT = tostring(mgmt),
    },
  }))

  local mgmt_url = "http://127.0.0.1:" .. mgmt
  http.wait_for(mgmt_url .. "/health/liveness", { timeout = "60s" })
  return { addr = "127.0.0.1:" .. port, mgmt_url = mgmt_url, root = root.path }
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
    -- The proto declares package example_service + service ExampleService.
    local proto = fs.read(root .. "/proto/example_service.proto")
    t:expect(proto, "proto package"):contains("package example_service")
    t:expect(proto, "proto service"):contains("service ExampleService")
    -- The servicer implements the stub RPC handlers.
    t:expect(fs.read(root .. "/src/servicer.ts"), "servicer handler"):contains("createExample")
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

-- Tier 3 - live gRPC: the running server answers real RPC calls; the management sidecar answers
-- real HTTP requests.
prova.group("typescript-grpc endpoints", { requires = { "pnpm" } }, function(g)
  g:test("the stub RPCs answer over the wire", function(t)
    local svc = t:use(service)
    local r = shell.run("pnpm exec tsx _acc_grpc_client.ts", {
      cwd = svc.root,
      env = { ADDR = svc.addr },
      timeout = "60s",
    })
    t:expect(r.code, "grpc client exit code"):equals(0)
    -- createExample echoes displayName; listExamples returns an empty page.
    t:expect(r.stdout, "createExample echoes displayName"):contains('"displayName":"widget"')
    t:expect(r.stdout, "listExamples returns an empty page"):contains('"items":[]')
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
