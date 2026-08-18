--- The p6m platform standards, held against this archetype (prova-p6m-standards docs/standards.md).
--- One suite, parameterized by the SAME answers the archetype renders from — and now literally the
--- same object: `p6m.spec{}` builds the identity, the render answers and the SQL oracle together,
--- so this file cannot answer the archetype one thing and assert another. That was not
--- hypothetical: before the shape harness, the fleet's suites gave FOUR different answers for the
--- entity's table (`items`, `Items`/`DisplayName`, `` `items` ``, `{prefix_name}s`) for one
--- standard that says it is name-derived — and every one of them passed.
---
--- Container-first (S8): the SUT is the archetype's own .platform/docker/prd image on a topology
--- network — docker is the only requirement, no Node or pnpm on the host.

local p6m = require("p6m")
local postgres = require("postgres")
local mysql = require("mysql")

local LANG_ANSWERS = {}

-- Two variants cover both axes cheaply: name shape (single vs multi-word — casing bugs only show
-- on the second) paired with persistence backend.
local VARIANTS = {
  { project = "customer-service", entity = "customer",
    persistence = "PostgreSQL", db = postgres, placeholder = "$1" },
  { project = "user-details-service", entity = "user-details",
    persistence = "MySQL", db = mysql, placeholder = "?" },
}

for _, v in ipairs(VARIANTS) do
  local spec = p6m.spec{
    language = "typescript", shape = "full", transport = "grpc",
    project = v.project, entity = v.entity, solution = "acme-platform",
    persistence = v.persistence, registry = "ghcr.io/acme",
  }

  local project = p6m.render(spec)

  local sut = prova.topology(spec.label .. ":sut", function(ctx)
    local root = ctx:use(project):dir(spec.project_dir)
    return p6m.sut(ctx, { root = root.path, id = spec.id, transport = "grpc", db = v.db })
  end)

  prova.group(spec.label, { requires = { "docker" }, tags = { "standards" } }, function(g)
    p6m.standards.api(g, sut, {
      persisted = function(t, name, count)
        local svc = t:use(sut)
        -- Table and column come from the spec, not from this file. A hardcoded name here could
        -- never fail against a hardcoded name there, which is how the drift survived.
        t:expect(
          svc.db.client:query_value(
            "SELECT count(*) FROM " .. spec.table_name
              .. " WHERE " .. spec.display_name_column .. " = " .. v.placeholder,
            { name }),
          "rows in the database"
        ):equals(count)
      end,
    })
    p6m.standards.runtime(g, sut)
  end)
end

-- S1b: the archetype's own prompt surface is the declared interface — a defaults=false render
-- proves nothing beyond the declared key is REQUIRED, and the composed catalog proves no vestigial
-- DEFAULTED prompt survives. Hermetic; no docker.
local archetype_spec = p6m.spec{
  language = "typescript", shape = "full", transport = "grpc",
  project = "billing-service", entity = "billing", solution = "acme-platform",
  registry = "ghcr.io/acme",
}

prova.group("typescript-grpc: the archetype itself", function(g)
  p6m.standards.prompt_surface(g, archetype_spec, { resources = { "typescript-resource-postgresql", "typescript-resource-mysql", "typescript-resource-redis", "typescript-resource-kafka", "typescript-resource-pulsar", "typescript-resource-s3", "typescript-resource-azure-blob" } })
end)

-- CI parity (S10): the rendered project's own build workflow path on a fresh clone, in the
-- toolchain image. The Dockerfile and CI are two independent build paths; S10 holds the second.
-- One hollow render suffices: resource variants change dependencies, not the command path.
local ci_spec = p6m.spec{
  language = "typescript", shape = "full", transport = "grpc",
  project = "example-service", entity = "example", solution = "acme-platform",
  persistence = "None", registry = "ghcr.io/acme",
}
local ci_project = p6m.render(ci_spec)

prova.group(ci_spec.label .. ":ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, ci_project, {
    stack = "pnpm",
    project_dir = ci_spec.project_dir,
    name = "typescript-grpc",
  })
end)

-- E7's released-tag bar, as the `p6m-pin` reminder: DUE while the manifest pins `dev` (the
-- YP6M-3372 staging window), silent again once the pin returns to a released tag. Heed it
-- (`prova --heed=p6m-pin`) when the window closes.
p6m.pin_reminder()
