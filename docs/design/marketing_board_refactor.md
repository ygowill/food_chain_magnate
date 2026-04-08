# Marketing Board Footprints & Marketing Panel Refactor

Last updated: 2026-01-16

## Goal

Fix the Marketing (营销) UX and rules so that marketing boards are not treated as 1x1 tokens:

- Each `board_number` has its own **map footprint size** (width/height in world grid cells).
- Boards **block** other placements (marketing cannot overlap marketing; structures cannot overlap marketing).
- Placement anchor is **top-left** of the (rotated) footprint.
- Boards **can rotate**; rotation must be respected in validation, previews, highlights, and rendering.
- For board previews and map rendering, the **product icon is centered** on the board area.
- Marketing panel selection is **visual** and **sorted by board_number**:
  - board picker shows footprint preview
  - product picker is visual (icons)
  - duration picker is visual (not just a SpinBox)
- The right-docked marketing panel must **never overflow the screen**.

## Confirmed Requirements / Decisions

### Footprint

- Footprint unit is **map cells** (“地图占格”).
- Anchor is **top-left** (“左上角”).
- Boards can rotate (“板件可以旋转放置”).

### Blocking

- Marketing boards are **blocking** (“阻挡”):
  - marketing vs marketing: no overlap
  - structures (house/restaurant/garden/etc) vs marketing: no overlap

### requires_edge semantics (Updated)

`requires_edge` means:

- **At least one full side** of the board footprint is **exactly flush with the map edge**.
- The footprint must be fully **inside** the map (cannot exceed bounds).

For a rectangular footprint with rotated `(w,h)` and anchor `(x0,y0)`:

- `left = x0`
- `right = x0 + w - 1`
- `top = y0`
- `bottom = y0 + h - 1`

With `world_min=(min_x,min_y)`, `world_max=(max_x,max_y)` the placement satisfies `requires_edge` iff:

- `left == min_x` OR `right == max_x` OR `top == min_y` OR `bottom == max_y`

### Product slot position

“产品槽位位置” here means **where the product icon is drawn** on the board preview / map rendering.  
Confirmed: **centered** (“放在中心”).

## Board Footprint Data

Format: `board_number  width  height` (unrotated). Rotation 90/270 swaps width/height.

### Base boards (1–16)

1  1 1  
2  1 1  
3  1 1  
4  2 1  
5  3 2  
6  5 2  
7  2 2  
8  2 2  
9  1 1  
10 1 1  
11 3 2  
12 2 2  
13 3 1  
14 2 1  
15 1 1  
16 1 1  

### Gourmet guide (17–20)

17 5 1  
18 5 1  
19 5 1  
20 5 1  

### Airplane dual (5100–5102)

Sizes correspond to boards 4–6:

- 5100 → same as 4:  2 1
- 5101 → same as 5:  3 2
- 5102 → same as 6:  5 2

## Identifiers Reference

- `17–20`: `modules/gourmet_food_critics/content/marketing/gourmet_guide_17.json` … `gourmet_guide_20.json` (`type: gourmet_guide`)
- `5100–5102`: `modules/new_milestones/content/marketing/airplane_dual_5100.json` … `5102.json` (`type: airplane`)

## Technical Notes / Architecture

### State storage (current + planned additions)

Existing (today):

- `state.map.marketing_placements[str(board_number)] = { board_number, type, owner, product, world_pos, remaining_duration, axis, tile_index }`
- `state.marketing_instances[]` contains matching instance dictionaries.

Planned additions (for footprint rendering + overlap queries without relying on registries in UI):

- `rotation` (int, degrees; one of `0/90/180/270`)
- `footprint_size` (Array `[w,h]`, unrotated)

### Backward compatibility

If an older placement lacks `rotation` / `footprint_size`, treat it as `rotation=0`, `footprint_size=[1,1]`.

## Implementation Plan (Tracked)

- [x] A. Document & progress tracking (this file)
- [x] B. Data layer: add `footprint_size` to `MarketingDef` + all marketing JSON
- [x] C. Core queries: marketing placement overlap becomes footprint-aware
- [x] D. initiate_marketing: validate/apply footprint+rotation; store `rotation/footprint_size`
- [x] E. Module actions placing marketing boards updated to the same footprint rules
- [x] F. Blocking: PlacementValidator rejects structure overlaps with marketing footprints
- [x] G. Map interaction: valid-anchor highlights & airplane axis inference based on footprint
- [x] H. Map rendering: draw footprint area; center product icon overlay
- [x] I. MarketingPanel UI refactor: board preview picker + product grid + duration picker + rotation

