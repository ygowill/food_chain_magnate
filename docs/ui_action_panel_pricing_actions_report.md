# 主 UI 动作面板：定价/折扣/奢侈品定价按钮常驻问题报告与整改方案

> 结论摘要：问题根因是 `ActionPanel` 以“阶段可用动作”渲染按钮，导致 **`set_price/set_discount/set_luxury_price` 在 Working 期间对所有玩家都被渲染**；尽管玩法层会把“无员工/非当前回合/已完成”的情况校验失败并灰显，但 **UI 仍常驻展示**，造成困惑。  
> 本次已采取最小整改：对上述 3 个“员工驱动强制动作”，当 `ActionRegistry` 判定 **当前玩家不可启动** 时 **不展示该按钮**（避免按钮常驻）。并已回归通过全量 headless tests（`72/72 PASS`）。

---

## 1. 问题描述

在主游戏场景右侧 `ActionPanel`（可用动作列表）中，玩家在未拥有对应员工（折扣经理 / 奢侈品经理）时，依然会长期看到：

- `设定折扣`（`set_discount`）
- `设定奢侈品价格`（`set_luxury_price`）

常见表现为按钮被灰显但仍占位，且在 Working 的各个子阶段都存在。

### 1.1 影响

- **认知噪音**：玩家会误以为“我漏了什么操作/规则”，尤其是新局尚未招到相关员工时。
- **误导阶段感**：玩家会误以为当前进入了“定价/折扣/奢侈品定价”的环节（尽管规则中这些是“强制动作”，并不对应 Working 子阶段枚举）。
- **UI 可用动作与可执行动作不一致**：列表展示的是“阶段可用”，但玩家理解通常是“当前可做”。

---

## 2. 复现路径（现象）

1. 进入主游戏 `ui/scenes/game/game.tscn`
2. 推进到 `Working` 任一子阶段（如 `Recruit/Train/...`）
3. 在未拥有 `discount_manager` / `luxury_manager` 的情况下，观察右侧 `ActionPanel`
4. 可看到对应按钮长期存在（通常为灰显）

---

## 3. 根因分析（为什么会“常驻显示”）

### 3.1 UI 层：ActionPanel 的渲染策略

`ui/components/action_panel/action_panel.gd` 的 `refresh()` 使用：

- `ActionRegistry.get_available_actions(state)` 作为 **展示列表**（phase/sub_phase gating）
- `ActionRegistry.get_player_initiatable_actions(state, player_id)` 作为 **是否灰显** 的依据

这意味着：只要某个 action 在该阶段“可用”，就会被渲染为按钮；即使当前玩家不具备执行条件（例如没有员工），也只是被灰显，并不会从列表移除。

### 3.2 规则/玩法层：set_* 动作为“Working 可用”（不按子阶段区分）

`gameplay/actions/set_price_action.gd`、`set_discount_action.gd`、`set_luxury_price_action.gd` 均配置：

- `allowed_phases = ["Working"]`
- `allowed_sub_phases = []`（意味着 Working 任意子阶段都视为可用点位）

因此在 **整个 Working 期间**，这 3 个 action 都会被 `get_available_actions` 列出，从而导致 UI 常驻。

### 3.3 “为什么会灰显”：validate 的玩家条件

以 `set_discount` 为例，`validate` 会检查：

- 是否当前玩家回合
- 玩家是否拥有 `EmployeeDef.mandatory_action_id == "set_discount"` 的员工（即 `discount_manager`）
- 本回合是否已完成

所以“没员工”的局面下按钮会被灰显，但仍会被 UI 渲染出来。

---

## 4. 对这几个功能实现的合理性审查（结论：整体合理，但 UI 表达需调整）

### 4.1 gameplay/actions（合理）

三项动作的玩法层行为一致、可解释、且与项目内既有规则结构对齐：

- 通过 `EmployeeDef.mandatory_action_id` 查找“提供该强制动作的员工”
- 通过 `round_state.mandatory_actions_completed[player_id]` 记录完成情况，确保 **每回合最多一次**
- 将价格修正写入 `round_state.price_modifiers[player_id][provider_employee_id] = delta`
- `PricingPipeline.calculate_unit_price()` 在结算时叠加 `price_modifiers`
- `skip/skip_sub_phase` 在 Working 最后子阶段会阻止玩家结束回合，避免“强制动作未完成导致软锁”

这些点在 `core/tests/mandatory_actions_test.gd` 中已有覆盖（以 `set_price` 为例）。

### 4.2 UI：PriceSettingPanel（合理但“语义是确认面板”）

`ui/components/price_panel/price_setting_panel.gd` 当前是“强制动作确认面板”，不做逐产品定价输入。  
这与 `set_price/set_discount/set_luxury_price` 当前为 **无参数** 动作的设计一致（避免 UI 与 gameplay 语义冲突）。

### 4.3 不合理点（主要是体验）

- `ActionPanel` 将“阶段可用”直接等同于“当前玩家可用动作”，导致员工驱动型强制动作对无员工玩家长期占位展示。

---

## 5. 已落地整改（最小、安全、可回归）

### 5.1 改动内容

在 `ui/components/action_panel/action_panel.gd` 中新增过滤规则：

- 对 `set_price/set_discount/set_luxury_price`：
  - 若能计算“当前玩家可启动动作”（`get_player_initiatable_actions/get_player_available_actions` 可用）
  - 且该 action **不在可启动列表**中
  - 则 **不在 ActionPanel 展示该按钮**

### 5.2 预期行为（整改后）

- 玩家未拥有对应经理员工时：按钮不出现（不再常驻灰显占位）
- 玩家拥有对应经理员工、且本回合未完成：按钮出现且可点击
- 玩家已完成该强制动作：按钮消失（因为不再“可启动”）

### 5.3 回归验证

- 已运行：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
- 结果：`[AllTests] SUMMARY passed=72/72`

---

## 6. 建议的后续优化（可选）

> 本节不属于本次最小整改，但可显著提升可理解性。

1. **在 ActionPanel 内分组展示**：
   - “强制动作（未完成）”置顶并高亮
   - “可选动作”按阶段/子阶段展示
2. **对灰显按钮展示失败原因**：
   - UI hover 时显示 validate 的错误原因（例如“招聘次数已用完/不是你的回合/缺货预支待清账”等）
3. **强制动作入口与阻塞提示联动**：
   - 当玩家在 Working 最后子阶段尝试结束但被阻塞时，弹出提示并直接引导到未完成强制动作按钮/面板

