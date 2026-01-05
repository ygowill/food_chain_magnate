# legacy_seeds/

本目录存放历史遗留的 `.tres` 种子数据（来自早期 Godot Resource 方案），仅用于**迁移/对照**，不作为运行期权威数据源。

当前运行期权威数据源：

- `modules/*/content/**/*.json`
- `data/config/game_config.json`

如需把 `.tres` 转换为 JSON 供人工对照，可使用：

- `python3 tools/migration/convert_migration_data.py --root .`

