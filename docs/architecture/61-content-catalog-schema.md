# ContentCatalog 内容格式（modules/*/content/*.json）

模块系统 V2 会从启用模块集合加载内容，构建本局 `ContentCatalog`：

- loader：`core/modules/v2/content_catalog_loader.gd`
- catalog：`core/modules/v2/content_catalog.gd`

目录约定（每个模块可选提供任意子目录；不存在则跳过）：

- 产品：例如 `modules/base_products/content/products/` → `ProductDef`（`core/data/product_def.gd`）
- 员工：例如 `modules/base_employees/content/employees/` → `EmployeeDef`（`core/data/employee_def.gd`）
- 里程碑：例如 `modules/base_milestones/content/milestones/` → `MilestoneDef`（`core/data/milestone_def.gd`）
- 营销板件：例如 `modules/base_marketing/content/marketing/` → `MarketingDef`（`core/data/marketing_def.gd`）
- 地图板块（tiles）：例如 `modules/base_tiles/content/tiles/` → `TileDef`（`core/map/tile_def.gd`）
- 地图选项（maps）：例如 `modules/base_maps/content/maps/` → `MapOptionDef`（`core/map/map_option_def.gd`）
- 建筑件（pieces）：例如 `modules/base_pieces/content/pieces/` → `PieceDef`（`core/map/piece_def.gd`）

通用规则（Strict Mode）：

- 每个目录内按文件名排序加载；
- 同一类型的 ID 重复会**直接失败**（Marketing 以 `board_number` 为唯一键）。

## ProductDef（products/*.json）

解析：`core/data/product_def.gd`

字段：

- `id`（String，必需；`drink` 为保留字）
- `name`（String，必需）
- `tags`（Array[String]，可选）
- `starting_inventory`（int>=0，可选）

## EmployeeDef（employees/*.json）

解析：`core/data/employee_def/parser/*`

必需字段（节选，完整约束以 parser 为准）：

- `id`（String）
- `name`（String）
- `description`（String，可为空）
- `role`（String，必需；枚举：`manager/recruit_train/produce_food/procure_drink/price/marketing/new_shop/special`）
- `salary`（bool）
- `unique`（bool）
- `manager_slots`（int>=0）
- `range`（Dictionary，必需）：
  - `type`：`null` 或 `"road"`/`"air"`
  - `value`：int（`type` 为空时必须为 0；允许 `-1` 语义以规则实现为准）
- `train_to`（Array[String]）
- `train_capacity`（int>=0）
- `tags`（Array[String]）
- `usage_tags`（Array[String]）
- `mandatory`（bool）
- `mandatory_action_id`（String，可为空；但 `mandatory=true` 时必须提供该字段）

条件字段（节选）：

- `recruit_capacity`：仅当 `usage_tags` 包含 `use:recruit` 时允许且必需（>0）
- `produces`（Dictionary，可选）：`{ food_type: String, amount: int>0 }`
- `pool`（Dictionary，可选）：`{ type: fixed|one_x|none, count? }`
- `effect_ids`（Array[String]，可选，必须为 `module_id:...` 形式）
- `can_be_fired`（bool，可选）
- `marketing_max_duration`（int>0，可选）

## MilestoneDef（milestones/*.json）

解析：`core/data/milestone_def_parser.gd`

字段：

- `id`（String）
- `name`（String）
- `trigger`（Dictionary，必需）：
  - `event`（String）
  - `filter`（Dictionary，可选）
- `effects`（Array[Dictionary]，必需且非空；每项至少包含 `type`）
- `exclusive_type`（String）
- `expires_at`（int>=0 或 null）
- `pool`（Dictionary，必需）：
  - `enabled`（bool）
  - `count`（int>0，可选）
- `effect_ids`（Array[String]，可选，必须为 `module_id:...` 形式）

## MarketingDef（marketing/*.json）

解析：`core/data/marketing_def.gd`

字段（均为严格必需或按实现要求存在）：

- `id`（String）
- `board_number`（int>0；作为唯一键）
- `type`（String；具体可用性由模块注册的 marketing type 决定）
- `footprint_size`（Vector2i；JSON 里为 `[w,h]`，w/h>0）
- `min_players`（int>=2）
- `max_players`（int 或 null；若不为 null，必须 >= min_players）

## TileDef（tiles/*.json）

解析：`core/map/tile_def_parser.gd`

必需字段：

- `id`、`display_name`
- `allowed_rotations`（Array[int]，必须属于 `MapUtils.VALID_ROTATIONS`）
- `road_segments`（5x5 网格：每格 Array[Dictionary]）
- `printed_structures`（Array[Dictionary]）
- `drink_sources`（Array[Dictionary]）
- `blocked_cells`（Array[Vector2i]，JSON 为 `[x,y]`）

## MapOptionDef（maps/*.json）

解析：`core/map/map_option_def.gd`

必需字段：

- `id`、`display_name`
- `min_players`、`max_players`
- `layout_mode`：`random_all_tiles` 或 `fixed`
- `random_rotation`（bool）
- `required_modules`（Array[String]）
- `tiles`（Array[Dictionary]）
  - `layout_mode=random_all_tiles` 时必须为空
  - `layout_mode=fixed` 时必须非空

## PieceDef（pieces/*.json）

解析：`core/map/piece_def_parser.gd`

字段（当前 parser 为“全字段必需”，缺失即失败）：

- `id`、`display_name`、`category`
- `footprint_mask`（2D array）
- `anchor`（Vector2i，[x,y]）
- `allowed_rotations`（Array[int]）
- `mirror_allowed`（bool）
- `must_be_on_empty`（bool）
- `must_touch_road`（bool）
- `allowed_on`（Array[String]）
- `forbidden_layers`（Array[String]）
- `entrance_type`（String）
- `entrance_points`（Array[Vector2i]）
- `is_house`（bool）
- `can_have_garden`（bool）
- `garden_extension_size`（Vector2i）

## UI 可选：VisualCatalog（content/visuals/*.json）

视觉资源不影响 core 规则初始化，但可由 UI 使用：

- loader：`core/modules/v2/visual_catalog_loader.gd`
- catalog：`core/modules/v2/visual_catalog.gd`

规则：

- `content/visuals/` 目录不存在：允许
- 单个 JSON 解析失败：fail-fast
- **key 重复允许覆盖**（按 module plan 顺序，后者覆盖前者），并返回 warnings

