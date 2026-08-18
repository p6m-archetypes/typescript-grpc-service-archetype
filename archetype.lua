local context = Context.new()

-- Identity (S1). One library, one implementation: p6m-identity asks for the project name and
-- the solution slug, plus the sample CRUD entity defaulted off the project name.
-- It replaces the author x org x project composition — nothing rendered here read the author, and
-- org_name x solution_name were two prompts building one string. `repo_name` and `github_owner`
-- are derived inside the library, never asked.
local identity = require("p6m-identity")
identity.prompt(context)

-- Service configuration
require("ports").prompt(context, { ports = { "service", "management", "debug" } })

-- Resources
context:prompt_select("Persistence:", "persistence", {
    "None", "PostgreSQL", "MySQL",
}, { default = "None" })

context:prompt_select("Cache:", "cache", {
    "None", "Redis",
}, { default = "None" })

context:prompt_select("Messaging:", "messaging", {
    "None", "Kafka", "Pulsar",
}, { default = "None" })

if context:get("messaging") ~= "None" then
    context:prompt_select("Messaging Access:", "messaging_access", {
        "produce", "consume",
    }, { default = "produce" })
else
    context:set("messaging_access", "produce")
end

context:prompt_multiselect("Object Storage:", "object_storage", {
    "S3", "Azure Blob",
}, { default = {} })

context:set("has_persistence", context:get("persistence") ~= "None")
context:set("has_cache",       context:get("cache")       ~= "None")
context:set("has_messaging",   context:get("messaging")   ~= "None")
context:set("has_s3",         context:contains("object_storage", "S3"))
context:set("has_azure_blob", context:contains("object_storage", "Azure Blob"))

-- EditorConfig + gitignore
local editor_config = require("editor-config")
editor_config.prompt(context, {
    languages     = { "JavaScript", "YAML", "Markdown" },
    gitattributes = true,
})

local gitignore = require("gitignore")
gitignore.prompt(context, {
    ignores = { "JavaScript", "Claude", "IDEA", "VSCode", "macOS" },
})

-- SCM
local scm = require("scm")
scm.prompt(context)

if archetype.switches.is_enabled("debug-context") then
    log.info(archetype.description .. " Context:")
    output.print(format.yaml(context))
end

-- Render base workspace
directory.render("contents/base", context)

-- Resource libraries
local dest = { destination = context:get("project-name") }

if context:get("persistence") == "PostgreSQL" then
    require("typescript-resource-postgresql").render(context, dest)
elseif context:get("persistence") == "MySQL" then
    require("typescript-resource-mysql").render(context, dest)
end

-- Sample scaffold entity + persistence-backed gRPC CRUD over the persistence resource
-- (Drizzle schema, ensure-schema bootstrap, items-backed service implementation) proving
-- the round trip end-to-end.
if context:get("has_persistence") then
    directory.render("contents/persistence", context)
end

if context:get("has_cache") then
    require("typescript-resource-redis").render(context, dest)
end

if context:get("messaging") == "Kafka" then
    require("typescript-resource-kafka").render(context, dest)
elseif context:get("messaging") == "Pulsar" then
    require("typescript-resource-pulsar").render(context, dest)
end

if context:get("has_s3") then
    require("typescript-resource-s3").render(context, dest)
end

if context:get("has_azure_blob") then
    require("typescript-resource-azure-blob").render(context, dest)
end

-- CI workflows
local ci = require("typescript-ci")
ci.render(context, dest)

-- Platform manifests
context:set("protocol", "gRPC")
local platform = require("platform-application-manifests")
platform.prompt(context)
platform.finalize(context, dest)

-- EditorConfig, gitignore, SCM finalize
editor_config.finalize(context, dest)
gitignore.finalize(context, dest)
scm.finalize(context)

-- Archive (zip / tarball switches for Ybor Studio)
require("archiver").finalize(context)

return context
