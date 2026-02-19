# UI 手工测试存档

本目录存放用于 **UI 功能手工复核** 的存档文件（`.json`）。

## 如何载入

主菜单 → 载入游戏 → "文件"页签 → 选择本目录下的 `.json`。

## 存档列表

| 文件 | 测试功能 | 场景说明 |
|------|----------|----------|
| `test_dinnertime_step_through.json` | 晚餐阶段逐步展示 | 3 房屋（花园售卖 / 跳过 / 普通售卖），含 waitress 小费和 CFO 加成 |

## 存档格式

存档为 JSON，顶层必需字段：

```
schema_version  : int          — 当前为 3（GameState.SCHEMA_VERSION）
game_version    : string       — 如 "0.1.0"
created_at      : string       — ISO 时间戳
modules_v2_base_dir : string   — "res://modules"
rng             : Dictionary   — { initial_seed: int, call_count: int }
initial_state   : Dictionary   — 完整 GameState 快照
commands        : Array        — 命令序列（回放用）
checkpoints     : Array        — 检查点元数据
current_index   : int          — 当前命令索引
final_hash      : string       — 状态哈希（可留空）
```

### initial_state 关键字段

```
phase / sub_phase   — 起始阶段（通常设为 Working/PlaceRestaurants）
round_number        — 回合号
players             — 玩家数组，每项含 cash / inventory / employees / restaurants
map                 — 地图（grid_size / cells / houses / restaurants / ...）
bank                — 银行状态
employee_pool       — 员工池
round_state         — 回合状态（含 sub_phase_passed 等）
modules             — 启用模块列表
rules               — 规则常量
```

### 命令格式

```json
{
  "action_id": "skip",
  "actor": 0,
  "index": 0,
  "phase": "Working",
  "sub_phase": "PlaceRestaurants",
  "params": {},
  "metadata": {},
  "timestamp": 0
}
```

常用 debug 命令：

- `debug_give_money` — `{ "player_id": 0, "amount": 50 }`
- `debug_add_inventory` — `{ "player_id": 0, "product": "burger", "amount": 3 }`
- `debug_add_house_demand` — `{ "house_id": "h0", "product": "burger", "amount": 1, "board_number": 0, "from_player": 0, "marketing_type": "debug" }`

## 如何生成新存档

推荐方式：以现有存档为模板，用 Python 脚本修改 `initial_state` 后输出。

### 基本步骤

1. 选择基础存档（推荐 `manual_cases/logs/event_log_dinnertime_sale.json`）
2. `copy.deepcopy` 后修改 `initial_state` 中的目标字段
3. 设置 `created_at` 为当前时间，`final_hash` 留空
4. 写入 `.savings/ui/` 目录

### 模板脚本

```python
import json, copy
from datetime import datetime

BASE = '.savings/manual_cases/logs/event_log_dinnertime_sale.json'

with open(BASE) as f:
    base = json.load(f)

save = copy.deepcopy(base)
state = save['initial_state']

# --- 修改 initial_state ---
# 示例：调整房屋需求
state['map']['houses']['h0']['demands'] = [{'product': 'burger'}]
# 示例：调整玩家库存
state['players'][0]['inventory']['burger'] = 3
# 示例：添加员工
state['players'][0]['employees'].append('waitress')

# --- 元数据 ---
save['created_at'] = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
save['final_hash'] = ''

with open('.savings/ui/my_test.json', 'w', encoding='utf-8') as f:
    json.dump(save, f, indent='\t', ensure_ascii=False)
```

### 注意事项

- `schema_version` 必须与代码中 `GameState.SCHEMA_VERSION` 一致（当前为 3）
- `rng` 中的 `initial_seed` 和 `call_count` 影响随机数序列，保持与基础存档一致即可
- 修改 `map.houses` 中的属性时，需同步更新 `map.cells` 中对应格子的 `structure`（如 `has_garden`）
- 如需新增房屋/餐厅，需同时在 `cells`、`houses`/`restaurants`、道路连通中添加
- `commands` 中的命令会按顺序回放；通常用 `skip` + `skip_sub_phase` 推进到目标阶段
- 存档起始阶段建议设为 `Working/PlaceRestaurants`，用 skip 命令让双方跳过后自动进入后续阶段
