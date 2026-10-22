local lu = require("luaunit")

-- src/api.lua against the real bundle: the public contract other plugins will get, and
-- the rule that nothing in src/core reaches outside the static data
return function(root)
    local suite = {}
    local api = require("src/api")

    -- the one npc id the build found on several pages, read straight from the index
    local function ambiguous_npc_id()
        local index = assert(loadfile(root .. "/src/bundle/generated/index.lua"))()
        local id = 0

        for gap, page in index.npcs:gmatch("([%w%-]+):([%w]*)") do
            id = id + tonumber(gap, 36)

            if tonumber(page, 36) == 0 then
                return id
            end
        end
    end

    local function run(search)
        local steps = 0

        while not search.step(250) do
            steps = steps + 1
            assert(steps < 1000, "search never finished")
        end

        return search.results(), steps
    end

    function suite:test_info_reports_schema_and_bundle()
        local info = api.info()

        lu.assertEquals(info.schema, api.SCHEMA)
        lu.assertTrue(info.monsters > 1000)
        lu.assertNotNil(tostring(info.built):match("^%d%d%d%d%-%d%d%-%d%d$"))
    end

    function suite:test_coverage_tells_every_case_apart()
        lu.assertEquals(api.coverage("Goblin").status, "covered")
        lu.assertEquals(
            api.coverage({ npc_id = 6260, name = "General Graardor" }).status,
            "covered"
        )
        lu.assertEquals(api.coverage({ npc_id = 6112, name = "Duckling" }).status, "no_drops")
        lu.assertEquals(api.coverage({ npc_id = 15824, name = "Bandit" }).status, "excluded")
        lu.assertEquals(
            api.coverage({ npc_id = 99999999, name = "Not a monster" }).status,
            "unknown"
        )
        lu.assertEquals(api.coverage("Not a real page").status, "unknown")
        lu.assertEquals(api.coverage(nil).status, "unknown")

        local id = assert(ambiguous_npc_id(), "index has no npc id on several pages")
        lu.assertEquals(api.coverage({ npc_id = id, name = "Anything" }).status, "ambiguous")
    end

    function suite:test_records_are_fresh_copies()
        local first = assert(api.monster("General Graardor"))
        local name = first.sections[1].drops[1].name
        first.sections[1].drops[1].name = "changed"
        first.title = "changed"

        local second = assert(api.monster("General Graardor"))
        lu.assertEquals(second.title, "General Graardor")
        lu.assertEquals(second.sections[1].drops[1].name, name)

        local missing, coverage = api.monster({ npc_id = 6112, name = "Duckling" })
        lu.assertNil(missing)
        lu.assertEquals(coverage.status, "no_drops")
    end

    function suite:test_lists_are_copies()
        local titles = api.titles()
        local count = #titles
        titles[1] = "changed"
        titles[#titles + 1] = "extra"
        lu.assertEquals(#api.titles(), count)
        lu.assertNotEquals(api.titles()[1], "changed")

        local ids = api.npc_ids("General Graardor")
        lu.assertTrue(#ids > 0)
        ids[1] = -1
        lu.assertNotEquals(api.npc_ids("General Graardor")[1], -1)
    end

    function suite:test_monster_search_is_stepped_and_returns_copies()
        local search = api.search_monsters("graardor")

        -- nothing happens until step, and one row at a time isnt done
        lu.assertEquals(search.results(), {})
        lu.assertFalse(search.step(1))

        local results = run(search)
        lu.assertEquals(results[1], { name = "General Graardor", wiki_title = "General Graardor" })

        results[1].name = "changed"
        lu.assertEquals(search.results()[1].name, "General Graardor")
    end

    function suite:test_searches_have_their_own_state()
        local goblins = api.search_monsters("goblin")
        local dragons = api.search_monsters("dragon")
        local goblin_results = run(goblins)
        run(dragons)

        lu.assertEquals(goblins.results(), goblin_results)

        for _, result in ipairs(goblin_results) do
            lu.assertStrContains(result.name:lower(), "goblin")
        end
    end

    function suite:test_wildcards_and_result_limit()
        local results = run(api.search_monsters("*"))
        lu.assertEquals(#results, 50)

        for _, result in ipairs(run(api.search_monsters("gen*dor"))) do
            lu.assertNotNil(result.name:lower():match("gen.*dor"))
        end
    end

    function suite:test_item_search_and_droppers()
        local items = run(api.search_items("abyssal whip"))
        lu.assertEquals(items[1].name, "Abyssal whip")
        lu.assertTrue(items[1].count > 0)

        local found = api.droppers("abyssal WHIP")
        lu.assertEquals(found.item.name, "Abyssal whip")
        lu.assertTrue(found.total >= #found.droppers)

        local titles = {}
        for _, dropper in ipairs(found.droppers) do
            titles[dropper.title] = true
        end
        lu.assertTrue(titles["Abyssal demon"])

        found.droppers[1].title = "changed"
        lu.assertNotEquals(api.droppers("Abyssal whip").droppers[1].title, "changed")
        lu.assertEquals(api.droppers("not an item"), { total = 0, droppers = {} })
    end

    function suite:test_stat_ranking_leaves_filters_alone()
        local choices = api.stat_choices()
        lu.assertEquals(choices[1], { id = 1, label = "Combat XP" })

        local filters = { bosses = "hide", max_combat = 100 }
        local results, total = api.stat_ranking(1, filters)

        lu.assertEquals(filters, { bosses = "hide", max_combat = 100 })
        lu.assertEquals(#results, 50)
        lu.assertTrue(total >= 50)
    end

    function suite:test_drop_maths_on_a_record()
        local record = assert(api.monster("Abyssal demon"))
        local value = api.kill_value(record.sections)

        lu.assertTrue(value.total > 0)
        lu.assertEquals(api.drop_chance({ chance = "50" }), 0.5)
        lu.assertNil(api.drop_modes(record.sections))
        lu.assertNotNil(api.drop_modes(assert(api.monster("General Graardor")).sections))

        local variants = api.variants(record)
        lu.assertTrue(#variants >= 1)
        lu.assertTrue(#api.stat_sections(variants[1].info, record.title).sections > 0)
    end

    -- runtime code stays local and static; offline tools never enter the export
    local FORBIDDEN = {
        "Event%.",
        "PersistentDB",
        "HTTPRequest",
        "prettyui",
        "%f[%w_]ui%.",
        "gepl",
        "Plugin%.",
        "MiniMenu",
        "HintList",
    }

    function suite:test_core_reaches_nothing_outside_static_data()
        local list = io.popen
            and io.popen(
                'git -C "' .. root .. '" ls-files --cached --others --exclude-standard src'
            )

        if not list then
            lu.skip("needs git to list the core files")
            return
        end

        local checked = 0
        local seen = {}

        for path in list:lines() do
            seen[path] = true

            local core = path:match("^src/") and not path:match("/generated/")

            if path:match("%.lua$") and core then
                local file = assert(io.open(root .. "/" .. path, "rb"))
                local text = file:read("a"):gsub("%-%-[^\n]*", "")
                file:close()
                checked = checked + 1

                for name in text:gmatch('require%("([^"]+)"%)') do
                    lu.assertTrue(name:match("^src/") ~= nil, path .. " requires " .. name)
                end

                for _, pattern in ipairs(FORBIDDEN) do
                    lu.assertNil(text:find(pattern), path .. " uses " .. pattern)
                end
            end
        end

        local closed = list:close()
        lu.assertTrue(closed == true)
        lu.assertTrue(seen["src/api.lua"])
        lu.assertTrue(seen["src/search/scan.lua"])
        lu.assertTrue(checked > 10)
    end

    return suite
end
