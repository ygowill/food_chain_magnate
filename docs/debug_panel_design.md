# 调试面板设计文档

> 更新（2026-01-08）：调试面板（控制台）已实现：`ui/scenes/debug/debug_panel.tscn`。  
> 本文保留早期设计背景；现状以代码与 `docs/development_progress_audit.md` 为准。

## 1. 现状分析

### 1.1 当前已有的调试功能

经过代码分析，项目中已经存在基础的调试功能实现：

| 组件 | 文件位置 | 功能描述 |
|------|----------|----------|
| 调试开关系统 | `autoload/debug_flags.gd` | 全局调试模式开关、详细日志、不变量校验 |
| 旧调试窗口（只读） | `ui/scenes/game/game.tscn` | 菜单里的 DebugDialog：显示只读文本 |
| 旧调试控制器 | `ui/scenes/game/game_menu_debug_controller.gd` | 管理旧调试窗口的打开/关闭和文本更新 |
| 调试面板（控制台） | `ui/scenes/debug/debug_panel.tscn` / `ui/scenes/debug/debug_panel.gd` | 可交互：命令执行、状态/历史/设置等标签页 |
| 调试命令集 | `core/debug/debug_commands/*` | 内置调试命令（state/game/util/action 等） |
| 诊断工具 | `core/engine/game_engine/diagnostics.gd` | 生成状态 dump 和简要状态信息 |

### 1.2 当前调试窗口显示的信息

```
round=X phase=XXX sub_phase=XXX current_player=X
bank={...}
marketing_instances=[...]
round_state={...}
```

### 1.3 当前快捷键

- `Ctrl+Shift+D`: 切换调试模式
- `~` (反引号): 切换调试面板（控制台）显示（由 `autoload/debug_flags.gd` 触发，`ui/scenes/game/game.gd` 负责 show/hide）

### 1.4 现有功能的不足

1. **调试入口存在重复** - 旧 DebugDialog（只读）与新 DebugPanel（可交互）并存，后续可考虑收敛为单一入口
2. **实体检查仍偏只读** - EntityTab 以浏览为主，尚未覆盖“直接修改实体属性”的完整工作流
3. **状态面板展示仍可加强** - 例如玩家/回合信息的折叠细节、导出按钮等可继续补齐

---

## 2. 改进方案设计

### 2.1 设计目标

参考星露谷物语、Factorio 等游戏的调试控制台，设计一个功能完善的调试面板，具备以下能力：

1. **状态查看** - 查看游戏各种状态的详细信息
2. **命令执行** - 通过按钮或输入框执行调试命令
3. **实体检查** - 查看和修改单个实体的属性
4. **历史记录** - 查看命令执行历史和日志
5. **快捷操作** - 常用调试功能的快捷按钮

### 2.2 UI 布局设计

```
┌─────────────────────────────────────────────────────────────────┐
│ 调试面板                                              [_][□][X] │
├─────────────────────────────────────────────────────────────────┤
│ [状态] [命令] [实体] [历史] [设置]                    ← 标签页  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                                                         │   │
│  │                    主内容区域                            │   │
│  │              (根据标签页切换内容)                        │   │
│  │                                                         │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│ > 命令输入框                                          [执行]   │
├─────────────────────────────────────────────────────────────────┤
│ 状态: 调试模式开启 | 命令数: 42 | Hash: a1b2c3d4              │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 标签页详细设计

#### 2.3.1 状态标签页 (State Tab)

显示游戏当前的完整状态信息，分为多个可折叠区域：

```
▼ 基础信息
  回合: 3
  阶段: working
  子阶段: player_actions
  当前玩家: 1

▼ 银行状态
  总金额: $150
  各面额: {1: 50, 5: 20, 10: 10, ...}

▼ 玩家状态
  ▶ 玩家 1: $45, 员工数: 5, 已行动: 2
  ▶ 玩家 2: $30, 员工数: 4, 已行动: 1

▼ 地图状态
  建筑数: 12
  空地数: 8

▼ 营销实例
  [列表显示所有活跃的营销]

▼ 回合状态
  turn_order: [0, 1, 2]
  current_turn_index: 1
```

#### 2.3.2 命令标签页 (Command Tab)

提供常用调试命令的快捷按钮和命令输入：

```
═══ 阶段控制 ═══
[推进阶段] [推进子阶段] [跳到下一回合]

