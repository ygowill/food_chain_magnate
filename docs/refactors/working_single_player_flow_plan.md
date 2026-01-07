# Working 重构：单玩家走完整个 Working + 子阶段自动跳过 + 事件日志面板（计划）

## 已确认需求（来自你的 A-D 回复）

- **A**：阶段“无玩家操作自动跳过”暂时只做成**首轮**，但设计要保留未来扩展为通用规则的可能性。
- **B**：`OrderOfBusiness` 仅在**首轮**自动跳过（自动决定顺序）。
- **C**：`Working/PlaceRestaurants` 子阶段的“跳过子阶段”允许等价于“确认结束”（结束该玩家 Working 回合）。
- **D**：结算阶段默认自动跳过；并在游戏主界面左侧新增一列“事件日志”，展示动作/阶段变化与结算结果等信息。

## 背景问题

当前实现与目标不一致：

1) UI 每次动作成功后会自动 `end_turn`，导致玩家无法“显式确认结束”。
2) 部分阶段（首轮 Restructuring / OrderOfBusiness、以及结算阶段）没有玩家操作，但需要手动推进/确认，体验不佳。
3) Working 当前为“按子阶段轮转玩家”，而目标是“单个玩家一次走完所有子阶段”，且子阶段内若无可做动作应自动跳过。
4) 游戏缺少可视化事件/结算输出，需要 UI 事件日志面板辅助理解与调试。

## 目标行为（落地口径）

### 1) 回合结束：取消自动 end_turn

- 任何玩家动作成功后**不再**自动执行 `end_turn`。
- 玩家回合结束必须通过显式点击“确认结束”（动作 `skip`，显示名保持“确认结束”）触发。

### 2) Setup：必须放置餐厅才能确认结束

- 在 `Setup` 阶段，玩家若未放置过餐厅，则不能执行“确认结束”。

### 3) 首轮无操作阶段自动跳过

- 首轮（`round_number == 1`）自动跳过：
	- `Restructuring -> OrderOfBusiness`
	- `OrderOfBusiness -> Working`
- `OrderOfBusiness` 的顺序决定在首轮采用“自动 finalize”的确定性规则（无玩家交互）。

### 4) 结算阶段默认自动跳过

- 默认自动跳过（无玩家交互）：
	- `Dinnertime -> Payday -> Marketing -> Cleanup -> ...`
- 结算结果需要通过“事件日志面板”可回看，不依赖玩家停留阅读。

### 5) Working：单玩家走完整子阶段序列

- `Working` 阶段由当前玩家一次性按顺序经历所有子阶段：
	`Recruit -> Train -> Marketing -> GetFood -> GetDrinks -> PlaceHouses -> PlaceRestaurants`
- 子阶段内：
	- 若**没有任何可做动作**或**已做完所有可做动作**：系统自动跳到下一子阶段。
	- 若仍有可做动作：显示“跳过子阶段”按钮，允许玩家放弃该子阶段剩余动作并进入下一子阶段。
	- 在最后子阶段 `PlaceRestaurants`，点击“跳过子阶段”可直接等价于“确认结束”（结束该玩家 Working 回合，轮到下一位玩家）。
- 玩家只有在“完成所有子阶段”（或在最后子阶段选择跳过=确认结束）后，才能执行“确认结束”结束自己的 Working 回合。
- 当所有玩家都完成各自的 Working 回合后，自动进入下一阶段（并按 D 默认跳过结算阶段）。

## 实施步骤（每完成一项会更新本文件）

### 1) 取消 UI 自动 end_turn

- [x] `ui/scenes/game/game.gd`：移除 `_execute_command()` 中“动作成功后自动 end_turn”的行为
- [x] 确保回合切换仅由 `skip(确认结束)` 驱动

### 2) UI：事件日志面板

- [x] `ui/scenes/game/game.tscn`：左侧新增日志列（可滚动）
- [x] `ui/scenes/game/game.gd`：订阅 `EventBus`，将事件追加到日志面板
- [x] 为结算结果补齐可观察信息（最少：阶段变化、玩家现金变化；可扩展）

### 3) Core：Setup 确认结束门禁 + 首轮自动跳过 Restructuring/OOB

- [x] `skip_action`：Setup 阶段验证“玩家至少放置 1 个餐厅”才能确认结束
- [x] 首轮自动推进：
	- [x] Restructuring 自动推进到 OrderOfBusiness
	- [x] OrderOfBusiness 自动 finalize，并自动推进到 Working
- [x] 结算阶段默认自动跳过：`Dinnertime -> (停留在 Payday) -> Marketing -> Cleanup -> ...`（Payday 保持可交互）

### 4) Core：Working 单玩家流转 + 子阶段自动跳过

- [x] Working 子阶段推进语义调整：不再“最后子阶段离开 Working”，而是“最后子阶段结束该玩家回合 -> 下一玩家从第 1 子阶段开始”
- [x] 新增/调整“跳过子阶段”动作（支持最后子阶段=确认结束；自动跳过时不自动结束回合）
- [x] 自动跳子阶段：当当前子阶段无可用动作时自动推进到下一子阶段
- [x] `advance_phase(target=sub_phase)` 的规则适配（避免仍要求“所有玩家 pass”）

### 5) UI：动作面板与流程适配

- [x] ActionPanel：根据“当前玩家可做动作”决定是否显示“跳过子阶段”
- [x] Working：当系统自动跳子阶段时 UI 正确刷新（可见日志记录）

### 6) 测试回归

- [x] 更新 `core/tests/test_phase_utils.gd` 等测试辅助，适配新 Working 流程
- [x] 修复受影响用例（不修改员工定义 JSON）
- [x] 运行 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 360`

## 当前进度

- 状态：已完成
- 已确认：A-D 需求口径
