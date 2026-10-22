# Monster Data Core

> **Local static data only.** All monster data is read from files shipped with this library.
> **No external HTTP calls are made at runtime**: lookups, searches and calculations stay local.

A static local data library for RS3 Lua plugins. It supplies RuneScape Wiki monster records,
drops, Slayer information, name and item searches, stat rankings, and monster/dungeon location
geometry. Monster Lookup uses this library for its local data; other plugins can depend on it
directly without loading Monster Lookup or its UI.

The data uses shared string dictionaries and packed shards. A monster lookup decodes the
requested record rather than constructing every monster's full record at startup. Consumers
use ordinary Lua tables; they do not need to understand the storage format.

The library makes no HTTP requests, stores no player settings, subscribes to no game events,
and creates no UI or map markers. Its prices and records are snapshots from the bundle build.
Updates arrive with a new core data build. Source attribution and data licensing are in
[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## Getting started

### 1. Declare the dependency

For local development, place the folders next to each other:

```text
dev_plugins/
  monster-data-core/
  your-plugin/
```

Merge this dependency entry into your plugin's `plugin.json`:

```json
{
  "requiredDependencies": {
    "MonsterDataCore": "monster-data-core"
  }
}
```

`MonsterDataCore` is the alias your Lua code receives. The value is the local dependency's
folder name. When preparing a published plugin, replace that value with the core's published
plugin id; the local folder name is for development. Keep your plugin's other manifest fields
and dependencies.

Refresh the client's plugin list with `prf`, then enable `monster-data-core` before your plugin.
The client provides the dependency export through the `MonsterDataCore` global. Use that
export instead of requiring files inside this repository: your plugin's `require("src/...")`
loads from its own package.

### 2. Read a monster

This can go in your plugin's `main.lua`. No UI or event subscription is needed:

```lua
local data = MonsterDataCore
assert(data.info().schema == 1, "Unsupported Monster Data Core schema")

local record, coverage = data.monster("Abyssal demon")
if not record then
    log("No local monster record: " .. coverage.status)
    return
end

log("Loaded " .. record.title)
for _, section in ipairs(record.sections) do
    for _, drop in ipairs(section.drops) do
        log(drop.name .. " | " .. drop.quantity .. " | " .. drop.rate)
    end
end
```

Use **dot calls**, such as `data.monster(...)`, rather than `data:monster(...)`. The functions
are exported directly and do not take a `self` argument.

### 3. Use the right identity

You can pass an exact Wiki page title as a string, a selected Wiki page, or a clicked NPC:

```lua
local data = MonsterDataCore

local by_page = data.monster({
    name = "General Graardor",
    wiki_title = "General Graardor",
})

local by_npc, coverage = data.monster({
    name = "General Graardor",
    npc_id = 6260,
})
```

A string or `wiki_title` is an exact page lookup, not a fuzzy name search. Preserve the
`wiki_title` returned by name search. For a clicked NPC, pass its numeric config id as
`npc_id`, not its entity uid. A visible name alone may be shared by several pages.

`identity_key(selection)` returns a consistent lookup key. `identity_selection(key)` converts
a key back to a selection, or returns nil when it cannot. `family(name)` returns a normalized
base name useful for grouping variants; it does not identify one exact monster record.

## Missing records and coverage

`monster(selection)` returns **two values**: `record, coverage`. The record can be nil.
`coverage(selection)` checks coverage without requesting a full decoded monster record.

| `coverage.status` | Meaning | Suggested handling |
| --- | --- | --- |
| `covered` | A local record is available. | Display it. |
| `no_drops` | The NPC is known, but has no bundled drop record. | Show an empty state. |
| `excluded` | Known content excluded from this dataset, such as quest or event encounters. | Explain that it is outside coverage. |
| `ambiguous` | An NPC id occurs on several pages. | Ask for an exact page selection. |
| `unknown` | The input is not identified by the available data. | Offer search or your own fallback. |

`unknown` can mean newer content, an incorrect title/id, or unavailable bundle data; it does
not prove the monster was recently added. The core never starts a Wiki lookup. If your plugin
needs a network fallback, it must provide one or use Monster Lookup's lookup service separately.

`info()` returns `{ schema, built, monsters }`: the public data schema, build date when
available, and bundled page count. The package version is currently **0.0.3** and the data
schema is **1**. The schema is separate from both the package version and the internal packed
bundle format. Validate the schema your code supports; do not parse generated shard files.

## Working with records and variants

A record contains these main fields. Missing optional values should be handled in your UI.
The annotated record shapes are in [types/records.lua](types/records.lua).

| Field | Contents |
| --- | --- |
| `title` | Canonical Wiki page title. |
| `info` | Infobox values for the first variant. |
| `variants` | Infobox tables for the page's variants. |
| `sections` | Drop sections containing `title`, `drops`, notes, and optional descriptive text. |
| `locations` | Location rows, when available, with names, levels, requirements, spawn counts and optional map pins. |
| `no_drops`, `no_locations` | Optional reasons explaining missing data. |

A drop includes `name`, `quantity`, `rate`, notes, an optional item id, and optional price and
numeric chance/quantity fields. Quantity and rarity display fields are **strings**, not always
numbers: examples include ranges and rarities such as `Rare`. A price may be a number, a
`{ minimum, maximum }` range, `"Not sold"`, or nil. Do not assume every field is present or
that a row's saved price is a unit price.

Use the variant helpers when building your own layout:

```lua
local data = MonsterDataCore
local record = assert(data.monster("General Graardor"))
local variants = data.variants(record)

for _, variant in ipairs(variants) do
    local blocks = data.stat_sections(variant.info, record.title)
    log(variant.name .. ": " .. #blocks.sections .. " stat sections")
end

local npc_ids = data.npc_ids(record.title)
```

`variants(record)` returns `{ name, info }` entries. `stat_sections(info, title)` returns
structured stat sections, including relevant Slayer information; it draws nothing.
`npc_ids(title)` supplies candidate model config ids, not a model viewer. `titles()` returns
the bundled Wiki page titles. Build your own UI, or depend on Monster Lookup separately for
its reusable UI/model components.

## Searching

Name search, item search and stat rankings are independent APIs. You can build one search
field or combine them in your own UI. These searches cover local data only and never include
Monster Lookup's separately saved Wiki lookups.

### Monster and item name searches

`search_monsters(query)` and `search_items(query)` return independent query objects with
`step(budget)`, `done()` and `results()`. Create a new object when the query changes. Matching
supports partial words, small typos, and `*` / `?` wildcards. The core does not impose Monster
Lookup's three-character UI threshold; choose your own minimum length and debounce policy.

Drive a search from your plugin's logic tick. This example prints results once and removes
its subscription on completion or shutdown:

```lua
local data = MonsterDataCore
local search = data.search_monsters("bloodveld god wars")
local subscription = "my_plugin_monster_search"

Event.Logic.Subscribe(subscription, function()
    if search.step(250) then
        Event.Logic.Unsubscribe(subscription)
        for _, result in ipairs(search.results()) do
            log(result.name)
            -- keep result.wiki_title when the user selects this row
        end
    end
end)

function PluginShutdown()
    Event.Logic.Unsubscribe(subscription)
end
```

Merge that cleanup into your plugin's existing shutdown handler. Cancel an abandoned query
by dropping the query object and stopping its subscription. The core owns no subscription
and has no search `destroy()` method. For a UI, pause work while hidden and debounce typing.

A budget of 250 means **up to 250 entries scanned per call**, not milliseconds and not a
strict time guarantee. Query construction prepares the input list synchronously; stepping
spreads the matching/ranking work. `results()` returns the best matches so far, at most 50;
wait for completion when you need the final order. Avoid a tight `while` loop in an interactive
game callback, and avoid constructing a new query on every tick.

| Search | Result fields |
| --- | --- |
| `search_monsters(query)` | `name`, `wiki_title`; pass the result to `monster`. |
| `search_items(query)` | `name`, optional `item_id`, `count`; pass its name to `droppers`. |

### Find which monsters drop an item

```lua
local data = MonsterDataCore
local found = data.droppers("Abyssal whip")

for _, dropper in ipairs(found.droppers) do
    log(dropper.title .. " | " .. dropper.rate)
    -- dropper.quantity and optional dropper.mode describe this result
end
log("Total matching dropper entries: " .. found.total)
```

`droppers(name)` takes an exact item name, case-insensitively. It returns `{ item, total,
droppers }`; `item` is absent if the item is unknown. The list contains at most 50 entries,
ordered by chance, and `total` may be larger. Entries can distinguish a monster's modes, so
do not assume each entry has a unique monster title. `items()` returns the full copied item
index when you need to populate your own picker.

### Rank by stats

Use ids from `stat_choices()` rather than hardcoding a dropdown's positions:

```lua
local data = MonsterDataCore
local stat_id
for _, choice in ipairs(data.stat_choices()) do
    if choice.label == "Combat XP" then
        stat_id = choice.id
    end
end
assert(stat_id, "Combat XP ranking is unavailable")

local results, total = data.stat_ranking(stat_id, {
    query = "demon",
    max_combat = 150,
    max_slayer = 99,
    bosses = "hide",
})
for _, result in ipairs(results) do
    log(result.label)
    -- result.title and optional result.variant identify the matching variant
end
```

Available choices include combat XP, combat XP per life point, Slayer XP, life points,
combat level and max hit. All filters are optional. `query` matches names or Slayer categories;
`max_combat` and `max_slayer` cap levels. `bosses = "hide"` excludes the index's boss/instance
category, `"only"` keeps it, and omitting it includes everything. The core's default therefore
differs from Monster Lookup's UI default of hiding bosses.

`stat_ranking` is **synchronous**, returns up to 50 `{ title, variant?, label }` rows and a
total matching variant count, and has no `step()` method. Run it when filters change, not on
every game tick. The returned label is formatted display text; read the monster's variant
record if your plugin needs the underlying numeric stats.

### Search your own entries

`scan(entries, query, options)` applies the same stepped matcher to caller-owned entries with
a `name`. Optional `prepare`, `bonus`, `key` and `limit` hooks control preparation, ordering
and the result limit; see `ScanOptions` in [src/search/scan.lua](src/search/scan.lua).
Unlike the monster/item wrappers, `scan().results()` contains references to **your own input
entries**, in a new result list. Keep that input stable while scanning.

For repeated matching without ranking, use `prepare_name(name)` once and call the predicate
returned by `name_matcher(query)` with the prepared name.

## Drop modes and average values

Select a mode before calculating a kill value so mutually exclusive boss modes are not added
together:

```lua
local data = MonsterDataCore
local record = assert(data.monster("General Graardor"))
local groups = data.drop_modes(record.sections)
local sections = groups and groups[1].sections or record.sections
local value = data.kill_value(sections)

log(string.format("Average kill: %.0f gp%s", value.total,
    value.estimate and " (estimate)" or ""))
```

`drop_modes(sections)` returns named groups when modes/enrage tables can be split, or nil
for a plain page. Use each group's `name` and `sections` for your picker. These groups reference
the sections you supplied; they are not separate monster lookups.

`kill_value(sections, unit_price?)` uses saved prices unless your optional callback returns
a price for **one item**. Its callback receives `(item_id, saved_reference_unit_price)`;
return nil to fall back to the saved price. It makes no GE/HTTP requests. Resolve any external
prices outside the callback and keep the callback cheap.

The result includes `total`, `estimate`, `counted`, `unknown_chance`, `unknown_quantity`,
`no_price`, `untradeable` and `conditional`. Preserve the estimate flag when displaying the
total: missing prices, unknown rates/quantities and conditional Always drops can leave rows
out. Coins count as 1 gp each and untradeable drops as zero.

Other helpers are `drop_chance(drop)` (0–1 or nil), `fill_odds(drop, rate, is_percent?)`
(fills numeric fields on a caller-owned row), and `without_wiki_averages(text)` (removes saved
Wiki average-value sentences when you display your own calculation).

## Locations and dungeon geometry

A Wiki map pin uses `{ id, plane, x, z }`. A game tile uses `{ level, x, z }`. Dungeon map
images can shift coordinates or combine areas, so do not use raw Wiki map x/z as game tiles.

```lua
local data = MonsterDataCore
local record = assert(data.monster("Abyssal demon"))
for _, location in ipairs(record.locations or {}) do
    local destination, reason = data.location_resolve(location)
    if destination then
        local tile = destination.target
        log(string.format("%s: floor %d, %d, %d",
            destination.label, tile.level, tile.x, tile.z))
    else
        log(location.name .. ": " .. tostring(reason))
    end
end
```

`location_resolve(row)` returns a resolution or `nil, reason`. `kind` describes a location,
entrance or access point. `target` is the usable tile; dungeon results can also include
`interior`, `interior_map`, `interiors`, `entry_maps` and portal metadata. Not every dungeon
has a verified interior destination. Unsupported instances or conflicting pins can return nil;
show the reason rather than inventing coordinates. `location_target(row)` returns just the
target tile and an optional reason. `location_valid(map)` checks the map fields, not whether
an area has a usable route.

| Helper | Purpose |
| --- | --- |
| `map_world(map)` | Convert a Wiki pin to a verified game tile, or nil. |
| `map_contains(map_id, tile)` | Test map membership, including floor. |
| `map_is_shared(map_id)` | Identify a map containing separated areas. |
| `map_region(map_id, tile)` | Identify a mapped region containing the tile, or nil if none matches. |
| `maps_connected(map_id, first, second)` | Check the static region/floor relationship of two tiles. |
| `map_name(map_id)`, `map_names()` | Read a map's name or a copied id-to-name table. |

These are static geometry checks, not collision/pathfinding, live instance detection, a
walking route, or marker management. Consumers own those features. Monster Lookup supplies
its own navigation on top of this data.

## Ownership, lifecycle and performance

- Treat the shared `MonsterDataCore` export as read-only. Do not replace its functions or add
  plugin state to it: the client shares the export across dependents.
- Record/list lookup methods return tables you own. Changing one returned monster does not
  change another caller's record. The explicit caller-input cases are `scan`, `drop_modes`
  and `fill_odds`, described above.
- There is no core session or handle to destroy. Your plugin owns its search scheduling,
  callbacks, UI and caches. Keep cleanup in your own shutdown handler.
- Reuse a decoded record while showing it. Do not decode every monster to implement search:
  use the dedicated name, item and stat indexes. The first access to an index can cost more
  than subsequent accesses because it is loaded lazily.
- Core updates can reload/stop dependent plugins. Enable/reload dependents after the core
  when needed. Do not expect an old export or query to survive a dependency reload.
- Do not persist the export or decoded implementation details. If saving selections, keep
  titles/NPC ids and validate saved data against the schema you support.

## Tests and offline builds

From this repository, with Lua 5.4+ and LuaUnit available on `package.path`:

```sh
lua tests/run.lua
lua-language-server --check . --checklevel=Warning
```

The annotated public record types live in `types/`. For LuaLS in a sibling consumer repo,
add `../monster-data-core/types` to `workspace.library` and `MonsterDataCore` to
`diagnostics.globals`. This supplies record types; it is not a runtime import.

Rebuild from saved Wiki inputs in ignored `work/wiki/`:

```sh
lua tools/bundle/build.lua
lua tools/bundle/build.lua --install
```

The first command writes to `work/bundle/`; `--install` writes to `src/bundle/generated/`.
The build decodes and compares its packed records and enforces a size budget. Fetching new
source data with `tools/fetch_wiki_data.py` is an explicit maintainer operation, not something
a consumer plugin should run. The `work/` inputs are not included in a fresh clone; tests
against the checked-in bundle do not require them. Preserve attribution when redistributing
the data, following [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

Monster Lookup's integration tests find this package as a sibling by default.
`MONSTER_DATA_CORE_ROOT` overrides that test path when repositories are stored separately.
Runtime dependency resolution always comes from the client manifest.