═══ 资源操作 ═══
[给当前玩家 +$50] [给所有玩家 +$100] [重置银行]

═══ 游戏流程 ═══
[跳过当前玩家] [结束当前阶段] [触发结算]

═══ 状态操作 ═══
[保存快照] [加载快照] [重置游戏]

═══ 调试工具 ═══
[导出状态 JSON] [验证不变量] [打印命令历史]
```

#### 2.3.3 实体标签页 (Entity Tab)

提供实体浏览和检查功能：

```
┌─────────────────┬─────────────────────────────────┐
│ 实体列表        │ 实体详情                        │
│                 │                                 │
│ ▼ 玩家          │ 玩家 1                          │
│   ├ 玩家 1      │ ─────────────────────           │
│   ├ 玩家 2      │ ID: 0                           │
│   └ 玩家 3      │ 金钱: $45                       │
│                 │ 员工数: 5                       │
│ ▼ 建筑          │ 已行动员工: 2                   │
│   ├ 餐厅 (2,3)  │                                 │
│   ├ 咖啡店 (4,5)│ ▼ 员工列表                      │
│   └ ...         │   - CEO (已行动)                │
│                 │   - 厨师 (未行动)               │
│ ▼ 员工          │   - 服务员 (未行动)             │
│   ├ CEO         │                                 │
│   └ ...         │ [修改金钱] [添加员工]           │
└─────────────────┴─────────────────────────────────┘
```

#### 2.3.4 历史标签页 (History Tab)

显示命令执行历史和游戏日志：

```
═══ 命令历史 ═══
#42 [系统] advance_phase → working
#41 [玩家1] place_employee {pos: (2,3), type: "chef"}
#40 [玩家2] skip
#39 [系统] advance_sub_phase → player_actions
...

═══ 过滤器 ═══
[✓] 系统命令  [✓] 玩家命令  [ ] 内部命令

[导出历史] [清空显示] [跳转到命令...]
```

#### 2.3.5 设置标签页 (Settings Tab)

调试相关的设置选项：

```
═══ 调试选项 ═══
[✓] 调试模式
[✓] 详细日志
[✓] 命令后校验不变量
[ ] 性能分析
[ ] 显示 FPS

═══ 显示选项 ═══
[✓] 显示网格坐标
[✓] 显示实体 ID
[ ] 显示碰撞框

═══ 日志级别 ═══
( ) DEBUG  (•) INFO  ( ) WARN  ( ) ERROR
```

---

## 3. 命令系统设计

### 3.1 命令格式

采用简单的命令格式：`命令名 [参数1] [参数2] ...`

### 3.2 内置命令列表

| 命令 | 参数 | 描述 |
|------|------|------|
| `help` | [命令名] | 显示帮助信息 |
| `state` | - | 打印当前状态摘要 |
| `dump` | - | 导出完整状态 |
| `advance` | [phase/sub_phase] | 推进阶段 |
| `skip` | [玩家ID] | 跳过玩家回合 |
| `give_money` | <玩家ID> <金额> | 给玩家金钱 |
| `set_phase` | <阶段名> | 设置当前阶段 |
| `spawn` | <实体类型> <参数...> | 生成实体 |
| `remove` | <实体ID> | 移除实体 |
| `teleport` | <实体ID> <x> <y> | 移动实体位置 |
| `save` | [文件名] | 保存游戏 |
| `load` | [文件名] | 加载游戏 |
| `snapshot` | - | 创建状态快照 |
| `restore` | - | 恢复到上一个快照 |
| `validate` | - | 验证游戏状态不变量 |
| `history` | [数量] | 显示命令历史 |
| `undo` | [步数] | 撤销命令 |
| `redo` | [步数] | 重做命令 |
| `clear` | - | 清空控制台输出 |
| `exec` | <action_id> <参数JSON> | 执行任意动作 |

### 3.3 命令自动补全

- 输入时显示匹配的命令建议
- Tab 键补全命令名
- 上/下箭头浏览历史命令

---

## 4. 技术实现方案

### 4.1 文件结构

```
ui/
├── scenes/
│   └── debug/
│       ├── debug_panel.tscn          # 主调试面板场景
│       ├── debug_panel.gd            # 主控制脚本
│       ├── tabs/
│       │   ├── state_tab.tscn        # 状态标签页
│       │   ├── state_tab.gd
│       │   ├── command_tab.tscn      # 命令标签页
│       │   ├── command_tab.gd
│       │   ├── entity_tab.tscn       # 实体标签页
│       │   ├── entity_tab.gd
│       │   ├── history_tab.tscn      # 历史标签页
│       │   ├── history_tab.gd
│       │   ├── settings_tab.tscn     # 设置标签页
│       │   └── settings_tab.gd
│       └── components/
│           ├── command_input.tscn    # 命令输入组件
│           ├── command_input.gd
│           ├── entity_tree.tscn      # 实体树组件
│           ├── entity_tree.gd
│           ├── property_editor.tscn  # 属性编辑器
│           └── property_editor.gd
│
core/
└── debug/
    ├── debug_command_registry.gd     # 命令注册表
    ├── debug_command_parser.gd       # 命令解析器
    └── debug_commands/
        ├── state_commands.gd         # 状态相关命令
        ├── game_commands.gd          # 游戏流程命令
        ├── entity_commands.gd        # 实体操作命令
        └── util_commands.gd          # 工具命令
