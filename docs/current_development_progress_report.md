# 当前开发进度与未开发缺口（工作区快照：2026-01-09）

> 目的：基于“当前工作区代码 + 现有开发文档 + 可验证日志”，梳理 **已经闭环可玩的能力**、**仍未开发/未闭环的缺口**，并给出每一项的验证入口与推荐下一步。

---

## 1. 信息源与可信度（建议阅读顺序）

1. `docs/development_progress_audit.md`：进度审计（偏“现在能验证什么/还缺什么”）
2. `docs/ui_remediation_plan.md`：UI 接线整改记录（以 code/测试可验证为准）
3. `docs/ui_development_plan.md`：UI 分阶段计划与组件清单（**个别段落存在历史结论，需以 1/2 为准**）
4. `docs/development_status.md`：里程碑/变更日志（最后更新较早，需注意时效）
5. `.godot/AllTests.log` / `.godot/GameSmokeTest.log`：本地 headless 验证日志

---

## 2. 可验证基线（当前工作区）

- 逻辑全量测试：`.godot/AllTests.log` 显示 `passed=72/72`（`[AllTests] SUMMARY passed=72/72`）
- 游戏场景冒烟：`.godot/GameSmokeTest.log` 显示 `[GameSmokeTest] PASS`
- 行为验证入口（手动）：运行 `godot --path .`，从主菜单新游戏进入 `ui/scenes/game/game.tscn`

> 备注：`GameSmokeTest` 退出时存在 Godot 资源泄漏/未释放告警（不影响 PASS，但建议作为技术债跟进，见第 6.3 节）。

---

## 3. 已闭环可玩的范围（按阶段/子阶段）

> 说明：这里的“闭环”指 **UI 能产生 Command** 且通过 `gameplay/actions/*` 校验，`game_engine.execute_command()` 可执行并刷新 UI；并且 headless smoke test 不报 SCRIPT ERROR。

### 3.1 Setup（开局）

- 入口：右侧 `ActionPanel` 触发 `place_restaurant`，进入地图选点覆盖层
- 覆盖层：`ui/components/restaurant_placement/restaurant_placement_overlay.tscn`
- 调度：`ui/scenes/game/game_panel_placement_overlays.gd`

### 3.2 Restructuring（重组公司）

- 入口：底部 `HandArea` 拖拽员工在“在岗/待命”之间切换；在公司结构面板中拖拽设置 CEO 直属/经理下属
- 相关命令：
  - `restructure_employee`
  - `set_company_structure_direct`
  - `set_company_structure_report`
  - `submit_restructuring`（需全员提交后才能离开阶段）
- 主要接线：`ui/scenes/game/game_panel_controller.gd`（`_on_hand_card_dropped`）

### 3.3 OrderOfBusiness（决定顺序）

- 入口：右侧 `TurnOrderTrack` 点击空位
- 命令：`choose_turn_order`
- 主要接线：`ui/scenes/game/game_panel_controller.gd:_on_turn_order_position_selected`

### 3.4 Working（9-5 工作时间）

#### Recruit

- 面板：`ui/components/recruit_panel/`
- 接线：`ui/scenes/game/game_panel_working_panels.gd:show_recruit_panel`
- 命令：`recruit`

#### Train

- 面板：`ui/components/train_panel/`
- 接线：`ui/scenes/game/game_panel_working_panels.gd:show_train_panel`
- 命令：`train`
- 已支持：`round_state.immediate_train_pending`（缺货预支待清账）与 `train_from_active_same_color`（在岗同色来源）

#### Marketing

- 面板：`ui/components/marketing_panel/`（地图选点回填 + 可用营销员/板件）
- 接线：`ui/scenes/game/game_panel_marketing_panels.gd`
- 命令：`initiate_marketing`
- 预览：`ui/overlays/marketing_range_overlay.gd`（hover/选点范围显示）

#### GetFood / GetDrinks