## Progress Log

### 2026-01-16

- UI overflow mitigation: removed MarketingPanel `custom_minimum_size = Vector2(450, 300)` so right-docked panel no longer forces width overflow (`ui/components/marketing_panel/marketing_panel.tscn`).
- Marketing panel icon sizing:
  - product icons in OptionButton scaled to 24x24 with caching
  - marketing type icons normalized to a 36x36 slot
  - type selector switched to a 2-column grid to reduce horizontal overflow
  (Implementation in `ui/components/marketing_panel/marketing_panel.gd`, `ui/components/marketing_panel/marketing_panel.tscn`, `ui/components/marketing_panel/marketing_type_button.gd`.)
- Data layer:
  - `core/data/marketing_def.gd` now requires `footprint_size: [w,h]` (strict parsing) and exposes it via `MarketingDef.footprint_size`.
  - All marketing JSON definitions updated to include `footprint_size`:
    - `modules/base_marketing/content/marketing/*.json` (1–16)
    - `modules/gourmet_food_critics/content/marketing/*.json` (17–20)
    - `modules/new_milestones/content/marketing/*.json` (5100–5102)
- Core query + initiate_marketing footprint storage:
  - `core/map/marketing_placement_query.gd` now treats marketing placements as rectangular footprints (size + optional rotation), so overlap queries work for multi-cell boards.
  - `gameplay/actions/initiate_marketing/validation.gd` + `gameplay/actions/initiate_marketing/apply.gd` now respect `MarketingDef.footprint_size`, accept `rotation`, and store `rotation/footprint_size` into `marketing_instances` + `map.marketing_placements` (backward compatible defaults for older saves/tests).

- Test/UI regression fixes while refactor is underway:
  - Fixed a GDScript indentation/syntax error in `core/tests/marketing_campaigns_test.gd` introduced during earlier edits.
  - Fixed a logic bug in marketing highlight scanning where the “adjacent road” check was accidentally unreachable (`ui/scenes/game/game_map_interaction_controller.gd`).

- Footprint-aware range checks (distance limits):
  - `core/utils/range_utils.gd` adds helpers to check road/air range against multiple target cells / target road cells (for multi-cell board footprints).
  - `gameplay/actions/initiate_marketing/validation.gd` now evaluates employee range using the board footprint (instead of only the anchor cell).
- Fixed `initiate_marketing` non-edge placement validation bug:
  - `gameplay/actions/initiate_marketing/validation.gd` restores correct indentation and re-enables per-cell road/non-road checks for footprint cells (previously the road check was accidentally unreachable).
- Blocking (structures vs marketing):
  - `core/map/placement_validator/validators.gd` adds `validate_no_marketing_overlap`, and `core/map/placement_validator/placement.gd` runs it for all structure placements.
  - Placement contexts now include `marketing_placements` so actions/previews reject placing houses/restaurants/gardens/parks/etc on top of marketing footprints:
    - `gameplay/actions/place_house_action.gd`, `gameplay/actions/place_restaurant_action.gd`, `gameplay/actions/move_restaurant_action.gd`, `gameplay/actions/add_garden_action.gd`
    - `modules/coffee/actions/place_or_move_coffee_shop_action.gd`, `modules/lobbyists/actions/place_lobbyists_road_action.gd`, `modules/lobbyists/actions/place_lobbyists_park_action.gd`
    - `ui/scenes/game/game_map_interaction_controller.gd` placement previews
- Module actions that place marketing boards are now footprint + rotation aware (match `initiate_marketing` rules) and store `rotation/footprint_size` in state:
  - `modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd`
  - `modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd`
  - `modules/new_milestones/actions/place_pizza_radio_action.gd`
  - Updated test fixture map to support multi-cell mailbox placement: `core/tests/new_milestones_new_restaurant_v2_test.gd`