```

### 4.2 核心类设计

#### 4.2.1 DebugCommandRegistry (命令注册表)

```gdscript
class_name DebugCommandRegistry
extends RefCounted

# 命令定义
class CommandDef:
    var name: String
    var description: String
    var usage: String
    var handler: Callable
    var arg_hints: Array[String]  # 用于自动补全

var _commands: Dictionary = {}  # name -> CommandDef

func register(name: String, handler: Callable, description: String, usage: String = "") -> void
func unregister(name: String) -> void
func execute(command_line: String) -> Result
func get_suggestions(partial: String) -> Array[String]
func get_help(command_name: String = "") -> String
```

#### 4.2.2 DebugPanel (调试面板主控制器)

```gdscript
class_name DebugPanel
extends Window

signal command_executed(command: String, result: Variant)

var _command_registry: DebugCommandRegistry
var _game_engine: GameEngine
var _command_history: Array[String]
var _history_index: int = -1

func _ready() -> void
func set_game_engine(engine: GameEngine) -> void
func execute_command(command_line: String) -> void
func print_output(text: String, type: String = "info") -> void
func refresh_state() -> void
```

### 4.3 与现有系统的集成

#### 4.3.1 修改 game.gd

```gdscript
# 添加调试面板引用
var debug_panel: DebugPanel = null

func _ready() -> void:
    # ... 现有代码 ...

    # 初始化调试面板
    if DebugFlags.is_debug_mode():
        _setup_debug_panel()

func _setup_debug_panel() -> void:
    var panel_scene = preload("res://ui/scenes/debug/debug_panel.tscn")
    debug_panel = panel_scene.instantiate()
    debug_panel.set_game_engine(game_engine)
    add_child(debug_panel)
    debug_panel.hide()

func _input(event: InputEvent) -> void:
    # ~ 键切换调试面板
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_QUOTELEFT:
            if debug_panel:
                debug_panel.visible = not debug_panel.visible
```

#### 4.3.2 修改 debug_flags.gd

```gdscript
# 添加调试面板相关信号
signal debug_panel_toggled(visible: bool)
signal debug_setting_changed(setting: String, value: Variant)

