--- The p6m platform standards, held against this archetype (see prova-p6m-standards/docs/
--- standards.md). One suite, parameterized by the SAME answers the archetype renders from — the
--- expectations come from the `p6m` oracle, never from this file, so every language's archetype is
--- held to the identical bar. Two name shapes on purpose: casing bugs only show on the second.
---
--- Container-first (S8): the SUT is the archetype's own .platform/docker/prd image on a topology
--- network — docker is the only requirement, no Node/pnpm toolchain on the host.

local p6m = require("p6m")
local postgres = require("postgres")
local mysql = require("mysql")

local SRC = "."

-- Two variants cover both axes cheaply: name shape (single vs multi-word — casing bugs only show
-- on the second) paired with persistence backend (PostgreSQL vs MySQL).
local VARIANTS = {
	{
		prefix = "Customer",
		persistence = "PostgreSQL",
		db = postgres,
		count_by_name = "SELECT count(*) FROM items WHERE display_name = $1",
	},
	{
		prefix = "User Details",
		persistence = "MySQL",
		db = mysql,
		count_by_name = "SELECT count(*) FROM items WHERE display_name = ?",
	},
}

for _, n in ipairs(VARIANTS) do
	local id = p6m.identity{ prefix = n.prefix }
	local label = "standards[" .. id.project_name .. "/" .. n.persistence .. "]"

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
				persistence = n.persistence,
			},
			destination = ctx:tempdir(),
			defaults = true,
		}
	end)

	local sut = prova.topology(label .. ":sut", function(ctx)
		local root = ctx:use(project):dir(id.project_name)
		return p6m.sut(ctx, { root = root.path, id = id, transport = "grpc", db = n.db })
	end)

	prova.group(label, { requires = { "docker" }, tags = { "standards" } }, function(g)
		p6m.standards.api(g, sut, {
			persisted = function(t, name, count)
				local svc = t:use(sut)
				t:expect(
					svc.db.client:query_value(n.count_by_name, { name }),
					"rows in the database"
				):equals(count)
			end,
		})
		p6m.standards.runtime(g, sut)
	end)
end
