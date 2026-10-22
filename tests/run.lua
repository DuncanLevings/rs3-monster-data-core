local root = arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. package.path

local lu = require("luaunit")
local runner = lu.LuaUnit.new()
runner:runSuiteByInstances({
    { "TestCoreApi", require("tests/core_api_spec")(root) },
    { "TestBundle", require("tests/bundle_spec")(root) },
    { "TestSearchIndex", require("tests/search_index_spec")(root) },
    { "TestMonsterInfo", require("tests/monster_info_spec")() },
    { "TestItemSearch", require("tests/item_search_spec")() },
    { "TestLocationMap", require("tests/location_map_spec")(root) },
    { "TestDungeonAccess", require("tests/dungeon_access_spec")(root) },
    { "TestMonsterLocations", require("tests/monster_locations_spec")(root) },
    { "TestJson", require("tests/json_spec")() },
    { "TestKillValue", require("tests/kill_value_spec")() },
    { "TestLocationSpawns", require("tests/location_spawns_spec")(root) },
})
os.exit(runner.result.notSuccessCount)