# 添加更多调试选项
var show_grid_coords: bool = false
var show_entity_ids: bool = false
var show_collision_boxes: bool = false
var show_fps: bool = false
```

---

## 5. 实现优先级

### Phase 1: 基础框架 (高优先级)

1. 创建 `debug_panel.tscn` 基础布局
2. 实现命令输入和执行框架
3. 实现状态标签页的基础显示
4. 集成到游戏主场景

### Phase 2: 命令系统 (高优先级)

1. 实现 `DebugCommandRegistry`
2. 实现基础命令：`help`, `state`, `advance`, `skip`
3. 实现命令历史和上下箭头浏览
4. 实现基础自动补全

### Phase 3: 状态查看增强 (中优先级)

1. 实现可折叠的状态区域
2. 添加玩家详细信息显示
3. 添加地图状态显示
4. 实现实时刷新

### Phase 4: 实体检查器 (中优先级)

1. 实现实体树组件
2. 实现属性查看器
3. 添加实体搜索功能

### Phase 5: 高级功能 (低优先级)

1. 实现属性编辑功能
2. 实现快照/恢复功能
3. 实现命令导出/导入
4. 实现性能分析面板

---

## 6. UI 样式指南

### 6.1 颜色方案

```gdscript
const COLORS = {
    "background": Color(0.1, 0.1, 0.12, 0.95),
    "panel": Color(0.15, 0.15, 0.18),
    "text": Color(0.9, 0.9, 0.9),
    "text_dim": Color(0.6, 0.6, 0.6),
    "accent": Color(0.3, 0.6, 0.9),
    "success": Color(0.3, 0.8, 0.3),
    "warning": Color(0.9, 0.7, 0.2),
    "error": Color(0.9, 0.3, 0.3),
    "command": Color(0.5, 0.8, 1.0),
    "system": Color(0.7, 0.7, 0.7),
}
```

### 6.2 字体

- 使用等宽字体 (Monospace) 以便对齐
- 推荐：JetBrains Mono, Fira Code, 或 Godot 默认等宽字体

### 6.3 输出格式

```
[INFO] 游戏状态已刷新
[WARN] 玩家金钱不足
[ERROR] 无效的命令参数
[CMD] > advance phase
[RESULT] 阶段已推进到: working
```

---

## 7. 快捷键设计

| 快捷键 | 功能 |
|--------|------|
| `~` | 切换调试面板显示 |
| `Ctrl+Shift+D` | 切换调试模式 |
| `Ctrl+Enter` | 执行命令 |
| `↑` / `↓` | 浏览命令历史 |
| `Tab` | 自动补全 |
| `Ctrl+L` | 清空输出 |
| `Ctrl+S` | 快速保存快照 |
| `Ctrl+Z` | 撤销上一条命令 |
| `Escape` | 关闭调试面板 |

---

## 8. 扩展性考虑

### 8.1 模块化命令注册

允许各个模块注册自己的调试命令：

```gdscript
# 在模块的 entry.gd 中
func register_debug_commands(registry: DebugCommandRegistry) -> void:
    registry.register("coffee_status", _cmd_coffee_status, "显示咖啡模块状态")
    registry.register("spawn_coffee", _cmd_spawn_coffee, "生成咖啡")