- 面板：`ui/components/production_panel/`
- 接线：`ui/scenes/game/game_panel_working_panels.gd:show_production_panel`
- 命令：`produce_food` / `procure_drinks`
- 已支持：`GetDrinks` 选择采购员后显示“自动路线预览”
  - 可视化：`ui/overlays/procurement_route_overlay.gd`
  - 触发：`ui/scenes/game/game_panel_working_panels.gd:_on_producer_changed`

#### PlaceHouses / PlaceRestaurants

- 覆盖层：
  - `ui/components/house_placement/house_placement_overlay.tscn`
  - `ui/components/restaurant_placement/restaurant_placement_overlay.tscn`
- 接线：`ui/scenes/game/game_panel_placement_overlays.gd`
- 命令：`place_house` / `add_garden` / `place_restaurant` / `move_restaurant`
- 已支持：有效位置扫描/高亮（PlacementValidator 扫描）

### 3.5 Dinnertime（晚餐结算）

- 展示：自动弹出 `ui/components/dinner_time/`（只读列表）
- 需求指示：`ui/components/demand_indicator/`（已成交需求标记）
- 主要调度：`ui/scenes/game/game_overlay_controller.gd` + `ui/scenes/game/game_overlay_dinnertime.gd`

### 3.6 Payday（发薪日）

- 面板：`ui/components/payday_panel/`
- 入口：右侧 `ActionPanel` 点击 `fire`（打开发薪日面板）
- 命令：`fire`（可多次）+ 系统 `advance_phase`（确认支付后推进）
- 主要调度：`ui/scenes/game/game_panel_end_panels.gd`

### 3.7 Marketing Settlement / Cleanup / GameOver

- Marketing/Cleanup：当前以引擎自动结算为主（UI 侧以信息展示/日志为主）
- GameOver：进入阶段后自动弹出 `ui/components/game_over/`

---

## 4. UI 开发进度（对照 `docs/ui_development_plan.md` 的 8.*）

> 结论：P0/P1 的“可玩闭环”已完成；P2 多数为“已实现但缺入口/缺数据源/未被调用”的增强项。

### 4.1 P0（已接入，12/12）

- 玩家信息、员工卡/手牌、公司结构、顺序轨、库存、动作面板
- 招聘/培训/发薪日/游戏结束/银行破产 UI

### 4.2 P1（已接入，8/8）

- 营销面板与地图选点、强制动作定价确认、生产/采购
- 房屋/餐厅放置（含高亮）
- 里程碑面板（只读入口：游戏菜单 → 里程碑）
- 晚餐展示与需求指示器

### 4.3 P2（已接入 8/8）

已接入：

- `settings_dialog`（主菜单 + 游戏内菜单）
- `game_log_panel`（游戏内菜单切换显示）
- `distance_overlay`（距离工具）
- `marketing_range_overlay`（营销范围预览）
- `help_tooltip_manager`（基础帮助提示：hover 关键 UI 元素显示说明）
- `ui_animation_manager`（弹窗居中后触发基础 bounce；headless 下禁用）
- `confirm_dialog`（危险操作二次确认：返回主菜单）
- `replay_player`（游戏菜单 → 回放播放器；默认加载 `user://savegame.json`，支持从 `user://` 列表切换加载）

---

## 5. 仍未开发 / 未闭环清单（建议按优先级）

### 5.1 P0 阻塞项

- 当前未发现“阻塞可玩闭环”的 P0 缺口（headless 全量测试与游戏场景冒烟均通过）。

### 5.2 P1 体验/信息缺口（不阻塞，但会影响可玩性或可理解性）

- **存档/回放 UX 不完整**：目前更偏“开发调试入口”（仍缺多存档槽管理/回放时间线/文件系统选择 UI）。
  - 已有最小入口：游戏菜单 → 回放播放器（默认加载 `user://savegame.json`；播放器内可从 `user://` 存档列表切换加载）