- Test updates to match multi-cell footprints:
  - `core/tests/new_milestones_v2_test.gd`, `core/tests/new_milestones_marketing_trainee_v2_test.gd`, `core/tests/new_milestones_brand_director_v2_test.gd` updated marketing placement anchors so multi-cell boards no longer overlap roads.
  - `core/tests/marketing_campaigns_test.gd` test map restaurant entrance is now adjacent to the road network (required by road-range).
- Map interaction wiring:
  - `ui/components/marketing_panel/marketing_panel.gd` now passes `board_number` + `rotation` into the map-selection callback so valid-anchor highlights can be footprint-aware (rotation UI still pending).
  - `ui/scenes/game/game_panel_marketing_panels.gd` now forwards `rotation` to `initiate_marketing` (omits param when `rotation=0`).
- Map rendering (marketing footprints):
  - `ui/scenes/game/map_canvas_indexer.gd` indexes marketing placements by all occupied footprint cells (tooltip/hover works on any covered cell).
  - `ui/scenes/game/map_canvas_drawer.gd` draws the full footprint rectangle and centers the product icon on the board area (rotation-aware; backward compatible defaults).
- MarketingPanel UX refactor:
  - `ui/components/marketing_panel/marketing_panel.tscn` now uses a ScrollContainer and wrapping FlowContainers so the docked right panel no longer overflows horizontally.
  - Board selection is now a visual footprint preview grid (sorted by board number), via `ui/components/marketing_panel/marketing_board_button.gd`.
  - Product selection is now a visual icon grid, and duration selection is now a visual button row/grid (no SpinBox).
  - Added rotation controls (0/90/180/270); rotation is passed into map highlights and `initiate_marketing`.
- Validation:
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` → `PASS 83/83` (`.godot/AllTests.log`).
  - Fixed startup-breaking script errors found by `GameSmokeTest`:
    - `ui/scenes/game/game_map_interaction_controller.gd` had indentation parse errors (caused `game.gd` preload to fail); corrected indentation.
    - `ui/components/marketing_panel/marketing_board_button.gd` renamed `rotation`/`set_rotation` to `board_rotation`/`set_board_rotation` to avoid clashing with Control/Button built-ins (warnings treated as errors).
    - `ui/components/game_log/game_log_panel.gd` removed cyclic `preload` of `full_log_window.tscn` (runtime `load` instead) to avoid scene/script load recursion.
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` → `PASS` (`.godot/GameSmokeTest.log`).

- Placement distance debugging (广告放置距离排查辅助):
  - `core/utils/range_utils.gd` adds `get_min_road_distance_to_any_road_cells()`; `is_within_road_range_to_any_road_cells()` now delegates to it.
  - `gameplay/actions/initiate_marketing/validation.gd` includes `min=` in the “超出距离范围” error, and reports “无法通过道路到达目标附近的道路” when unreachable.

- Investigating: marketing green-highlight range too small (e.g. campaign_manager road=3 only shows 0-1 tiles).
  - Hypothesis: range helpers ignored `state.map.external_cells` (external road graph nodes), so start/target road adjacency could miss highway/off-map road connections.
  - Change: `core/utils/range_utils.gd` now uses `has_cell_any/has_road_at_any` in adjacency + target-road filtering so external roads participate in road-range checks.
  - Change: `core/utils/range_utils.gd` road-range now respects `drive_thru_active` by treating restaurant 4 corners as entrance points (start road cells = union of all entrances).
- Fixed base tile bridge connectivity (suspected root cause for inflated “distance tool” readings like 5–6 across nearby tiles):
  - `modules/base_tiles/content/tiles/tile_g.json` and `modules/base_tiles/content/tiles/tile_p.json` previously omitted the center horizontal segment, making the E–W road discontinuous.
  - Added a second road segment at the center cell so both N–S (bridge) and W–E roads stay continuous without intersecting.
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` → `PASS 83/83`.
- Distance tool correctness:
  - `ui/overlays/distance_overlay.gd` no longer falls back to Manhattan distance when no road path exists; it now displays “无法连接” instead of a misleading number.
- Removed hard-coded employee id rename migration in archive loader:
  - `core/engine/game_engine/loader.gd` no longer rewrites employee ids on load; old saves relying on renamed ids should be discarded instead of patched.
  - Searched codebase for similar “rename map / migrate id” patterns; none found outside docs.
