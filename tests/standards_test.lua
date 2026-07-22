--- The p6m platform standards, held against this archetype (see prova-p6m-standards/docs/
--- standards.md). One suite, parameterized by the SAME answers the archetype renders from — the
--- expectations come from the `p6m` oracle, never from this file, so every language's archetype is
--- held to the identical bar. Two name shapes on purpose: casing bugs only show on the second.
---
--- Container-first (S8): the SUT is the archetype's own .platform/docker/prd image on a topology
--- network — docker is the only requirement, no Node/pnpm toolchain on the host.

local p6m = require("p6m")
local postgres = require("postgres")

local SRC = "."

local NAMES = {
	{ prefix = "Customer" },
	{ prefix = "User Details" },
}

for _, n in ipairs(NAMES) do
	local id = p6m.identity(n)
	local label = "standards[" .. id.project_name .. "]"

	local project = prova.fixture(label .. ":project", Scope.File, function(ctx)
		return archetect.render{
			source = SRC,
			answers = {
				author_name = "Test Author",
				author_email = "test@example.com",
				org_name = "acme",
				solution_name = "platform",
				prefix_name = id.answers.prefix_name,
				suffix_name = id.answers.suffix_name,
				image_registry = "ghcr.io/acme",
				persistence = "PostgreSQL",
			},
			destination = ctx:tempdir(),
			defaults = true,
		}
	end)

	local sut = prova.topology(label .. ":sut", function(ctx)
		local root = ctx:use(project):dir(id.project_name)
		return p6m.sut(ctx, { root = root.path, id = id, transport = "grpc", db = postgres })
	end)

	prova.group(label, { requires = { "docker" }, tags = { "standards" } }, function(g)
		p6m.standards.api(g, sut, {
			persisted = function(t, name, count)
				local svc = t:use(sut)
				t:expect(
					svc.db.client:query_value("SELECT count(*) FROM items WHERE display_name = $1", { name }),
					"rows in the database"
				):equals(count)
			end,
		})
		p6m.standards.runtime(g, sut)
	end)
end
