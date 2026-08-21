local context = Context.new()

-- The prompt surface is laid out in PAGES and SECTIONS. These carry the author's grouping intent —
-- the one thing a derived interface cannot infer from the script — to every renderer: a wizard step
-- in Ybor Studio, a titled heading in the terminal, a block comment in an answers template.
--
-- Built for the HYBRID drive: a client describes with the answers it has, renders the first page
-- that still has children, collects them, and describes again. Two consequences shape what is
-- written here:
--
--   * Keys are PINNED, never derived from a title, because a wizard routes on them and pages
--     appear and disappear between rounds. Titles are display text; keys are identity.
--   * A prompt that depends on an earlier answer sits in the SAME page as what it depends on
--     (Messaging Access under Messaging, repository details under Source Control). The page comes
--     back with new fields and the client stays on that step — progressive disclosure, rather than
--     a step that vanishes and reappears elsewhere.
--
-- The vocabulary is the fleet's, not this archetype's: every p6m archetype uses the same page and
-- section keys, so a form reads identically whatever the language or shape. An archetype omits a
-- section it has no prompts for; it does not invent one.
local identity = require("p6m-identity")

context:page({ title = "Project", key = "project",
               help = "What this service is called, and the domain it models." }, function(ctx)
    identity.prompt_project(ctx)

    -- The deployment coordinates, grouped deliberately: this is exactly the set Ybor Studio
    -- supplies per solution, so hiding them later is "this section came back empty" rather than a
    -- re-grouping exercise.
    ctx:section({ title = "Platform", key = "platform",
                  help = "Where this service deploys and publishes." }, function(ctx)
        identity.prompt_solution(ctx)

        -- The registry is asked here rather than by `platform.prompt()` below: the manifests
        -- library runs last (it needs the resource selections), which would put the registry dead
        -- last in the derived interface. The library still owns the prompt definition.
        require("platform-application-manifests").prompt_registry(ctx)
    end)

    ctx:section({ title = "Service", key = "service",
                  help = "The ports this service listens on." }, function(ctx)
        -- `debug` is not asked: nothing this archetype renders reads `debug_port` (S1b / E2).
        require("ports").prompt(ctx, { ports = { "service", "management" } })
    end)
end)

context:page({ title = "Resources", key = "resources",
               help = "Platform-provisioned backing services. The platform provisions each one and "
                   .. "injects its connection settings; no credentials are asked for here." }, function(ctx)
    ctx:section({ title = "Persistence", key = "persistence" }, function(ctx)
        ctx:prompt_select("Persistence:", "persistence", { "None", "PostgreSQL", "MySQL" },
            { default = "None" })
    end)

    ctx:section({ title = "Cache", key = "cache" }, function(ctx)
        ctx:prompt_select("Cache:", "cache", { "None", "Redis" }, { default = "None" })
    end)

    ctx:section({ title = "Messaging", key = "messaging" }, function(ctx)
        ctx:prompt_select("Messaging:", "messaging", { "None", "Kafka", "Pulsar" },
            { default = "None" })
        -- Intra-page dependency, deliberately: choosing a broker brings this page back with one
        -- more field rather than sending the client to a different step.
        if ctx:get("messaging") ~= "None" then
            ctx:prompt_select("Messaging Access:", "messaging_access", { "produce", "consume" },
                { default = "produce" })
        else
            ctx:set("messaging_access", "produce")
        end
    end)

    ctx:section({ title = "Object Storage", key = "object_storage" }, function(ctx)
        ctx:prompt_multiselect("Object Storage:", "object_storage", { "S3", "Azure Blob" },
            { default = {} })
    end)
end)

context:set("has_persistence", context:get("persistence") ~= "None")
context:set("has_cache",       context:get("cache")       ~= "None")
context:set("has_messaging",   context:get("messaging")   ~= "None")
context:set("has_s3",          context:contains("object_storage", "S3"))
context:set("has_azure_blob",  context:contains("object_storage", "Azure Blob"))

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

-- SCM — its own page: publishing is a decision about delivery, not about the service. The
-- repository details it reveals are intra-page, so choosing a provider keeps the client here.
local scm = require("scm")
-- Ybor Studio's generator-service creates the repository and packages the output itself, so it
-- renders with `-s no-scm` and never sees this page. The CLI supplies no switches and keeps it:
-- switches are never prompted, so the DEFAULT has to be the interactive path and the programmatic
-- caller is the one that opts out (S1d). Answering `scm_provider = "None"` would not do — the page
-- still derives, and a client that renders the interface as a form shows a step that asks nothing.
local scm_external = archetype.switches.is_enabled("no-scm")
if not scm_external then
    context:page({ title = "Source Control", key = "source_control",
                   help = "Optionally create and publish the repository." }, function(ctx)
        scm.prompt(ctx)
    end)
end

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
if not scm_external then
    scm.finalize(context)
end

-- Archive (zip / tarball switches for Ybor Studio)
require("archiver").finalize(context)

return context
