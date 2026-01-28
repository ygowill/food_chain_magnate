# GameState：序列化/反序列化与 schema 归一化

`GameState` 的序列化/反序列化是确定性与 Strict Mode 的核心护栏之一：

- 存档（archive）依赖 `GameState.to_dict()` 的 JSON-safe 输出；
- 读档必须严格校验类型与必需字段；
- 模块扩展字段需要在读档时进行“int-key Dictionary 归一化”，避免 JSON 把 key 变成字符串导致运行期类型漂移。

主要实现文件：

- `core/state/game_state_serialization.gd`
- `core/state/serialization/*`
- `core/state/state_schema_registry.gd`

## JSON-safe 输出（to_dict）

`GameStateSerialization.to_dict` 会把部分嵌套结构转为 JSON-safe：

- `rules` / `map` / `round_state` 会通过 `JsonSafe.to_json_safe(...)` 深度转换
  - 典型用途：把 `Vector2i` 编码成 `[x,y]`，确保 JSON 可表示且 hash 稳定

对应实现：

- `core/state/serialization/json_safe.gd`

## 严格读档（apply_from_dict）

`GameStateSerialization.apply_from_dict` 的特点：

- schema_version 不匹配直接失败（不做兼容迁移）
- 对关键字段做强类型校验（int/bool/String/Array/Dictionary）
- 对结构较复杂的部分使用专用 parser/decoder：
  - `ValueDecoder.decode_map/decode_value`：把 JSON-safe 的地图结构解码回 Variant（如 Vector2i）
  - `RoundStateParser.parse_round_state`：对 round_state 做 required/optional 字段分层解析

相关实现：

- `core/state/serialization/value_decoder.gd`
- `core/state/serialization/round_state_parser.gd`
- `core/state/serialization/round_state_parser_required_fields.gd`
- `core/state/serialization/round_state_parser_optional_fields.gd`

## 模块扩展：int-key Dictionary 归一化（StateSchemaRegistry）

问题背景：

- JSON 存档会把 Dictionary 的 int key 写成字符串（例如 `0` → `"0"`）
- 模块扩展字段中常见 `{player_id(int) -> ...}` 结构
- 若不归一化，读档后会出现 “key 类型从 int 变成 String” 的漂移，进而导致规则代码失败或静默错判

解决方式：

- 模块通过 `RulesetV2.register_state_int_key_dict_schema(...)` 注册 schema 路径
- 装配时由 `StateSchemaRegistry.configure_from_ruleset(...)` 收集并排序
- 读档时：
  - `GameState.map`：`StateSchemaRegistry.normalize_int_key_dicts_in_container("map", ...)`
  - `GameState.round_state`：`StateSchemaRegistry.normalize_int_key_dicts_in_container("round_state", ...)`

并且会对“模块自有字段”做额外告警扫描：

- 若仍发现 `"0"/"1"...` 这类玩家 key，会返回 warnings，提示可能缺少 schema 注册

实现入口：

- `core/state/state_schema_registry.gd`