```

### 8.2 插件支持

预留插件接口，允许添加自定义标签页：

```gdscript
func register_tab(tab_name: String, tab_scene: PackedScene) -> void
func unregister_tab(tab_name: String) -> void
```

---

## 9. 测试计划

### 9.1 单元测试

- 命令解析器测试
- 命令注册/执行测试
- 状态格式化测试

### 9.2 集成测试

- 调试面板与游戏引擎的交互
- 命令执行对游戏状态的影响
- UI 响应和刷新

### 9.3 手动测试清单

- [ ] 调试面板可以正常打开/关闭
- [ ] 所有标签页可以正常切换
- [ ] 命令输入和执行正常工作
- [ ] 状态显示实时更新
- [ ] 快捷键全部生效
- [ ] 在各种游戏阶段都能正常使用

---

## 10. 参考资料

- Godot 4 Window 和 TabContainer 文档
- 星露谷物语调试控制台分析
- Factorio 控制台命令系统
- Unity Debug Console 实现参考

---

## 11. 设计评审与实现进度（2026-01-08）

> 本节用于把“设计 → 当前实现”的差距、风险与落地清单记录在案，并作为后续执行的进度表。  
> 说明：以下结论基于静态代码审查（未运行 Godot 验证）。

### 11.1 评审结论（摘要）

1. **设计整体合理**：从“现状缺陷 → 分阶段目标 → 文件结构/核心类 → 集成与测试计划”的组织方式可执行。
2. **当前实现已覆盖 Phase 1–3 的大部分**：已具备 DebugPanel（Window + TabContainer + 命令输入 + 状态栏）、DebugCommandRegistry、State/Command/Entity/History/Settings 五类标签页骨架与多组命令。
3. **存在 P0 阻断问题**：`EntityTab` 脚本存在语法错误，可能导致调试面板场景无法实例化。
4. **存在 P0 架构风险**：部分调试命令直接改 `GameState`，绕过 `GameEngine.execute_command()` 的命令历史/回放/不变量校验体系，需尽快收敛。

### 11.2 设计要求对照（核心条目）

| 设计项 | 设计位置 | 当前实现 | 备注 |
|------|----------|----------|------|
| 调试面板 Window + TabContainer + 底部命令输入 + 状态栏 | 2.2 / 4.2.2 | `ui/scenes/debug/debug_panel.tscn` / `ui/scenes/debug/debug_panel.gd` | ✅ 已实现 |
| 命令注册/解析/帮助/补全 | 3.x / 4.2.1 | `core/debug/debug_command_registry.gd` | ✅ 已实现（补全为“命令名级别”最小可用） |
| State 标签页（可折叠区块） | 2.3.1 | `ui/scenes/debug/tabs/state_tab.gd` | ✅ 已实现（玩家展开为占位） |
| Command 标签页（快捷按钮 + 参数弹窗） | 2.3.2 | `ui/scenes/debug/tabs/command_tab.gd` / `ui/scenes/debug/components/param_dialog.gd` | ✅ 已实现 |
| Entity 标签页（实体树 + 详情） | 2.3.3 | `ui/scenes/debug/tabs/entity_tab.gd` | ⚠️ 当前存在语法错误，需修复 |
| History 标签页（命令历史 + 导出 + 过滤） | 2.3.4 | `ui/scenes/debug/tabs/history_tab.gd` | ✅ 已实现（未覆盖“游戏日志/跳转”等扩展项） |
| Settings 标签页（调试开关/快捷键说明） | 2.3.5 | `ui/scenes/debug/tabs/settings_tab.gd` / `autoload/debug_flags.gd` | ⚠️ 存在状态同步与“面板显示”语义不一致风险 |
| 与 `game.gd` 集成（`~` 切换） | 4.3.1 | `ui/scenes/game/game.gd` | ✅ 已实现 |

### 11.3 问题与改进清单（按优先级）

- [x] **P0 / 阻断**：修复 `ui/scenes/debug/tabs/entity_tab.gd` 的语法错误（当前 `inst.get("position", )` 会导致脚本解析失败）。
- [x] **P0 / 架构一致性**：禁止调试命令直接修改 `GameState`（例如 `give_money` / `set_phase` 的 fallback/实现），所有状态变更必须通过 `GameEngine.execute_command()`（必要时增加内部 debug action）。
- [x] **P1 / 交互一致性**：统一 `~` 的“面板显示”单一真相（`game.gd` 与 `DebugFlags.show_console` 目前可能不同步），并使 Settings 的“显示控制台”能真实驱动面板显示。
- [x] **P1 / 设置同步**：`DebugFlags.enable_debug()` 会连带修改 `verbose_logging` 等；SettingsTab 的复选框需在切换后重新同步，避免 UI 与实际 flag 漂移。
- [x] **P2 / 体验对齐**：补齐标签页标题/命名与文档一致（状态/命令/实体/历史/设置），并补齐/明确快捷键的实际落地范围（焦点冲突、LineEdit 行为等）。
- [x] **P2 / 功能增强**：自动补全扩展到参数提示/历史建议（在不引入复杂依赖的前提下逐步增强）。

### 11.4 执行记录（每完成一项在此打勾并补充说明）

- 2026-01-08：建立清单与基线审查（本节）。
- 2026-01-08：✅ 修复 EntityTab 语法错误（`ui/scenes/debug/tabs/entity_tab.gd`）。
- 2026-01-08：✅ `give_money/set_phase/next_round` 收敛到引擎命令体系（新增 `debug_give_money` 内部 action，并移除直接修改 `GameState` 的实现）。
- 2026-01-08：✅ `~`/Settings 驱动调试面板显示：以 `DebugFlags.show_console` 为单一真相，Game 监听 `debug_panel_toggled`；关闭面板（Esc/窗口关闭）会回写开关并同步 UI。
- 2026-01-08：TabContainer 标签标题已对齐（输出/状态/命令/实体/历史/设置）。
- 2026-01-08：✅ 补齐调试面板快捷键：Ctrl+S 快照、Ctrl+Z/Ctrl+Shift+Z 撤销重做、Ctrl+Enter 执行（并在 SettingsTab 同步说明；撤销/重做默认避开输入框焦点冲突）。
- 2026-01-08：✅ Headless 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（passed=71/71）。
- 2026-01-08：✅ 自动补全增强：Tab 支持“公共前缀扩展”与“参数提示（usage/arg_hints 输出）”。
- 2026-01-08：✅ Headless 回归（复跑）：AllTests 通过（用于验证自动补全改动）。
