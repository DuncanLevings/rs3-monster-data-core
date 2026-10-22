local lu = require("luaunit")
return function(root)
    local suite = {}
    local pins = require("tools/wiki/location_spawns")
    function suite:test_missing_or_malformed_optional_source_does_not_break_location_rows()
        local result = { { page = "Polypore Dungeon" } }
        pins.attach(result, false)
        pins.attach(result, "{{LocLine|loc=[[Polypore Dungeon]]|mapID=41|x:3411,y:9687")
        lu.assertNil(result[1].spawn_maps)
        pins.attach(result, "{{LocLine|loc=[[Polypore Dungeon]]|mapID=bad|x:3411,y:9687}}")
        lu.assertNil(result[1].spawn_maps)
        pins.attach(
            result,
            "{{LocLine|loc=[[Polypore Dungeon]]|mapID=41|x:3411.5,y:9687|x:3411,y:9687,plane:bad}}"
        )
        lu.assertNil(result[1].spawn_maps)
    end

    function suite:test_source_template_nesting_and_duplicate_points_are_handled()
        local result = { { page = "Polypore Dungeon" } }
        pins.attach(
            result,
            "{{LocLine|loc=[[Polypore Dungeon|Cave]]|requirements={{Skillreq|Slayer|1}}|mapID=41|x:3411,y:9687|x:3411,y:9687}}"
        )
        lu.assertEquals(#result[1].spawn_maps, 1)
    end

    function suite:test_point_limit_keeps_other_native_floors()
        local source = { "{{LocLine|loc=[[Polypore Dungeon]]|mapID=41" }
        for _ = 1, 300 do
            source[#source + 1] = "|x:3277,y:9336"
        end
        source[#source + 1] = "|x:3411,y:9687}}"
        local result = { { page = "Polypore Dungeon" } }
        pins.attach(result, table.concat(source))
        lu.assertEquals(#result[1].spawn_maps, 2)
    end

    return suite
end
