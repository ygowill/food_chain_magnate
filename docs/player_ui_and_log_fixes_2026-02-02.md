# 玩家日志与面板修复清单（2026-02-02）

> 范围：玩家晚餐售出日志、动作面板、玩家信息面板、日志回放播放器、调试/命令面板。  
> 约定：每项修复或更新后，运行 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`；通过后更新本文档并提交 git。  
> 状态字段：`TODO / DOING / DONE / BLOCKED`。

---

## 1. 晚餐售出后的现金变化事件需要展示“来源明细”

- 状态：DONE
- 现象：晚餐时间售出日志后跟随的现金变化事件日志仅展示总收入，不展示收入构成。
- 期望：现金变化事件日志除“收入金额”外，还需展示来源明细（例如：食物售价、花园加成、公园加成、CFO 加成等）。
- 实施：
	- 晚餐结算 `sale_house_bonus` 记录 `house_bonus_breakdown`（当前覆盖：公园、薯条厨师）。
	- 进入 Dinnertime 时的 `PLAYER_CASH_CHANGED` 事件附带 `income_breakdown`，并在日志中展示“晚餐收入来源：...”
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(log): add dinnertime income breakdown to cash events`

---

## 3. 动作面板“生产食物”不应使用下拉框，应直接展示可点选的食物图标

- 状态：DONE
- 现象：生产食物时通过下拉框选择食物类型，交互效率低且不直观。
- 期望：直接显示食物图标（可点击选择），并保持 headless 测试可跑。
- 实施：
	- `ProductionPanel` 中“多食物可选”（见习厨师）改为图标按钮选择；使用 `UiSkinCache` 的 product_icons，支持 tooltip。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(ui): replace produce-food dropdown with icon picker`

---

## 4. 玩家信息面板左侧图标复用“玩家顺位中的餐厅图标”，保持同样背景色并正确缩放

- 状态：DONE
- 现象：玩家信息面板左侧图标与顺位轨（玩家顺位）餐厅图标样式不一致；缩放可能超出范围。
- 期望：复用同一套餐厅图标组件/样式（含背景色），并在信息面板既定区域内自适应缩放不溢出。
- 实施：
	- 玩家 tab 使用同一餐厅 logo 贴图来源，并对齐顺位轨的浅色背景与图标缩放策略。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(ui): move player restaurant tabs to top and match turn-order style`

---

## 5. 玩家信息面板左侧的“餐厅图标 tab”应移动到信息面板上方，横向排列

- 状态：DONE
- 现象：餐厅图标 tab 位于信息面板左侧区域，信息架构不理想。
- 期望：将 tab 放到信息面板上方，横向排列，并保持现有切换逻辑可用。
- 实施：
	- `LeftPanel` 的玩家 tab 从左侧纵向改为面板顶部横向排列。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(ui): move player restaurant tabs to top and match turn-order style`

---

## 6. 日志面板“回放播放器”宽度溢出导致横向滚动/裁切问题

- 状态：DONE
- 现象：回放播放器宽度大于日志面板，导致横向溢出。
- 期望：回放播放器不应超过日志面板可用宽度（必要时自适应或换行），避免横向溢出。
- 实施：
	- 回放条改为可换行布局（窄宽度下自动折行），避免撑出日志面板宽度。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(ui): prevent replay bar overflow in log panel`

---

## 7. 调试/命令面板：玩家相关命令必须显式指定玩家；对象选择应改为下拉框列出当前游戏可用项

- 状态：DONE
- 现象：
	- 玩家相关命令（例如生产食物等）依赖“面板当前玩家”隐式状态，易误操作。
	- 给房屋添加花园、广告牌等命令需要手动输入目标，缺少“从当前游戏可用对象中选择”的 UI。
- 期望：
	- 所有玩家相关命令均提供 `player` 参数（下拉/输入）并以该参数为准，不依赖面板内部“当前玩家”。
	- 房屋/广告牌等目标对象选择使用下拉框展示当前局可用对象（参考动作面板实现并尽量复用）。
- 已澄清（按你的最新要求实现）：
	- `player` 参数：必须显式提供；不允许“当前玩家”；允许输入“顺位 1..N”，也允许直接输入 `player_id`。
	- `player` 必须写进命令参数本身（按钮/弹窗提交的命令行必须包含 player 参数）。
	- 彻底移除命令面板顶部的“目标玩家”选择器（也不再在参数弹窗内提供“目标玩家”选择）。
	- 房屋下拉展示格式：`房号 + house_id + 坐标`。
	- marketing 下拉展示：`board_number + type + 尺寸(footprint_size)`。
	- 若当前没有可选对象：仍允许执行；执行后报错（不要通过禁用按钮来阻止执行）。
- 实施：
	- 彻底移除命令面板顶部“目标玩家”选择器与参数弹窗内“目标玩家”选择。
	- 所有玩家相关命令改为显式携带 `player` 参数；默认按“玩家顺位 1..N”解析（也支持 `id:<player_id>` / `pid:<player_id>`）。
	- 房屋相关命令（添加花园/加需求）使用房屋下拉框：展示 `房号 + house_id + 坐标`，提交时写入 `house_id`。
	- marketing 使用板件下拉框：展示 `#board_number type (wxh)`，并过滤当前玩家数下移除/已放置的板件。
	- 每次执行命令后刷新 CommandTab，使下拉选项保持“当前对局可用”的最新状态。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(debug): require explicit player args in command panel`

---

## 8. 顶部工具栏：供应堆与里程碑无法打开

- 状态：DONE
- 现象：游戏最上方工具栏中的供应堆与里程碑入口点击后无响应/无法打开。
- 期望：点击后正确打开对应面板/弹窗，并保持 headless 测试稳定。
- 实施：
	- 顶部工具栏打开“里程碑/供应堆”时，将对应全屏视图强制设为 `FULL_RECT`（anchors/offset/size），避免 0 尺寸导致“看起来打不开”。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（PASS 141/141）
- 提交：`fix(ui): make topbar milestone/supply views fullscreen`

---

## 9. 地图公园与花园背景色不应有透明度

- 状态：TODO
- 现象：公园与花园的背景色存在透明度（alpha < 1），视觉上“发灰/透底”。
- 期望：公园与花园背景色为完全不透明（alpha = 1）。
- 验证：待补充
- 提交：待补充