### 5.3 P2 增强项（已实现但未接入/未使用）

- **音效系统未接入**：`ui/audio/*` 存在 Sound/Music 管理器与初始化器，但未被主菜单/游戏场景加载，UI/动作也未触发音效。

### 5.4 规则/内容层缺口（非 UI）

- **6 人地图生成未实现**：`modules/base_rules/rules/phase_and_map.gd` 明确返回 failure（需要后续扩展模块/生成器）。
- **抽象校验器基类占位**：`gameplay/validators/base_validator.gd` 的 `validate()` 返回“未实现”（设计为仅供子类继承；不应被直接实例化）。
- **部分素材为占位**：见 `modules/movie_stars/assets/map/icons/README.md`（缺少若干 png）

### 5.5 规则对齐/可选复杂交互（当前明确未做）

- **Restructuring 的“秘密分堆/同时揭示”流程**：当前更偏 hotseat 推进（多玩家同屏），未实现隐藏信息流程。
- **`procure_drinks` 路线手绘规划**：当前由规则自动生成（并已可视化预览）；未实现“画路线/编辑路线”的交互。

---

## 6. 技术债与文档一致性

### 6.1 技术债（建议记录到 backlog）

- `GameSmokeTest` 退出时存在：
  - `ObjectDB instances leaked at exit`
  - `resources still in use at exit`
  这通常意味着场景/资源未正确释放或测试退出时机过快；建议在后续迭代中定位并清理。

### 6.2 文档一致性（避免误读）

- `docs/ui_development_plan.md` 的早期“实现状态审计”段落里仍有“❌ 未实现/完全缺失”的历史结论，但其 8.* 章节与实际代码已大幅更新；建议以：
  - `docs/ui_remediation_plan.md`（整改记录）
  - `docs/development_progress_audit.md`（可验证现状）
  作为“当前事实来源”。
- `docs/development_status.md` 最后更新较早（2026-01-04），与近期 UI 整改与测试基线可能存在时效差异。

---

## 7. 推荐下一步（按“最小增量可验证”排序）

1. **补齐 P2 的“入口/数据源”**（收益高、风险低）  
   - HelpTooltip：✅ 已接入基础入口；下一步补齐更多控件绑定与内容（例如强制动作阻断的常见失败原因）  
   - ConfirmDialog：✅ 已接入“返回主菜单”确认；下一步接“重新开局/强制执行命令”等危险操作  
2. **完善回放 UX（ReplayPlayer）**  
   - 已支持 `user://` 存档列表切换加载；下一步补“多存档槽/回放时间线/文件系统选择”  
3. **音效系统最小接线**  
   - 先接 UI 点击/面板打开，确保不会影响 headless（可在 DebugFlags 下禁用）  
4. **决定是否要做两项“规则复杂交互”**  
   - Restructuring 的隐藏信息流程  
   - procure_drinks 路线手绘规划  
5. **若目标包含 6 人局**：补齐 6 人地图生成（或引入扩展模块作为生成器）

---

## 8. 快速验证命令（建议）

```bash
# 全量逻辑测试
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60

# 游戏场景冒烟（加载 game.tscn 并执行最小流程）
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
```

---

## 9. 关键代码索引（便于定位）

- 游戏主场景协调器：`ui/scenes/game/game.gd`
- 阶段/面板调度中枢：`ui/scenes/game/game_panel_controller.gd`
- Working 阶段面板：`ui/scenes/game/game_panel_working_panels.gd`
- Working/Marketing 面板：`ui/scenes/game/game_panel_marketing_panels.gd`
- 放置覆盖层：`ui/scenes/game/game_panel_placement_overlays.gd`
- Payday/BankBreak/GameOver：`ui/scenes/game/game_panel_end_panels.gd`
- 覆盖层（dinnertime/distance/range/zoom）：`ui/scenes/game/game_overlay_controller.gd`
