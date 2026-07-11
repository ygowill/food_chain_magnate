---
id: F-003
doc_kind: feature
status: in-progress
created: 2026-05-03
updated: 2026-07-11
owners: [player-experience]
requirement_ids: [REQ-005, REQ-006, REQ-007, REQ-008, NFR-005]
decision_refs: []
validation_refs: [docs/validation/VAL-2026-001-all-tests-baseline.md]
review_after: 2026-10-11
---

# F-003：Tutorial Campaign

## 当前结论

主菜单可进入教学战役参考场景，基础规则与扩展模块已有真实素材、地图示例和章节导航；Setup/Game 也已有教学局预设、运行时约束、spotlight 与流程提示。完整设计中的多关卡可操作战役、逐关目标判定、复盘和综合实战尚未全部实现或验收，因此 Feature 保持 in-progress。

## 背景、目标与范围

目标是让第一次接触游戏的玩家通过可视化示例与受控教学局理解开局、公司结构、营销、晚餐结算、地图对象和主要扩展规则，而不是只阅读卡牌文字。

当前范围包括教学战役参考页、真实资产预览、Setup 教学预设、Game 内上下文导览与第一回合关键动作约束。目标范围还包括设计文档中的基础学院关卡、扩展学院和综合实战。

Non-goals：

- 不把教学是否启用或已看进度持久化到用户设置。
- 不让教学状态进入 core 对局真相或污染普通局、回放和读档。
- 不用静态 tooltip 替代流程教学，也不把 tooltip 与 spotlight 的职责合并。
- 不把教学文案当作规则权威源；规则变化必须先更新代码、规则测试和 Architecture。

## Requirements 与验收标准

这些 Requirement ID 的规范性定义来自[项目级需求](../REQUIREMENTS.md)；本页只维护 F-003 的验收解释、判定与证物映射。

| ID | Requirement / AC | 判定 | 证物 |
|---|---|---|---|
| REQ-005 | 教学覆盖 Setup、储备卡、公司结构、距离、营销、晚餐、收入与银行破产的完整基础规则链 | not-covered | [Tutorial Campaign scene](../../ui/scenes/tutorial_campaign/tutorial_campaign.tscn) 与[资产加载测试](../../ui/scenes/tests/tutorial_campaign_assets_loaded_test.gd)证明参考素材存在；尚无覆盖整条规则链的可操作关卡与 E2E |
| REQ-006 | 提示在玩家执行对应操作时出现，并指向当前真实可见的 UI 与规则状态 | not-covered | [Setup target contract](../../ui/scenes/tests/setup_tutorial_targets_contract_test.gd)与[Game target contract](../../ui/scenes/tests/game_tutorial_targets_contract_test.gd)只证明目标节点契约；尚未证明所有关键动作的触发时机和可完成性 |
| REQ-007 | 扩展模块教学与基础规则分层，并明确行为来自哪个启用模块 | not-covered | 当前参考页已有基础/扩展章节与 Setup 模块入口，但缺少提交绑定的用户路径验收，不能据静态章节判 pass |
| REQ-008 | 基础学院、扩展专题、逐关目标、复盘与综合实战形成可操作且可验收的完整战役 | not-covered | 当前代码以参考章节和首回合教学局为主；尚无覆盖全部设计关卡的关卡状态机与 E2E 验收 |
| NFR-005 | 教学预设、提示和约束只在显式教学运行时启用，不进入 core 真相，也不污染普通局、回放和读档 | pass | [Runtime scope 测试](../../ui/scenes/tests/tutorial_runtime_scope_test.gd)、[Tutorial match runtime 测试](../../ui/scenes/tests/tutorial_match_runtime_test.gd)、[场景边界测试](../../ui/scenes/tests/tutorial_scene_boundary_contract_test.gd) |

## Related Artifacts

### 原始需求与设计意图

- [项目级 Requirements](../REQUIREMENTS.md) 定义 REQ-005 至 REQ-008 与 NFR-005。
- [教学战役设计方案](../design/tutorial_campaign_design_2026-05-03.md) 是目标范围与课程结构来源。
- [早期 Tutorial / Onboarding 设计](../tutorial_onboarding_design.md) 是历史背景；当前实现边界以 Architecture 为准。

### Decisions

当前没有专属 ADR。若后续引入可持久化进度、规则脚本 DSL、独立存档格式或改变 core/UI 边界，必须先创建 ADR 并关联 F-003。

### Architecture

- [Onboarding / 教学系统当前架构](../architecture/22-ui-onboarding-tutorials.md)
- [UI 场景与导航](../architecture/20-ui.md)
- [测试架构](../architecture/52-testing.md)

### Plans

- [教学战役设计方案的技术落地章节](../design/tutorial_campaign_design_2026-05-03.md) 同时记录了现有实施建议，但不是活跃 Plan 的状态源。
- 当前没有独立、带状态的活跃 Plan。继续实现 REQ-007 前应从未交付关卡生成新的 Plan，而不是继续向设计正文追加执行日志。

### Code

- [Tutorial Campaign scene script](../../ui/scenes/tutorial_campaign/tutorial_campaign.gd)
- [Tutorial Campaign scene](../../ui/scenes/tutorial_campaign/tutorial_campaign.tscn)
- [通用 Tutorial controller](../../ui/tutorial/tutorial_controller.gd)
- [Setup 教学预设](../../ui/scenes/setup/controllers/tutorial_match_preset.gd)
- [Game 教学运行时约束](../../ui/scenes/game/controllers/tutorial_match_runtime.gd)
- [Game 教学 controller](../../ui/scenes/game/controllers/tutorials_controller.gd)
- [运行时标记](../../autoload/globals.gd)

### Tests and Validation

- [Campaign assets loaded](../../ui/scenes/tests/tutorial_campaign_assets_loaded_test.gd)
- [Tutorial runtime scope](../../ui/scenes/tests/tutorial_runtime_scope_test.gd)
- [Tutorial match runtime](../../ui/scenes/tests/tutorial_match_runtime_test.gd)
- [Setup target contract](../../ui/scenes/tests/setup_tutorial_targets_contract_test.gd)
- [Game target contract](../../ui/scenes/tests/game_tutorial_targets_contract_test.gd)
- [Scene boundary contract](../../ui/scenes/tests/tutorial_scene_boundary_contract_test.gd)
- [2026-07-11 AllTests 基线](../validation/VAL-2026-001-all-tests-baseline.md)

## 已知限制与偏差

- Tutorial Campaign 主脚本体量很大，当前把大量章节数据、预览构造和 UI 渲染放在同一脚本中，后续扩展前应拆分数据与渲染职责。
- 现有自动化主要覆盖资产、目标节点、运行时边界和少量教学 gate；没有证明所有章节可在不同窗口尺寸、语言和输入方式下完成。
- 设计中的 18 个基础关卡、扩展专题和综合实战尚未形成完整可玩的关卡流程。
- 没有当前提交绑定的用户可用性测试、截图序列或人工验收记录。

## Next Action

- player-experience：为 REQ-005 至 REQ-008 建立带 owner 和 AC 的实施 Plan，优先交付基础学院最小闭环，而不是继续扩充静态参考章节。
- quality-engineering：为主菜单进入、章节遍历、教学局开始和退出增加 headless 场景 E2E，并记录多分辨率人工验收证物。
