# Architecture 模块审查计划（2026-04-30）

本文档用于规划一次按 `docs/architecture/` 模块索引展开的架构与代码审查。目标不是立即重构，而是先形成可复核的证据链，逐个模块判断是否存在设计不合理、代码冗余、职责划分不清、耦合过深、测试缺口或潜在稳定性风险。

## 审查目标

- 对照 `docs/architecture/README.md` 的模块顺序，逐项检查文档描述、代码实现、测试覆盖是否一致。
- 识别模块边界问题：UI/Autoload/Core/Gameplay/Modules/Server/Backend 是否有反向依赖或职责泄漏。
- 识别冗余与重复：重复校验、重复事件构建、重复状态访问、重复 UI 适配、历史兼容路径长期残留。
- 识别解耦不足：直接访问全局单例、直接读取其他模块私有 state、跨层 preload、server 依赖 UI、core 依赖 autoload 等。
- 识别过度兜底：不该静默回退时返回默认值、吞掉错误、兼容旧字段过久、用 warning 代替 fail-fast、用空集合/空字符串掩盖 schema 或注册缺失。
- 识别潜在稳定性问题：确定性、回放、存档兼容、联机恢复、RoadGraph 缓存、异步 UI 刷新、headless 测试可运行性。
- 输出后续审查报告，建议路径：`docs/reports/general/architecture_module_review_report_2026-04-30.md`。

## 审查原则

- 以文档中声明的边界为准，但以当前代码事实校验文档是否过期。
- 每个问题必须有证据：文件路径、函数/类、调用链、测试缺口或可复现命令。
- 先记录风险与影响，不在审查阶段做大规模重构。
- “过度兜底”默认按 `P2` 记录；如果它可能掩盖 archive/schema/联机同步/权威 server 状态错误，则上调到 `P1` 或 `P0`。
- 分级使用 `P0/P1/P2/P3`：
  - `P0`：可能破坏确定性、读档、联机同步、命令唯一写入口或 headless 测试。
  - `P1`：职责边界明显错误、长期维护成本高、重要路径重复或耦合强。
  - `P2`：局部冗余、命名/组织不清、文档与代码小幅漂移。
  - `P3`：可读性、注释、低风险清理建议。

## 初步优先级依据

以下只是用于安排审查顺序的初扫结果，不作为最终结论：

- 体量较大的高风险文件优先看：`server/room.gd`、`autoload/net_client/server.gd`、`ui/scenes/online/online_lobby.gd`、`ui/scenes/game/game.gd`、`ui/scenes/game/controllers/online_resync_controller.gd`、`ui/components/game_log/game_log_panel.gd`。
- 存在需要重点核实的跨层依赖样本：`autoload/*` 与 `server/*` 中有对 `ui/*` 的 preload；`server/dedicated_server.gd` 多处直接访问 `NetClient._room_manager` 内部字段。
- `modules/*` 大量读写 `state.map` / `state.round_state`，需要逐模块校验是否遵守 `33a-core-state-schema-contract.md` 的 namespace 与 schema 约定。
- 代码中存在较多 `legacy` / `fallback` / `compat` 路径，需要区分“必要兼容”与“已可收敛的历史包袱”。

## 通用审查模板

每个模块按同一模板记录：

1. 文档契约：该模块在 `docs/architecture/*.md` 中承诺的职责、依赖方向、扩展点。
2. 代码入口：对应脚本、场景、JSON schema、测试入口。
3. 依赖方向：是否违反目录分层；是否有跨层 preload、直接单例访问、私有字段访问。
4. 状态所有权：谁可以写 state；是否存在非唯一写入口；模块私有 state 是否 namespaced。
5. 重复与冗余：是否存在重复校验、重复事件生成、重复 UI 适配、重复 registry 查询。
6. 错误处理：fail-fast、Result 传播、日志、回退策略是否一致。
7. 兜底与兼容：是否存在过度 fallback、legacy/compat 路径长期残留、warning 代替错误、默认值掩盖坏数据。
8. 确定性与存档：随机、序列化、hash、archive、replay 是否稳定。
9. 测试覆盖：已有测试能否证明边界；是否需要新增 core 测试或 headless 场景测试。
10. 结论：问题级别、修复建议、是否需要拆分专项计划。

## 分阶段执行计划

### 阶段 1：架构清单与依赖基线

目标：建立文档到代码的完整映射，避免漏审模块。

- 读取 `docs/architecture/README.md` 与全部 architecture 文档标题。
- 生成模块清单：architecture 文档、代码目录、核心入口、测试入口。
- 建立目录依赖规则：
  - `core/` 不应直接依赖 UI/Node 场景；必要 autoload 访问应通过可注入 sink 或 `AutoloadAccess`。
  - `gameplay/` 可依赖 core，但不应承担 UI 生命周期。
  - `ui/` 可读 state 并发 command，但不应绕过 `GameEngine.execute_command` 写规则状态。
  - `modules/*` 通过 V2 registry/provider/hook 扩展，不应直接读取其他模块私有 state。
  - `server/` 应避免依赖 UI 视觉脚本，除非是明确隔离的渲染导出适配层。
- 建议采集命令：
  - `rg -n "^#{1,3} " docs/architecture`
  - `rg --files core gameplay ui autoload modules server backend tools`
  - `rg -n "preload\\(\"res://ui|load\\(\"res://ui" core gameplay autoload server backend`
  - `rg -n "Globals|SceneManager|EventBus|NetClient|PlatformApi|PlatformSession" core gameplay server backend --glob "!core/tests/**"`

### 阶段 2：Core 引擎主线审查

覆盖文档：

- `30-core-engine.md`
- `30a-core-engine-auto-advance.md`
- `30b-core-engine-archive.md`
- `31-core-phase-manager.md`
- `32-core-actions-framework.md`
- `33-core-state-model.md`
- `33a-core-state-schema-contract.md`
- `33b-core-state-serialization.md`
- `34-core-events.md`
- `35-core-data-random.md`
- `36-core-map.md`
- `37-core-rules.md`

重点问题：

- `GameEngine.execute_command` 是否仍是规则状态唯一写入口；force/debug 路径是否有边界。
- AutoAdvance 是否只依赖 engine/core state，不依赖 UI 状态或实时事件订阅。
- Archive/load 是否保证先装配模块 schema，再反序列化 `GameState`。
- `PhaseManager` 的 hook/order/settlement trigger 是否可预测，模块覆盖是否有冲突检测。
- `ActionRegistry` 的 gating、global validators、action validators、executor 顺序是否与文档一致。
- `ActionExecutor.compute_new_state` 与 in-place 变体是否被清楚隔离；缓存失效是否完整。
- `GameState.to_dict/from_dict/compute_hash` 是否统一处理 Godot JSON float、Vector2i、int-key Dictionary。
- `state.map` 与 `state.round_state` 的 core-owned key 是否集中定义；模块 key 是否 namespaced。
- `EventBus` 历史重建是否与 replay/rewind/load 保持一致；是否存在双重事件源造成 UI 日志漂移。
- `RandomManager` 是否在初始化、回放、存档恢复中保持确定性。
- `MapBaker`、runtime map、placement validator、road graph cache 是否有清晰写入和 invalidation 规则。
- `core/rules` registry/provider 是否阻止模块互相窥探私有 state。

建议证据：

- 命令执行调用链：`core/engine/game_engine.gd`、`core/engine/game_engine/command_runner.gd`。
- 存档链路：`core/engine/game_engine/archive.gd`、`loader.gd`、`archive_recovery.gd`。
- 状态链路：`core/state/game_state.gd`、`core/state/game_state_serialization.gd`、`core/state/state_schema_registry.gd`。
- 地图链路：`core/map/map_runtime/*`、`core/map/placement_validator/*`。
- 规则链路：`core/rules/*`、`core/modules/v2/ruleset*.gd`。

### 阶段 3：Gameplay 与 UI 边界审查

覆盖文档：

- `20-ui.md`
- `21-ui-game-scene.md`
- `22-ui-onboarding-tutorials.md`
- `23-ui-overlay-guidelines.md`
- `25-debug-and-profiling.md`
- `40-gameplay-actions.md`
- `41-gameplay-validators.md`
- `42-gameplay-replay-timelines.md`

重点问题：

- UI 是否只把用户意图转换为 `Command`，并统一走 `game._execute_command` / `command_controller`。
- `game.gd` 是否仍只是编排器，controller 之间是否出现循环调用或职责重叠。
- `Panel`、`MapInteraction`、`Overlay`、`Timeline` 是否共享了隐式状态，导致难以回放或恢复。
- `gameplay/actions` 是否有重复的参数读取、校验、事件生成；可沉入 validators/rules 的逻辑是否仍散落。
- `gameplay/validators` 与 `ActionRegistry` validators 分工是否清晰。
- `StepTimeline` / `EventTimeline` 是否坚持从 engine facts 派生，不依赖实时 `EventBus` 订阅。
- UI 日志是否仍存在两条并行链路；如果保留，边界是否清楚且测试覆盖。
- Tutorial/Onboarding 是否把进度和设置写入 `Globals` 时避免污染对局状态。
- Overlay 和 modal 是否遵守统一遮罩、输入捕获、生命周期释放约定。
- Debug/PerfTrace 是否在关闭时没有热路径开销；调试命令是否不会绕过 core 校验造成误导。

建议证据：

- `ui/scenes/game/game.gd`
- `ui/scenes/game/controllers/*`
- `ui/scenes/game/panel/*`
- `ui/scenes/game/map_interaction/*`
- `ui/scenes/game/timeline/*`
- `ui/components/game_log/*`
- `gameplay/actions/*`
- `gameplay/validators/*`
- `gameplay/replay/*`

### 阶段 4：Autoload 与跨场景全局状态审查

覆盖文档：

- `10-autoload.md`
- `70-online-multiplayer.md`
- `71-online-platform-backend-and-accounts.md`

重点问题：

- `Globals.current_game_engine`、`NetContext.online_resume_state`、`NetClient` pending cache 是否有明确生命周期。
- 新局、读档、回放、联机恢复、退出房间是否都清理对应全局状态。
- `SceneManager` 加载遮罩与场景切换是否会吞掉错误或造成重复实例。
- `PlatformSession` 本地持久化是否与 Guest/绑定/登出流程一致。
- `OnlineSessionCoordinator` 是否只做编排，不承载 UI 具体表现。
- `autoload` 中对 `ui/*` 的 preload 是否属于合理 UI glue，还是造成底层服务依赖表现层。
- server 启动时通过 `NetClient` autoload 复用逻辑是否导致 client/server 职责混在一起。

建议证据：

- `autoload/globals.gd`
- `autoload/net_context.gd`
- `autoload/net_client.gd`
- `autoload/net_client/client.gd`
- `autoload/net_client/server.gd`
- `autoload/online_session_coordinator.gd`
- `autoload/online_resume_session_state.gd`
- `autoload/platform_api.gd`
- `autoload/platform_session.gd`

### 阶段 5：模块系统 V2 与内容包审查

覆盖文档：

- `60-modules-v2.md`
- `61-content-catalog-schema.md`
- `62-module-development-guide.md`

重点问题：

- `module.json` 的 dependencies/conflicts/priority 是否足以表达模块顺序与互斥关系。
- `ContentCatalogLoader` 是否 fail-fast，且错误信息能定位模块、文件、字段。
- `RulesetLoader` 是否保活 entry/part 实例，避免 Callable 失效。
- `RulesetV2UiExtensions` 是否保持 UI 扩展与规则扩展分离。
- 各模块是否通过 registrar 注册 actions、validators、settlements、effects、providers、state schema。
- 模块私有状态是否遵守 `module_id` 或 `module_id_` 前缀；是否注册 int-key Dictionary schema。
- 模块是否直接读写 core-owned key；如果读写，是否经由 core helper/registry，而不是复制结构细节。
- 模块间协作是否通过 provider/registry，不直接读取另一个模块的私有 state。
- content JSON 的 ID、effect_ids、piece/tile/map 引用是否都由 strict 校验覆盖。

逐模块检查顺序：

1. 基础模块：`base_rules`、`base_products`、`base_employees`、`base_milestones`、`base_marketing`、`base_maps`、`base_tiles`、`base_pieces`。
2. 规则扩展模块：`new_milestones`、`hard_choices`、`reserve_prices`、`mass_marketeers`、`night_shift_managers`。
3. 地图/放置/营销扩展：`lobbyists`、`rural_marketeers`、`new_districts`、`gourmet_food_critics`。
4. 产品/食品扩展：`coffee`、`kimchi`、`sushi`、`noodles`、`fry_chefs`。
5. 其它内容/效果模块：`movie_stars`、`ketchup_mechanism`。

建议采集命令：

- `rg --files modules | rg "module.json|rules/entry.gd|content/.+\\.json$"`
- `rg -n "register_state_initializer|register_.*int_key_dict_schema|retain_entry_instance" modules core/modules/v2`
- `rg -n "state\\.map|state\\.round_state|round_state\\[|map\\[" modules`
- `rg -n "register_.*provider|register_primary_settlement|register_extension_settlement|register_action" modules`

### 阶段 6：联机、平台后端与恢复链路审查

覆盖文档：

- `70-online-multiplayer.md`
- `71-online-platform-backend-and-accounts.md`

重点问题：

- 平台后端、房间服、客户端之间的权威边界是否清楚：HTTP 目录/账号 vs WebSocket 实时房间。
- `connect_token`、resume ticket、session_id、user_id 的信任边界是否明确。
- `server/room.gd` 的权威 engine 是否和客户端 full live engine 保持同一命令历史语义。
- resync、rewind、delta snapshot、full archive 的触发条件是否互斥且可测试。
- 恢复房单引擎模型是否已经完全收敛，是否仍有双轨残留字段造成误用。
- timeline/log cache 是否只在冷路径 full build，热路径走 append/debounce。
- `server/dedicated_server.gd` 直接访问 `NetClient` 内部字段是否需要抽象成 server facade。
- `server/map_snapshot_cpu_canvas.gd` 依赖 UI 绘制脚本是否是明确例外，还是需要拆出 shared rendering core。
- Backend API 模型、数据库写入、房间目录、历史对局 archive 是否与 Godot archive schema 对齐。

建议证据：

- `server/room.gd`
- `server/room_manager.gd`
- `server/dedicated_server.gd`
- `autoload/net_client*.gd`
- `ui/scenes/online/online_lobby.gd`
- `ui/scenes/game/controllers/online_resync_controller.gd`
- `backend/app/*`
- `backend/tests/*`

### 阶段 7：工具、测试与验证体系审查

覆盖文档：

- `50-tools-replay.md`
- `52-testing.md`
- `docs/testing.md`

重点问题：

- `core/tests` 是否覆盖核心规则、determinism、Strict Mode、archive、schema、module failures。
- `ui/scenes/tests` 是否只承担 headless 场景入口与 UI 回归，不把规则真相写进 UI 测试。
- `all_tests` 聚合是否可维护；是否存在测试只覆盖 happy path。
- replay runner 是否覆盖 checkpoint、hash、full replay、模块组合。
- 测试命名、输出、退出码是否符合 headless 约定。
- 是否需要增加“架构约束测试”，例如禁止 server/core preload UI，禁止模块私有 state 未 namespaced。

建议验证命令：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`
- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
- `godot --headless --path . --script res://tools/replay_runner.gd -- res://tools/replays/m1_phase_cycle_22.json`

## 审查输出格式

最终报告建议按模块输出：

```text
## 模块：core/engine

结论：P1，边界整体清晰，但 archive/load 与 EventBus 历史重建需要补充契约测试。

发现：
- [P1] 标题
  - 证据：文件:行、调用链、测试名
  - 风险：影响 determinism / archive / UI / online 的哪一部分
  - 建议：短期修复与长期整理

测试缺口：
- 缺少某失败路径 / 边界场景 / 模块组合测试
```

## 建议执行顺序

1. 先审 `core/engine + state + actions + phase_manager`，确认唯一写入口、确定性、存档和回放基础没有漂移。
2. 再审 `modules_v2 + content schema + module packages`，因为模块系统影响大部分规则与状态扩展。
3. 然后审 `gameplay/replay + UI timeline/log`，确认派生时间线没有依赖实时事件副作用。
4. 接着审 `autoload + online + server/backend`，重点看全局状态生命周期和恢复链路。
5. 最后审 UI controllers、overlays、tutorial、debug/profiling 与测试体系，整理冗余和可维护性问题。

## 完成标准

- 每个 architecture 文档对应的模块都有审查记录。
- 每条问题都有明确证据、级别、影响范围和建议处理方式。
- 明确区分“必须修复”“建议重构”“文档同步”“可暂缓”。
- 给出可执行的测试/验证命令，并记录是否已运行。
- 若发现文档与代码不一致，明确建议改文档还是改代码。

## 审查执行记录

### Step 1：阶段 1 架构清单与依赖基线

日期：2026-04-30

范围：

- `docs/architecture/`
- `core/`
- `gameplay/`
- `ui/`
- `autoload/`
- `modules/`
- `server/`
- `backend/`
- `tools/`

采集命令：

- `rg --files docs/architecture`
- `rg -n "^#{1,3} " docs/architecture`
- `rg --files core gameplay ui autoload modules server backend tools`
- `rg -n "preload\\(\"res://ui|load\\(\"res://ui" core gameplay autoload server backend --glob '!core/tests/**' --glob '!ui/scenes/tests/**'`
- `rg -n "\\bGlobals\\b|\\bSceneManager\\b|\\bEventBus\\b|\\bNetClient\\b|\\bPlatformApi\\b|\\bPlatformSession\\b|\\bOnlineSessionCoordinator\\b|AutoloadAccess" core gameplay server backend --glob '!core/tests/**' --glob '!ui/scenes/tests/**'`

基线结果：

- `docs/architecture/` 当前有 30 个文档，模块清单与 `README.md` 的索引基本一致。
- `core gameplay ui autoload modules server backend tools` 下当前有 2770 个文件，其中 `.gd/.tscn/.json/.py` 约 1475 个。
- 非测试代码中发现 8 处 `res://ui` preload/load 跨层依赖。
- 本轮基线未发现 `core/` 直接 preload `ui/` 的 P0 级反向依赖；`core` 访问 autoload 主要通过 `core/utils/autoload_access.gd`，符合当前文档约定。

发现：

- [P1] `NetClient` 恢复缓存支持直接依赖 Game 场景日志构建器。
  - 证据：`autoload/net_client_online_resume_support.gd:8` preload `res://ui/scenes/game/timeline/log_entries_builder.gd`；同文件 `219-235` 与 `282` 在网络恢复缓存路径中调用 `GameTimelineLogEntriesBuilderClass.build(...)`。
  - 风险：`autoload/net_client_online_resume_support.gd` 属于联机会话/恢复状态层，但它直接依赖 Game 场景 UI 日志 entry builder。这样会让网络恢复缓存无法独立于 UI 场景演进，且把 `42-gameplay-replay-timelines.md` 中“UI 侧装配层”反向拉入 autoload 热路径。
  - 建议：把“events -> log entries”的纯转换部分下沉到 `gameplay/replay` 或新的中立 adapter；UI 只负责渲染 entries，NetClient 只缓存中立 timeline/entry 数据。

- [P1] `server/map_snapshot_cpu_canvas.gd` 复用 UI map canvas/drawer 作为服务端渲染实现。
  - 证据：`server/map_snapshot_cpu_canvas.gd:4-6` preload `ui/visual/ui_skin_cache.gd`、`ui/scenes/game/map/indexer.gd`、`ui/scenes/game/map/drawer/drawer.gd`。
  - 风险：服务端快照渲染与 Game 场景 Canvas 内部字段、绘制 pass、UI skin cache 强耦合。若 UI 地图实现调整，server 侧历史对局/快照导出可能被连带破坏。
  - 建议：短期在架构文档中把它标为“明确例外”并补充 contract test；长期拆出 `core/map/render_snapshot` 或 shared map rendering adapter，server 与 UI 分别接入。

- [P1] `server/dedicated_server.gd` 大量直接访问 `NetClient._room_manager` 与其内部 `rooms`。
  - 证据：`server/dedicated_server.gd:108-121`、`157-165`、`457-490`、`531-589`、`639-645`。
  - 风险：DedicatedServer 与 NetClient 内部字段强耦合，RoomManager 的字段名或封装变化会直接影响持久化、目录同步、心跳、远端房间裁剪等服务端关键路径。
  - 建议：为 server 侧暴露稳定 facade，例如 `NetClient.get_room_manager()`、`NetClient.create_room_persistence_snapshot()`、`NetClient.force_remove_room()`、`NetClient.list_active_room_codes()`，DedicatedServer 不再读 `_room_manager.rooms`。

- [P1] `server/room.gd` 在权威房间启动时临时写入 `Globals` 的配置覆盖。
  - 证据：`server/room.gd:1872-1889` 在 `engine.initialize(...)` 前后保存/写入/恢复 `Globals.game_config_overrides` 与 `Globals.game_option_overrides`。
  - 风险：房间服是权威对局层，临时修改全局 UI/客户端配置单例会让并发房间启动、测试注入和后续配置来源变得脆弱。即使当前调用路径没有 `await`，它仍把 server 初始化语义绑定到 `Globals`。
  - 建议：把 config/game option overrides 作为 `GameEngine.initialize(...)` 或依赖对象的显式参数传入，避免 server 通过全局单例传递权威配置。

- [P2] `OnlineSessionCoordinator` 依赖位于 UI 目录的错误分类策略。
  - 证据：`autoload/online_session_coordinator.gd:3` preload `res://ui/scenes/online/online_resume_error_policy.gd`；该 policy 本身是纯 `RefCounted` 静态分类逻辑。
  - 风险：实际逻辑不依赖 UI 节点，但文件位置导致 autoload 编排层反向依赖 UI 目录。
  - 建议：移动到 `autoload/`、`core/utils/online/` 或 `gameplay/online/` 类似中立目录，UI 继续复用该 policy。

暂不列为问题：

- `autoload/globals.gd` 对 `ui/audio/sound_manager.gd`、`ui/audio/music_manager.gd` 的依赖，以及 `autoload/scene_manager.gd` 对 loading overlay 的依赖，符合当前 `10-autoload.md` 中“跨场景 UI 粘合层”的定位；后续若要收紧 autoload 边界，可单独拆音频/加载服务。
- `gameplay/*` 中大量 `EventBus.EventType` 引用目前主要用于事件类型常量，不等同于直接订阅或写 `EventBus.history`；真正事件源一致性留到 `Step 3：Gameplay 与 UI 边界审查` 再判断。

阶段结论：

- 阶段 1 未发现需要立即阻断的 P0 问题。
- 当前最明确的结构性风险是：联机/服务端层为了复用 UI 产物而产生的反向依赖，以及 DedicatedServer 对 NetClient 内部字段的强耦合。
- 下一步进入 `core/engine + state + actions + phase_manager` 主线，重点确认唯一写入口、存档/回放、EventBus 历史重建与 auto-advance 边界。

### Step 2：阶段 2A Core 引擎、状态与动作主线初审

日期：2026-04-30

范围：

- `core/engine/game_engine.gd`
- `core/engine/game_engine/command_runner.gd`
- `core/engine/game_engine/initializer.gd`
- `core/engine/game_engine/loader.gd`
- `core/engine/game_engine/replay.gd`
- `core/engine/game_engine/event_history_rebuild.gd`
- `core/engine/game_engine/command_index_queries.gd`
- `core/engine/game_engine/auto_advance*.gd`
- `core/actions/action_registry.gd`
- `core/actions/action_executor.gd`
- `core/state/game_state.gd`
- `core/state/game_state_serialization.gd`
- `core/state/state_schema_registry.gd`
- `gameplay/replay/step_timeline_build/*`

本步定位：

- 这是 `阶段 2` 的主线初审，重点检查命令执行、回放、读档/schema、事件重建和 auto-advance。
- `PhaseManager` 细节、`core/map`、`core/rules`、模块注册冲突与地图缓存失效尚未完成深审，留到后续 Step 继续补充。

采集命令：

- `nl -ba core/engine/game_engine/command_runner.gd | sed -n '1,250p'`
- `nl -ba core/engine/game_engine/command_runner.gd | sed -n '300,360p'`
- `nl -ba core/actions/action_registry.gd | sed -n '110,175p'`
- `nl -ba core/engine/game_engine/loader.gd | sed -n '20,95p'`
- `nl -ba core/state/game_state_serialization.gd | sed -n '135,230p'`
- `nl -ba core/state/state_schema_registry.gd | sed -n '1,140p'`
- `nl -ba core/engine/game_engine/replay.gd | sed -n '70,175p'`
- `nl -ba core/engine/game_engine/event_history_rebuild.gd | sed -n '30,95p'`
- `nl -ba gameplay/replay/step_timeline_build/build_full_impl.gd | sed -n '80,165p'`
- `nl -ba gameplay/replay/step_timeline_build/build_append_impl.gd | sed -n '65,135p'`
- `nl -ba gameplay/replay/step_timeline_build/auto_advance_drain.gd | sed -n '1,130p'`
- `rg -n "compute_new_state_force|compute_new_state\\(|generate_events\\(|drain_auto_advances|AutoAdvanceClass\\.drain|AutoAdvanceClass\\.try_advance_one" core/engine gameplay/replay core/actions --glob '!core/tests/**'`
- `rg -n "random_manager|get_int\\(|get_float\\(|randi|randf|RandomNumberGenerator" core gameplay modules server --glob '!core/tests/**' --glob '!ui/scenes/tests/**'`

已确认的结构：

- `GameEngine.execute_command` 的主体职责已抽到 `CommandRunner.execute_command`，执行顺序与文档大体一致：初始化检查、截断未来命令、取 executor、补 phase/sub_phase、写确定性 timestamp、判定 force、跑 validators 或 force path、计算新 state、生成事件、drain auto-advance、写回 state、记录命令、创建 checkpoint、补 `command_index` 并发事件。证据：`core/engine/game_engine/command_runner.gd:102-225`。
- `ActionRegistry.run_validators` 顺序清楚：先 phase/sub_phase availability gating，再 global validators，最后 action validators。证据：`core/actions/action_registry.gd:146-167`。
- 读档链路已经按模块系统 V2 的约束先读取 `initial_state.modules` 并装配 ruleset/schema，再解析 `GameState`，这能避免 `round_state` / `map` 中 int-key Dictionary 被 JSON string key 固化。证据：`core/engine/game_engine/loader.gd:60-64`。
- `GameStateSerialization.apply_from_dict` 会在 map 解码后调用 `StateSchemaRegistry.normalize_int_key_dicts_in_container("map", ...)`，并在读档后对模块自有字段中的字符串玩家 key 发 warning；`StateSchemaRegistry.configure_from_ruleset` 对 schema id、root、path、重复注册做 fail-fast。证据：`core/state/game_state_serialization.gd:151-162`、`201-224`，`core/state/state_schema_registry.gd:48-121`。
- `RandomManager` 当前主要用于初始化、地图生成、state initializer 和 checkpoint/archive 记录；本轮没有确认到现有运行期 action 在 `compute_new_state` 内直接消耗 engine RNG。证据：`core/engine/game_engine/initializer.gd:50`、`193`、`217`，`core/engine/game_engine/checkpoints.gd:10-21`，`core/engine/game_engine/replay.gd:124-168`。

发现：

- [P1] 回放、事件历史重建、StepTimeline 与命令索引查询重复实现“应用一条历史命令”的核心流程。
  - 证据：`core/engine/game_engine/replay.gd:74-96` 与 `139-161`、`core/engine/game_engine/event_history_rebuild.gd:34-94`、`core/engine/game_engine/command_index_queries.gd:147-184`、`gameplay/replay/step_timeline_build/build_full_impl.gd:82-140`、`gameplay/replay/step_timeline_build/build_append_impl.gd:65-115` 都重复执行 executor 查找、force 判定、actor 合法性检查、`compute_new_state[_force]`、warning 传播与 auto-advance。
  - 风险：这些路径都在重建同一段事实历史，但各自决定事件生成、auto-advance、warning、force actor 校验、错误文案和 state 推进。以后改 force 语义、auto-advance 事件、命令 replay 规则或 executor 返回契约时，容易出现“运行时正确、读档日志错误”或“StepTimeline 与 EventBus.history 不一致”的漂移。
  - 建议：抽一个中立的 `ReplayStepRunner` / `CommandApplicationReplay` helper，至少统一 executor 查找、force 判定、actor 校验、state 推进、auto-advance 和 warnings；事件历史/StepTimeline 可以在统一 step facts 上再做各自的展示分段。短期先补 contract test：同一 command history 经 runtime、full replay、EventHistoryRebuild、StepTimeline full/append 生成的关键状态 hash、command_index、phase transition 事件数量必须一致。

- [P2] auto-advance 存在三套 drain 契约，当前可工作，但职责边界需要文档化或收敛。
  - 证据：`core/engine/game_engine/auto_advance_impl.gd:9-31` 的 `drain` 只返回状态推进成功与 warnings；`core/engine/game_engine/command_runner.gd:315-344` 的 `_drain_auto_advances` 在推进时额外生成 phase/cash 事件；`gameplay/replay/step_timeline_build/auto_advance_drain.gd:11-103` 又为 StepTimeline 单独做 phase step 分段和事件归属。
  - 风险：三者都调用 `AutoAdvanceClass.try_advance_one`，但返回值和事件语义不同。后续如果增加新的 auto-advance 事件、phase enter/exit hook 或 settlement 副作用，容易只改其中一处，导致实时事件、读档事件和 StepTimeline 展示不一致。
  - 建议：保留 `AutoAdvanceImpl.drain` 作为纯 state runner，同时把“每一步 before/after/state change”作为统一 facts 暴露；CommandRunner 和 StepTimeline 只消费 facts 生成事件/分段。若短期不重构，应在 `30a-core-engine-auto-advance.md` 明确三套适配层职责，并增加针对 auto-advance phase/cash/milestone 事件一致性的测试。

- [P2] `GameEngine` 初始化已经支持依赖注入覆盖，但仍保留从 `Globals` 读取配置覆盖的 fallback。
  - 证据：`core/engine/game_engine/initializer.gd:61-105` 先读 `GameEngineDependencies.game_config_overrides` / `game_option_overrides`，缺省时回退到 `Globals.game_config_overrides` / `Globals.game_option_overrides`。
  - 风险：对本地 UI 启动来说这是兼容路径，但与 Step 1 中 `server/room.gd` 临时写 `Globals` 初始化权威 engine 的问题叠加后，会让 server 初始化语义依赖全局 UI/客户端单例。
  - 建议：server/online 权威路径必须改为显式注入 `GameEngineDependencies`；保留 `Globals` fallback 时也应在架构文档中标注为“本地 UI 兼容入口”，避免服务端继续使用它传参。

- [P2] 运行期 RNG 约束目前依赖约定，没有在 command replay API 上显式表达。
  - 证据：`core/engine/game_engine/replay.gd:124-168` 会从 checkpoint 恢复 `RandomManager` 并返回，但 replay loop 应用命令时只把 `state` 和 `command` 传给 executor，并通过 `AutoAdvanceClass.drain(...)` 推进；当前 `rg` 结果显示 RNG 消耗主要集中在初始化、地图生成、state initializer 和服务端房号/快照排序等非命令路径。
  - 风险：当前未发现现有 action 因此出错；但如果后续有人在 action executor 或 auto-advance 中引入运行期随机，而 replay step runner 不接收/推进同一个 RNG，上线后会破坏 determinism、archive replay 和 rewind。
  - 建议：在 `35-core-data-random.md` 与 `32-core-actions-framework.md` 中明确“运行期 command executor 禁止直接消耗 RNG，除非 replay API 同步扩展”；同时加一个架构约束测试或静态扫描，阻止 `gameplay/actions` / module action executor 直接使用 `RandomNumberGenerator` 或 `engine.random_manager`。

暂不列为问题：

- `CommandRunner` 的 force/debug 边界目前没有发现 P0：非 replay 路径会通过 debug options 和 release feature 限制，force actor 仍校验合法范围；replay 路径通过 `ReplayClass.should_force_execute_in_replay` 兼容历史命令。该路径需要保留现有测试，例如 actor mismatch 与 force replay 相关测试。
- `StateSchemaRegistry` 的 schema 注册与读档归一化目前比文档要求更严格，未发现明显职责倒挂；真正的模块私有 state 是否全部遵守 namespace 与 int-key schema，需要在模块系统专项 Step 中逐模块扫描。

阶段结论：

- 本步未发现破坏唯一写入口、读档 schema 装配或基础 validator 顺序的 P0 问题。
- 最高优先级风险是“历史命令应用逻辑”分散在 replay、event rebuild、command index query 和 StepTimeline 中；它不是当前立刻崩溃的 bug，但属于会持续放大维护成本和一致性风险的 P1 设计问题。
- 下一步继续 `阶段 2B`，建议补审 `PhaseManager`、`core/map`、`core/rules` 与 `ActionRegistry` 注册冲突/fail-fast 边界，再决定是否需要把 P1 拆成专项重构计划。

### Step 3：过度兜底专项从头复查（阶段 1 + 阶段 2A 回扫）

日期：2026-04-30

触发原因：

- 新增审查要求：过度兜底代码默认按 `P2` 记录；若掩盖 archive/schema/联机同步/权威 server 状态错误，则上调到 `P1` 或 `P0`。
- 因此从头回扫已审过的阶段 1 与阶段 2A，并修正上一轮对部分 warning-only 路径的判断。

范围：

- `core/engine/game_engine/*`
- `core/state/*`
- `gameplay/replay/*`
- `autoload/*`
- `modules/*`
- `server/*`
- `backend/*`
- `tools/*`
- `docs/architecture/*`

采集命令：

- `rg -n "fallback|legacy|compat|backward|default|默认|回退|兼容|兜底|忽略|跳过|warning|warnings|with_warning|log_warn|push_warning" core gameplay ui autoload modules server backend tools docs/architecture --glob '!*.uid' --glob '!*.import'`
- `rg -n "return Result\\.success\\(\\)|return \\[\\]|return \\{\\}|return null|return false|return true|continue\\b|pass\\b" core gameplay autoload modules server backend --glob '!*.uid' --glob '!*.import'`
- `rg -n "schema|archive|from_dict|to_dict|deserialize|parse|load_archive|load_game|resume|snapshot|checkpoint|modules_v2|strict|fail-fast" core gameplay autoload modules server backend docs/architecture --glob '!*.uid' --glob '!*.import'`
- `nl -ba core/engine/game_engine/loader.gd | sed -n '70,110p'`
- `nl -ba core/engine/game_engine/action_setup.gd | sed -n '1,100p'`
- `nl -ba core/engine/game_engine/action_wiring.gd | sed -n '1,70p'`
- `nl -ba core/engine/game_engine/command_runner.gd | sed -n '70,105p'`
- `nl -ba core/engine/game_engine/command_runner.gd | sed -n '145,180p'`
- `nl -ba core/engine/game_engine/command_runner.gd | sed -n '220,280p'`
- `nl -ba core/state/state_schema_registry.gd | sed -n '120,160p'`
- `nl -ba core/state/state_schema_registry.gd | sed -n '216,282p'`
- `nl -ba core/state/game_state_serialization.gd | sed -n '200,230p'`
- `nl -ba gameplay/replay/event_timeline_build.gd | sed -n '50,110p'`
- `nl -ba core/modules/v2/ruleset/patches.gd | sed -n '1,160p'`

发现：

- [P1] 存档加载遇到非法 `modules_v2_base_dir` 会回退默认模块目录，而不是拒绝加载。
  - 证据：`core/engine/game_engine/loader.gd:83-96` 读取 archive 中的 `modules_v2_base_dir` 后，若 `ModuleDirSpec.parse_base_dirs(...)` 失败，只追加 warning 并改用 `GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR`。
  - 风险：archive/replay 的确定性依赖“当时启用的模块集合与模块来源”。非法模块目录被回退为默认目录后，加载可能继续成功，但实际使用的 ruleset/schema/content 已经不是存档声明的来源。这会掩盖坏存档、错误导出或跨环境模块路径问题。
  - 建议：archive 中显式携带 `modules_v2_base_dir` 时必须 fail-fast；仅对完全缺失该字段的旧存档允许有版本化兼容策略，并在结果中明确标注 legacy archive migration。

- [P2] 动作注册 provider 缺失或错误时会创建空 `ActionRegistry`，初始化链路可能继续运行。
  - 证据：`core/engine/game_engine/action_setup.gd:44-62` 对未配置、加载失败或缺少 `build_registry` 的 provider 只记录 error，随后 `return ActionRegistry.new()`；`core/engine/game_engine/action_wiring.gd:14-18` 直接把该 registry 写入 engine；当前 `project.godot:49` 配置为 `res://gameplay/action_setup.gd`，所以现有默认配置是有效的。
  - 风险：如果 ProjectSettings 或注入 provider 出错，系统不是在初始化阶段失败，而是得到一个没有内建动作的 registry。后续 availability 编译可能基于空动作集合继续通过，问题会延迟到 UI/在线命令执行阶段才暴露。
  - 建议：把 `ActionSetup.build_registry(...)` 改为返回 `Result`，或者在 `ActionWiring.setup_action_registry(...)` 中校验 provider 成功与必需动作 id 存在；测试注入空 registry 时应使用显式 test provider，避免生产路径静默降级。

- [P2] `CommandRunner` 事件构建 provider 缺失时静默返回空派生事件。
  - 证据：`core/engine/game_engine/command_runner.gd:79-100` 在 provider path 缺失或加载失败时返回 `null`；`core/engine/game_engine/command_runner.gd:151-170` 只有 provider 非空才追加现金/里程碑事件；`core/engine/game_engine/command_runner.gd:227-275` 的多个 `build_*_events` helper 在 provider 为 `null` 时直接返回 `[]`。当前 `project.godot:50` 配置为 `res://gameplay/replay/command_runner_event_build.gd`。
  - 风险：派生事件是 UI 日志、timeline 和在线恢复缓存的重要输入。provider 配置坏掉时，命令本身仍可执行，但现金变化、里程碑、阶段、营销、清理等事件可能消失，造成“状态正确但历史/日志/恢复事实不完整”。
  - 建议：运行时 engine 初始化应验证事件构建 provider；若某些纯 core 测试确实不需要事件，应通过显式依赖注入声明“无事件 provider 模式”，而不是由配置缺失自然降级。

- [P2] `StateSchemaRegistry` 未加载时会跳过 int-key 字典归一化。
  - 证据：`core/state/state_schema_registry.gd:126-131` 在 registry 未 loaded 时直接 `Result.success(container)`，注释说明允许非模块系统场景下跳过；存档 loader 正常路径会先装配模块，但直接调用 `GameState.from_dict` 的测试/工具路径可能绕过该保障。
  - 风险：包含模块字段的 state 若在 schema 未装配时被反序列化，`"0"` / `"1"` 这类 JSON 字符串 key 不会恢复为 int key，后续规则读取会出现隐蔽漂移。
  - 建议：`GameState.from_dict` 在 `modules` 非空时应要求 schema registry 已 loaded，或提供命名更明确的 `from_dict_without_module_schema` 仅供纯 legacy/test 使用。

- [P2] 模块自有字段出现字符串玩家 key 时只发 warning，不阻断读档。
  - 证据：`core/state/state_schema_registry.gd:216-259` 明确写着“仅告警，不改写状态”；`core/state/state_schema_registry.gd:272-277` 检测到疑似缺少 schema 注册时追加 warning；`core/state/game_state_serialization.gd:212-224` 只收集这些 warnings 后继续返回成功。
  - 风险：这类 warning 的语义实际是“模块忘记注册 int-key schema”。继续读档会让模块私有状态的 key 类型不符合运行时预期，问题可能延迟到特定 action/settlement 才出现。
  - 建议：至少在 archive/load/replay 路径提供 strict mode，把这类 warning 升级为 failure；若 UI 需要打开损坏存档做诊断，应使用显式的 recovery mode。

- [P2] `EventTimelineBuild` 缺少或损坏初始 checkpoint 时仍返回成功，并把 `GAME_STARTED.state_hash` 留空。
  - 证据：`gameplay/replay/event_timeline_build.gd:64-98` 对缺少 checkpoint、checkpoint 类型错误、缺少 `state_dict`、`GameStartedEventBuild` 失败都返回成功字典，只附加 warning。
  - 风险：timeline 构建会继续完成，但初始状态 hash 缺失，削弱 replay/恢复日志对状态源的校验能力。对纯 UI 展示这是可接受的 best-effort；对 archive/replay 诊断路径则属于过度兜底。
  - 建议：拆分 best-effort UI timeline 与 strict verification timeline；严格路径中缺少初始 checkpoint 或 hash 构建失败应直接失败。

- [P2] 新局初始化遇到非法 `modules_v2_base_dir` 会回退默认目录。
  - 证据：`core/engine/game_engine/initializer.gd:34-42` 在传入非空但非法的 base dir 时追加 warning 并改用默认目录；`autoload/globals.gd:465-469` 对 UI 配置中的非法目录也会警告后回退默认。
  - 风险：本地 UI 偏好配置中回退默认可以理解，但 server/test/online 权威初始化若沿用同一行为，会掩盖错误模块目录，导致实际模块来源与调用方意图不一致。
  - 建议：把“UI 用户偏好恢复默认”和“engine 权威初始化”分开：UI 层可以修正坏配置，传入 engine 的非空非法目录应 fail-fast。该问题与 Step 2 中 `GameEngine` fallback 到 `Globals` 配置覆盖的问题同源。

修正上一轮判断：

- Step 2 的“`StateSchemaRegistry` 注册与读档归一化较严格”只适用于 schema 注册入口本身；本次回扫确认，读档后的 `warn_if_module_owned_has_string_player_keys(...)` 和 registry 未 loaded 时跳过归一化属于过度兜底，应按 P2 继续跟踪。

暂不列为问题：

- `core/modules/v2/ruleset/patches.gd:63-70` 对 employee patch 目标缺失的跳过只在 patch 显式声明 `optional=true` 时发生，且注释说明默认仍 fail-fast；本轮不按过度兜底记录。
- `tools/run_headless_test.sh` 对 Godot 退出阶段的 benign leak warning 做兼容处理，属于测试工具对引擎噪声的局部适配；除非后续发现它吞掉真实失败，否则不列入架构问题。
- Visual catalog 的重复 key warning/override 属于 UI 资源覆盖策略，并已在内容 schema 相关文档中表达；它不影响规则状态与 archive determinism。

阶段结论：

- 本次从头回扫没有发现新的 P0。
- 新增最高优先级问题是 archive 加载对非法模块目录的回退，按 `P1` 处理，因为它可能破坏存档/回放确定性。
- 其余过度兜底集中在 provider 装配、schema 归一化、timeline verification 与 engine 初始化配置，应作为 P2 专项持续跟踪。
- 后续审查从 `阶段 2B` 继续，但每个模块都必须额外检查：是否存在 warning 代替 failure、空集合/默认值掩盖注册缺失、legacy/compat 路径长期残留。

### Step 4：阶段 2B PhaseManager、core/map、core/rules 与模块装配边界

日期：2026-04-30

范围：

- `core/engine/phase_manager/*`
- `core/map/*`
- `core/rules/*`
- `core/modules/v2/*`
- `modules/base_rules/rules/*`
- `modules/lobbyists/rules/*`
- `modules/rural_marketeers/rules/*`
- 相关 UI 调用点：`ui/components/reserve_area/reserve_area_supply_helpers.gd`

本步定位：

- 继续阶段 2，补审 PhaseManager、地图运行时缓存、规则 registry 与模块装配边界。
- 本步同时执行新增的“过度兜底”检查，重点看 hook/settlement/provider 回调是否 warning-only、是否有 core 反向知道具体模块、是否有损坏 state 被自动修补。

采集命令：

- `rg -n "register_named_sub_phase_hook|register_sub_phase_hook_by_name|hook_type|validate_required_primary_settlements|register_primary_settlement|parse_base_dirs|fallback|回退|warning|with_warning|or_default|optional" core/engine/phase_manager core/modules/v2 core/map core/rules modules/base_rules/rules modules/lobbyists/rules modules/rural_marketeers/rules --glob '!*.uid'`
- `find core/engine/phase_manager core/map core/rules core/modules/v2 -type f -name '*.gd' -print | sort`
- `rg -n "invalidate_road_graph|road_graph|set_map|state\\.map\\[|state\\.map\\.get|state\\.round_state\\[|state\\.round_state\\.get|require_optional|optional_.*default" core gameplay modules --glob '!core/tests/**' --glob '!ui/scenes/tests/**'`
- `nl -ba core/modules/v2/ruleset.gd | sed -n '110,165p'`
- `nl -ba core/engine/phase_manager/hooks.gd | sed -n '25,155p'`
- `nl -ba core/engine/phase_manager/hooks.gd | sed -n '188,215p'`
- `nl -ba core/modules/v2/ruleset/phase_hooks.gd | sed -n '1,75p'`
- `nl -ba core/modules/v2/ruleset/sub_phase_registration.gd | sed -n '36,130p'`
- `nl -ba core/engine/phase_manager/settlement_triggers.gd | sed -n '1,120p'`
- `nl -ba core/engine/phase_manager/order_config.gd | sed -n '1,155p'`
- `nl -ba core/engine/game_engine/modules_v2.gd | sed -n '200,230p'`
- `nl -ba core/rules/settlement_registry.gd | sed -n '75,160p'`
- `nl -ba core/rules/module_supply_fallbacks.gd | sed -n '1,70p'`
- `nl -ba ui/components/reserve_area/reserve_area_supply_helpers.gd | sed -n '1,90p'`
- `nl -ba modules/base_rules/rules/phase/payday_settlement.gd | sed -n '80,105p'`

已确认的结构：

- Phase order 与 working sub-phase order 的配置是严格校验的：未知阶段、重复阶段、缺少基础阶段、包含 Setup/GameOver 都会失败。证据：`core/engine/phase_manager/order_config.gd:18-55`、`64-91`、`114-143`。
- 必需主结算器与触发点会在模块装配后 fail-fast 校验。证据：`core/engine/phase_manager/settlement_triggers.gd:86-114`；装配调用在 `core/engine/game_engine/modules_v2.gd:211-224`。
- `core/map` 的 baked map 与外部 tile 编辑入口整体是 fail-fast，并会在改变 road graph 输入后失效运行时缓存。证据：`core/map/map_runtime/baked_map.gd:62-151`、`core/map/map_runtime/tile_edit.gd:109-128`、`130-190`。
- 内容 catalog 的核心定义重复会 fail-fast，例如 product、employee、milestone、marketing、tile、map。证据：`core/modules/v2/content_catalog_loader.gd:75-90`、`101-116`、`127-142`、`153-172`、`183-200`、`211-228`。
- effect handler 与 milestone effect handler 的内容引用校验会在初始化阶段失败，而不是运行时才发现。证据：`core/modules/v2/ruleset/content_validation.gd:8-80`、`82-140`。

发现：

- [P2] `register_named_sub_phase_hook(...)` 缺少 `hook_type` 范围校验，错误模块输入不会以 `Result.failure` 形式在注册阶段暴露。
  - 证据：`core/modules/v2/ruleset.gd:149-161` 只校验 `sub_phase_name` 与 callback，没有校验 `hook_type`；同类入口 `register_phase_hook` 与 `register_sub_phase_hook` 在 `core/modules/v2/ruleset.gd:117-147` 会校验 `hook_type < 0 or > 3`；working/cleanup 的命名 hook helper 也在 `core/modules/v2/ruleset/sub_phase_registration.gd:41-70`、`106-130` 校验。
  - 调用链风险：`core/modules/v2/ruleset/phase_hooks.gd:50-64` 会把未校验的 `hook_type0` 传给 `phase_manager.register_sub_phase_hook_by_name(...)`；`core/engine/phase_manager/hooks.gd:93-105` 只初始化 `_hook_types` 中的 key，随后直接访问 `_sub_phase_hooks_by_name[sub_phase_name][hook_type]`。
  - 风险：非法 hook_type 可能表现为运行时 dictionary key 错误，而不是模块装配阶段可定位的失败；这和模块系统 “Fail Fast” 目标不一致。
  - 建议：在 `RulesetV2.register_named_sub_phase_hook` 和 `PhaseManager.register_sub_phase_hook_by_name` 都补同样的 hook_type 校验；`RulesetV2PhaseHooks.apply` 也应对反序列化/手动写入的 hook 字典做防御性校验。

- [P2] Phase hook callback 返回值类型错误时，非 debug 模式只 warning 后继续。
  - 证据：`core/engine/phase_manager/hooks.gd:191-212` 中 hook callback 若没有返回 `Result`，只记录 warning；只有 `AutoloadAccessClass.is_debug_mode()` 为 true 时才返回 failure。
  - 风险：hook 是模块扩展规则的关键入口，返回值类型错误意味着模块契约已破坏。生产/普通运行模式继续执行会让错误模块“看似启用成功”，后续状态缺失或副作用不完整才暴露。
  - 建议：hook callback 返回非 `Result` 应始终 fail-fast；如果确实要兼容旧 hook，应在模块加载阶段做一次显式 migration 或 adapter，而不是运行时 warning-only。

- [P2] Settlement callback 返回值类型错误时，非 debug 模式只 warning 后继续。
  - 证据：`core/rules/settlement_registry.gd:88-107`、`109-128`、`135-154` 对 extension/primary settlement callback 返回非 `Result` 都只 warning；只有 debug 模式才 failure。
  - 风险：primary settlement 是 Dinnertime/Payday/Marketing/Cleanup 的权威状态推进入口。callback 契约错误不应被吞掉，否则可能出现“阶段推进成功，但结算没有按规则修改状态”的隐蔽错误。
  - 建议：SettlementRegistry 应与 `EffectRegistry`、`MilestoneEffectRegistry` 一样严格；非 `Result` 返回值应始终失败。若允许 `null` 表示 no-op，也应在注册 API 上显式声明，并只允许 extension，不允许 primary。

- [P2] `core/rules/module_supply_fallbacks.gd` 在 core 层硬编码具体模块的 UI 供给兜底。
  - 证据：`core/rules/module_supply_fallbacks.gd:5-16` 硬编码 `lobbyists_*`、`rural_marketeers_*`、`rural_billboard_*` key 与数量；实际使用点是 `ui/components/reserve_area/reserve_area_supply_helpers.gd:6`、`41-60`。
  - 风险：`core/rules` 按项目结构应保持 engine-first、可复用，不应知道具体扩展模块的 UI 展示兜底。现在新增模块供给展示时，需要改 core 文件，模块边界和 ownership 都不清晰。
  - 建议：把供给展示 fallback 移到模块侧 metadata/provider，例如 module manifest UI extension、`gameplay/module_ui_metadata.gd` 或 reserve area supply provider registry；core 只保留通用 registry/接口。

- [P2] Payday settlement 对缺失/错误的 `player.inventory` 自动修补为空字典。
  - 证据：`modules/base_rules/rules/phase/payday_settlement.gd:90-98` 在 player 缺少 inventory 或类型错误时写 warning、将其视为 `{}` 并回写 state；但 `core/state/player_state_access.gd:84-88` 与 `core/state/state_updater/inventory.gd:7-18` 都把 inventory 作为必需字段严格读取。
  - 风险：损坏存档或坏迁移会在 Payday 被静默修补成“玩家没有 token”，可能直接改变薪水支付结果。此类修补应发生在明确的存档 migration/recovery 模式，而不是权威结算规则里。
  - 建议：Payday settlement 使用 `PlayerStateAccess.require_inventory(...)` fail-fast；若需要兼容旧存档，迁移器在读档阶段补齐并记录 migration，而不是在结算中改坏数据。

暂不列为问题：

- `MapStateAccess.require_optional_*_or_default/empty` 本身不直接算过度兜底；本轮看到的 lobbyists/rural supply 使用点是在模块初始化阶段把缺失供给字段补成初始值，并且对类型错误/负数仍 fail-fast。证据：`modules/lobbyists/rules/entry.gd:214-242`、`modules/rural_marketeers/rules/entry.gd:141-152`。
- `ContentCatalogLoader` 对缺失的 content 子目录返回成功，符合“模块可以只提供部分内容类型”的设计；重复 id 与解析错误仍 fail-fast。
- `RoadGraphCache.get_road_graph(...)` 返回 `null` 的风格诊断信息偏弱，但主要调用点会把 `null` 转成 Result failure；本轮先不列为 P2，后续 `core/map` 可单独评估是否要把该 API 改成 `Result` 以增强错误定位。

阶段结论：

- Phase/order/settlement trigger 的主干比预期清晰，未发现 P0。
- 本步最需要优先处理的是 hook 与 settlement callback 的 warning-only 契约错误；它们属于典型过度兜底，会让模块装配错误逃过初始化。
- `core/rules/module_supply_fallbacks.gd` 是明确的边界倒挂，应在后续模块 UI/metadata 审查时拆出。
- 下一步进入 `阶段 3：modules_v2 与逐模块 rules/content 审查`，继续沿用“过度兜底默认 P2”的标准。

### Step 5：阶段 3 modules_v2 主链路与模块扩展点抽查

日期：2026-04-30

范围：

- `docs/architecture/60-modules-v2.md`
- `core/modules/v2/*`
- `core/engine/game_engine/modules_v2.gd`
- `core/engine/game_engine/action_wiring.gd`
- `core/actions/action_availability_registry.gd`
- `core/rules/dinnertime_demand_registry.gd`
- `gameplay/module_ui_metadata.gd`
- `modules/*/module.json`
- `modules/noodles/rules/entry.gd`
- `modules/sushi/rules/entry.gd`
- `modules/kimchi/rules/entry.gd`

本步定位：

- 进入逐模块审查前，先确认 `modules_v2` 的装配主链路是否符合文档宣称的 Strict Mode。
- 对当前模块实际使用的扩展点做第一轮抽查，重点看：注册 API 是否只校验形状、不校验语义；是否仍允许 legacy 返回值；是否存在空数组/默认值掩盖模块声明错误。

采集命令：

- `nl -ba docs/architecture/60-modules-v2.md | sed -n '1,120p'`
- `nl -ba docs/architecture/60-modules-v2.md | sed -n '145,166p'`
- `find modules -maxdepth 2 -name module.json -print | sort`
- `for f in modules/*/module.json; do printf '%s\n' "$f"; rg -n '"dependencies"|"conflicts"|"provides"|"entry_script"' "$f"; done`
- `rg -n "register_employee_patch|register_milestone_patch|register_employee_pool_patch|register_marketing_type|register_action_executor|register_.*provider|register_.*schema|register_.*settlement|register_.*hook|register_.*effect" modules/*/rules modules/*/actions --glob '*.gd'`
- `rg -n "optional=true|\"optional\"|optional" modules/*/rules modules/*/actions --glob '*.gd'`
- `nl -ba core/engine/game_engine/modules_v2.gd | sed -n '100,275p'`
- `nl -ba core/modules/v2/module_package_loader.gd | sed -n '25,75p'`
- `nl -ba core/modules/v2/ruleset_loader.gd | sed -n '20,55p'`
- `nl -ba core/modules/v2/module_manifest.gd | sed -n '40,100p'`
- `nl -ba core/rules/dinnertime_demand_registry.gd | sed -n '125,185p'`
- `nl -ba core/actions/action_availability_registry.gd | sed -n '70,190p'`
- `nl -ba core/modules/v2/ruleset/action_registration.gd | sed -n '100,150p'`
- `nl -ba core/engine/game_engine/action_wiring.gd | sed -n '70,125p'`
- `nl -ba core/modules/v2/ruleset/ui_extensions.gd | sed -n '1,80p'`
- `nl -ba gameplay/module_ui_metadata.gd | sed -n '55,90p'`

已确认的结构：

- 文档明确宣称模块系统 V2 是 Strict Mode，缺失依赖、重复注册、无效引用应在初始化阶段直接失败。证据：`docs/architecture/60-modules-v2.md:1-3`。
- `apply_modules_v2(...)` 的主链路整体是严格的：enabled modules 为空、base dir 解析失败、manifest 加载失败、plan 构建失败、catalog/ruleset 加载失败、registry 配置失败、content/effect/train_to 引用失败，都会返回 `Result.failure`。证据：`core/engine/game_engine/modules_v2.gd:109-130`、`133-145`、`155-199`、`201-234`、`239-268`。
- manifest 包加载对目录不可读、manifest 解析失败、目录名与 `manifest.id` 不一致、重复 module id 都 fail-fast。证据：`core/modules/v2/module_package_loader.gd:31-63`。
- rules entry 加载对脚本缺失、无法实例化、缺少 `register(registrar)`、`register` 返回错误类型都 fail-fast；`register` 返回 `null` 仍被允许，当前可理解为无规则模块的兼容入口。证据：`core/modules/v2/ruleset_loader.gd:23-45`。
- 当前 24 个 `modules/*/module.json` 都显式包含 `dependencies`、`conflicts`、`entry_script`、`provides` 字段；`new_milestones` 正确声明与 `base_milestones`、`hard_choices` 冲突。
- 多模块共用 `EXTRA_LUXURY_MANAGER_PATCH_ID` 不是问题：`EmployeePoolPatchRegistry` 对相同 patch_id 且相同 employee/delta 的重复注册会去重；如果内容不一致则失败。证据：`core/rules/employee_pool_patch_registry.gd:89-105`。

发现：

- [P2] `DinnertimeDemandRegistry` 仍长期支持 legacy provider 返回 `Array` 或 `null`，当前模块也在使用该兼容路径。
  - 证据：`core/rules/dinnertime_demand_registry.gd:155-173` 中 provider 返回 `null` 会直接 `continue`，返回 `Array` 会被接受；只有其他类型才失败。`modules/noodles/rules/entry.gd:32-46`、`modules/sushi/rules/entry.gd:32-50`、`modules/kimchi/rules/entry.gd:111-130` 的 `_get_demand_variants(...)` 都直接返回 `Array[Dictionary]`，且对输入异常返回空数组。
  - 风险：这是典型“长期兼容 + 空集合兜底”。如果 provider 因参数结构变化、house 字段缺失或 base_required 异常而返回空数组，Dinnertime 会继续按“没有额外需求变体”执行，模块规则失效不会在初始化或当场暴露。
  - 建议：在 `modules_v2` strict path 中要求 dinnertime demand provider 返回 `Result`；`null/Array` 只保留在显式 legacy adapter 或测试专用路径。当前 noodles/sushi/kimchi 应改成 `Result.success(variants)`，输入契约错误返回 `Result.failure`，真正的“不适用”再返回空 variants。

- [P2] Action availability override 只校验 `phase/sub_phase` 字段形状，不校验阶段/子阶段语义是否存在或是否可达。
  - 证据：注册入口 `core/modules/v2/ruleset/action_registration.gd:115-129` 只要求 `phase` 非空、存在 `sub_phase` 字段；`core/actions/action_availability_registry.gd:76-96` 也只做同类形状校验。编译阶段只校验 `action_id` 是否存在，随后把任意 phase/sub_phase 字符串写入 `_compiled`。证据：`core/actions/action_availability_registry.gd:98-183`。而 PhaseManager 已有基础名称解析能力：`core/engine/phase_manager/definitions.gd:117-129`。
  - 风险：模块里 typo 一个 phase/sub_phase，初始化仍成功，但 action 会被挂到不可达 bucket，表现为某阶段 UI/命令不可用。由于这类错误不一定触发命令执行，测试覆盖不足时会长期潜伏。
  - 建议：在 modules_v2 完成 sub-phase order 装配后，对 action availability points 做一次语义校验：phase 必须是已知阶段，sub_phase 必须是该 phase 当前配置下可达的子阶段；允许自定义子阶段，但必须来源于已经注册/插入的 order。空 points 表示“任意阶段”可以保留，但应显式记录。
  - 附带问题：`core/engine/game_engine/action_wiring.gd:77-89` 对 malformed override item 直接 `continue`，虽然当前 ruleset 通常由注册 API 生成，但这仍是 warning-less skip；建议改成失败或至少作为内部不变量断言。

- [P2] `module.json` 解析器对多个 schema 字段使用默认值，可能掩盖 manifest 漏字段。
  - 证据：文档把 `dependencies`、`conflicts`、`entry_script`、`provides` 列为当前 schema 字段。证据：`docs/architecture/60-modules-v2.md:149-165`。但解析器会把缺失/`null` 的 `dependencies`、`conflicts` 默认成 `[]`，把 `entry_script` 默认成空字符串，把缺失/`null` 的 `provides` 默认成 `{}`。证据：`core/modules/v2/module_manifest.gd:69-93`。
  - 风险：当前模块文件都显式填写这些字段，所以这不是现有 manifest 的错误；但从架构角度看，Strict Mode 下“漏写依赖”和“明确无依赖”语义不同。默认空依赖可能让新模块忘记声明依赖却仍通过 plan 构建，直到运行期引用内容/registry 时才失败，甚至只表现为 UI provider 缺数据。
  - 建议：将 schema requiredness 与默认值分离：`dependencies/conflicts/provides` 可以显式为空，但字段缺失应 fail-fast；`entry_script` 可允许空字符串表示纯内容模块，但字段也应显式存在。若要兼容旧 manifest，使用一次性 migration 或 manifest schema_version 分支。

- [P2] 模块 UI modal scene path 只校验字符串前缀，不校验资源存在或可加载。
  - 证据：`RulesetV2UiExtensions.register_phase_action_ui_modal(...)` 只校验 phase/kind 非空、`scene_path` 以 `res://` 开头。证据：`core/modules/v2/ruleset/ui_extensions.gd:18-40`。UI 聚合侧 `ModuleUiMetadata` 也只重复校验类型、非空和 `res://` 前缀。证据：`gameplay/module_ui_metadata.gd:74-83`。当前模块中 `kimchi` 注册了 modal path：`modules/kimchi/rules/entry.gd:99-105`。
  - 风险：这类错误不会影响 core determinism，但会让模块初始化成功、进入 UI 时才发现 scene 路径错误。对于模块系统来说，这仍属于“无效引用未在初始化暴露”的 Strict Mode 漏口。
  - 建议：把 UI 扩展资源引用纳入模块初始化校验：对 scene path 至少使用 `ResourceLoader.exists(path)`，必要时校验能加载为 `PackedScene`。如果 headless server 不应加载 UI 资源，则应拆出 `validate_ui_extensions`，在客户端启动或 UI metadata 构建时 fail-fast，而不是打开 modal 时才失败。

暂不列为问题：

- `RulesetLoaderV2` 允许 `entry_script` 为空并跳过注册，当前用于纯内容模块（例如 base content 模块）。只要 manifest 显式写出 `entry_script: ""`，这不是过度兜底。
- `EmployeePoolPatchRegistry` 对相同 patch_id、相同内容的重复 patch 去重，当前是为 noodles/sushi/coffee/kimchi 等模块共同增加 luxury manager 的明确设计；不同内容仍失败，不按冗余或过度兜底处理。
- `DinnertimeRoutePurchaseRegistry` provider 已要求返回 `Result` 并严格校验输出结构，本轮不列为问题，可作为 demand provider 改造目标的参照。

阶段结论：

- `modules_v2` 的加载、plan、catalog、ruleset、registry 注入主链路总体清晰，未发现 P0。
- 本步新增问题均为 P2：主要集中在扩展点契约仍保留兼容返回值、只做形状校验、不做语义/资源引用校验。
- 下一步继续逐模块审查 `base_rules`、`base_marketing`、`coffee`、`reserve_prices` 等规则模块，重点检查 action executor/validator、settlement、effect handler 是否也存在空结果兜底、warning-only 或跨模块硬编码。

### Step 6：逐模块审查 A - base_rules

日期：2026-04-30

范围：

- `modules/base_rules/README.md`
- `modules/base_rules/module.json`
- `modules/base_rules/rules/entry.gd`
- `modules/base_rules/rules/phase_and_map.gd`
- `modules/base_rules/rules/effects.gd`
- `modules/base_rules/rules/milestone_effects.gd`
- `modules/base_rules/rules/phase/dinnertime_settlement.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_house_sales.gd`
- `modules/base_rules/rules/phase/payday_settlement.gd`
- `modules/base_rules/rules/phase/marketing_settlement.gd`
- `modules/base_rules/rules/phase/cleanup_settlement.gd`
- `modules/base_rules/rules/phase/marketing/*`

本步定位：

- `base_rules` 是基础规则模块，提供 Dinnertime、Payday、Marketing、Cleanup 的 primary settlement，并承载基础 phase hook、地图生成、effect handler、milestone effect handler。
- 本轮重点检查：primary settlement 是否仍承担 UI/online 职责、是否有 warning-only、是否修补损坏 state、是否有状态访问绕过 helper、是否有过度兜底。

采集命令：

- `find modules/base_rules -type f -maxdepth 5 | sort`
- `nl -ba modules/base_rules/README.md | sed -n '1,220p'`
- `nl -ba modules/base_rules/module.json | sed -n '1,120p'`
- `nl -ba modules/base_rules/rules/entry.gd | sed -n '1,220p'`
- `rg -n "warning|with_warning|fallback|回退|兜底|legacy|compat|return \\[\\]|return \\{\\}|return null|continue\\b|pass\\b|state\\.map|state\\.round_state|round_state\\[|map\\[|Globals|NetClient|SceneManager|EventBus|AutoloadAccess" modules/base_rules --glob '*.gd'`
- `nl -ba modules/base_rules/rules/phase_and_map.gd | sed -n '1,520p'`
- `nl -ba modules/base_rules/rules/effects.gd | sed -n '1,260p'`
- `nl -ba modules/base_rules/rules/milestone_effects.gd | sed -n '1,260p'`
- `nl -ba modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd | sed -n '1,530p'`
- `nl -ba modules/base_rules/rules/phase/dinnertime/dinnertime_house_sales.gd | sed -n '1,430p'`
- `nl -ba modules/base_rules/rules/phase/payday_settlement.gd | sed -n '1,210p'`
- `nl -ba modules/base_rules/rules/phase/marketing_settlement.gd | sed -n '1,520p'`
- `nl -ba modules/base_rules/rules/phase/cleanup_settlement.gd | sed -n '1,390p'`
- `rg -n "process_event\\(state|MilestoneSystemClass\\.process_event|if not ms\\.ok|里程碑触发失败" modules core gameplay --glob '*.gd'`
- `rg --files core/tests ui/scenes/tests | rg "dinnertime|payday|cleanup|marketing|base_rules|milestone|online_.*confirm|fridge"`

已确认的结构：

- `base_rules` README 与 manifest 声明清楚：该模块提供四个 primary settlements。证据：`modules/base_rules/README.md:7-13`、`modules/base_rules/module.json:10-17`。
- `entry.gd` 只做模块 part 聚合与 Cleanup fridge modal 注册，业务规则下沉到 `phase_and_map/effects/milestone_effects`。证据：`modules/base_rules/rules/entry.gd:11-31`。
- primary settlement 和 phase hook 注册入口整体是 strict 的：每个 `registrar.register_*` 后都会检查 `r.ok`。证据：`modules/base_rules/rules/phase_and_map.gd:27-72`。
- 地图生成器对 player_count、rng、catalog、map_option、6 人局 New Districts 前置条件、layout_mode、tile 数量都 fail-fast。证据：`modules/base_rules/rules/phase_and_map.gd:372-440`。
- Dinnertime、Marketing 的主要数据结构校验较严格：map/houses/restaurants/marketing_instances/placements/house demand 等多数路径使用 `Result.failure`。证据：`modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd:164-207`、`modules/base_rules/rules/phase/marketing/marketing_instances_validation.gd:13-97`、`modules/base_rules/rules/phase/marketing/settlement_house_demand.gd:16-77`。
- Cleanup 和 Payday 已有针对 inventory/milestones 的 state access helper 使用点。证据：`modules/base_rules/rules/phase/cleanup_settlement.gd:41-55`、`modules/base_rules/rules/phase/payday_settlement.gd:185-196`。

发现：

- [P1] `base_rules` 的规则结算直接依赖运行环境和全局联机单例，导致同一规则路径会因 headless/windowed/online 状态产生不同 state。
  - 证据：Dinnertime settlement 直接读取 `NetContext` 判断 online mode：`modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd:60-82`；在写入 pending phase action 时用 `DisplayServer.get_name() != "headless"` 决定是否注入确认任务：`modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd:431-438`。Marketing settlement 也使用同样模式：`modules/base_rules/rules/phase/marketing_settlement.gd:247-250`、`260-278`。
  - 风险：规则模块应该根据显式 game option / engine context 决定状态变更，而不是读取当前进程显示模式或 autoload。现在同一局面在 GUI、headless 测试、ONLINE_SERVER 下可能写出不同 `round_state`，这会污染 replay/archive 的可比性，也让测试和生产行为之间存在隐式分叉。
  - 建议：把“是否需要结算确认 pending”改成显式输入，例如 `state.rules` 中严格解析的 option、GameEngine init option 或 PhaseManager context；`NetContext/DisplayServer` 判断留在 UI/online bootstrap 层，进入规则结算前转成确定的 state/config。规则模块只读取该显式配置，并对非法类型 fail-fast。

- [P1] Online 确认状态的损坏会被静默重建或只记录日志，可能掩盖联机权威状态错误。
  - 证据：Dinnertime 的 `_read_online_dinnertime_confirmed_players(...)` 遇到 `round_state` 缺失、字段不是 Array、长度不等于玩家数、元素类型非法时返回空数组；随后 `_build_dinnertime_confirm_pending(...)` 会把空数组当成“重新构建确认状态”。证据：`modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd:97-116`、`126-152`。pending 数量与 expected 不一致时只 `AutoloadAccessClass.log_warn`，不失败。证据：`modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd:447-466`。Marketing 的确认读取也在损坏时返回空数组并重建。证据：`modules/base_rules/rules/phase/marketing_settlement.gd:293-348`。
  - 风险：确认 pending 是联机同步与 auto-advance 的关键 gating。损坏的 confirmed_players 被静默重建，可能让已经确认/弃权的玩家状态丢失，或让服务端与客户端对 pending 的理解不一致。因为它只表现为 warning 或重建后的“正常状态”，后续 resync/卡阶段会更难定位。
  - 建议：把确认状态解析改成 `Result`；online mode 下字段缺失、长度不符或元素非法应 fail-fast。若确实要恢复，应由明确 recovery/migration 路径完成并写入可审计事件，而不是在 settlement 中静默重建。

- [P1] 多处关键里程碑触发失败被降级为 warning，结算仍成功。
  - 证据：`MilestoneSystem.process_event(...)` 的失败来源包括 `MilestoneEffectRegistry` 未设置、context 产品非法、milestone effect 执行失败等。证据：`core/rules/milestone_system.gd:23-30`、`47-52`、`69-94`、`96-119`。但 `base_rules` 中多处把 `ms.ok == false` 转成 warning 后继续：Waitress UseEmployee：`modules/base_rules/rules/effects.gd:45-52`；Marketing DemandMarked：`modules/base_rules/rules/phase/marketing_settlement.gd:149-155`；Payday PaySalaries：`modules/base_rules/rules/phase/payday_settlement.gd:130-136`；CleanupDiscard：`modules/base_rules/rules/phase/cleanup_settlement.gd:100-108`。
  - 风险：里程碑 effect 可以改变真实规则状态，例如获得卡、ban card、salary modifier、CFO ability 等。若触发失败但 settlement 成功，主状态已经完成现金/库存/阶段推进，却缺失里程碑副作用，属于权威规则状态不完整。
  - 建议：对权威规则路径，`MilestoneSystem.process_event` 失败应向上返回 `Result.failure`；只有“纯展示型里程碑日志失败”才允许 warning。短期至少为 settlement/action 增加 strict mode，默认 strict，旧行为仅在显式 best-effort/recovery 路径启用。

- [P2] Payday settlement 仍会把缺失或类型错误的 `player.inventory` 修补为空字典。
  - 证据：`modules/base_rules/rules/phase/payday_settlement.gd:90-99` 在 inventory 缺失或错误时追加 warning、写回 `{}` 并继续。该问题已在 Step 4 标出，本步确认它属于 `base_rules` 模块内的权威结算逻辑。
  - 风险：损坏存档或错误迁移会被解释成“没有可用于发薪的 token”，可能改变薪水支付结果。
  - 建议：改用 `PlayerStateAccess.require_inventory(...)` fail-fast；兼容旧存档应在读档 migration/recovery 层补齐。

- [P2] Cleanup 里程碑池清理对 `milestones_claimed[milestone_id]` 的错误结构按 1 份处理。
  - 证据：`modules/base_rules/rules/phase/cleanup_settlement.gd:300-318` 对 top-level `milestones_claimed` 类型会失败，但单个 milestone entry 不是 Array 时，会按 1 份加入 `claimed_remove_counts` 并继续。`StateUpdater.claim_milestone(...)` 正常写入的是 Array。证据：`core/state/state_updater/employees_and_milestones.gd:94-106`。
  - 风险：如果 `milestones_claimed` 被损坏或旧 schema 写错，Cleanup 会删除错误数量的 milestone supply，并把损坏结构变成“看似成功的清理结果”。这会影响后续可获得里程碑数量。
  - 建议：entry 类型错误应 fail-fast；如需兼容旧结构，应在读档迁移阶段明确转换，并记录 migration。

- [P2] Cleanup “opening soon restaurant” 翻面逻辑对重复/已开业餐厅和不匹配地图结构静默跳过，最后仍清除 pending 列表。
  - 证据：若 `restaurants` 已包含 `rid`，`_open_opening_soon_restaurants(...)` 直接 `continue`。证据：`modules/base_rules/rules/phase/cleanup_settlement.gd:225-227`。遍历 cells 时，缺失 structure、piece_id 不等于 restaurant、restaurant_id 不匹配都静默跳过。证据：`modules/base_rules/rules/phase/cleanup_settlement.gd:253-267`。循环结束后无论是否全部翻面成功，都会 `state.round_state.erase("opening_soon_restaurants")`。证据：`modules/base_rules/rules/phase/cleanup_settlement.gd:269-270`。
  - 风险：如果 pending 列表或 map cells 损坏，系统可能清掉 pending 标记但留下地图 structure 的 opening_soon 状态，形成 map/restaurants/player.restaurants 三者不一致。
  - 建议：重复 `rid`、目标 cells 缺失或 structure 不匹配应返回 failure，除非能证明这是幂等重放路径；如果保留幂等，应至少验证 map 与 restaurants/player list 已经一致后再跳过。

- [P2] Restructuring phase hook 会自动修复 CEO 从 reserve 到 employees，掩盖上游状态损坏。
  - 证据：进入重组时若 employees 缺 CEO 但 reserve 有 CEO，会移除 reserve 中 CEO，并强制 `employees=["ceo"]`。证据：`modules/base_rules/rules/phase_and_map.gd:133-147`。离开重组时同样会在 reserve 有 CEO 时修复回 employees。证据：`modules/base_rules/rules/phase_and_map.gd:215-224`。
  - 风险：CEO 所在区是玩家结构状态的核心不变量。权威 phase hook 自动修复会让上游 action/读档错误失去定位机会；如果 reserve 中 CEO 的出现本身来自旧存档兼容，应迁移在读档阶段发生，而不是每轮规则阶段隐式修补。
  - 建议：常规路径改为 fail-fast；保留一个显式 migration/recovery 函数处理旧存档，并在 archive/replay strict path 禁止自动修复。

暂不列为问题：

- `base_rules` 拆分出 `phase_and_map`、`effects`、`milestone_effects`、`phase/dinnertime/*`、`phase/marketing/*` 后，文件职责比单体 settlement 更清晰；本轮未把这种拆分视为冗余。
- `Restructuring overflow` 把除 CEO 外员工移回 reserve 属于规则语义，不按过度兜底处理。证据：`modules/base_rules/rules/phase_and_map.gd:267-288`。
- `DinnertimeInventory` 对库存扣减为负数会失败；本轮未发现它在库存写入口上过度兜底。证据：`modules/base_rules/rules/phase/dinnertime/dinnertime_inventory.gd:55-79`。
- Marketing settlement 已有专门 fail-fast 测试入口，且本轮看到 `marketing_instances` 结构校验较完整；后续只需补充 online confirm 与 malformed pending 的负例。

测试缺口：

- 缺少对 “Dinnertime/Marketing 同一 state 在 headless 与 GUI/online 配置下是否产生同一权威状态” 的确定性测试。
- 缺少 online confirmed_players 字段损坏、长度错误、元素类型错误时必须 fail-fast 的测试。
- 缺少 `MilestoneSystem.process_event` 在 settlement 中失败时必须阻断结算的测试。
- 缺少 Cleanup `milestones_claimed[milestone_id]` 非 Array、opening_soon map structure 不一致时的 fail-fast 测试。
- Payday 已有 state access 相关测试，但需要补一个 inventory 缺失/类型错误应失败的负例，以替换当前 warning 修补行为。

阶段结论：

- `base_rules` 主注册结构清晰，未发现 P0。
- 本步新增最高优先级为 P1：规则结算依赖 `DisplayServer/NetContext` 造成环境耦合，以及在线确认状态损坏的过度兜底。
- 里程碑失败 warning-only 也是 P1，需要作为跨模块专项继续追踪，因为 `gameplay/actions` 与其他模块也存在同类模式。
- 下一步建议审 `base_marketing` 与 `gameplay/actions/initiate_marketing`，因为它们与 Marketing settlement、action availability、milestone warning-only 路径直接相邻。

### Step 7：逐模块审查 B - marketing/actions 与剩余 gameplay 模块

日期：2026-04-30

范围：

- `modules/base_marketing/rules/entry.gd`
- `gameplay/actions/initiate_marketing/*`
- `gameplay/actions/confirm_dinnertime_action.gd`
- `gameplay/actions/confirm_marketing_action.gd`
- `gameplay/actions/employee_usage_helper.gd`
- `modules/new_milestones/**/*`
- `modules/coffee/**/*`
- `modules/lobbyists/**/*`
- `modules/rural_marketeers/**/*`
- `modules/night_shift_managers/rules/entry.gd`
- `modules/mass_marketeers/rules/entry.gd`
- `modules/reserve_prices/rules/entry.gd`
- `modules/hard_choices/rules/entry.gd`
- `modules/ketchup_mechanism/rules/entry.gd`
- `modules/movie_stars/rules/entry.gd`
- `modules/gourmet_food_critics/rules/entry.gd`
- `modules/fry_chefs/rules/entry.gd`
- `modules/new_districts/rules/entry.gd`
- `modules/kimchi/rules/entry.gd`
- `modules/noodles/rules/entry.gd`
- `modules/sushi/rules/entry.gd`

本步定位：

- 承接 Step 6 的 `base_rules` 结论，继续检查 action、marketing provider、extension settlement、模块私有 state 是否存在设计边界不清、冗余兼容、过度兜底。
- 本步重点不再重复 catalog/manifest 严格性，而是检查模块运行期路径：action validator/apply、range/demand provider、pending phase actions、milestone/event 联动。

采集命令：

- `find modules -maxdepth 4 -type f \( -path '*/rules/*.gd' -o -path '*/rules/*/*.gd' -o -path '*/actions/*.gd' -o -name 'module.json' \) | sort`
- `rg -n "warning|with_warning|fallback|legacy|compat|return \\[\\]|return \\{\\}|return null|continue\\b|pass\\b|state\\.map|state\\.round_state|round_state\\[|map\\[|Globals|NetClient|SceneManager|EventBus|AutoloadAccess|MilestoneSystemClass\\.process_event|process_event\\(state" modules gameplay/actions gameplay/validators --glob '*.gd'`
- `rg -n "register_action|register_.*validator|register_.*settlement|register_.*hook|register_.*provider|register_state|register_.*schema|register_effect|register_milestone_effect|register_phase_action_ui_modal|register_.*patch" modules --glob '*.gd'`
- `rg -n "was_milestone_awarded_this_turn|milestones_auto_awarded|with_warning|里程碑触发失败|process_event\\(state" modules/new_milestones modules/coffee modules/lobbyists modules/rural_marketeers gameplay/actions --glob '*.gd'`
- 对上述范围内关键文件使用 `nl -ba ... | sed -n ...` 定点阅读。

已确认的结构：

- `night_shift_managers` 与 `mass_marketeers` 的核心 hook/settlement 基本是 strict 的：员工数组、round_state、未知员工、marketing_rounds 类型都会失败。证据：`modules/night_shift_managers/rules/entry.gd:32-87`、`modules/mass_marketeers/rules/entry.gd:19-67`。
- `ketchup_mechanism` 对 milestone 触发失败会直接返回 failure，没有沿用 warning-only。证据：`modules/ketchup_mechanism/rules/entry.gd:124-130`。
- `gourmet_food_critics` 的 range provider 对 houses/has_garden 严格，placement conflict 也走 registry 查询；其 validator 中 `state == null/command == null/board_spec 不适用` 返回 success，当前更像 action validator 的“不适用”约定，暂不单独列为问题。证据：`modules/gourmet_food_critics/rules/entry.gd:37-63`、`64-116`。
- `new_districts` 只注册 UI hint，未发现运行期规则状态问题。证据：`modules/new_districts/rules/entry.gd:3-15`。
- `noodles/sushi/kimchi` 的 demand provider 已在 Step 5 归入 “DinnertimeDemandRegistry legacy Array/null provider” 问题，本步不重复升级优先级。

发现：

- [P1] `MilestoneSystem.process_event(...)` 失败被降级为 warning 的模式不只存在于 `base_rules`，已经扩散到 gameplay actions 与多个扩展模块。
  - 证据：公共 helper 明确把 UseEmployee 失败追加到 warning：`gameplay/actions/employee_usage_helper.gd:11-15`。`initiate_marketing` 在写入营销实例后触发 `InitiateMarketing`，失败只 `with_warning`：`gameplay/actions/initiate_marketing/apply.gd:219-245`。
  - 其他 gameplay action 也同样处理：`gameplay/actions/produce_food_action.gd:198-214`、`gameplay/actions/place_restaurant_action.gd:360-365`、`gameplay/actions/recruit_action.gd:275-293`、`gameplay/actions/train_action.gd:598-615`、`gameplay/actions/set_price_action.gd:60-67`、`gameplay/actions/set_discount_action.gd:73-80`、`gameplay/actions/place_house_action.gd:315-327`、`gameplay/actions/choose_fridge_keep_action.gd:164-205`、`gameplay/actions/choose_kimchi_storage_action.gd:141-210`。
  - 模块 action/settlement 中也存在：`modules/lobbyists/actions/place_lobbyists_road_action.gd:235-249`、`modules/lobbyists/actions/place_lobbyists_park_action.gd:156-168`、`modules/rural_marketeers/actions/place_giant_billboard_action.gd:165-176`、`modules/rural_marketeers/rules/entry.gd:231-257`。
  - 风险：里程碑 effect 不是纯日志，可能改变员工池、薪水、库存保留、额外动作、bankruptcy/price 等权威规则状态。action 已经完成状态写入但里程碑副作用缺失，会形成“动作成功、规则状态不完整”的不一致。
  - 建议：把所有权威 action/settlement 中的 milestone 触发改成 fail-fast；若有 UI 提示或历史兼容需求，拆成显式 `best_effort_milestone_log` 路径。`EmployeeUsageHelper.append_use_employee_warning(...)` 应改为返回 `Result`，由调用方决定是否允许非严格模式。

- [P2] Dinnertime/Marketing confirm action 仍保留 legacy global pending 和 confirmed_players 长度恢复路径，和 online 确认状态 strict 目标冲突。
  - 证据：两个 confirm action 都允许 pending list 为单个字符串时直接通过，并清空整个阶段 pending。Dinnertime：`gameplay/actions/confirm_dinnertime_action.gd:30-31`、`59-62`、`127-128`；Marketing：`gameplay/actions/confirm_marketing_action.gd:30-31`、`59-62`、`127-128`。
  - 证据：`online_*_confirmed_players` 长度不等于玩家数时返回 `Result.success([])`，后续会退回按 pending list 更新。Dinnertime：`gameplay/actions/confirm_dinnertime_action.gd:157-172`；Marketing：`gameplay/actions/confirm_marketing_action.gd:157-172`。
  - 证据：测试仍把 legacy global confirm 和 “recovers missing pending” 作为期望行为。Dinnertime：`core/tests/confirm_dinnertime_pending_phase_actions_key_test.gd:9-18`、`21-36`、`83-103`；Marketing：`core/tests/confirm_marketing_pending_phase_actions_key_test.gd:9-18`、`21-36`、`83-103`。
  - 风险：确认 pending 是联机 gating。长度错误或 legacy 字符串被正常化，会让损坏状态绕过 online 严格检查，且清空整阶段 pending 可能误清其他同阶段任务。
  - 建议：把 legacy global confirm 迁移到读档/回放 migration；常规 confirm action 只接受 `{kind, player_id}` 结构。`confirmed_players` 长度错误应 failure，并补充负例测试替换当前 recovery 测试。

- [P2] `base_marketing` 与 `initiate_marketing` 在营销占地/冲突路径仍保留旧数据默认值，会掩盖 `marketing_placements` 或 board spec 损坏。
  - 证据：mailbox range 直接使用 `RoadGraphCacheClass.get_road_graph(state)` 的返回值调用 `get_block_cells(...)`，未检查 `road_graph == null`。证据：`modules/base_marketing/rules/entry.gd:128-129`。
  - 证据：营销 footprint 解析缺失/错误时默认 `Vector2i.ONE`；airplane `footprint_size` 非法也重置为 `Vector2i.ONE`。证据：`modules/base_marketing/rules/entry.gd:82-106`、`240-263`。
  - 证据：`initiate_marketing` 的 drink source 校验只在 `state.map.drink_sources is Array` 时生效，数组元素不是 Dictionary 时直接跳过。证据：`gameplay/actions/initiate_marketing/validation.gd:188-200`。
  - 证据：airplane overlap 校验跳过 malformed existing placement、world_pos、axis/side/length；非 airplane overlap 对非法 footprint/rotation 回退到 `Vector2i.ONE/0`。证据：`gameplay/actions/initiate_marketing/validation.gd:351-384`、`389-410`、`480-508`。
  - 风险：营销放置和影响范围是权威规则。已有 placement 损坏时继续放置可能产生重叠、错误营销范围或漏判 drink source 占用。
  - 建议：在 strict path 中要求 `footprint_size/rotation/axis/world_pos/drink_sources` 都严格解析；兼容旧 placement 的尺寸推断只能在 migration 中完成。`RoadGraphCache.get_road_graph` 使用点必须统一 null -> `Result.failure`。

- [P2] `new_milestones` 的 extension settlement 对 Dinnertime 报告结构采取“缺失即不适用、坏 entry 跳过”，会隐藏上游结算输出损坏。
  - 证据：`round_state.dinnertime`、`sales` 缺失/类型错误时直接 success；sales entry、required、product、owner、route purchase 等 malformed entry 多处 `continue`。证据：`modules/new_milestones/rules/settlement_and_hooks.gd:65-99`、`117-180`。
  - 证据：pizza radio used boards 读取 `marketing_placements` 失败时只是不加入 used boards，后续仍继续。证据：`modules/new_milestones/rules/settlement_and_hooks.gd:127-139`。
  - 证据：Brand Manager provider 修改 `marketing_instance.remaining_duration = -1` 后，只在 `placements_read.ok` 时同步 `state.map.marketing_placements`；读取失败不会让 provider 失败。证据：`modules/new_milestones/rules/marketing_initiation.gd:280-293`。
  - 风险：extension settlement 依赖 primary settlement 的权威输出。坏报告被跳过会让里程碑漏发、mandatory pizza radio pending 漏注入，或者让 `state.marketing_instances` 与 `state.map.marketing_placements` 生命周期不一致。
  - 建议：对已经存在的 `round_state.dinnertime/sales/marketing_placements` 必须严格校验；只有字段完全不存在且明确表示“本局无该模块事件”时才 no-op。

- [P2] `coffee` 模块在 range origin、route purchase、First Coffee Sold pending 注入中存在多处过度跳过。
  - 证据：range origin provider 遇到 actor < 0、缺少 `coffee_shops`、shop entry 非 Dictionary、owner 不匹配、position 缺失时返回空 origins 或跳过。证据：`modules/coffee/rules/coffee_actions_and_state.gd:62-105`。
  - 证据：First Coffee Sold settlement 在 `round_state.dinnertime` 或 `sales` 不存在/类型错误时 success，sale/route_purchase/seller malformed 时跳过。证据：`modules/coffee/rules/coffee_first_coffee_sold.gd:84-119`。
  - 证据：Cleanup pending 读取仍兼容 legacy `int/float` pending entry 并映射为 `fridge_keep`；注入 coffee bonus 时 pending player 越界被跳过。证据：`modules/coffee/rules/coffee_first_coffee_sold.gd:18-61`、`183-204`。
  - 证据：route purchase provider 在 coffee stop index 与 purchase simulation 中跳过 malformed restaurant/shop/stop entry、owner 缺失、list 结构错误。证据：`modules/coffee/rules/coffee_dinnertime_route.gd:223-249`、`269-350`、`473-493`、`533-580`。
  - 风险：咖啡购买会扣库存、支付收入、触发 ProductSold，并影响首杯咖啡奖励。坏 stop/pending/sale 结构被跳过，会把状态损坏解释成“无人买咖啡/无人待处理奖励”。
  - 建议：将 module-owned state（`coffee_shops`、route purchases、bonus pending）全部通过 schema/helper 严格读取；legacy Cleanup pending 从 runtime 中移除，改为 migration；route purchase 只允许“无路可达”返回空 purchases，结构损坏必须 failure。

- [P2] `lobbyists` 和 `rural_marketeers` 的部分模块私有状态仍在 phase/action 中被自动创建或 best-effort 渲染，边界不够清晰。
  - 证据：Lobbyists UI overlay provider 对 malformed `pending_roads/roadworks_markers` 返回 `{}`/`[]` 或跳过 entry。证据：`modules/lobbyists/rules/entry.gd:95-108`、`110-159`、`161-184`。这是 UI provider，风险低于权威结算，但会让坏私有状态在 UI 上消失。
  - 证据：Lobbyists 重组 hook 会自动写入 `road_graph_connect_parallel_lanes`、补 supply、缺失 `pending_roads/roadworks_markers` 时创建默认值。证据：`modules/lobbyists/rules/entry.gd:186-247`。
  - 证据：放置 road 时，如果 `roadwork_markers` 或 `pending_roads` 缺失/类型错误，会直接创建 `{}`/`[]` 再写入。证据：`modules/lobbyists/actions/place_lobbyists_road_action.gd:169-216`。
  - 证据：Rural Marketeers 重组 hook 会创建/修补 `rural_area`，并填充 `has_garden/cells/demands/giant_billboards` 默认字段。证据：`modules/rural_marketeers/rules/entry.gd:103-154`。
  - 证据：Rural airplane/offramp conflict validator 在 state/params/board spec 不适用时 success，并跳过 malformed existing offramps；offramp action 对 malformed airplane placement 也跳过或默认 footprint。证据：`modules/rural_marketeers/rules/entry.gd:332-421`、`modules/rural_marketeers/actions/place_highway_offramp_action.gd:322-380`、`452-469`。
  - 风险：模块私有 state 的创建应集中在初始化/migration，权威 action/phase hook 中自动补齐会让坏存档或漏初始化不暴露。UI best-effort 可以保留，但应与 strict state validation 分开。
  - 建议：把模块 state 初始化从 “每次进入阶段补齐” 改成明确 initializer/migration；action 中遇到已有字段类型错误应 failure。UI overlay provider 可以继续 best-effort，但应在 debug/strict 校验工具中对同一私有 state 执行严格验证。

- [P2] `reserve_prices` 初始化会把非法 `reserve_card_selected` 重置为 -1，而不是暴露状态损坏。
  - 证据：`_init_state(...)` 解析已有 `reserve_card_selected` 时，只接受 int/整数 float；越界或类型不合最终写回 -1。证据：`modules/reserve_prices/rules/entry.gd:40-53`。
  - 风险：如果 initializer 会在载入旧局或模块切换时运行，非法选择会被解释成“未选择”，影响第一次破产的 base price 决策；真正的坏字段来源被隐藏。
  - 建议：新局初始化可以写默认值；对已存在字段应严格校验。若这是旧存档兼容，应放进 migration 并记录迁移事件。

暂不列为问题：

- `ketchup_mechanism`、`night_shift_managers`、`mass_marketeers` 的主规则路径本轮未发现过度兜底；它们可以作为后续 strict 改造参照。
- `new_districts` 当前只有 UI hint 注册，不涉及权威 state。
- `fry_chefs` 对 sushi/noodle cook 的 optional patch 是跨模块可选依赖设计，不按过度兜底处理；内容不存在时 registry 应只跳过 optional patch。证据：`modules/fry_chefs/rules/entry.gd:10-19`。
- `Movie Stars` validator 中 `state/command/params/to_employee` 不适用返回 success，符合 action validator 只拦截目标 action 子场景的约定；真正命中 movie star train 时会严格检查玩家和员工结构。证据：`modules/movie_stars/rules/entry.gd:144-171`。

测试缺口：

- 缺少 milestone trigger failure 应阻断每个核心 action/settlement 的负例测试。
- 缺少 `initiate_marketing` 对 malformed `drink_sources/marketing_placements/footprint_size/rotation/axis` 的 strict 测试。
- 缺少 Dinnertime/Marketing confirm legacy pending 被拒绝、`confirmed_players` 长度错误失败的测试。
- 缺少 coffee/new_milestones extension settlement 对 malformed `round_state.dinnertime.sales/route_purchases` 的失败测试。
- 缺少 lobbyists/rural module-owned state 初始化与 runtime strict validation 的边界测试。

阶段结论：

- 本步未发现 P0。
- 最严重的新增问题仍是 P1：里程碑失败 warning-only 已从 `base_rules` 扩散到大部分玩家动作和部分模块 action，属于架构级契约缺口。
- 多数 P2 问题集中在 “旧数据兼容/恢复逻辑仍留在运行期规则路径”。后续应统一定义 strict runtime、migration、best-effort UI 三条边界。
- 下一步进入 Replay/UI/timeline/log/controller 审查，重点检查权威 core/gameplay 是否被 UI、autoload、日志、回放兼容逻辑反向耦合。

### Step 8：Replay、Timeline、UI 日志与 Game Scene Controller 审查

日期：2026-04-30

范围：

- `core/engine/game_engine/replay.gd`
- `core/engine/game_engine/event_history_rebuild.gd`
- `core/engine/game_engine/archive_recovery.gd`
- `core/engine/game_engine/command_runner.gd`
- `gameplay/replay/event_timeline_build.gd`
- `gameplay/replay/step_timeline_build*.gd`
- `gameplay/replay/step_timeline_build/*`
- `ui/scenes/game/game.gd`
- `ui/scenes/game/controllers/*`
- `ui/scenes/game/timeline/*`
- `ui/scenes/game/event_log/*`
- `ui/components/game_log/*`

本步定位：

- 根据 `docs/architecture/42-gameplay-replay-timelines.md`，Replay/Timeline 应是从 engine facts 派生的确定性视图，不应在展示层补规则语义或吞掉坏事件。
- 根据 `docs/architecture/20-ui.md` 与 `docs/architecture/21-ui-game-scene.md`，UI 负责把用户操作转换成 `Command`、调用 engine、读取 state；日志当前明确存在 StepTimeline 与 EventLog 两条链路。
- 本步重点检查：回放是否保持权威校验、timeline 是否包含规则硬编码、UI controller 是否承担过多恢复/兜底职责、日志链路是否冗余且边界不清。

采集命令：

- `rg -n "step_timeline_loaded|EventLog|GameLog|timeline|append_event|EventBus|skip|fallback|兜底|warning|with_warning|force" ui/scenes/game ui/components/game_log gameplay/replay core/engine/game_engine core/actions/action_executor.gd`
- `nl -ba core/actions/action_executor.gd | sed -n '35,75p'`
- `nl -ba core/engine/game_engine/replay.gd | sed -n '70,200p'`
- `nl -ba core/engine/game_engine/event_history_rebuild.gd | sed -n '35,90p'`
- `nl -ba core/engine/game_engine/archive_recovery.gd | sed -n '20,110p'`
- `nl -ba core/engine/game_engine/archive_recovery.gd | sed -n '130,205p'`
- `nl -ba gameplay/replay/step_timeline_build/build_full_impl.gd | sed -n '85,105p'`
- `nl -ba gameplay/replay/step_timeline_build/build_full_impl.gd | sed -n '175,268p'`
- `nl -ba gameplay/replay/step_timeline_build/build_append_impl.gd | sed -n '15,85p'`
- `nl -ba gameplay/replay/step_timeline_build/build_append_impl.gd | sed -n '150,265p'`
- `nl -ba ui/scenes/game/event_log/controller.gd | sed -n '45,180p'`
- `nl -ba ui/scenes/game/timeline/controller.gd | sed -n '350,455p'`
- `nl -ba ui/scenes/game/timeline/step_timeline_build_helpers.gd | sed -n '1,260p'`

已确认的结构：

- `GameCommandController.execute_command(...)` 对 replay mode、online client、查看历史状态、tutorial gate、mandatory action auto-complete 都集中在 UI 命令入口，整体符合 “UI 发命令、engine 执行” 的大方向。证据：`ui/scenes/game/controllers/command_controller.gd:326-381`。
- `_maybe_auto_complete_mandatory_actions_before_skip(...)` 对 `round_state.mandatory_actions_completed` 的类型检查较严格，缺字段/类型错误会 failure；这部分不是过度兜底。证据：`ui/scenes/game/controllers/command_controller.gd:432-480`。
- Replay seek 与 history seek 主要通过 step snapshot 恢复 state，没有直接把 UI 逻辑写入 core；只读历史 seek 会关闭 timeline edit mode。证据：`ui/scenes/game/timeline/controller.gd:666-681`、`ui/scenes/game/timeline/replay_step_timeline_support.gd:65-82`、`ui/scenes/game/timeline/history_step_timeline_support.gd:111-128`。
- `docs/architecture/21-ui-game-scene.md` 已承认 Game 场景当前同时存在派生时间线链路与事件格式化链路。证据：`docs/architecture/21-ui-game-scene.md:136-151`。

发现：

- [P1] Replay/EventHistory/StepTimeline 在 actor 不匹配或 pending-blocked skip 时会走 `compute_new_state_force(...)`，从而绕过 action 的 `_validate_specific(...)`。
  - 证据：正常执行 `compute_new_state(...)` 会调用完整 `validate(...)`，再执行 `_apply_changes(...)`。证据：`core/actions/action_executor.gd:41-55`。强制执行只做 `_validate_base(...)`，直接 `_apply_changes(...)`。证据：`core/actions/action_executor.gd:57-68`。
  - 证据：`Replay.replay_to(...)` 与 `Replay.full_replay(...)` 在 `should_force_execute_in_replay(...)` 为真时调用 `compute_new_state_force(...)`。证据：`core/engine/game_engine/replay.gd:80-87`、`145-152`。触发条件包括 pending-blocked skip 和 `command.actor != current_player_id`。证据：`core/engine/game_engine/replay.gd:171-189`。
  - 证据：`EventHistoryRebuild` 与 `StepTimelineBuild` 也复用相同 force 语义。证据：`core/engine/game_engine/event_history_rebuild.gd:40-48`、`gameplay/replay/step_timeline_build/build_full_impl.gd:92-100`、`gameplay/replay/step_timeline_build/build_append_impl.gd:72-82`。
  - 风险：回放、读档恢复、事件历史重建、日志 timeline 构建都可能接受一个当前严格 action validator 会拒绝的命令历史。这样会把坏历史解释成“可回放”，并继续产生 state、事件和 UI 日志，削弱 archive/replay 作为确定性审计链的价值。
  - 建议：默认 replay path 应严格执行完整 action 校验；需要兼容旧 online history 时，使用显式 `legacy_replay_recovery_mode`，记录被绕过的 validator、命令索引和原因，并禁止该模式产出的 archive 覆盖原始权威历史。

- [P1] Online resume archive recovery 默认允许 prefix 截断并返回成功，属于高风险数据恢复兜底。
  - 证据：`load_for_online_resume(archive, allow_prefix_recovery = true)` 默认开启截断恢复。证据：`core/engine/game_engine/archive_recovery.gd:28-38`。完整 load 失败后，会从失败点向前尝试 prefix archive，找到可回放前缀就返回 `Result.success`，并标记 `truncated/recovered_command_count`。证据：`core/engine/game_engine/archive_recovery.gd:59-92`。
  - 证据：截断 warning 文案只作为 warnings 附带。证据：`core/engine/game_engine/archive_recovery.gd:286-295`。
  - 风险：恢复房可能把尾部坏命令静默丢掉后继续开局。对联机恢复而言，这等价于从损坏历史中派生一个新事实链，可能导致玩家动作丢失、事件日志与服务端历史不一致。
  - 建议：prefix recovery 必须是用户或运维显式选择的灾难恢复模式；默认 online resume 应 fail-fast。恢复产物应带不可忽略的 recovered 标记，并保留原始 archive 供审计。

- [P2] Archive replay import 会根据命令历史反推并补齐 online confirm 规则标记，把运行期语义迁移放进了 recovery path。
  - 证据：`_repair_online_confirm_markers_for_replay(...)` 扫描 commands，只要发现 `confirm_dinnertime/confirm_marketing` 且 initial rules 缺标记，就写入 `online_require_*_confirm = 1`。证据：`core/engine/game_engine/archive_recovery.gd:137-199`。
  - 证据：prefix checkpoint metadata 遇到坏 checkpoint entry 会跳过；没有可用 checkpoint 时合成 `{index=0, hash="", rng_calls=0}`。证据：`core/engine/game_engine/archive_recovery.gd:253-271`。
  - 风险：命令历史反推规则开关会把 “archive 缺规则字段” 解释成可恢复旧格式，而不是暴露 archive schema 不完整；合成空 hash checkpoint 又会削弱 replay/hash 审计。
  - 建议：online confirm marker 修复应迁移到版本化 archive migration；常规 replay import 只接受完整 initial rules/checkpoint。空 hash checkpoint 不应进入 strict replay。
  - 状态：Fix 35 已移除普通导入/联机恢复中的 marker 反推修补，并将 prefix checkpoint metadata 改为 strict 校验。

- [P2] 事件 envelope 在 core runner、event history rebuild、EventTimeline、StepTimeline 多处被静默过滤，坏事件不会暴露。
  - 证据：`CommandRunner` 发送事件时跳过非 Dictionary、空 type，并把非 Dictionary data 变成 `{}`。证据：`core/engine/game_engine/command_runner.gd:195-211`。
  - 证据：`EventHistoryRebuild` 对生成事件同样跳过非 Dictionary，并把 bad data 变成 `{}`。证据：`core/engine/game_engine/event_history_rebuild.gd:74-82`。
  - 证据：`EventTimelineBuild` 与 `StepTimelineHelpers.append_events(...)` 也跳过坏事件，data 错误时替换为空字典。证据：`gameplay/replay/event_timeline_build.gd:43-54`、`gameplay/replay/step_timeline_build/helpers.gd:31-50`。
  - 风险：事件是 UI 日志、回放 timeline、自动验证的重要中间契约。坏事件被跳过会造成日志缺失、timeline 与 EventBus.history 不一致，并隐藏 action/rule event builder 的 bug。
  - 建议：core/event rebuild/strict timeline 应验证 event schema 并 failure；只有纯 UI formatter 层可以 best-effort 跳过无法展示的 entry，并且应记录 debug diagnostics。
  - 状态：Fix 36 已新增统一 event envelope 校验，runtime、EventHistoryRebuild、EventTimelineBuild 与 StepTimelineBuild 都会在坏事件上失败。

- [P2] EventTimeline 的 `GAME_STARTED` 在缺 checkpoint 或 state_dict 错误时仍返回成功，只把 `state_hash` 留空。
  - 证据：缺少初始 checkpoint、checkpoint 类型错误、`state_dict` 缺失/类型错误、`build_from_state_dict` 失败都会 `Result.success({... "state_hash": ""}).with_warning(...)`。证据：`gameplay/replay/event_timeline_build.gd:64-99`。
  - 风险：`GAME_STARTED` 是整条事件时间线的身份锚点；空 hash 成功会让 timeline 看起来可用，但无法证明初始状态与 archive/checkpoint 一致。
  - 建议：strict timeline 中缺初始 checkpoint/hash 应 failure；如果 UI 需要展示不完整历史，使用独立的 degraded timeline 类型，并在面板上明确标识不可审计。

- [P2] StepTimeline 构建层硬编码具体规则/动作/里程碑，并在末尾用 flush 兜底补事件，职责已经越过 “派生视图” 边界。
  - 证据：full/append 构建都特判 `choose_fridge_keep`，用于延后 `first_throw_away` 里程碑事件。证据：`gameplay/replay/step_timeline_build/build_full_impl.gd:184-191`、`gameplay/replay/step_timeline_build/build_append_impl.gd:163-178`。
  - 证据：helper 直接识别 milestone_id `first_throw_away` 并放入 pending。证据：`gameplay/replay/step_timeline_build/helpers.gd:91-114`。
  - 证据：构建末尾有两个明确 “兜底”：Marketing enter effects 和 cleanup delayed milestone 若未刷出，则追加到最后一个 step。证据：`gameplay/replay/step_timeline_build/build_full_impl.gd:246-265`、`gameplay/replay/step_timeline_build/build_append_impl.gd:232-262`。
  - 风险：timeline 构建器理解了 `choose_fridge_keep/first_throw_away/Marketing enter effects` 等规则细节，新增模块或调整 settlement 顺序时，UI/replay 层必须同步改；末尾 flush 还可能把事件归属到错误 step，掩盖规则层未提供足够 attribution 的根因。
  - 建议：规则层应在 event metadata 中提供排序/归属信息，例如 `display_after_action_id`、`phase_segment`、`step_anchor`；StepTimeline 只消费通用 metadata。无法归属的 pending event 应触发构建失败或 strict diagnostic，不应自动塞到最后一格。
  - 状态：Fix 62 已先把 cleanup discard milestone 延后改为事件 metadata 驱动，StepTimeline 不再硬编码 `first_throw_away` / `choose_fridge_keep`；Fix 63 继续把 Marketing enter effects 改为 PhaseManager timeline settlement policy 驱动，并移除构建末尾 flush 到最后一个 step 的兜底。

- [P2] 增量 timeline 与预构建 entry 的 cache 路径存在 “过滤坏缓存后继续使用” 的行为。
  - 证据：append 构建从 `existing_timeline.steps/events` 只收集 Dictionary entry，非 Dictionary 被跳过。证据：`gameplay/replay/step_timeline_build/build_append_impl.gd:19-28`。
  - 证据：缺少 `_build_meta` 时，processed command count 与 last sequence 会从 events/steps 反推。证据：`gameplay/replay/step_timeline_build/helpers.gd:152-193`。
  - 证据：UI 对 prebuilt entries 同样只复制 Dictionary entry，坏 entry 被跳过。证据：`ui/scenes/game/timeline/step_timeline_build_helpers.gd:119-154`。
  - 风险：timeline cache 一旦损坏，系统可能局部丢 step/event/entry 后继续 append，导致日志与 engine history 慢慢漂移；缺 meta 反推也让缓存版本边界不清。
  - 建议：cached/prebuilt timeline 必须有 schema version、processed count、event sequence、engine/history signature。校验失败时整块缓存失效并 full rebuild；不应部分过滤后继续 append。
  - 状态：Fix 37 已要求增量 append 缓存必须带 `_build_meta`，并严格校验 cached/prebuilt steps/events/entries；坏缓存不再被部分过滤。

- [P2] Game 日志仍有 StepTimeline 与 EventBus EventLog 双链路，靠 runtime 条件避免重复，职责划分仍不清晰。
  - 证据：文档已说明同时存在派生时间线链路与事件格式化链路。证据：`docs/architecture/21-ui-game-scene.md:136-151`。
  - 证据：`GameEventLogController.setup(...)` 会清空日志、恢复 EventBus.history、订阅 EventBus。证据：`ui/scenes/game/event_log/controller.gd:49-70`。`rebuild_from_history(...)` 又能从 EventBus.history 重建日志。证据：`ui/scenes/game/event_log/controller.gd:72-85`。
  - 证据：当 `GameLogPanel` 已加载 step_timeline 时，EventBus 实时事件直接 return，以避免重复日志。证据：`ui/scenes/game/event_log/controller.gd:130-142`。Timeline controller 同时在实时局中构建并加载 step_timeline。证据：`ui/scenes/game/timeline/controller.gd:350-435`。
  - 风险：两个日志来源共享同一个 panel，但是否追加取决于 `has_step_timeline_loaded()` 的运行时状态。任何时序问题都会产生重复、丢失或命令索引错误；同时 formatter 与 timeline entries builder 需要维护两套文本规则。
  - 建议：确立单一日志数据源：优先让 StepTimeline 成为唯一 UI log model；EventBus formatter 只作为 StepTimeline entries builder 的内部格式化器或 debug 视图。迁移前需增加 “同一 command history 下 EventBus flat log 与 StepTimeline entries 数量/命令索引一致” 的回归测试。
  - 状态：Fix 61 已补运行时架构守卫，确保 `game.gd` 与 Game 控制器构建器不再重新接入 `GameEventLogController` / EventBus flat log；当前 `event_log/controller.gd` 保留为 legacy/test fallback 与格式化兼容，不是 Game 运行时主链路。

暂不列为问题：

- `GameCommandController` 的在线客户端命令转发到 `_online_resync_controller.try_send_online_action(...)`，本步只确认 UI 不直接绕过 online sync；具体 online resync 语义放到下一步审查。
- `apply_live_log_timeline_from_engine(...)` 在 timeline 构建失败时 warning 并不更新日志，作为 UI 展示降级可以接受；问题不在 UI warning，而在下游 StepTimeline/Replay 是否过度接受坏历史。
- `HistoryStepTimelineSupport.seek_to_step(...)` 与 `ReplayStepTimelineSupport.seek_to_step(...)` 直接从 step snapshot 恢复 state 是 timeline seek 的核心设计，不按过度兜底处理；风险主要来自 snapshot/timeline 构建严格性。

测试缺口：

- 缺少 “replay/full_replay/EventHistoryRebuild/StepTimelineBuild 对 actor 不匹配命令仍必须执行 `_validate_specific`” 的负例测试。
- 缺少 online resume archive load 失败时默认不得 prefix 截断的测试。
- 缺少 malformed event envelope 在 core runner/event rebuild/strict timeline 中必须失败的测试。
- 缺少缺初始 checkpoint 或空 `GAME_STARTED.state_hash` 必须失败的 timeline 测试。
- 缺少 StepTimeline 不允许硬编码具体 milestone/action 的契约测试；短期可先补 `first_throw_away`/Marketing pending event 归属稳定性测试。
- 缺少 EventBus flat log 与 StepTimeline log 在同一历史下的一致性测试。

阶段结论：

- 本步未发现 P0。
- 新增两个 P1：replay force execution 绕过 action-specific validation，以及 online resume prefix recovery 默认成功。
- Replay/Timeline/UI 日志的主要架构问题是 “展示/恢复层承担规则兼容与修补职责”。后续应拆分 strict replay、legacy migration/recovery、best-effort UI 三条路径。
- 下一步进入 Autoload、online、server、backend 恢复链路，重点确认这些 P1/P2 是否从 UI/replay 延伸到网络同步与服务端状态。

### Step 9：Autoload、Online、Server、Backend 恢复链路审查

日期：2026-04-30

范围：

- `docs/architecture/10-autoload.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/71-online-platform-backend-and-accounts.md`
- `autoload/net_client.gd`
- `autoload/net_client/client.gd`
- `autoload/net_client/client_resync_service.gd`
- `autoload/net_client/server.gd`
- `autoload/net_client/server_resync_service.gd`
- `autoload/net_client/server_resync_transfer_builder.gd`
- `autoload/net_client_online_resume_support.gd`
- `autoload/online_resume_session_state.gd`
- `autoload/net_context.gd`
- `autoload/online_match_bootstrap.gd`
- `autoload/online_session_coordinator.gd`
- `autoload/platform_api.gd`
- `server/room.gd`
- `server/room_manager.gd`
- `server/dedicated_server.gd`
- `backend/app/rooms.py`
- `backend/app/internal.py`
- `backend/app/matches.py`
- `backend/app/replay_storage.py`
- `backend/app/connect_token.py`

本步定位：

- 根据 `docs/architecture/70-online-multiplayer.md`，当前联机链路是平台后端发 `connect_token`，Godot 房间服持有权威 engine，客户端通过命令广播、resync、恢复房单 full-engine 同步。
- 本步重点追踪 Step 8 中的 replay/recovery 问题是否进入 server/client 主链路，并检查 autoload 全局状态、后端房间配置、snapshot/delta 恢复是否有过度兜底或边界不清。

采集命令：

- `rg --files autoload server backend/app ui/scenes/game/controllers | sort`
- `rg -n "fallback|兜底|legacy|compat|has_method|return \\{\\}|return \\[\\]|return null|continue\\b|pass\\b|with_warning|warning|warn|ignore|truncate|recovery|recover|snapshot|chunk|archive|state_hash|compute_hash|hash|resync|resume|full_history|single_full" autoload server backend/app ui/scenes/game/controllers/online_resync_controller.gd ui/scenes/game/controllers/startup_online_resume_controller.gd --glob '*.gd' --glob '*.py'`
- `find autoload server backend/app ui/scenes/game/controllers -type f \( -name '*.gd' -o -name '*.py' \) -print0 | xargs -0 wc -l | sort -nr | head -n 50`
- 对 `server/room.gd`、`autoload/net_client/client.gd`、`autoload/net_client/client_resync_service.gd`、`autoload/net_client/server_resync_service.gd`、`backend/app/rooms.py`、`autoload/platform_api.gd` 使用 `nl -ba ... | sed -n ...` 定点阅读。

已确认的结构：

- 联机主链路总体是 server authoritative：server 收到 action request 后根据 peer 映射 actor，执行 `room.game_engine.execute_command(cmd)`，再广播 `command_applied(cmd, state_hash)`。证据：`autoload/net_client/server.gd:1638-1673`、`1715-1739`。
- 客户端实时命令回放会校验 command index；直接回放失败或 state hash 不一致会触发 resync。证据：`ui/scenes/game/controllers/online_resync_controller.gd:405-432`、`463-474`。
- Delta resync 本身对 sequence、entry 类型、Command 解析、post hash、final hash 都较严格。证据：`autoload/net_client/client_resync_service.gd:240-344`。
- Server rollback 会在权威 engine 上 rewind、truncate、计算 hash 并重置 recovery store；客户端收到 rollback meta 后也会校验历史长度与 hash，不一致会 force snapshot resync。证据：`server/room.gd:1980-2037`、`ui/scenes/game/controllers/online_resync_controller.gd:666-714`。

发现：

- [P1] 联机 archive/resync 加载路径依赖全局 `NetContext.mode` 临时切换到 HOTSEAT，规则执行语义被 autoload 运行模式反向影响。
  - 证据：客户端 `_load_archive_for_online_client(...)` 在 `NetContext.Mode.ONLINE_CLIENT` 下会把 `NetContext.mode` 改成 `HOTSEAT`，执行 `engine.load_from_archive(...)` 后再恢复。证据：`autoload/net_client/client.gd:902-918`。
  - 证据：恢复完成后 `_mark_online_client_engine_ready(...)` 会调用 `OnlineResumePointValidator.prepare_engine_for_online_resume(...)`，再绑定 engine 到 `Globals.current_game_engine` 与 `NetContext`。证据：`autoload/net_client/client.gd:653-662`。
  - 风险：archive/replay 的规则语义不应取决于加载时全局 autoload mode。临时切到 HOTSEAT 可能绕过 online-only settlement/confirm 行为；同时 progress callback、EventBus 或后续初始化如果观察 `NetContext.mode`，会看到错误模式。
  - 建议：`GameEngine.load_from_archive` 应接受显式 replay/load context，例如 `{online_mode, strict, migration_profile}`，并传入规则层；禁止通过写全局 `NetContext.mode` 改变 core 行为。

- [P1] Server 恢复房创建实际使用了 Step 8 中的 prefix recovery 默认截断路径，P1 已进入权威房间链路。
  - 证据：`server/room.gd.configure_resume_lobby(...)` 调用 `ArchiveRecoveryClass.load_for_online_resume(...)`，未传 `allow_prefix_recovery=false`，因此使用默认 `true`。证据：`server/room.gd:1110-1129` 与 `core/engine/game_engine/archive_recovery.gd:28-92`。
  - 证据：成功后 `_resume_lobby_archive` 会保存 `loaded_info.archive`，后续 start game 由 `_prepare_effective_resume_start_engine()` 载入该 archive。证据：`server/room.gd:1121-1129`、`400-430`、`1825-1835`。
  - 风险：平台恢复房可能从被截断的 archive 起局，所有玩家看到的是“可恢复对局”，但尾部命令已被删除。这个行为属于灾难恢复，不应是普通恢复房默认路径。
  - 建议：`configure_resume_lobby` 默认 strict load；prefix recovery 需要单独 API/后台按钮/明确标记，并把 recovered/truncated 信息写入房间状态和后端 match artifact。

- [P2] Online resume point validator 在常规恢复路径中直接修补 rules、checkpoint 与 Dinnertime pending guard，恢复链路继续承担运行期迁移职责。
  - 证据：`prepare_engine_for_online_resume(...)` 若 `state.rules` 不是 Dictionary 会直接替换为 `{}`，并写入 `online_require_dinnertime_confirm/online_require_marketing_confirm = 1`。证据：`core/engine/game_engine/online_resume_point_validator.gd:18-25`。
  - 证据：它还会持久化到初始 checkpoint，并可能重算 checkpoint hash。证据：`core/engine/game_engine/online_resume_point_validator.gd:30-35`、`44-69`。
  - 证据：Dinnertime pending guard 会把 missing/invalid/legacy/empty pending 自动修复为 per-player pending，并把坏 `confirmed_players` 重建为 forfeited-only 数组。证据：`core/engine/game_engine/auto_advance_try_step.gd:156-239`、`265-298`。
  - 风险：恢复点校验器既做 validation，又修改权威 state/checkpoint。这样会把 archive schema 缺陷、pending_phase_actions 损坏、confirmed_players 类型错误变成“可恢复”，与 Step 6/7 对 confirm 状态 strict 的目标冲突。
  - 建议：拆成 `validate_resume_point_strict` 与 `migrate_online_resume_archive`。常规恢复只 validate；旧 archive 需要显式 migration，并记录被修改字段。
  - 状态：Fix 60 已新增 `validate_resume_point_strict(...)`，恢复房启动改用 strict 校验；缺 marker、checkpoint marker 或 Dinnertime pending guard 损坏会拒绝启动，不再在普通恢复房启动路径中修补。

- [P2] Server recovery delta store 是 best-effort：记录失败被静默吞掉，resync 服务再用 full snapshot 兜底，缺少诊断边界。
  - 证据：`record_resume_delta(...)` 如果 `_resume_checkpoint_archive` 为空，会调用 `_reset_recovery_store_from_current_engine("delta_init")`；失败时直接 `return`，没有把错误传回广播链路。证据：`server/room.gd:570-577`。
  - 证据：server 广播命令时只调用 `room.record_resume_delta(cmd, state_hash)`，没有接收/处理 Result。证据：`autoload/net_client/server.gd:2107-2124`。
  - 证据：`build_best_effort_resume_transfer(...)` 只要 delta 构建失败，就构建 full snapshot，并把 delta error 作为 `fallback_reason`。证据：`autoload/net_client/server_resync_service.gd:96-115`。
  - 风险：delta 缓存损坏、checkpoint 创建失败、cursor/hash mismatch 都会被归入 snapshot fallback。状态最终可能可恢复，但 server 失去了“delta store 已经坏掉”的强信号，性能问题和恢复链路缺陷会长期隐藏。
  - 建议：`record_resume_delta` 返回 Result，并在广播链路记录结构化 error；delta fallback 应区分正常 stale cursor、client 强制 snapshot、server recovery store 损坏三类原因，后者应告警并进入健康状态。
  - 状态：Fix 59 已让 `record_resume_delta(...)` 返回 `Result`，checkpoint 初始化/轮转失败会回传，并由 server broadcast 链路记录结构化 error；Fix 64 继续区分 force snapshot、stale/hash mismatch、delta gap/size 与 recovery store unhealthy fallback reason。

- [P2] 客户端 snapshot 分片组装失败只记录 error，不发失败信号或 force resync，恢复等待可能只能靠超时退出。
  - 证据：`handle_snapshot_chunk(...)` 收齐 chunks 后 `assemble_snapshot(...)` 失败时，清空 pending snapshot state、记录 `GameLog.error` 后直接 return。证据：`autoload/net_client/client_resync_service.gd:117-123`。
  - 证据：同一函数 bootstrap 失败会发 `match_bootstrap_local_failed`，普通 assemble failure 没有对应信号。证据：`autoload/net_client/client_resync_service.gd:124-140`。
  - 证据：启动恢复等待条件需要收到 `game_started` 且 archive/delta transport ready；delta failure 有单独信号，但 snapshot assemble failure 没有。证据：`autoload/online_session_coordinator.gd:391-423`、`541-553`。
  - 风险：分片损坏、manifest/chunk hash 不一致时，UI/恢复状态机可能停在加载中直到 timeout；对 resync 场景也无法立即请求新的 snapshot。
  - 建议：新增 `resync_snapshot_failed` 或复用 `resync_delta_failed` 的 failure channel；assemble failure 应触发 force snapshot retry 或清晰终止恢复。
  - 状态：Fix 66 复核当前代码已复用 `resync_delta_failed` 作为 snapshot assemble failure channel，并在失败时调用 `request_resume_force_snapshot_once()`；`OnlineClientResyncSnapshotChunkTest` 已覆盖坏 chunk 会发 failure、清空 pending state，并请求下一次强制 snapshot。

- [P2] Resync 后的 pending command flush 与实时 command_applied 路径不一致：解析/执行失败会移除 queued command，而不是立即 resync。
  - 证据：实时 `_on_online_command_applied(...)` 解析失败只 log return，执行失败会触发 `_request_online_resync("command_apply_failed")`。证据：`ui/scenes/game/controllers/online_resync_controller.gd:405-432`。
  - 证据：`_flush_online_pending_commands_after_resync(...)` 中，pending command 解析失败或执行失败会 `queue.remove_at(i)` 并继续/退出当前循环，没有立即触发 resync；如果队列已空，函数会走到正常 UI 刷新。证据：`ui/scenes/game/controllers/online_resync_controller.gd:744-789`、`811-821`。
  - 风险：同步中收到的 malformed/failed server command 可能被客户端丢弃，直到后续 index/hash 才暴露；如果没有后续命令，客户端可能停在落后一条历史的位置。
  - 建议：pending flush 的解析失败、执行失败应与实时路径一致，立即进入 force resync 或断开恢复，不应删除后继续。
  - 状态：Fix 67 复核当前 `_flush_online_pending_commands_after_resync(...)` 已在 pending command 解析失败/执行失败时调用 `_request_online_force_resync(...)` 并返回，不再走成功 UI 刷新；`GameOnlineResyncRequestRejectionTest` 已覆盖两类 pending failure。

- [P2] 后端房间配置解析失败会退回 `{}`，可能把坏配置解释成非恢复房或允许观战。
  - 证据：`_parse_room_config_json(...)` 对空字符串、JSON 解析异常、非 dict 都返回 `{}`。证据：`backend/app/rooms.py:102-114`。
  - 证据：恢复房判定依赖这个 dict 中的 `room_mode`。证据：`backend/app/rooms.py:117-118`、`521-523`。
  - 证据：观战策略解析 `config_json` 失败时将 `allow_spectators` 设为 true。证据：`backend/app/rooms.py:594-603`。
  - 风险：房间配置是平台后端和 Godot 房间服之间的边界契约。坏配置被当成 `{}` 会改变房间类型、seat binding、观战策略，属于权限/恢复语义上的过度兜底。
  - 建议：创建/同步房间时校验 config schema；读取已损坏 config 时返回 500/room unhealthy，而不是默认公开可观战。`allow_spectators` 在解析失败时应默认拒绝。
  - 状态：Fix 68 复核当前后端已通过 `backend/app/room_config.py` 统一解析 `config_json`；创建请求坏配置返回 400，已存坏配置返回 409，观战坏配置不再默认允许。

- [P2] `PlatformApi.parse_http_json_response(...)` 对 2xx 非 JSON 响应返回 `{"ok": {}}`，会把后端协议错误伪装成成功。
  - 证据：JSON 解析为 `null` 时直接改成 `{}`；只要 HTTP status 是 2xx，就返回 `{"ok": parsed}`。证据：`autoload/platform_api.gd:116-131`。
  - 风险：如果 backend/proxy 返回 200 HTML、空 body 或损坏 JSON，调用方会看到成功空字典，后续再以缺字段方式失败，定位困难；对房间/账号/恢复 ticket 这种强契约接口尤其不合适。
  - 建议：2xx 响应 body 不是 JSON object 时应返回 transport/protocol error；只有明确允许空 body 的 endpoint 才单独放行。
  - 状态：Fix 69 复核当前 `parse_http_json_response(...)` 已在 JSON 解析失败时返回 `error` 并保留 `_http_status/parse_error/body_text`；`PlatformApiResponseParseTest` 已覆盖 200 非 JSON body 必须失败，且合法 JSON `null` 不再被改写为 `{}`。

- [P2] Online client 从 server config 初始化 engine 时，`modules_v2_base_dir` 非法会回退默认目录，可能和 server 权威模块装配不一致。
  - 证据：`_initialize_online_client_engine_from_config(...)` 解析 `modules_v2_base_dir` 失败时只 warning，并设为 `GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR`。证据：`autoload/net_client/client.gd:570-577`。
  - 风险：联机客户端必须与 server 使用同一模块目录和模块集合。即便当前 server 多数情况下会在 initialize 失败时阻止开局，client 侧仍不应拥有“不同配置也继续初始化”的路径。
  - 建议：联机 config 缺失/非法时 fail-fast，请求 server resync 或拒绝启动；默认模块目录只用于本地新局 UI，不用于已由 server 签发的房间配置。
  - 状态：Fix 70 复核当前 `_initialize_online_client_engine_from_config(...)` 已在空/非法 `modules_v2_base_dir` 时返回 `Result.failure`，不再回退默认目录；`OnlineClientConfigBootstrapOverridesTest` 已覆盖失败时不写入 `Globals.current_game_engine`。

- [P3] Online/server 关键文件仍承担多个子系统职责，后续维护风险较高。
  - 证据：当前最长文件包括 `server/room.gd` 2431 行、`autoload/net_client/server.gd` 2297 行、`ui/scenes/game/controllers/online_resync_controller.gd` 1149 行、`autoload/net_client/client.gd` 1082 行、`autoload/net_client.gd` 993 行。
  - 风险：虽然已经抽出 `server_resync_service`、`client_resync_service`、`server_disconnect_grace_service` 等 helper，但主文件仍混合房间状态、恢复房、回滚、resync、结算上报、性能诊断和 UI 回调协调。后续 strict/migration 拆分会继续增加复杂度。
  - 建议：按职责继续拆：`OnlineRoomResumeStore`、`OnlineRoomRollbackService`、`OnlineRoomStartSession`、`ClientCommandReplayService`、`ClientSnapshotBootstrapService`。每个服务使用明确 Result contract，减少 `has_method` 与 callback 字典胶水。
  - 状态：Fix 74 已先从 `server/room.gd` 抽出 rollback proposal pending/vote/public payload 状态管理，降低 `OnlineRoom` 在回滚子系统上的状态承载；Fix 76 继续抽出 start session pending/ready/payload 状态，减少房间启动 bootstrap 子系统对 `OnlineRoom` 主文件的字段占用。该 P3 属于持续拆分项，后续仍可继续按 resume/client replay 边界拆分。

暂不列为问题：

- Delta resync 的客户端应用过程本身较严格，sequence/hash/command parse 失败都会 fail；问题在失败后的 retry/channel 和 server fallback 分类，而不是 delta 校验本身。
- Server action request 以 peer 映射 actor，并拒绝 forfeited player；本步未发现普通 action request 直接信任客户端 actor 的问题。证据：`autoload/net_client/server.gd:1638-1669`。
- Backend replay 下载接口会校验参与者或 admin 权限；本步未把 replay download 权限列为问题。证据：`backend/app/matches.py:684-720`。
- `Backend` 为 match list 读取 replay logo override 时 best-effort 返回 `{}` 只影响展示，不影响权限或权威状态；本步暂不升级。证据：`backend/app/matches.py:254-282`。

测试缺口：

- 缺少 `configure_resume_lobby` 默认 strict 拒绝坏 archive、不得 prefix truncate 的 server 级测试。
- 缺少客户端 archive load 不得修改 `NetContext.mode` 的回归测试。
- 缺少 `OnlineResumePointValidator` 对坏 rules/pending/confirmed_players 只 validate 不 mutate 的测试。
- 缺少 snapshot assemble failure 会发 failure signal/触发 retry 的测试。
- 缺少 pending command flush 解析/执行失败必须 resync 的测试。
- 缺少 backend bad `config_json` 不得允许 spectator、不得丢失 resume_room 语义的 API 测试。
- 缺少 PlatformApi 2xx invalid JSON 返回 protocol error 的测试。

阶段结论：

- 本步未发现 P0。
- Step 8 的两个 P1 在 online/server 链路中都被证实：server 恢复房会使用 prefix recovery，client 恢复会通过全局 mode 切换改变 archive load 语义。
- Online 恢复链路的核心整改方向是：server/client 都只做 strict load 与 strict sync；旧 archive 修复、prefix 截断、pending guard 修复必须迁移到显式 recovery/migration 模式，并从 UI/后台清楚暴露。
- 下一步审查 tools、tests、architecture 约束和文档一致性，确认是否有测试/工具正在固定这些过度兜底行为。

### Step 10：Tools、Tests 与架构约束缺口审查

日期：2026-04-30

范围：

- `docs/architecture/50-tools-replay.md`
- `docs/architecture/52-testing.md`
- `docs/architecture/25-debug-and-profiling.md`
- `tools/run_headless_test.sh`
- `tools/run_headless_script.sh`
- `tools/replay_runner.gd`
- `tools/export_match_artifacts_from_replay.gd`
- `core/tests/*`
- `ui/scenes/tests/all_tests_refs.gd`
- `ui/scenes/tests/all_tests_plan.gd`
- 与 Step 8/9 问题相关的 online/replay 测试。

本步定位：

- `docs/architecture/52-testing.md` 要求测试覆盖 Strict Mode 的 fail-fast 行为，并通过 `core/tests` + headless 场景运行。证据：`docs/architecture/52-testing.md:27-34`、`43-58`。
- `docs/architecture/50-tools-replay.md` 把 replay runner 定义为确定性校验工具：逐条执行命令、`full_replay()`、对比 state hash、校验 checkpoints。证据：`docs/architecture/50-tools-replay.md:34-40`。
- 本步主要检查：是否已有测试把过度兜底固定成“正确行为”；是否存在工具侧 best-effort 输出掩盖 replay/archive 问题；是否还有关键 P1/P2 没有测试护栏。

采集命令：

- `rg -n "prefix|truncate|recover|recovery|repair|legacy|fallback|with_warning|warning|force|compute_new_state_force|debug_force|online_require|confirmed_players|pending_phase_actions|allow_prefix|state_hash|resync|resume|archive" core/tests ui/scenes/tests tools docs --glob '*.gd' --glob '*.sh' --glob '*.md'`
- `rg --files core/tests ui/scenes/tests tools docs/architecture docs/plans | sort`
- `find core/tests ui/scenes/tests tools -type f \( -name '*.gd' -o -name '*.sh' \) -print0 | xargs -0 wc -l | sort -nr | head -n 60`
- 对 `callback_result_contract_test.gd`、`online_resume_archive_recovery_test.gd`、`confirm_dinnertime_pending_phase_actions_key_test.gd`、`confirm_marketing_pending_phase_actions_key_test.gd`、`tools/export_match_artifacts_from_replay.gd`、`tools/run_headless_test.sh`、`all_tests_plan.gd` 等文件使用 `nl -ba ... | sed -n ...` 定点阅读。

已确认的强约束：

- 已有 fail-fast 测试覆盖 archive 根字段、command timestamp、invariants 和 map/state access 等基础约束。证据：`core/tests/archive_fail_fast_test.gd:1-5`、`54-149`；`core/tests/invariants_fail_fast_test.gd:1-5`、`42-89`。
- 测试聚合入口已经把关键架构约束测试纳入 AllTests，包括 `CallbackResultContractTest`、`ModuleBoundaryContractTest`、`CoreArchitectureBoundaryContractTest`、`ArchiveFailFastTest`、`InvariantsFailFastTest`。证据：`ui/scenes/tests/all_tests_plan.gd:110-119`、`666-683`。
- online resync 已覆盖一部分严格链路：delta 成功后 hash/sequence 必须一致，server resync 首选 delta、hash mismatch/force snapshot 时才发 snapshot，wrong-room rollback/snapshot/delta 不应缓存。证据：`core/tests/online_client_resync_delta_apply_test.gd:249-306`、`core/tests/server_resync_guard_test.gd:102-178`、`core/tests/online_client_resync_room_isolation_test.gd:30-75`。
- snapshot chunk 正常组装有测试覆盖：manifest 前 chunk 不直接完成恢复，组装完成后只发一次 archive，且清理 pending manifest/chunks。证据：`core/tests/online_client_resync_snapshot_chunk_test.gd:47-79`。
- Kimchi cleanup 已存在“坏 pending item 必须失败且不允许部分写入”的负例。证据：`core/tests/kimchi_cleanup_state_access_test.gd:63-88`。

发现：

- [P1] 测试已经明确固定 online resume archive prefix truncation 为成功行为，阻碍 Step 8/9 的 strict 恢复整改。
  - 证据：`OnlineResumeArchiveRecoveryTest._run_recover_bad_tail_command_case()` 构造尾部坏命令后，要求 `ArchiveRecoveryClass.load_for_online_resume(archive)` 成功，且 `truncated=true`、`recovered_command_count=original_count-1`。证据：`core/tests/online_resume_archive_recovery_test.gd:245-281`。
  - 证据：同一测试还要求 `RoomManager.create_resume_room_with_code(...)` 接受可截断 archive，并检查房间内 archive 命令数已变成 `bad_index`。证据：`core/tests/online_resume_archive_recovery_test.gd:283-324`。
  - 风险：这不只是缺少测试，而是现有测试把灾难恢复语义作为普通恢复房成功路径固定下来。后续若把 `configure_resume_lobby` 改成 strict，会直接被该测试挡住。
  - 建议：拆成两个测试：普通恢复房 `strict` 必须拒绝坏 tail；显式 `recovery mode` 才允许 prefix truncation，并要求房间状态、后端 artifact 和 UI 明确暴露 `truncated/recovered_command_count/failed_command_index`。

- [P2] Hook/settlement callback 返回非 `Result` 的 warning-only 行为被 contract test 固定。
  - 证据：`CallbackResultContractTest` 在非 debug 模式下要求 phase hook 返回非 `Result` 时 `hr.ok == true` 且产生 warning。证据：`core/tests/callback_result_contract_test.gd:25-33`。
  - 证据：同一测试要求 settlement callback 返回非 `Result` 时非 debug 模式只 warning。证据：`core/tests/callback_result_contract_test.gd:41-49`。
  - 风险：Step 4 已把 hook/settlement warning-only 识别为过度兜底；当前测试会使“始终 fail-fast”的修改变成测试失败。
  - 建议：将测试改为迁移期双轨：legacy adapter 可 warning，Strict Mode 默认应 failure。目标状态下，非 debug 与 debug 都应拒绝非 `Result` callback。

- [P2] Dinnertime/Marketing confirm 测试把 legacy global confirm 与 missing pending recovery 固定为成功行为。
  - 证据：`ConfirmDinnertimePendingPhaseActionsKeyTest.run()` 先跑 `_case_legacy_global_confirm(...)`，再跑 per-player 与 missing pending recovery。证据：`core/tests/confirm_dinnertime_pending_phase_actions_key_test.gd:9-19`。
  - 证据：Dinnertime missing pending recovery 会从 `online_dinnertime_confirmed_players` 重建其它玩家待确认项，并要求恢复后数量为 `player_count - 1`。证据：`core/tests/confirm_dinnertime_pending_phase_actions_key_test.gd:83-131`。
  - 证据：Marketing 测试也保持相同的 legacy global confirm 与 missing pending recovery 预期。证据：`core/tests/confirm_marketing_pending_phase_actions_key_test.gd:9-19`、`83-131`。
  - 风险：Step 6/7/9 已确认 confirm/pending guard 在运行期修补 state，会掩盖损坏 archive 或 server 权威 pending 丢失。当前测试会把“运行期自动恢复坏 pending”变成长期契约。
  - 建议：保留 legacy archive migration 测试，但从 action runtime 测试中移除 silent recovery 预期；普通 action 对缺失/非法 `pending_phase_actions` 应失败。

- [P2] Tooling 导出 latest autosave 时会猜测最终 snapshot event，可能输出与 replay event 不一致的 artifact。
  - 证据：`_export_latest_autosave(...)` 找不到 `_snapshot_event_for_state_after_command(...)` 时调用 `_fallback_final_snapshot_event(...)`。证据：`tools/export_match_artifacts_from_replay.gd:145-161`。
  - 证据：fallback 会根据最终 `state.phase` 和 `state.round_number` 推导 `round_number/snapshot_kind`，最低回退到 round 1。证据：`tools/export_match_artifacts_from_replay.gd:253-270`。
  - 风险：导出工具用于回放/对局 artifact 时，找不到 event 应该表示历史事件链或 phase 边界不完整。继续输出 guessed latest autosave 会把工具产物变成“看似完整但来源不可验证”。
  - 建议：导出标准 artifact 时改为 fail-fast；如需要运营补档，提供 `--best-effort` 参数，并在 manifest 中标记 `snapshot_event_source = "fallback"`。

- [P2] Online resync 测试覆盖了实时命令失败触发 resync，但没有覆盖 pending command flush 的失败路径。
  - 证据：`GameOnlineResyncRequestRejectionTest` 用 failing engine 覆盖 `_on_online_command_applied(...)`，要求命令回放失败后立刻请求 resync。证据：`core/tests/game_online_resync_request_rejection_test.gd:34-72`。
  - 证据：同一测试覆盖 delta failed 后 force snapshot fallback。证据：`core/tests/game_online_resync_request_rejection_test.gd:143-159`。
  - 缺口：没有测试 `_flush_online_pending_commands_after_resync(...)` 中解析失败/执行失败不得丢弃 queued command、必须重新 resync 的路径。这个缺口对应 Step 9 的 P2。
  - 建议：新增 controller 级测试：resync 中 queue 一条 malformed command、一条执行失败 command，flush 后必须触发 `request_resync(force_snapshot=true 或明确 reason)`，且不得静默清空队列后刷新 UI。

- [P2] Snapshot assemble failure 没有测试 failure signal 或 retry，现有测试只覆盖成功与 wrong-room ignore。
  - 证据：正常 chunk test 只断言成功 assemble、发 archive、清 pending。证据：`core/tests/online_client_resync_snapshot_chunk_test.gd:52-79`。
  - 证据：room isolation test 只断言 wrong-room manifest/delta/rollback 不缓存、不透传。证据：`core/tests/online_client_resync_room_isolation_test.gd:47-75`。
  - 风险：Step 9 已确认 `client_resync_service` assemble failure 只 log error 后 return。没有测试要求 failure channel，恢复等待卡住的问题会继续存在。
  - 建议：新增 corrupt chunk/hash mismatch 测试，要求发 `resync_snapshot_failed` 或 `match_bootstrap_local_failed`，并触发 force snapshot retry/终止恢复。

- [P2] `tools/run_headless_test.sh` 对 Godot 退出码有多处 success fallback，作为测试工具可以理解，但 CI/架构验证需要更明确的严格模式。
  - 证据：preflight/import 非 0 但只有已知 benign shutdown leak warnings 时继续。证据：`tools/run_headless_test.sh:115-128`、`150-162`。
  - 证据：运行后如果日志已有 PASS/SUMMARY，即使 Godot exit code 非 0，也会 treat as success；另有“SUMMARY failed=[] 兜底成功”。证据：`tools/run_headless_test.sh:232-260`、`301-327`。
  - 风险：目前脚本仍会拦截 `SCRIPT ERROR` 和明确 FAIL，因此不是直接缺陷；但当架构审查需要验证 fail-fast 时，exit-code fallback 会降低 CI 信号纯度。
  - 建议：保留默认兼容模式，同时增加 `STRICT_EXIT=1` 或 `--strict-exit`，用于架构/发布验证，要求 Godot exit code 与日志同时成功。
  - 状态：Fix 75 已确认脚本具备 `--strict-exit` / `STRICT_EXIT=1`，并将 GitHub CI 的 AllTests 调用切换为 `--strict-exit`，让发布验证链路不再接受非 0 Godot exit code 的 PASS 日志兜底。

- [P3] AllTests 聚合文件过大，新增/迁移测试需要同时维护 refs 与 plan，容易漏接架构测试。
  - 证据：`ui/scenes/tests/all_tests_plan.gd` 当前 1558 行，`all_tests_refs.gd` 集中 preload 大量测试类。证据：`ui/scenes/tests/all_tests_plan.gd:1-8` 与本轮 `wc -l` 结果。
  - 风险：测试覆盖已经很丰富，但聚合入口本身成为手工维护热点。新增 strict/recovery 双轨测试时，漏加到 AllTests 的概率上升。
  - 建议：按 domain 拆分 test suites，例如 `all_tests_core_architecture.gd`、`all_tests_online.gd`、`all_tests_modules.gd`，再由顶层 AllTests 聚合 suite 列表。
  - 状态：Fix 65 已将顶层 `all_tests_plan.gd` 缩减为 suite 聚合器，并按 bootstrap/core architecture/online/ui/core rules/runtime timeline/modules/settlement 拆出 8 个 domain suite。

暂不列为问题：

- `tools/run_headless_script.sh` 与 `run_headless_test.sh` 对 Godot 退出阶段资源泄漏 warning 的兼容，是 headless 工具对引擎噪声的局部适配；当前脚本仍检查 `SCRIPT ERROR` 与非预期 `ERROR`，不单独升级为 P2。证据：`tools/run_headless_script.sh:63-87`、`tools/run_headless_test.sh:85-113`。
- DebugPanel 的 `debug_force` 命令属于明确调试入口；问题不在 debug 命令本身，而在 replay/timeline/online 复用 force path 时未保留 action-specific validation。
- Manual test save builders 中的 fallback 用于构造人工测试存档，不直接进入 runtime 权威链路；本轮不按架构问题记录，但建议后续加注释标明“仅测试数据生成”。

测试缺口汇总：

- `configure_resume_lobby` 普通恢复房 strict 拒绝坏 archive，prefix truncation 仅显式 recovery mode 放行。
- `load_for_online_resume(allow_prefix_recovery=false)` 在 server/UI 恢复房入口被实际使用。
- `NetClient` archive load 不得修改 `NetContext.mode`。
- Hook/settlement callback 非 `Result` 在 Strict Mode 下始终 failure。
- Confirm action 对坏 `pending_phase_actions` fail-fast，legacy archive 修补只能走 migration。
- Replay/full_replay/StepTimeline/EventHistory rebuild 对 force/debug command 仍执行 action-specific validation。
- Snapshot assemble failure 发 failure signal 并触发 retry/终止恢复。
- Pending command flush 解析/执行失败触发 resync，不静默丢弃。
- Backend bad room `config_json` 不得默认为非恢复房或允许观战。
- PlatformApi 2xx invalid JSON 返回 protocol error。
- Tool artifact export 找不到 snapshot event 时默认失败；best-effort 必须显式参数和 manifest 标记。

阶段结论：

- 本步未发现 P0。
- 本步新增 1 个 P1：测试已经把 online resume prefix truncation 固定为普通成功路径，必须在整改前先重写测试契约。
- 测试层总体方向是好的：已有大量 state access、fail-fast、boundary、online resync 测试。但仍存在“迁移期兜底被测试固化”的问题，需要把 strict runtime 与 legacy recovery/migration 测试拆开。
- Tools 层主要问题是 best-effort artifact 和 test runner exit-code fallback 需要显式模式化，避免在架构验证时混淆“真实成功”和“工具兼容成功”。

## 最终审查总览

完成状态：按 `docs/architecture/README.md` 当前索引列出的 architecture 相关模块，本轮已完成覆盖。证据：文档索引列出 `00-system-overview` 到 `71-online-platform-backend-and-accounts` 的 29 个主题。证据：`docs/architecture/README.md:29-59`。

已覆盖模块清单：

- 系统总览、autoload、UI 入口、Game 场景 controller、debug/profiling。
- Core engine、auto-advance、archive、phase manager、actions framework、state model、state schema/serialization、events、random/data、map、rules。
- Gameplay actions、validators、replay/timelines。
- Tools replay、testing 分层。
- Modules V2、content catalog、module development guide，以及当前主要模块 rules/content。
- Online multiplayer、platform backend/accounts、server room、NetClient、恢复房、resync、rollback。

未继续逐行审查的内容：

- 与 architecture 边界无直接关系的纯视觉 asset、字体、图片资源没有逐项审查。
- 后端每个历史/账号 API 的业务权限没有逐 endpoint 深挖；本轮只审查了和房间配置、恢复链路、replay artifact 相关的接口。
- UI 叶子组件没有全部逐行审查；已覆盖 architecture 文档中标出的 Game 场景 controller、timeline/log、online resume、module UI 边界与主要 contract tests。

最高优先级问题队列：

- [P1] Replay/EventHistory/StepTimeline 的 force execution 会绕过 action-specific validation。
- [P1] Online resume archive recovery 默认允许 prefix truncation，并且 server 恢复房与现有测试都把它当普通成功路径。
- [P1] Client archive/resync load 通过临时修改全局 `NetContext.mode` 改变 core load 语义。
- [P1] `base_rules` 中 Dinnertime/Marketing 的 confirm/server 环境耦合仍会影响联机恢复与权威状态边界。
- [P1] `NetClient` 恢复缓存层直接依赖 Game 场景 timeline/log builder，autoload 与 UI 反向耦合。

主要 P2 问题簇：

- Strict Mode 被 warning-only/legacy adapter 稀释：hook、settlement、dinnertime provider、state schema warning、module manifest 默认值。
- Runtime 规则承担 migration/recovery：confirm pending、online markers、checkpoint 修补、Payday inventory 自动修补。
- Replay/timeline/event envelope 是 best-effort UI 与 strict verification 混用：空 state hash、跳过坏 event、硬编码 milestone/action、缓存过滤坏 entries。
- Online resync fallback 分类不清：delta store best-effort、snapshot assemble failure 无 failure channel、pending command flush 丢失败、server fallback reason 过粗。
- 平台/后端协议过度兜底：bad room config -> `{}`、2xx invalid JSON -> success `{}`、online client config 非法回退默认 modules dir。
- Test/tools 把一部分迁移期兜底固化为成功路径，需要先拆 strict/recovery 双轨契约。

建议整改顺序：

1. 先拆测试契约：把 online prefix truncation、callback warning-only、confirm pending recovery 改成 strict runtime 与 explicit migration/recovery 两套测试。
2. 处理 P1 恢复链路：server 恢复房 strict load、client load context 显式化、禁止 `NetContext.mode` 临时切换。
3. 统一 replay step runner：runtime/replay/EventHistory/StepTimeline 共用同一条 strict command application 语义。
4. 把 recovery/migration 从 runtime action/settlement 中移出，集中到 archive migration 或后台恢复工具，并记录修改字段。
5. 收敛 online failure channels：snapshot assemble、pending flush、delta store corruption 都要有明确 Result/signal/retry 策略。
6. 最后拆大文件与 UI/autoload 边界：`OnlineRoomResumeStore`、`ClientCommandReplayService`、`ClientSnapshotBootstrapService`、timeline/log 单一数据源。

审查完成标记：

- 当前 architecture 文档索引内没有剩余未审模块。
- 过度兜底已按 P2 默认重新从头回扫，并对进入 archive/schema/online/server 权威链路的问题上调为 P1。
- 后续工作应进入“按优先级整改与补测试”阶段，而不是继续扩大审查范围。

### Step 11：main 同步后新增改动增量审查

日期：2026-05-01

同步与基线：

- 已执行 `git merge --ff-only main`，工作树从 `7abb9152` 快进到 `904665cd`。
- 当前审查基线：`HEAD = 904665cd`，与本地 `main` 一致（当前 worktree 仍是 detached HEAD）。
- 增量范围按同步前后区间 `7abb9152..904665cd` 识别，共 16 个提交。

增量范围：

- Lobbyists 放置动作面板与模块 UI 扩展：
  - `modules/lobbyists/module.json`
  - `modules/lobbyists/ui/lobbyists_placement_flow_controller.gd`
  - `modules/lobbyists/ui/components/lobbyists_placement/action_panel_lobbyists_placement_context.gd`
  - `modules/lobbyists/ui/components/lobbyists_placement/lobbyists_placement_overlay.gd`
  - `ui/scenes/game/panel/placement_overlays.gd`
  - `ui/components/action_panel/action_panel_context_controller.gd`
- Lobbyists piece preview / roadworks rendering：
  - `ui/utils/piece_preview_layout.gd`
  - `ui/components/action_panel/piece_picker_button.gd`
  - `ui/scenes/game/map/drawer/passes/structures_pass.gd`
  - `ui/scenes/game/map/drawer/texture_utils.gd`
  - `ui/overlays/distance_overlay.gd`
  - `ui/scenes/game/map_interaction/distance_tool_controller.gd`
- 零命令 snapshot / 手工存档载入：
  - `ui/scenes/game/game.gd`
  - `ui/scenes/game/timeline/controller.gd`
  - `testdata/saves/manual_cases/employees/lobbyist.json`
  - `ui/scenes/tests/game_timeline_zero_command_snapshot_test.gd`
- 测试入口：
  - `ui/scenes/tests/all_tests_refs.gd`
  - `ui/scenes/tests/all_tests_plan.gd`
  - `ui/scenes/tests/placement_staff_picker_ui_test.gd`
  - `ui/scenes/tests/piece_preview_layout_test.gd`
  - `ui/scenes/tests/distance_overlay_roadworks_penalty_test.gd`
  - `ui/scenes/tests/manual_test_saves_smoke_test.gd`

采集命令：

- `git status --short --branch`
- `git merge --ff-only main`
- `git diff --name-status 7abb9152..904665cd`
- `git diff --stat 7abb9152..904665cd`
- `git log --oneline --decorate 7abb9152..904665cd`
- 对同步后的实际文件使用 `nl -ba <path> | sed -n ...` 定点阅读。
- `rg -n "NET_MODE_ONLINE_CLIENT|staff_id|command_history\\.is_empty\\(\\)|placement_overlays|load\\(path\\)" ...`

说明：以下结论已在同步后的实际工作树上复核，不再基于未同步状态下的 `HEAD..main` 只读比较。

已确认的正向变化：

- Lobbyists 的放置 UI 开始走 manifest 暴露的 `provides.ui.placement_overlays`，方向上比把模块 UI 硬编码进主 Game scene 更好。证据：`modules/lobbyists/module.json:16-20` 与 `ui/scenes/game/panel/placement_overlays.gd:449-484`。
- Piece preview 的几何计算被抽到 `ui/utils/piece_preview_layout.gd`，并被 action panel 和地图绘制复用，减少了 road/park 预览布局的手写分散。证据：`ui/utils/piece_preview_layout.gd:1-176`、`ui/components/action_panel/piece_picker_button.gd:108-151`、`ui/scenes/game/map/drawer/passes/structures_pass.gd:632-705`。
- Roadworks 距离修正让起点/终点 marker 在正反方向都按同一规则计入，并补充了 endpoint/reverse 测试。证据：`ui/overlays/distance_overlay.gd:185-190`、`ui/scenes/game/map_interaction/distance_tool_controller.gd:567-572`、`ui/scenes/tests/distance_overlay_roadworks_penalty_test.gd:42-80`。
- 新增 `GameTimelineZeroCommandSnapshotTest` 把 lobbyist 手工零命令存档载入后右侧动作面板可用的场景纳入 AllTests。证据：`ui/scenes/tests/all_tests_plan.gd:1090-1094`、`ui/scenes/tests/game_timeline_zero_command_snapshot_test.gd:95-140`。

发现：

- [P2] 零命令 archive 被无条件视为“可继续操作”的手工 snapshot，回放语义与存档语义继续混在同一入口。
  - 证据：`start_replay_from_file(...)` 中 `should_enter_playable := bool(replay_load_playable) or engine.command_history.is_empty()`；只要命令历史为空，即使 `Globals.replay_load_playable=false` 也进入 `_enter_loaded_archive_as_playable(...)`。证据：`ui/scenes/game/timeline/controller.gd:448-498`。
  - 证据：新增测试显式把 `Globals.replay_load_playable=false`，再断言零命令 lobbyist 存档“不应进入只读回放模式”、ActionPanel 不应禁用、且不打开右侧日志面板。证据：`ui/scenes/tests/game_timeline_zero_command_snapshot_test.gd:101-138`、`272-289`。
  - 风险：任何零命令 archive 都会被解释为可操作手工快照，而不是只读 replay。这里用 `command_history.is_empty()` 推断 archive 类型，属于新的过度兜底：缺少日志不等于用户希望进入可变对局。
  - 建议：archive 增加明确 metadata，例如 `archive_kind = "manual_snapshot" | "replay"` 或 `load_mode = "playable_snapshot"`；`start_replay_from_file` 只根据显式 metadata/调用参数进入可操作模式，不能仅凭空命令历史。
  - 状态：Fix 43 已移除 `engine.command_history.is_empty()` 隐式推断，改为 `Globals.replay_load_playable` 或 archive 显式 `ui_load_mode == "playable_snapshot"` 才进入可操作模式，并补未标记零命令 archive 的只读负例。

- [P2] 模块提供的 placement overlay 控制器按 best-effort 动态加载，新增 lobbyists 主放置 UI 已依赖这条不严格链路。
  - 证据：`lobbyists` manifest 新增 `provides.ui.placement_overlays`，包含 `lobbyists_placement_flow_controller.gd` 与 `lobbyists_extra_tile_flow_controller.gd`。证据：`modules/lobbyists/module.json:16-20`。
  - 证据：`PlacementOverlays._ensure_module_overlay_controllers_loaded()` 对 `manifest_val` 非 `ModuleManifest`、`ui` 非 Dictionary、`placement_overlays` 非 Array、路径为空/重复都直接 `continue`；`load(path)` 不是 Script 时也不报错；成功与否没有 Result/warning。证据：`ui/scenes/game/panel/placement_overlays.gd:449-484`。
  - 风险：该扩展点现在承载 Lobbyists 主入口。若路径拼错、脚本构造函数签名不匹配、资源不是 Script，UI 会静默降级；`place_lobbyists_park` 又在 manifest `hidden_action_ids` 中，用户可能只看到部分或错误的通用 piece placement。
  - 建议：在 modules_v2 装配或 GamePanel 初始化阶段校验 `provides.ui.placement_overlays` schema、资源存在性、脚本构造契约；失败应返回清晰错误或至少进入可见诊断，不应静默跳过。
  - 状态：Fix 72 复核当前 `PlacementOverlays` 已对 module manifest、路径、Script 类型、controller 创建与必要方法做严格校验；加载失败会返回 `Result.failure`、缓存错误并显示 toast 诊断。

- [P2] Lobbyists 新 UI 选择具体 `staff_id`，但 road/park action 仍只按聚合次数计数，UI 表达的“具体员工选择”与权威规则不一致。
  - 证据：新 flow controller 会把选中的 `staff_id` 写入 command params。证据：`modules/lobbyists/ui/lobbyists_placement_flow_controller.gd:196-223`。
  - 证据：UI employee items 从 `players[].employees`、`staff_registry`、`employees_staff_ids` 推出具体员工卡，并用 `lobbyists_place_counts` 把前 N 个 staff 标成 used。证据：`modules/lobbyists/ui/lobbyists_placement_flow_controller.gd:371-413`、`462-473`。
  - 证据：`place_lobbyists_road` 与 `place_lobbyists_park` 的校验只看 `EmployeeRules.count_active_by_usage_tag_for_working(...)` 和 `RoundStateCounters.get_player_count(...)`，apply 时也只递增 `lobbyists_place_counts`；动作实现没有读取或校验 command.params.staff_id。证据：`modules/lobbyists/actions/place_lobbyists_road_action.gd:54-64`、`230-249`；`modules/lobbyists/actions/place_lobbyists_park_action.gd:48-58`、`152-168`。
  - 风险：UI 现在表现为“选择哪一个说客”，但 server/core 权威层实际只消费“本玩家本子阶段用了几次说客”。如果 staff order、staff_registry、旧存档迁移或客户端传参异常，UI 灰显/选择与规则消耗会漂移；联机下恶意/坏客户端传不可用 `staff_id` 也不会被权威 action 拒绝。
  - 建议：二选一：要么 Lobbyists action 正式接入 `StaffState`，校验并消耗具体 `staff_id` 的 `use:lobbyists` track；要么 UI 不暴露具体 staff_id，只展示聚合可用次数，避免伪造一个不存在的权威语义。
  - 状态：Fix 71 复核当前 road/park action 已接入 `LobbyistsStaffUsage`，会校验显式 `staff_id` 的可用性并消耗 `StaffState` 的 `lobbyists` track；`LobbyistsRoadStateAccessTest` 已覆盖指定第二个说客只消耗第二个、指定已用完说客会失败。

- [P2] 新增 `lobbyists_placement_flow_controller.gd` 硬编码 `NetContext.Mode.ONLINE_CLIENT == 1`，和其它模块 UI 的联机判断方式不一致。
  - 证据：该文件定义 `const NET_MODE_ONLINE_CLIENT := 1`，再通过 `/root/NetContext` 读取 `mode` 并与常量比较。证据：`modules/lobbyists/ui/lobbyists_placement_flow_controller.gd:12`、`321-337`。
  - 证据：当前 enum 中 `ONLINE_CLIENT = 1`，但这是 `autoload/net_context.gd` 的实现细节。证据：`autoload/net_context.gd:4-8`。
  - 对比：同模块已有 `lobbyists_extra_tile_flow_controller.gd` 直接使用 `NetContext.Mode.ONLINE_CLIENT`。证据：`modules/lobbyists/ui/lobbyists_extra_tile_flow_controller.gd:69-83`。
  - 风险：枚举顺序一旦调整，新 Lobbyists 主放置 UI 会错误判断在线本地玩家回合，可能在在线客户端显示/隐藏错误操作入口。
  - 建议：改为直接使用 `NetContext.Mode.ONLINE_CLIENT`，或抽 `OnlinePhaseInteraction`/UI session helper；避免模块 UI 复制 autoload enum 数值。
  - 状态：Fix 38 已移除硬编码数值，改为直接读取 `net_context.Mode.ONLINE_CLIENT` 与 `net_context.local_player_id`。

- [P3] Lobbyists placement flow controller 新增 523 行，集中处理 manifest UI 扩展、员工列表派生、地图高亮/预览、命令构造、ActionPanel context 绑定与 refresh。
  - 证据：`modules/lobbyists/ui/lobbyists_placement_flow_controller.gd` 新增 523 行；其中 `_show_overlay`、`_refresh_map_selection`、`_on_placement_confirmed`、`_build_lobbyist_employee_items`、`_bind_action_panel_context` 均在同一文件内。证据：`modules/lobbyists/ui/lobbyists_placement_flow_controller.gd:82-120`、`161-235`、`274-292`、`371-413`。
  - 风险：这是模块 UI 层可以接受的短期整合，但后续如果继续增加 park/road/extra-tile 规则、online 约束和 staff usage，它会很快变成模块内的第二个 GamePanel controller。
  - 建议：若继续扩展，拆出 `LobbyistsPlacementViewModel`（从 state 派生员工/可选 pieces）、`LobbyistsPlacementCommandBuilder`（构造 command params）、`LobbyistsPlacementActionPanelBinder`（绑定 context）三类 helper。
  - 状态：Fix 58 已先拆出 `LobbyistsPlacementCommandBuilder`；Fix 73 继续拆出 `LobbyistsPlacementViewModel` 与 `LobbyistsPlacementActionPanelBinder`，flow controller 从 449 行降到 345 行，保留生命周期/地图交互/命令执行职责。

暂不列为问题：

- `game.gd` 在 main-menu replay 启动时不再先 `_initialize_game()`，避免 pending replay 被本地新局覆盖；本轮看是针对零命令 snapshot 的必要修正，不单独列问题。证据：`ui/scenes/game/game.gd:263-266`。
- `distance_overlay` 与 `distance_tool_controller` 同步改为对路径全点计 roadworks penalty，并有 forward/reverse endpoint 测试；本轮不列为架构问题。
- `EmployeePicker` 改为运行时 load registry，并允许 caller 直接传 `employee_def`；作为 UI 组件复用策略可接受，但如果后续要在 core/headless 纯逻辑中复用，需要再拆 registry adapter。

新增测试缺口：

- 缺少“零命令但 metadata 标记为 replay/readonly 的 archive 不应自动进入 playable”的负例。
- 缺少 `provides.ui.placement_overlays` 指向无效路径/非 Script/构造函数签名错误时必须失败或给出可见诊断的测试。
- 缺少 Lobbyists action 对 `staff_id` 的权威校验测试：已使用 staff、非本玩家 staff、不存在 staff 应失败；或者明确测试 action 不接受 `staff_id` 语义。
- 缺少在线客户端场景下 Lobbyists 主放置 UI 的本地玩家回合 gating 测试，避免硬编码 enum 数值导致回归。

增量结论：

- 本轮 main 增量未发现新的 P0/P1。
- 新增 P2 主要集中在“为了修复 UI 流程而引入新的隐式推断/动态兜底”：零命令 archive 自动变 playable、module UI extension 静默加载、staff picker 表达的具体员工语义没有进入权威 action。
- 这些问题与前面总审查中的主线一致：strict runtime、显式 metadata、显式 extension contract，需要和 best-effort UI/手工测试工具分开。

## 整改记录

### Fix 1：online resume prefix recovery 默认 strict

日期：2026-05-01

对应问题：

- Step 8 `[P1] Online resume archive recovery 默认允许 prefix 截断并返回成功`。
- Step 9 `[P1] Server 恢复房创建实际使用了 prefix recovery 默认截断路径`。
- Step 10 `[P1] 测试已经明确固定 online resume archive prefix truncation 为成功行为`。

改动：

- `core/engine/game_engine/archive_recovery.gd`：`load_for_online_resume(...)` 默认改为 `allow_prefix_recovery=false`；新增显式 `load_for_online_resume_with_prefix_recovery(...)`，把灾难恢复/截断语义从普通 online resume 入口分离出来。
- `server/room.gd`：`configure_resume_lobby(...)` 显式以 strict 模式调用 `load_for_online_resume(..., false)`，普通恢复房不再接受可截断坏尾部存档。
- `core/tests/online_resume_archive_recovery_test.gd`：拆分测试契约。普通 online resume 默认拒绝坏尾部命令；显式 prefix recovery helper 仍允许截断并要求返回 `truncated/recovered_command_count/failed_command_index`；普通恢复房创建失败后不得留下房间。

验证：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`389/389`。

结论：

- 已完成该 P1 的第一阶段整改：普通 UI/server 恢复入口回到 strict load；prefix truncation 只保留在显式 recovery helper 中。
- 后续如果需要面向运维/用户暴露 prefix recovery，需要另建带明确 UI/后台标记的恢复模式，并把截断审计信息写入房间状态或后端 artifact。

### Fix 2：replay/timeline rebuild 禁止 force execution 绕过动作校验

日期：2026-05-01

对应问题：

- Step 8 `[P1] Replay/EventHistory/StepTimeline 在 actor 不匹配或 pending-blocked skip 时会走 compute_new_state_force(...)`。
- Step 10 中关于测试固定 `pending-blocked skip` 与 force replay 契约的缺口。

改动：

- `core/engine/game_engine/replay.gd`：`should_force_execute_in_replay(...)` 改为始终返回 `false`。archive load、full replay、rewind、EventHistoryRebuild、StepTimeline full/append 与 command index replay 不再因为 `debug_force`、actor mismatch 或 pending-blocked skip 进入 `compute_new_state_force(...)`。
- `core/tests/step_timeline_force_execute_actor_mismatch_test.gd`：从“允许 out-of-turn/debug_force replay”改为 strict 负例，覆盖 replay execute、StepTimelineBuild、EventHistoryRebuild、full_replay、rewind_to_command 与 archive load。
- `core/tests/skip_cleanup_pending_regression_test.gd`：坏 archive 中 `skip` 位于 Cleanup pending 之前时必须加载失败；正常 `choose_fridge_keep` archive 仍保持成功。
- `core/tests/server_resync_guard_test.gd`：修正 actor-scope rewind 测试构造，直接修改 state 后同步初始 checkpoint，避免测试依赖 force replay 掩盖不一致 checkpoint。

验证：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`389/389`。

结论：

- 已完成该 P1 的严格化整改：历史命令重放链路不再使用 force execution 跳过 action-specific validation。
- 运行时 debug 面板的显式 `compute_new_state_force(...)` 能力未在本次移除；它仍属于调试命令执行语义，不再被 replay/archive/timeline rebuild 自动复用。

### Fix 3：教学运行时只允许由规则教学入口触发

日期：2026-05-01

对应问题：

- 用户补充反馈：载入回放等非规则教学模式仍有残留教学；期望教学只存在于“规则教学”中。
- 本项属于 UI/onboarding 运行边界问题：全局设置项 `tutorial_enabled=true` 被当成运行时教学开关，导致普通模式、回放/加载路径存在误触发空间。

改动：

- `autoload/globals.gd`：移除 `tutorial_enabled` 全局字段和 `apply_tutorial_preferences_from_settings(...)`；`is_tutorial_runtime_enabled()` 只根据规则教学入口写入的运行时标记判断，包括 `tutorial_pending_setup_tour`、`tutorial_pending_game_ui_tour`、`tutorial_pending_flow_tutorial`、`tutorial_match_enabled`。
- `autoload/globals.gd`：新增 `clear_tutorial_runtime_flags()`，并在 `reset_game_config()` 中复用，避免规则教学运行标记散落清理。
- `ui/scenes/menus/main_menu.gd`、`ui/scenes/game/game.gd`：进入本地新局、联机大厅、载入回放，以及 Game 场景消费 pending replay path 时，显式清理教学运行标记。
- `ui/dialogs/settings_dialog.gd`、`ui/dialogs/settings_dialog.tscn`、`ui/scenes/game/overlay/controller.gd`：设置页移除“启用新手教学”开关；当时保存设置仍清理旧 `game/tutorial_enabled` 配置键。后续补充更新已继续移除“重置规则教学进度”入口，Fix 30 已进一步移除设置保存路径中的教学历史键清理。
- `ui/scenes/game/controllers/tutorials_controller.gd`、`ui/scenes/game/controllers/tutorial_match_runtime.gd`、`ui/components/modal_panel/reserve_card_selection_modal.gd`：移除对 `Globals.tutorial_enabled` 的兜底依赖。
- `ui/scenes/tests/tutorial_runtime_scope_test.gd`：新增教学运行范围契约测试，固定“无规则教学运行标记时普通模式不启用教学；规则教学 pending/match 标记才启用教学”的行为。
- `docs/architecture/22-ui-onboarding-tutorials.md`、`docs/tutorial_onboarding_design.md`：同步移除 `tutorial_enabled` 的设计记录。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成本次补充修复：教学运行时不再有用户设置总开关，也不会因默认设置在普通模式、回放/加载路径误触发。
- 后续如果需要新增其他教学类型，应新增明确入口和独立运行标记，不能复用全局“教学启用”式开关。

补充更新（2026-05-01）：

- 用户进一步明确：规则教学已有主动入口后，不再需要“已看过/重置进度”标记；设置页也不应保留教学进度入口。
- `autoload/globals.gd`：删除 `TUTORIAL_PROGRESS_VERSION`、`tutorial_setup_tour_seen`、`tutorial_game_ui_tour_seen`、`tutorial_flow_hints_seen` 及相关读写方法；`request_rules_tutorial()` 仅清理并设置本次运行时标记。
- `ui/dialogs/settings_dialog.gd`、`ui/dialogs/settings_dialog.tscn`：移除“教学”设置分组和“重置规则教学进度”按钮；当时保存设置仍清理旧 `tutorial/progress_version`、`setup_tour_seen`、`game_ui_tour_seen`、`flow_hints_seen` 等历史键，Fix 30 已进一步移除这段兼容清理。
- `ui/scenes/setup/controllers/tutorials_controller.gd`：Setup 导览完成/跳过只清理 pending 标记，不再写持久化进度；启动游戏时每次规则教学都继续触发 Game UI 导览和流程提示。
- `ui/scenes/game/controllers/tutorials_controller.gd`：上下文导览与流程提示的去重改为控制器实例内 `_seen_tutorial_ids`，只约束本次规则教学，不再写入用户设置。
- `ui/scenes/tests/tutorial_runtime_scope_test.gd`、`ui/scenes/tests/game_tutorial_targets_contract_test.gd`：同步移除对持久化教学进度字段的依赖。
- `docs/architecture/22-ui-onboarding-tutorials.md`、`docs/tutorial_onboarding_design.md`：更新设计说明，明确教学进度不再持久化。
- 追加复核：继续清理文档中残留的“教学设置持久化”“设置页开关 + 重置教学进度”“Globals 负责进度与偏好”等旧描述；当时设置页只保留历史配置键清理逻辑，Fix 30 已进一步移除设置路径中的所有教学配置处理。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

### Fix 4：online archive/resync 加载不再临时切换 NetContext.mode

日期：2026-05-01

对应问题：

- Step 8 `[P1] 联机 archive/resync 加载路径依赖全局 NetContext.mode 临时切换到 HOTSEAT，规则执行语义被 autoload 运行模式反向影响`。
- Step 8/10 的测试缺口：缺少“客户端 archive load 不得修改 `NetContext.mode`”的回归测试。

改动：

- `autoload/net_client/client.gd`：`_load_archive_for_online_client(...)` 直接调用 `engine.load_from_archive(...)`，移除 `ONLINE_CLIENT -> HOTSEAT -> ONLINE_CLIENT` 的全局模式切换。
- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`、`modules/base_rules/rules/phase/marketing_settlement.gd`：online confirm 是否启用只读取 `state.rules/round_state` 中显式 `online_require_*_confirm` marker，不再通过 `NetContext.mode` 隐式启用。
- `core/tests/online_dinnertime_confirm_enforced_test.gd`、`core/tests/online_resume_start_validation_test.gd`、`core/tests/game_online_resync_reconnect_flow_test.gd`：测试构造改为通过 `OnlineResumePointValidator.prepare_engine_for_online_resume(...)` 写入 marker，预期从“HOTSEAT 读档语义”改为“显式 marker 读档语义”。
- `core/tests/online_resume_single_full_engine_cache_test.gd`：新增 mode probe，验证 `_load_archive_for_online_client(...)` 期间 progress callback 看到的 `NetContext.mode` 始终保持 `ONLINE_CLIENT`，读档后也不被改写。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P1 的第一阶段整改：联机 archive/resync 加载不再通过写全局 `NetContext.mode` 改变规则执行语义。
- 当前仍保留 `OnlineResumePointValidator.prepare_engine_for_online_resume(...)` 对恢复点写入 marker/修复 pending 的行为；这对应 Step 8 的另一个 P1（validator mutation/repair），需要作为后续独立整改继续拆分。

### Fix 5：OnlineResumePointValidator 的 validate 路径不再污染传入 engine

日期：2026-05-01

对应问题：

- Step 8 `[P1] OnlineResumePointValidator 同时 validate + repair，并在校验过程中改写权威 state/checkpoint` 的第一阶段拆分。
- Step 10 测试缺口：缺少 `OnlineResumePointValidator` 对验证调用不得修改原 engine 的回归测试。

改动：

- `core/engine/game_engine/online_resume_point_validator.gd`：`validate_resume_point(...)` 改为先从传入 engine 构造验证快照，再在独立 validation engine 上执行 prepare/validate，因此不再修改调用方传入的 engine、rules 或 checkpoint。
- `core/engine/game_engine/online_resume_point_validator.gd`：新增 `prepare_and_validate_resume_point(...)`，保留“恢复房真正启动前需要写入 online confirm marker 并校验”的显式路径。
- `server/room.gd`：恢复房 `_prepare_effective_resume_start_engine()` 改用 `prepare_and_validate_resume_point(...)`，让启动用的 prepared engine 仍显式写入 marker，但不再依赖 `validate_resume_point(...)` 的副作用。
- `core/tests/online_resume_archive_recovery_test.gd`：新增 `validate_resume_point` no-mutate 契约，验证调用后原 engine 的 `state.compute_hash()`、`state.rules`、archive initial checkpoint 均不被写入 online confirm marker。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成 validator 职责拆分的第一步：预览/校验调用不再污染原始恢复点；实际恢复房启动仍通过显式 prepare 路径写入运行所需 marker。
- 尚未完全移除 `prepare_engine_for_online_resume(...)` 内部对 pending/confirmed_players 的修复逻辑；该部分仍对应 Step 8 的“repair 过度兜底”后续整改。

### Fix 6：Dinnertime/Marketing settlement 拒绝损坏的 online confirmed_players

日期：2026-05-01

对应问题：

- Step 6 `[P1] Dinnertime/Marketing confirmed_players 损坏时静默重建，并仅 warning pending mismatch`。
- Step 8 中关于 `OnlineResumePointValidator`/online pending repair 的后续拆分：权威结算路径不应把已经存在但损坏的 confirmed 状态覆盖成默认值。

改动：

- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`：online confirm 启用时，`online_dinnertime_confirmed_players` 缺失才创建默认数组；字段已存在但不是 Array、长度不等于玩家数、元素不是 bool/int/整数 float 时直接 `Result.failure`。
- `modules/base_rules/rules/phase/marketing_settlement.gd`：同样 strict 校验 `online_marketing_confirmed_players`，不再把损坏字段静默覆盖为默认 confirmed 数组。
- `core/tests/dinnertime_settlement_test.gd`：新增非法 `online_dinnertime_confirmed_players` 负例，断言晚餐结算失败且失败时不改写原字段。
- `core/tests/marketing_settlement_fail_fast_test.gd`：新增非法 `online_marketing_confirmed_players` 负例，断言营销结算失败且失败时不改写原字段。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成 confirmed_players 损坏重建路径的 strict 化：缺失字段表示新进入 confirm gate，可以初始化；损坏字段表示状态不可信，必须失败。
- confirm action 中 legacy global pending 与 missing pending recovery 仍是单独 P2 问题，尚未在本次提交中改动。

### Fix 7：confirm_dinnertime/confirm_marketing 拒绝 legacy pending 与 missing pending recovery

日期：2026-05-01

对应问题：

- Step 7 `[P2] Dinnertime/Marketing confirm action 仍保留 legacy global pending 和 confirmed_players 长度恢复路径`。
- Step 10 `[P2] confirm 测试把 legacy global confirm 与 missing pending recovery 固定为成功行为`。

改动：

- `gameplay/actions/confirm_dinnertime_action.gd`、`gameplay/actions/confirm_marketing_action.gd`：legacy global pending（`["confirm_*"]`）不再被接受；validate/apply 均直接失败。
- 两个 confirm action 的 `online_*_confirmed_players` 长度不等于玩家数时改为失败，不再返回空数组触发 fallback。
- 两个 confirm action 在 confirmed_players 存在时要求 pending list 与 confirmed 状态一致：未确认玩家必须有 per-player pending；已确认玩家不得仍在 pending；重复或越界 player_id 直接失败。
- apply 阶段不再用 confirmed_players 重建 pending list，而是只移除本次 actor 对应的既有 pending，防止“缺 pending”被恢复成看似正常的状态。
- `core/tests/confirm_dinnertime_pending_phase_actions_key_test.gd`、`core/tests/confirm_marketing_pending_phase_actions_key_test.gd`：原 legacy/recovery 成功用例改为负例，断言失败时不改写 pending 与 confirmed state。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成 confirm action 层面的 P2 strict 化：旧格式 pending 与 confirmed/pending 不一致不再被默默修复。
- 如果以后需要导入旧 archive，应放到显式 migration/recovery 路径中处理，而不是常规 action 执行路径。

### Fix 8：base_rules 关键里程碑触发失败不再降级为 warning

日期：2026-05-01

对应问题：

- Step 6 `[P1] 多处关键里程碑触发失败被降级为 warning，结算仍成功`。
- 过度兜底复审中确认：Waitress `UseEmployee`、Marketing `DemandMarked`、Payday `PaySalaries`、Cleanup `CleanupDiscard` 都属于规则状态写入点；`MilestoneSystem.process_event(...)` 失败意味着 registry/context/effect 执行不可信，不应继续把阶段结算标记为成功。

改动：

- `modules/base_rules/rules/effects.gd`：女服务员 tips 触发 `UseEmployee/waitress` 失败时直接返回 `Result.failure`，不再设置 `use_employee_triggered=true`；成功时继续透传 `ms.warnings`。
- `modules/base_rules/rules/phase/marketing_settlement.gd`：`DemandMarked` 触发失败时直接使 Marketing settlement 失败；成功时透传 milestone warnings。
- `modules/base_rules/rules/phase/payday_settlement.gd`：`PaySalaries` 触发失败时直接使 Payday settlement 失败；成功时透传 milestone warnings。
- `modules/base_rules/rules/phase/cleanup_settlement.gd`：`CleanupDiscard` 触发失败时直接使 Cleanup settlement 失败；成功路径保持 warning 透传。
- `core/tests/dinnertime_settlement_test.gd`、`core/tests/marketing_settlement_fail_fast_test.gd`、`core/tests/payday_salary_test.gd`、`core/tests/cleanup_inventory_test.gd`：新增四个 fail-fast 回归用例，通过临时移除当前 `MilestoneEffectRegistry` 验证上述触发点不再 warning-only。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P1 的 strict 化：关键里程碑触发失败现在会中止对应规则效果或阶段结算，不再把不可信状态以 warning 形式吞掉。
- 结算函数本身仍不是事务式回滚模型；若未来继续收紧规则执行一致性，应单独评估 settlement apply 的状态提交边界。

### Fix 9：非法 modules_v2_base_dir 不再回退默认模块目录

日期：2026-05-01

对应问题：

- Step 3 `[P1] 存档加载遇到非法 modules_v2_base_dir 会回退默认模块目录，而不是拒绝加载`。
- Step 3 `[P2] 新局初始化遇到非法 modules_v2_base_dir 会回退默认目录`。
- Step 8 `[P2] Online client 从 server config 初始化 engine 时，modules_v2_base_dir 非法会回退默认目录`。

改动：

- `core/engine/game_engine/loader.gd`：archive 中的 `modules_v2_base_dir` 解析失败时直接 `Result.failure`，不再追加 warning 后使用 `GameDefaults.DEFAULT_MODULES_V2_BASE_DIR`。
- `core/engine/game_engine/initializer.gd`：调用方显式传入非空但非法的 `modules_v2_base_dir` 时直接初始化失败；空字符串仍表示使用默认模块目录。
- `autoload/net_client/client.gd`：联机 `GameStarted.config.modules_v2_base_dir` 缺失/为空/非法时直接 bootstrap 失败，不再回退默认目录，避免客户端模块装配与服务端权威配置分叉。
- `autoload/globals.gd` 的 UI 用户偏好归一化未改动：用户设置损坏时仍可恢复默认目录，但恢复后的值再传入 engine。
- `core/tests/archive_file_roundtrip_test.gd`、`core/tests/module_system_v2_bootstrap_test.gd`、`core/tests/online_client_config_bootstrap_overrides_test.gd`：新增非法 base dir 负例，覆盖 archive load、engine initialize 和 online client config bootstrap。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P1/P2 同源问题的 strict 化：权威运行路径不再把非法模块目录解释成默认模块集。
- 仍保留 UI 设置层的用户偏好恢复默认行为，边界是“进入 engine/server/client bootstrap 前必须已经是合法 res:// spec”。

### Fix 10：Payday settlement 不再修补损坏的 player.inventory

日期：2026-05-01

对应问题：

- Step 4 / Step 6 `[P2] Payday settlement 对缺失/错误的 player.inventory 自动修补为空字典`。

改动：

- `modules/base_rules/rules/phase/payday_settlement.gd`：用 `PlayerStateAccess.require_inventory(...)` 读取 `player.inventory`；缺失或类型错误直接失败，不再 warning 后写回 `{}`。
- `core/tests/payday_settlement_state_access_test.gd`：新增 `player.inventory` 类型错误负例，断言失败时不改写 `players/bank/round_state`。
- `core/tests/payday_salary_test.gd`：补全手写最小 `GameState` fixture 的 `inventory` 字段，使测试 fixture 符合运行时 state schema。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：Payday 权威结算不再把坏库存字段解释成“没有 token”。
- 如果需要兼容旧 archive，应在显式 migration/recovery 阶段补齐 `inventory` 并记录迁移，而不是在结算时静默修改。

### Fix 11：Cleanup 里程碑池清理拒绝损坏的 milestones_claimed entry

日期：2026-05-01

对应问题：

- Step 6 `[P2] Cleanup 里程碑池清理对 milestones_claimed[milestone_id] 的错误结构按 1 份处理`。

改动：

- `modules/base_rules/rules/phase/cleanup_settlement.gd`：`round_state.milestones_claimed[milestone_id]` 必须是 `Array`；非 Array 直接 `Result.failure`，不再按 1 份兜底从 `milestone_pool` 移除。
- `core/tests/cleanup_inventory_test.gd`：新增 malformed `milestones_claimed` entry 负例，断言失败时不改写 `milestone_pool` 和 `round_state`。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：Cleanup 不再把损坏的里程碑领取结构解释为正常领取 1 份。
- 旧结构兼容应移动到显式 archive migration/recovery，而不是 Cleanup 权威结算。

### Fix 12：Cleanup opening-soon 开业逻辑拒绝不一致地图结构

日期：2026-05-01

对应问题：

- Step 6 `[P2] Cleanup “opening soon restaurant” 翻面逻辑对重复/已开业餐厅和不匹配地图结构静默跳过，最后仍清除 pending 列表`。

改动：

- `modules/base_rules/rules/phase/cleanup_settlement.gd`：`_open_opening_soon_restaurants(...)` 改为先完整校验 pending entries 与地图格子，再统一写入 `map.restaurants`、`player.restaurants` 并清除 `opening_soon` 标记。
- 同一函数现在拒绝重复 pending `restaurant_id`、已经存在于 `state.map.restaurants` 的 restaurant、地图外 cells、缺失/错误 cell structure、`piece_id`/`restaurant_id` 不匹配、缺少 `opening_soon` 标记等损坏状态。
- `core/tests/cleanup_settlement_opening_soon_state_access_test.gd`：新增已存在 restaurant 与 cell restaurant_id 不匹配负例，断言失败时不清除 pending，也不写入 map/player restaurants。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：Cleanup 不再把 opening-soon pending 与地图结构不一致解释成可跳过状态。
- 若未来要支持幂等恢复，应先验证 map/player/restaurants 三者已经一致，再由显式 recovery 路径清理 pending。

### Fix 13：Restructuring 拒绝 CEO 位于待命区的损坏状态

日期：2026-05-01

对应问题：

- Step 6 `[P2] Restructuring phase hook 会自动修复 CEO 从 reserve 到 employees，掩盖上游状态损坏`。

改动：

- `modules/base_rules/rules/phase_and_map.gd`：进入重组与离开重组时，如果 `reserve_employees` 中出现 `ceo`，直接 `Result.failure`；不再从待命区移除 CEO 并自动追加到 `employees`。
- 同一 hook 继续要求 `employees` 中存在 CEO；缺失时直接失败，不再把 reserve 中的 CEO 视为可恢复来源。
- `core/tests/base_rules_phase_and_map_state_access_test.gd`：新增进入/离开重组两个负例，覆盖 `reserve_employees=["ceo", ...]` 时必须失败，并断言失败时不会把 CEO 搬回在岗区。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：Restructuring 不再把 CEO 错位状态解释为可自动修复状态。
- 若旧存档确实存在 CEO 位于 reserve 的情况，应由显式 archive migration/recovery 处理，不能留在运行期阶段 hook 中。

### Fix 14：ActionSetup provider 错误不再创建空 ActionRegistry

日期：2026-05-01

对应问题：

- Step 2 `[P2] 动作注册 provider 缺失或错误时会创建空 ActionRegistry，初始化链路可能继续运行`。

改动：

- `core/engine/game_engine/action_setup.gd`：`build_registry(...)` 改为返回 `Result`；provider 缺失、路径为空、缺少 `build_registry`、或返回值不是 `ActionRegistry` 时直接 `Result.failure`，不再创建空 registry。
- `core/engine/game_engine/action_wiring.gd`：初始化动作注册时必须消费 `Result`，失败直接返回给 `GameEngine.initialize(...)`。
- `core/tests/engine_dependencies_injection_test.gd`：新增坏 provider 回归测试，覆盖缺少 `build_registry` 与返回 `null` 两类错误，要求初始化阶段失败。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：动作注册 provider 配置或契约错误会在 engine 初始化阶段暴露，不会延迟成“空动作集合”的运行期问题。
- 测试如需空 registry，后续应通过显式 test helper 构造，不能走生产初始化兜底。

### Fix 15：CommandRunner 事件构建 provider 初始化期校验

日期：2026-05-01

对应问题：

- Step 2 `[P2] CommandRunner 事件构建 provider 缺失时静默返回空派生事件`。

改动：

- `core/engine/game_engine/command_runner.gd`：新增事件构建 provider 解析与方法集校验，要求 provider 提供现金、里程碑、阶段、Payday、Dinnertime、Marketing、Cleanup 等事件构建方法；注入 provider 错误不再回退到 ProjectSettings provider。
- `core/engine/game_engine/initializer.gd`：新局初始化时先校验 CommandRunner event build provider，失败直接中止初始化。
- `core/tests/engine_dependencies_injection_test.gd`：补齐测试 stub 的完整事件构建方法集，并新增坏 event provider 初始化失败回归测试。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：事件构建 provider 配置或契约错误会在初始化阶段暴露，不再把缺 provider 解释为空派生事件。
- 纯展示层如需 best-effort timeline，应走独立的显式宽松构建入口，而不是依赖 CommandRunner 静默缺省。

### Fix 16：含模块状态反序列化要求 StateSchemaRegistry 已装配

日期：2026-05-01

对应问题：

- Step 2 `[P2] StateSchemaRegistry 未加载时会跳过 int-key 字典归一化`。

改动：

- `core/state/game_state_serialization.gd`：`GameState.from_dict` 解析到非空 `modules` 后，如果 `StateSchemaRegistry` 未加载，直接 `Result.failure`；空模块的纯 core 状态仍允许无 schema 反序列化。
- `core/tests/state_schema_archive_load_test.gd`：新增负例，先用含模块状态构造存档态，再强制卸载 `StateSchemaRegistry`，断言 `GameState.from_dict` 必须失败。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：含模块 state 不再能在 schema 未装配时跳过 int-key 归一化。
- 直接调用 `GameState.from_dict` 的工具/测试如果要处理模块态，必须先通过 engine/archive loader 路径装配模块 schema。

### Fix 17：模块自有字符串玩家 key 从 warning 升级为读档失败

日期：2026-05-01

对应问题：

- Step 2 `[P2] 模块自有字段出现字符串玩家 key 时只发 warning，不阻断读档`。

改动：

- `core/state/game_state_serialization.gd`：`StateSchemaRegistry.warn_if_module_owned_has_string_player_keys(...)` 检测到 module-owned 字段下存在 `"0"`/`"1"` 等字符串玩家 key 时，`GameState.from_dict` 直接失败，不再作为 warning 继续返回成功。
- `core/tests/state_schema_unregistered_module_key_warning_test.gd`：原 warning 预期改为 strict 预期；注入未注册 schema 的 `lobbyists_unregistered_test` 后，`load_from_archive(...)` 必须失败并给出字段名。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：模块漏注册 int-key schema 不再被降级为读档 warning。
- 若需要诊断损坏存档，应提供显式 recovery/inspection 工具；运行期读档路径不应继续加载 key 类型漂移的模块状态。

### Fix 18：EventTimelineBuild 缺初始 checkpoint 时 fail-fast

日期：2026-05-01

对应问题：

- Step 2 `[P2] EventTimelineBuild 缺少或损坏初始 checkpoint 时仍返回成功，并把 GAME_STARTED.state_hash 留空`。

改动：

- `gameplay/replay/event_timeline_build.gd`：`GAME_STARTED` 构建失败时直接返回 `Result.failure`；缺少 `checkpoints[0]`、checkpoint 类型错误、缺少 `state_dict`、或 `GameStartedEventBuild` 恢复失败都不再生成空 `state_hash`。
- `core/tests/event_timeline_build_test.gd`：新增缺少初始 checkpoint 的负例，断言 `build_full(...)` 必须失败并明确提到 `GAME_STARTED`/`checkpoint`。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：完整事件时间线不再产生缺 `state_hash` 的 `GAME_STARTED` 事件。
- 需要 best-effort 展示时，应提供单独的 UI 宽松构建入口，而不是让完整 replay/timeline 构建吞掉初始状态损坏。

### Fix 19：named sub-phase hook 拒绝非法 hook_type

日期：2026-05-01

对应问题：

- Step 4 `[P2] register_named_sub_phase_hook(...) 缺少 hook_type 范围校验，错误模块输入不会以 Result.failure 形式在注册阶段暴露`。

改动：

- `core/modules/v2/ruleset.gd`：`register_named_sub_phase_hook(...)` 与普通 phase/sub-phase hook 一样校验 `hook_type` 范围，非法值直接 `Result.failure`。
- `core/modules/v2/ruleset/phase_hooks.gd`：`RulesetV2PhaseHooks.apply(...)` 对手工写入的 `named_sub_phase_hooks` 字典补防御性校验。
- `core/engine/phase_manager/hooks.gd`：PhaseManager 直接注册 phase/sub-phase/named sub-phase hook 时，对未知 `hook_type` 记录 warning 并拒绝写入内部 hook 字典。
- `core/tests/module_system_v2_bootstrap_test.gd`：新增非法 named sub-phase `hook_type` 的注册与 apply 负例。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：非法 named sub-phase hook 类型会在模块注册/装配阶段暴露，不再延迟成 PhaseManager 内部字典访问风险。

### Fix 20：Phase hook callback 返回非 Result 时始终失败

日期：2026-05-01

对应问题：

- Step 4 `[P2] Phase hook callback 返回值类型错误时，非 debug 模式只 warning 后继续`。
- Step 10 `[P2] Hook/settlement callback 返回非 Result 的 warning-only 行为被 contract test 固定` 中 hook 部分。

改动：

- `core/engine/phase_manager/hooks.gd`：phase/sub-phase/named hook callback 返回非 `Result` 时立即 `Result.failure`，不再依赖 debug mode 才失败。
- `core/tests/callback_result_contract_test.gd`：hook 用例改为任何模式下都必须失败；settlement 用例暂时保留旧契约，作为下一项单独修复。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成 hook 部分 P2 strict 化：模块 hook 契约错误会在阶段推进时立即暴露，不再作为 warning 继续执行。

### Fix 21：Settlement callback 返回非 Result 时始终失败

日期：2026-05-01

对应问题：

- Step 4 `[P2] Settlement callback 返回值类型错误时，非 debug 模式只 warning 后继续`。
- Step 10 `[P2] Hook/settlement callback 返回非 Result 的 warning-only 行为被 contract test 固定` 中 settlement 部分。

改动：

- `core/rules/settlement_registry.gd`：primary 与 extension settlement callback 返回非 `Result` 时立即 `Result.failure`，不再依赖 debug mode 才失败。
- `core/tests/callback_result_contract_test.gd`：settlement 用例改为任何模式下都必须失败，并补充 extension settlement 负例。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests`：PASS，`390/390`。

结论：

- 已完成 settlement 部分 P2 strict 化：权威结算入口的回调契约错误不再作为 warning 继续推进阶段。

### Fix 22：模块供给兜底从 core 迁回模块侧 provider

日期：2026-05-01

对应问题：

- Step 4 `[P2] core/rules/module_supply_fallbacks.gd 在 core 层硬编码具体模块的 UI 供给兜底`。

改动：

- `core/modules/v2/ruleset/ui_extensions.gd`、`core/modules/v2/ruleset_builder.gd`：新增 `register_reserve_supply_provider(...)` 模块 UI 扩展注册点，作为模块侧向 UI 提供储备区供给数量的桥接。
- `gameplay/module_ui_metadata.gd`、`gameplay/module_ui_metadata_bootstrap.gd`：缓存并暴露 `reserve_supply_providers`，启动时纳入 UI metadata 统计。
- `modules/lobbyists/rules/entry.gd`：模块自身注册道路/公园 piece 的储备供给数量 provider。
- `modules/rural_marketeers/rules/entry.gd`：模块自身注册 offramp 与 rural billboard 储备供给数量 provider；billboard 剩余数量由 rural_area.giant_billboards 当前占用计算。
- `ui/components/reserve_area/reserve_area_supply_helpers.gd`：储备区 UI 改为读取 `ModuleUiMetadata.get_reserve_supply_provider_entries()`，按启用模块过滤 provider，不再引用 core 中的具体模块 fallback。
- `core/rules/module_supply_fallbacks.gd`、`core/rules/module_supply_fallbacks.gd.uid`：删除 core 层模块硬编码 fallback。
- `core/tests/ruleset_ui_extensions_facade_test.gd`、`core/tests/core_architecture_boundary_contract_test.gd`：补充 reserve supply provider 注册、metadata 缓存、clear 行为与 core UI metadata 边界白名单。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 边界整改：core 不再保存具体模块的储备供给兜底配置；模块供给数量由各模块通过 UI metadata provider 暴露，ReserveArea 只消费通用 provider 输出。

### Fix 23：Dinnertime demand provider 只接受 Result 返回值

日期：2026-05-01

对应问题：

- Step 5 `[P2] DinnertimeDemandRegistry 仍长期支持 legacy provider 返回 Array 或 null，当前模块也在使用该兼容路径`。

改动：

- `core/rules/dinnertime_demand_registry.gd`：`get_variants(...)` 不再接受 provider 直接返回 `Array` 或 `null`；provider 必须返回 `Result`，`Result.value == null` 仍表示不提供额外方案，`Result.value` 非 Array 时失败。
- `modules/noodles/rules/entry.gd`、`modules/sushi/rules/entry.gd`、`modules/kimchi/rules/entry.gd`：dinnertime demand provider 改为返回 `Result.success(Array[Dictionary])`；输入契约错误改为 `Result.failure(...)`，不再用空数组吞掉。
- `core/tests/dinnertime_demand_registry_v2_test.gd`：契约测试从“接受 Result + legacy Array”改为“只接受 Result，直接 Array/null/其他类型均失败”。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：模块 demand provider 的失败原因可通过 `Result.failure` 明确传播，错误返回值不再被 registry 当作 legacy 兼容路径继续执行。

### Fix 24：Action availability override 校验阶段与子阶段语义

日期：2026-05-01

对应问题：

- Step 5 `[P2] Action availability override 只校验 phase/sub_phase 字段形状，不校验阶段/子阶段语义是否存在或是否可达`。
- 附带问题：`action_wiring.gd` 对 malformed override item 使用静默 `continue`，模块配置错误可能被跳过而不是失败暴露。

改动：

- `core/actions/action_availability_registry.gd`：`compile_with_validation(...)` 新增可选 `phase_manager` 参数；模块 override point 会校验 phase 是否存在，以及 sub_phase 是否属于对应阶段的可达顺序。`Setup` 只允许空 sub-phase 或 `ReserveCards`，`GameOver` 只允许空 sub-phase，`Working`/`Cleanup` 使用 PhaseManager 的阶段顺序查询。
- `core/engine/game_engine/action_wiring.gd`：`action_availability_overrides` 中非 Dictionary、空 `action_id`、非 Array `points` 直接返回 `Result.failure(...)`，不再静默跳过；编译 availability 时传入 engine 的 `phase_manager` 做语义校验。
- `core/tests/action_availability_override_v2_test.gd`：新增非法 phase、非法 Working sub-phase、非法 Setup sub-phase 负例；补充 malformed override item 应让 action wiring 失败的契约测试。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：模块 action availability override 不能再指向未知或不可达的阶段/子阶段；override 配置结构错误也会在 action registry wiring 阶段失败暴露。

### Fix 25：module.json manifest 必须显式声明 schema 字段

日期：2026-05-01

对应问题：

- Step 5 `[P2] module.json 解析器对多个 schema 字段使用默认值，可能掩盖 manifest 漏字段`。

改动：

- `core/modules/v2/module_manifest.gd`：`dependencies`、`conflicts`、`entry_script`、`provides` 改为必需字段；字段可以显式为空数组、空字符串或空字典，但缺字段或 `null` 会在 manifest 解析阶段失败，不再自动补默认值。
- `core/tests/module_package_loader_v2_test.gd`：新增缺少必需字段的负例，固定 strict manifest 契约。
- `core/tests/module_plan_builder_v2_test.gd`、`modules_test/*/module.json`、`core/tests/fixtures/modules_v2_*/*/module.json`：测试模块与 fixture manifest 迁移到当前 schema，显式写出 `dependencies/conflicts/entry_script/provides`。
- `docs/architecture/60-modules-v2.md`：补充当前 schema 的 requiredness 说明，区分“显式为空”和“字段缺失”。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：首次运行因 `ModulePlanBuilderV2Test` 内联 manifest 缺少 `provides` 失败；补齐后重跑 PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：新模块 manifest 漏写关键 schema 字段会在加载模块包时立即失败；纯内容模块仍可通过显式 `entry_script: ""` 与 `provides: {}` 表达无规则入口/无额外声明。

### Fix 26：phase action UI modal 路径在 metadata 装配阶段校验资源

日期：2026-05-01

对应问题：

- Step 5 `[P2] 模块 UI modal scene path 只校验字符串前缀，不校验资源存在或可加载`。

改动：

- `gameplay/module_ui_metadata.gd`：`configure_from_ui_extensions(...)` 处理 `phase_action_ui_modals` 时，除类型、非空与 `res://` 前缀外，新增 `ResourceLoader.exists(scene_path, "PackedScene")` 与 `ResourceLoader.load(scene_path, "PackedScene")` 校验；不存在、类型不对或无法作为 `PackedScene` 加载时直接 `Result.failure(...)`。
- `core/tests/ruleset_ui_extensions_facade_test.gd`：测试注册改用真实 modal scene，并新增坏 `scene_path` 在 `ModuleUiMetadata` 装配阶段失败的负例。
- `docs/architecture/60-modules-v2.md`：记录 `phase_action_ui_modals[*].scene_path` 在 gameplay UI metadata 装配时必须是可加载 `PackedScene`。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：模块注册的 phase action modal 坏路径会在 UI metadata bootstrap 时失败暴露，不再等到用户打开 modal 时才出现 warning 或静默缺 UI。

### Fix 27：营销占地与冲突路径拒绝损坏状态

日期：2026-05-01

对应问题：

- Step 7 `[P2] base_marketing 与 initiate_marketing 在营销占地/冲突路径仍保留旧数据默认值，会掩盖 marketing_placements 或 board spec 损坏`。
- Step 7 测试缺口：缺少 `initiate_marketing` 对 malformed `drink_sources/marketing_placements/footprint_size/rotation/axis` 的 strict 测试。

改动：

- `modules/base_marketing/rules/entry.gd`：billboard footprint 解析不再把缺失/错误字段回退为 `Vector2i.ONE/0`；`marketing_instance.footprint_size` 与 `rotation` 必须显式存在且合法。airplane range 也必须读取合法 `footprint_size`，不再重置为 1x1；mailbox range 在 road graph 构建失败时返回 `Result.failure`。
- `gameplay/actions/initiate_marketing/validation.gd`：`board_spec.footprint_size` 必须显式为 `Vector2i`；`state.map.drink_sources` 必须是结构正确的数组；airplane overlap 与非 airplane overlap 对损坏的 `marketing_placements`、缺失 `world_pos/axis/footprint_size/rotation` 均 fail-fast，不再跳过或默认成 1x1/0。
- `core/state/map_state_access.gd`：新增 `require_drink_sources(...)`，让营销动作使用统一 state 访问 helper。
- `core/tests/base_marketing_state_access_test.gd`、`core/tests/initiate_marketing_overlap_state_access_test.gd`、`core/tests/initiate_marketing_airplane_overlap_state_access_test.gd`、`core/tests/marketing_campaigns_test.gd`：补充缺失/非法 footprint、rotation、axis、drink_sources 等负例。
- `core/tests/step_timeline_marketing_milestone_order_test.gd`、`core/tests/milestone_system/milestone_system_triggers_test.gd`、`core/tests/marketing_dinnertime_golden_replay_test.gd`、`core/tests/mass_marketeers_v2_test.gd`、`core/tests/new_districts_v2_test.gd`、`core/tests/marketing_settlement_fail_fast_test.gd`：迁移旧手工营销夹具，显式写入 `footprint_size` 与 `rotation`，避免测试继续依赖运行期默认兜底。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：首次运行因旧测试夹具缺少 `footprint_size/rotation` 失败；迁移夹具后重跑 PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：营销占地、饮品点冲突、飞机冲突和营销范围计算不再把损坏 state 或坏配置解释成默认 1x1/0 或空冲突。
- 旧存档/旧手工测试数据如缺少营销 footprint/rotation，应通过显式迁移或测试夹具更新处理；运行期规则路径不再承担隐式数据修复。

### Fix 28：new_milestones 不再跳过损坏的 Dinnertime 报告

日期：2026-05-01

对应问题：

- Step 7 `[P2] new_milestones 的 extension settlement 对 Dinnertime 报告结构采取“缺失即不适用、坏 entry 跳过”，会隐藏上游结算输出损坏`。
- 同项附带问题：Brand Director provider 修改 `marketing_instance.remaining_duration = -1` 后，只在 `marketing_placements` 读取成功时同步 map placement，读取失败不会让 provider 失败。

改动：

- `modules/new_milestones/rules/settlement_and_hooks.gd`：`_after_dinnertime_primary(...)` 要求 `round_state.dinnertime` 与 `sales` 显式存在且类型正确；`sales[*]` 必须是 Dictionary，`winner_owner`、`required`、required product key/value 必须合法。坏报告不再被 `continue` 跳过。
- `modules/new_milestones/rules/settlement_and_hooks.gd`：First Pizza Sold 的 radio pending 构建必须能读取合法 `marketing_placements`；placement key、`marketing_instances[*].board_number` 损坏时直接失败。pizza sale 需要的 `house_id/house_number` 也改为 strict 校验。
- `modules/new_milestones/rules/marketing_initiation.gd`：Brand Director radio 永久化必须同步到合法 `state.map.marketing_placements[board_number]`；缺失、类型错误或 board_number 非法时失败，并避免失败前部分修改 `marketing_instance`。
- `core/tests/new_milestones_pizza_pending_state_access_test.gd`：把缺失/错误 `marketing_placements` 的 fail-soft 用例改为 fail-fast，并新增缺失 `dinnertime`、错误 `sales`、坏 sale entry、坏 `required` 的负例。
- `core/tests/new_milestones_brand_director_state_access_test.gd`：Brand Director 的缺失/错误 `marketing_placements` 用例改为 fail-fast，并断言失败时不提前修改 `remaining_duration/no_release`。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：`new_milestones` 的 Dinnertime 扩展结算不再把 primary settlement 的坏报告解释成“没有相关事件”，也不再允许 Brand Director 状态只改实例、不改 map placement。

### Fix 29：coffee 模块状态访问改为 strict runtime 契约

日期：2026-05-01

对应问题：

- Step 7 `[P2] coffee 模块在 range origin、route purchase、First Coffee Sold pending 注入中存在多处过度跳过`。

改动：

- `modules/coffee/rules/coffee_actions_and_state.gd`：range origin provider 不再把负 actor、缺失 `coffee_shops`、坏 shop entry、缺失 owner 或 owned shop 缺少位置解释为空 origins；这些都改为 `Result.failure`。仍保留 `entrance_pos` 缺失时回退 `anchor_pos` 的显式数据契约。
- `modules/coffee/rules/coffee_first_coffee_sold.gd`：Dinnertime extension settlement 要求 `round_state.dinnertime.sales` 与 `sales[*].route_purchases` 结构正确；坏 sale、坏 route purchase、coffee seller 缺失/越界均失败。Cleanup pending 不再兼容 legacy `int/float` item，bonus pending player 越界也失败。
- `modules/coffee/rules/coffee_dinnertime_route.gd`：route stop index、purchase simulation、filtered simulation 与最终购买应用都校验 stop/purchase 结构；坏 restaurant/shop/stop entry、缺失 owner/id/kind、seller/price 类型错误不再跳过。
- `core/tests/coffee_range_origins_state_access_test.gd`、`core/tests/coffee_first_coffee_sold_state_access_test.gd`、`core/tests/coffee_route_state_access_test.gd`：更新旧 fail-soft/legacy pending 用例，补充 malformed coffee shop、route purchase、stop item 与 bonus pending 越界负例。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：咖啡模块不再把损坏的 module-owned state、Dinnertime route purchases 或 Cleanup pending 解释成“没有咖啡可买/没有奖励待处理”。旧 pending 形态应由迁移路径处理，而不是运行期结算兼容。

### Fix 30：设置系统完全移除教学配置兼容逻辑

日期：2026-05-01

对应问题：

- 用户进一步明确：既然已有“规则教学”主动入口，设置系统中不应再保留任何教学标记、开关、重置或历史键清理逻辑。

改动：

- `autoload/globals.gd`：`save_settings()` 不再读取或清理旧 `game/tutorial_enabled`、`game/tutorial_auto_popup` 与 `tutorial/*_seen` 等配置键；删除 `_erase_legacy_tutorial_settings(...)`。
- `ui/dialogs/settings_dialog.gd`：设置保存路径完全移除 tutorial 历史键清理逻辑；设置页不再对教学配置有任何读写/清理职责。
- `ui/scenes/menus/main_menu.gd`：规则教学按钮只调用 `Globals.request_rules_tutorial()`，移除旧版本直接写 `tutorial_pending_setup_tour` 的兼容 fallback。
- `ui/scenes/tests/tutorial_scene_boundary_contract_test.gd`：新增设置配置边界测试，防止 `Globals` 或 `SettingsDialog` 重新引入旧 tutorial 设置键。
- `docs/architecture/22-ui-onboarding-tutorials.md`、`docs/tutorial_onboarding_design.md`：同步说明设置页完全不再包含教学设置，不读取、不写入、不清理任何教学配置键。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 教学相关用户设置入口和设置保存路径已清空；规则教学仍通过主菜单入口写入一次性运行时标记串联 Setup/Game，不再通过设置或历史配置键影响普通模式、回放和加载路径。

### Fix 31：lobbyists 模块私有 map state 改为显式初始化与 strict runtime

日期：2026-05-01

对应问题：

- Step 7 `[P2] lobbyists/rural_marketeers 模块私有状态边界仍存在初始化、运行期访问和 UI 兜底混杂` 中的 lobbyists 部分。
- 具体问题：`lobbyists` 在重组 hook 中自动写入 `road_graph_connect_parallel_lanes`、供应、`lobbyists_pending_roads`、`lobbyists_roadworks_markers`；`place_lobbyists_road` apply 路径也会在缺失 pending/markers 时自动创建 `{}`/`[]`，掩盖模块初始化缺失或存档损坏。

改动：

- `modules/lobbyists/rules/entry.gd`：新增 `register_state_initializer("%s:init_state")`，在新局初始化 `road_graph_connect_parallel_lanes=true`、road/park supply、`lobbyists_pending_roads=[]`、`lobbyists_roadworks_markers={}`。
- `modules/lobbyists/rules/entry.gd`：`_on_restructuring_before_enter(...)` 改为 strict runtime 访问；缺失或错误类型的 parallel-lanes marker、supply、pending roads、roadwork markers 直接失败，不再自动补默认值。
- `modules/lobbyists/actions/place_lobbyists_road_action.gd`：`_apply_changes(...)` 在任何结构、marker、pending、supply mutation 前要求 `lobbyists_roadworks_markers` 为 Dictionary、`lobbyists_pending_roads` 为 Array；缺失/错类型直接失败，不再创建空容器。
- `core/tests/lobbyists_supply_state_access_test.gd`：把“重组 hook 初始化缺失 supply”的旧契约迁移到 state initializer；新增重组 hook 缺失 supply/pending/markers/parallel-lanes 的 fail-fast 用例。
- `core/tests/lobbyists_road_state_access_test.gd`：新增 road action 缺失 pending/markers 时失败且无 partial mutation 的回归测试。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成 lobbyists 部分 strict 化：模块私有 map state 由 initializer 明确创建，运行期规则和 action 不再承担隐式修复。UI overlay provider 的 best-effort 展示逻辑本次未改，它只负责把已存在的私有状态转换成可视 overlay，不再作为权威规则入口。

### Fix 32：rural_marketeers 模块私有 state 与冲突查询改为 strict runtime

日期：2026-05-01

对应问题：

- Step 7 `[P2] lobbyists/rural_marketeers 模块私有状态边界仍存在初始化、运行期访问和 UI 兜底混杂` 中的 rural_marketeers 部分。
- 具体问题：`rural_marketeers` 在重组 hook 中自动创建/修补 `rural_area` 和 offramp supply；offramp 冲突查询、dinnertime 入口更新、offramp action 与 airplane overlap 查询把缺失 offramps/marketing placements 或坏 entry 当成空数据跳过。

改动：

- `modules/rural_marketeers/rules/entry.gd`：新增 state initializer，负责初始化 `rural_area`、`rural_marketeers_offramp_supply_remaining` 与 `rural_marketeers_offramps=[]`。
- `modules/rural_marketeers/rules/entry.gd`：`_on_restructuring_before_enter(...)` 仅校验已初始化状态；缺失/损坏 `rural_area`、offramp supply、offramps 直接失败，不再自动创建或补字段。
- `modules/rural_marketeers/rules/entry.gd`：placement conflict provider 与 airplane-offramp validator 改为要求 `rural_marketeers_offramps` 显式存在且结构合法；坏 entry、缺失 pos/side 直接失败。
- `modules/rural_marketeers/actions/place_highway_offramp_action.gd`：offramp placements、external_cells、marketing_placements/airplane placement 读取改为 strict；`has_offramp_at_pos(...)` 改为返回 `Result`，避免 malformed offramps 被解释成“不存在冲突”。
- `core/tests/rural_marketeers_state_access_test.gd`、`core/tests/rural_offramp_state_access_test.gd`、`core/tests/rural_marketeers_dinnertime_state_access_test.gd`、`core/tests/rural_marketeers_marketing_state_access_test.gd`、`core/tests/rural_offramp_airplane_overlap_state_access_test.gd`：更新旧初始化/空数据契约，新增缺失 offramps、坏 offramps entry、坏 airplane placement、缺失 marketing_placements 的 fail-fast 覆盖。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：首次运行旧测试仍固定 fail-soft 契约，更新测试夹具后重跑 PASS，`390/390`。

结论：

- 已完成 rural_marketeers 部分 strict 化：模块私有 rural/offramp state 由 initializer 明确创建，运行期 hook、offramp action 与冲突查询不再把缺失或损坏的模块状态解释为空状态。

### Fix 33：reserve_prices 初始化拒绝非法已存在选择字段

日期：2026-05-01

对应问题：

- Step 7 `[P2] reserve_prices 初始化会把非法 reserve_card_selected 重置为 -1，而不是暴露状态损坏`。
- 具体问题：`modules/reserve_prices/rules/entry.gd` 在 `_init_state(...)` 中读取已存在 `reserve_card_selected` 时，非 int、越界或其它非法值最终会被写回 `-1`，把坏状态解释成“未选择”。

改动：

- `modules/reserve_prices/rules/entry.gd`：`_init_state(...)` 改为先校验所有玩家已有 `reserve_card_selected`，只有缺失字段才按新局初始化为 `-1`；已有字段必须是 int 且范围为 `-1..CARDS_PER_PLAYER-1`。
- `modules/reserve_prices/rules/entry.gd`：校验通过后才写入替代储备卡与 `reserve_card_revealed=false`，避免失败时留下半初始化 state。
- `core/tests/reserve_prices_v2_test.gd`：新增合法已有选择保留、越界选择失败且不发生 partial mutation、非 int 选择失败且不发生 partial mutation 的回归测试。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：`reserve_prices` 不再把损坏的已存在储备卡选择字段重置为“未选择”，初始化阶段会直接暴露坏状态。

### Fix 34：玩家动作与扩展模块的里程碑触发失败改为 fail-fast

日期：2026-05-01

对应问题：

- Step 7 `[P1] MilestoneSystem.process_event(...) 失败被降级为 warning 的模式不只存在于 base_rules，已经扩散到 gameplay actions 与多个扩展模块`。
- 具体问题：多个 action/module 在完成权威 state mutation 后，把 `Produce`、`UseEmployee`、`InitiateMarketing`、`RestaurantPlaced`、`Train`、`LowerPrice`、`HouseBuilt`、`CleanupDiscard`、`DemandMarked` 等里程碑触发失败追加为 warning，导致“动作成功但里程碑副作用缺失”。

改动：

- `gameplay/actions/employee_usage_helper.gd`：`append_use_employee_warning(...)` 改为 `apply_use_employee_event(...) -> Result`；`UseEmployee` 失败直接返回 failure，并保留 milestone warnings。
- `gameplay/actions/*`：`produce_food`、`initiate_marketing`、`place_restaurant`、`recruit`、`train`、`set_price`、`set_discount`、`place_house`、`choose_fridge_keep`、`choose_kimchi_storage`、`procure_drinks` 等权威动作改为里程碑失败即失败，不再降级为 warning。
- `modules/lobbyists/actions/*`、`modules/rural_marketeers/actions/place_giant_billboard_action.gd`、`modules/rural_marketeers/rules/entry.gd`：模块 action/settlement 的 `UseEmployee` / `DemandMarked` 触发失败改为 fail-fast。
- `gameplay/actions/procure_drinks_action.gd`：保留事件生成层的 best-effort 派生行为；权威 validate/apply 使用 strict helper，日志事件在 plan 派生失败时仅从命令参数补充展示字段，不影响动作执行契约。
- `core/tests/milestone_system/milestone_system_triggers_test.gd`：新增 action milestone handler 损坏时 `set_price` 必须失败、不得记录命令历史或写入 round_state 的契约测试。
- `core/tests/rural_giant_billboard_state_access_test.gd`：直接调用 action 的测试保留初始化 engine 引用，避免模块 milestone callback 因测试夹具释放而失效。

验证：

- `rg -n "append_use_employee_warning|with_warning\\(\"里程碑触发失败|warnings\\.append\\(\"里程碑触发失败|result\\.with_warning\\(\"里程碑触发失败" gameplay modules -g"*.gd"`：无匹配。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P1 strict 化：玩家动作和已覆盖扩展模块不再把关键里程碑触发失败吞为 warning；失败会阻断动作/结算，避免权威状态缺失里程碑副作用。

### Fix 35：archive recovery 不再反推修补 online confirm marker

日期：2026-05-01

对应问题：

- Step 8 `[P2] Archive replay import 会根据命令历史反推并补齐 online confirm 规则标记，把运行期语义迁移放进了 recovery path`。
- 具体问题：`ArchiveRecovery` 在 replay import / online resume 的普通加载路径中扫描 `confirm_dinnertime` / `confirm_marketing` 命令，并把缺失的 online confirm marker 写回 `initial_state.rules`；显式 prefix recovery 还会在 checkpoint metadata 不可用时合成空 hash checkpoint。

改动：

- `core/engine/game_engine/archive_recovery.gd`：移除 `_repair_online_confirm_markers_for_replay(...)` 以及普通导入/联机恢复中的 marker 反推修补；`load_for_online_resume(...)` 与 `load_for_replay_import(...)` 只加载调用方提供的 archive，缺 marker 会沿用 `GameEngine.load_from_archive(...)` 的 strict 失败。
- `core/engine/game_engine/archive_recovery.gd`：显式 prefix recovery 的 checkpoint metadata 由跳过坏 entry / 合成 `{hash=""}` 改为严格校验 `index/hash/rng_calls`；缺失、类型错误、空 hash 或没有可用前缀 checkpoint 都会失败。
- `core/tests/online_resume_archive_recovery_test.gd`：把缺失 marketing marker 的旧成功契约改为 online resume 与 replay import 均必须失败；新增 prefix recovery 拒绝空 hash checkpoint metadata 的负例。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：普通 archive import/resume 不再承担 online confirm marker migration；显式灾难恢复模式也不再制造不可审计的空 hash checkpoint。

### Fix 36：事件 envelope 损坏不再被日志/时间线链路跳过

日期：2026-05-01

对应问题：

- Step 8 `[P2] 事件 envelope 在 core runner、event history rebuild、EventTimeline、StepTimeline 多处被静默过滤，坏事件不会暴露`。
- 具体问题：多个链路遇到非 Dictionary event、空 `type` 或非 Dictionary `data` 时会跳过或替换为空字典，导致 runtime、EventBus history 与 timeline 可以接受不完整事件契约。

改动：

- `core/engine/game_engine/command_runner.gd`：新增 `normalize_event_envelope(...)` / `normalize_event_list(...)`，统一要求事件为 `{type: String 非空, data: Dictionary}`；runtime command 在写入 state、记录命令和 emit 事件之前校验完整事件列表，坏事件会让命令失败且不落 state/history。
- `core/engine/game_engine/event_history_rebuild.gd`、`gameplay/replay/event_timeline_build.gd`：重建/完整事件时间线不再跳过坏事件或把坏 data 替换为 `{}`，统一失败并携带 `event.data` 等具体错误。
- `gameplay/replay/step_timeline_build/*`：`append_events(...)`、phase override、first_throw_away 过滤与 phase transition 事件拆分均改为 strict `Result` 传播；StepTimeline full/append/auto-advance 构建遇到坏 envelope 会失败。
- `core/tests/engine_dependencies_injection_test.gd`：新增 malformed event provider / bad generated event action 负例，覆盖 runtime CommandRunner、EventHistoryRebuild、EventTimelineBuild、StepTimelineBuild 都必须拒绝 `data` 非 Dictionary 的事件。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：事件 envelope 从 core runtime 到 replay/timeline 派生视图都变成显式契约，坏事件不再被日志链路悄悄丢弃或降级展示。

### Fix 37：timeline cache 与 prebuilt entries 不再过滤坏项后继续使用

日期：2026-05-01

对应问题：

- Step 8 `[P2] 增量 timeline 与预构建 entry 的 cache 路径存在 “过滤坏缓存后继续使用” 的行为`。
- 具体问题：`append_from_existing(...)` 会跳过非 Dictionary 的 cached step/event，并在缺少 `_build_meta` 时从 events/steps 反推 processed command count；UI prebuilt entries 也会跳过坏 entry。

改动：

- `gameplay/replay/step_timeline_build/build_append_impl.gd`：增量 append 入口改为要求 `_build_meta.processed_command_count` 与 `_build_meta.last_event_sequence` 显式存在且为非负 int；`existing_timeline.steps/events` 必须是 Array 且所有元素为 Dictionary，否则 append 失败并交由上层 full rebuild。
- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`：`build_info_from_timeline(...)` 与 `build_info_from_prebuilt_entries(...)` 严格校验 timeline `steps/events` 和 prebuilt `entries`，不再过滤坏项后继续构建 UI 日志。
- `core/tests/step_timeline_incremental_append_test.gd`：新增缺 `_build_meta`、坏 step、坏 event、坏 prebuilt entry 的负例，固定坏缓存必须失败的契约。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：timeline cache/prebuilt 数据不再局部丢弃坏项；增量缓存失效会显式失败，让调用方使用完整重建路径。

### Fix 38：Lobbyists 主放置 UI 不再硬编码 NetContext enum 数值

日期：2026-05-01

对应问题：

- main 增量 `[P2] 新增 lobbyists_placement_flow_controller.gd 硬编码 NetContext.Mode.ONLINE_CLIENT == 1，和其它模块 UI 的联机判断方式不一致`。

改动：

- `modules/lobbyists/ui/lobbyists_placement_flow_controller.gd`：移除 `NET_MODE_ONLINE_CLIENT := 1`；在线客户端判断改为 `net_context.mode == net_context.Mode.ONLINE_CLIENT`，本地玩家读取改为 `net_context.local_player_id`，与同模块 `lobbyists_extra_tile_flow_controller.gd` 的模式一致。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 修复：Lobbyists 主放置 UI 不再复制 autoload enum 的底层数值，后续 enum 顺序调整不会破坏在线客户端回合 gating。

### Fix 39：PlatformApi 2xx 非 JSON 响应不再伪装成成功

日期：2026-05-01

对应问题：

- Step 9 `[P2] PlatformApi.parse_http_json_response(...) 对 2xx 非 JSON 响应返回 {"ok": {}}，会把后端协议错误伪装成成功`。

改动：

- `autoload/platform_api.gd`：`parse_http_json_response(...)` 改用 `JSON.new().parse(...)`，显式区分合法 `null` 与解析失败；任何响应体 JSON 解析失败都会返回 `error`，并包含 `_http_status`、`parse_error`、`parse_error_line` 与原始 `body_text`。
- `core/tests/platform_api_response_parse_test.gd`：新增合法 JSON `null` 仍为 ok、2xx 非 JSON 必须返回 error 的契约测试，防止后端协议错误再次被解释为空成功体。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：平台 API 客户端不再把坏 JSON 响应降级为成功空对象，调用方可以明确感知后端协议错误。

### Fix 40：后端房间 config_json 解析失败不再回退为空配置

日期：2026-05-01

对应问题：

- Step 9 `[P2] 后端房间配置解析失败会退回 {}，可能把坏配置解释成非恢复房或允许观战`。

改动：

- `backend/app/room_config.py`：新增严格房间配置解析 helper；空配置仍表示 `{}`，但非法 JSON 或非对象 JSON 会抛出 `RoomConfigParseError`。
- `backend/app/rooms.py`：创建房间时拒绝非法 `config_json`；读取已持久化房间配置时若发现损坏，join/resume/spectate/list/token 入口返回显式错误，不再按默认普通房间配置继续执行。
- `backend/app/rooms.py`：观战入口不再用 `except Exception: allow_spectators = True`，坏配置会阻断观战而不是默认允许。
- `backend/app/internal.py`：内部房间目录同步在写入数据库前预校验每个 `rooms[i].config_json`，坏配置返回 400，避免污染后端房间目录。
- `backend/tests/test_rooms.py`、`backend/tests/test_internal.py`：新增创建房间拒绝非法配置、内部同步拒绝非法配置、持久化坏配置不得允许观战的契约测试。

验证：

- `python3 -m py_compile backend/app/room_config.py backend/app/rooms.py backend/app/internal.py backend/tests/test_rooms.py backend/tests/test_internal.py`：PASS。
- `pytest tests/test_rooms.py::test_create_room_rejects_invalid_config_json tests/test_rooms.py::test_spectate_room_rejects_corrupt_config_json tests/test_internal.py::test_sync_room_directory_rejects_invalid_config_json -q`：PASS，`3 passed`。
- `pytest -q`（backend 目录）：PASS，`119 passed`。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：后端不再把损坏或错误类型的房间配置解释为空配置，恢复房识别与观战权限不会被坏 JSON 兜底绕过。

### Fix 41：resync 后 pending command 失败立即触发 force snapshot

日期：2026-05-01

对应问题：

- Step 9 `[P2] Resync 后的 pending command flush 与实时 command_applied 路径不一致：解析/执行失败会移除 queued command，而不是立即 resync`。
- Step 10 `[P2] Online resync 测试没有覆盖 pending command flush 的失败路径`。

改动：

- `ui/scenes/game/controllers/online_resync_controller.gd`：实时 `CommandApplied` 解析失败不再只记录日志返回，改为立即触发 `force_snapshot=true` 的 resync。
- `ui/scenes/game/controllers/online_resync_controller.gd`：`_flush_online_pending_commands_after_resync(...)` 中 pending command 解析失败或执行失败不再 `remove_at(...)` 后继续/退出成功路径，改为立即触发 `force_snapshot=true` 的 resync，并避免后续 UI 成功刷新。
- `core/tests/game_online_resync_request_rejection_test.gd`：新增实时 malformed CommandApplied、pending command 执行失败、pending command 解析失败三组契约覆盖，要求失败后进入 resync、`force_snapshot=true`，且 pending flush 失败不得走成功 UI refresh。

验证：

- 首次 AllTests 暴露测试直接给 typed `Array[Dictionary]` 属性赋未类型化数组的问题；已改为 `clear()/append()` 后重跑通过。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：resync 后积压命令的坏 envelope 或本地执行失败不会被当作可跳过项处理，客户端会立即请求强制快照，避免以不可信本地状态继续刷新 UI。

### Fix 42：snapshot 分片组装失败进入恢复失败通道

日期：2026-05-01

对应问题：

- Step 9 `[P2] 客户端 snapshot 分片组装失败只记录 error，不发失败信号或 force resync，恢复等待可能只能靠超时退出`。
- Step 10 `[P2] Snapshot assemble failure 没有测试 failure signal 或 retry`。

改动：

- `autoload/net_client/client_resync_service.gd`：`ResyncSnapshotTransfer.assemble_snapshot(...)` 失败后不再只写日志返回；现在复用 `resync_delta_failed` 失败通道，并调用 `request_resume_force_snapshot_once()`，让恢复状态机和 Game resync controller 能立即进入重试/失败处理。
- `core/tests/online_client_resync_snapshot_chunk_test.gd`：新增损坏 chunk hash 的负例，要求坏 snapshot 不发 `resync_archive_received`，必须发出一次恢复失败信号，清理 pending manifest/chunks，并请求下一次恢复强制 snapshot。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 strict 化：损坏的 snapshot 分片不会让客户端只靠超时脱离恢复等待；失败会通过既有 resync failure channel 传播，并明确要求后续恢复走强制快照。

### Fix 43：零命令 archive 不再隐式进入可操作模式

日期：2026-05-01

对应问题：

- main 增量 `[P2] 零命令 archive 被无条件视为“可继续操作”的手工 snapshot，回放语义与存档语义继续混在同一入口`。

改动：

- `ui/scenes/game/timeline/controller.gd`：移除 `engine.command_history.is_empty()` 作为进入可操作模式的判断；现在只有设置项 `Globals.replay_load_playable` 或 archive 显式声明 `ui_load_mode == "playable_snapshot"` 时才进入可操作模式。
- `ui/scenes/game/timeline/replay_session_support.gd`：新增保留 archive metadata 的 `load_replay_import_from_file(...)`，供 timeline controller 读取加载语义；原 `load_engine_from_file(...)` 保持兼容。
- `tools/generate_manual_test_saves.gd`：冻结为 initial_state 的手工复核存档会写出 `ui_load_mode: "playable_snapshot"`，后续生成的手工 snapshot 不再依赖空命令历史推断。
- `testdata/saves/manual_cases/employees/lobbyist.json`：为当前自动化覆盖的 lobbyist 手工快照补充显式 `ui_load_mode`。
- `ui/scenes/tests/game_timeline_zero_command_snapshot_test.gd`：新增“移除 `ui_load_mode` 的零命令 archive 必须保持只读回放”的负例，同时保留 lobbyist 手工快照按显式标记进入可操作模式的覆盖。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1106`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`390/390`。

结论：

- 已完成该 P2 边界整改：回放入口不再把“零命令”解释为“可继续操作”，手工 snapshot 语义由 archive metadata 显式表达。

### Fix 44：latest autosave 导出不再猜测最终 snapshot event

日期：2026-05-01

对应问题：

- Step 10 `[P2] Tooling 导出 latest autosave 时会猜测最终 snapshot event，可能输出与 replay event 不一致的 artifact`。

改动：

- `tools/export_match_artifacts_from_replay.gd`：删除 `_fallback_final_snapshot_event(...)`；`latest_autosave.json` 导出必须基于 `_snapshot_event_for_state_after_command(...)` 得到明确的 `round_end` 或 `game_over` snapshot event，否则导出失败并报告当前 `state_phase / command_phase / round`。
- `core/tests/export_match_artifacts_contract_test.gd`：新增工具契约测试，覆盖明确 round_end、明确 game_over，以及非 snapshot 最终状态不得被猜测为成功。
- `ui/scenes/tests/all_tests_refs.gd`、`ui/scenes/tests/all_tests_plan.gd`：将新测试接入 AllTests。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 strict 化：artifact backfill 工具不会再为不明确的最终状态合成 latest autosave 元数据，避免输出与 replay 真实事件边界不一致的产物。

### Fix 45：GameEngine 配置覆盖不再隐式读取 Globals

日期：2026-05-01

对应问题：

- Step 1 `[P1] server/room.gd 在权威房间启动时临时写入 Globals 的配置覆盖`。
- Step 2 `[P2] GameEngine 初始化已经支持依赖注入覆盖，但仍保留从 Globals 读取配置覆盖的 fallback`。
- Step 9 中同源风险：online/client/server 初始化不应把坏配置覆盖形状解释为默认配置。

改动：

- `core/engine/game_engine/initializer.gd`：移除 `Globals.game_config_overrides` / `Globals.game_option_overrides` fallback；`GameEngine` 初始化只接受 `GameEngineDependencies` 中显式注入的配置覆盖。
- `ui/scenes/game/game.gd`：本地新局在创建 `GameEngine` 后显式注入 `Globals.game_config_overrides` 与 `Globals.game_option_overrides`，把 UI 设置层与 core 初始化层的边界拆开。
- `server/room.gd`：权威房间启动不再临时改写 `Globals`；房间 config 中存在覆盖字段时直接注入到 engine，且字段类型不是 `Dictionary` 时 fail-fast。
- `autoload/net_client/client.gd`：online client bootstrap 同样拒绝非 `Dictionary` 的配置覆盖字段，不再静默忽略坏配置后用默认规则初始化。
- `core/tests/engine_dependencies_injection_test.gd`：新增 `Globals` 覆盖不再隐式影响普通 `GameEngine.initialize(...)` 的回归测试。
- `core/tests/online_client_config_bootstrap_overrides_test.gd`：新增 online room config 中坏 `game_option_overrides` 必须拒绝且不得创建本地 engine 的负例。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1/P2 边界整改：core/server 初始化语义不再依赖跨场景全局单例；UI、server、online client 均通过显式注入表达配置覆盖。
- 后续若还需要 `Globals` 承载 UI 设置缓存，也应只停留在 UI/setup 层，不能再作为 `GameEngine` 默认 fallback。

### Fix 46：base_rules 结算确认不再读取运行环境

日期：2026-05-01

对应问题：

- Step 6 `[P1] base_rules 的规则结算直接依赖运行环境和全局联机单例，导致同一规则路径会因 headless/windowed/online 状态产生不同 state`。
- 同源遗留：Dinnertime/Marketing 本地动画确认仍由 `DisplayServer.get_name()` 隐式决定是否写入 `pending_phase_actions`。

改动：

- `core/data/game_config.gd`、`core/state/game_state_factory.gd`：新增 `rules.require_dinnertime_confirm` 与 `rules.require_marketing_confirm`，作为进入规则 state 的显式 `0/1` 标记。
- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`、`modules/base_rules/rules/phase/marketing_settlement.gd`：移除对 `DisplayServer` 与 `NetContext` 的直接读取；是否注入本地确认 pending 只取决于显式规则标记，online per-player pending 仍取决于已有 online marker。
- `ui/scenes/game/game.gd`：图形 UI 新局启动时在 UI 层根据显示环境显式注入本地确认标记；headless/core/server 路径默认不注入。
- `ui/scenes/game/overlay/controller.gd`：本地确认命令改为携带当前玩家 actor，匹配结构化 pending；online client 继续使用 `NetContext.local_player_id`。
- `tools/manual_test_saves/builders/manual_test_save_marketing_builders.gd`、`testdata/saves/manual_cases/marketing/marketing_phase_animation_review.json`、`core/tests/manual_marketing_review_save_test.gd`：手工营销动画复核存档从 legacy string pending 改为结构化 `{kind, player_id}` pending，并保留显式 `require_marketing_confirm=1`。
- `core/tests/dinnertime_settlement_test.gd`、`core/tests/marketing_settlement_fail_fast_test.gd`：新增显式本地确认 marker 会注入结构化 pending 的回归测试。
- `core/tests/module_boundary_contract_test.gd`：新增架构守卫，禁止 `modules/base_rules/rules` 再直接引用 `DisplayServer` 或 `NetContext`。

验证：

- 首次 AllTests 暴露 `GameState.rules` 只能序列化整数规则值，已将新增规则标记改为 `0/1` 存储后重跑。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1 边界整改：`base_rules` 权威结算不再根据当前进程是 headless、GUI、client 或 server 改变 state；运行环境差异由 UI/online bootstrap 显式转成规则标记。
- online confirmed/pending 的灾难恢复 guard 仍有单独 P2（`AutoAdvanceTryStep._ensure_online_dinnertime_pending_guard` 会修复 pending），后续应继续拆分为 strict runtime 与显式 recovery。

### Fix 47：online Dinnertime pending guard 拆分运行期严格校验与显式恢复

日期：2026-05-01

对应问题：

- Fix 46 遗留 P2：`AutoAdvanceTryStep._ensure_online_dinnertime_pending_guard` 会在普通 auto-advance 运行期修复缺失、空、legacy 或错位的 `pending_phase_actions[Dinnertime]` 与 `online_dinnertime_confirmed_players`，属于过度兜底。

改动：

- `core/engine/game_engine/auto_advance_try_step.gd`：`_ensure_online_dinnertime_pending_guard(...)` 改为返回 `Result`，普通 auto-advance 只做 strict 校验并向上失败传播；缺 confirmed 数组、confirmed 长度/类型错误、缺少应存在的 per-player pending、重复/越界/legacy pending 都不再被修复。
- `core/engine/game_engine/auto_advance_try_step.gd`：新增 `_repair_online_dinnertime_pending_guard_for_resume(...)`，把旧的修复语义限定到名字明确的 online resume 准备路径；该路径修复失败也返回 `Result.failure`，不再只 log warning 后继续。
- `core/engine/game_engine/online_resume_point_validator.gd`：Dinnertime 恢复点准备改为显式调用 resume repair，并在失败时阻断恢复点验证/启动。
- `core/tests/online_dinnertime_confirm_enforced_test.gd`：新增 strict guard 负例，构造 Dinnertime 后删除确认 pending，确认 auto-advance 会失败且不会重建 `pending_phase_actions[Dinnertime]` 或改写 confirmed 数组。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 strict 化：online Dinnertime 的普通运行期不再用 auto-advance 修补损坏 state；旧 archive/resume 需要补 pending 时，只能经过显式 online resume repair 入口。

### Fix 48：NetClient 恢复缓存不再依赖 Game 场景日志构建器

日期：2026-05-01

对应问题：

- Step 1 `[P1] NetClient 恢复缓存支持直接依赖 Game 场景日志构建器`。

改动：

- `autoload/net_client_online_resume_support.gd`：移除对 `res://ui/scenes/game/timeline/log_entries_builder.gd` 的 preload；NetClient full-history cache 只负责构建和保存中立的 step timeline，不再在 autoload 层预构建 UI 日志 entries。
- `autoload/net_client_online_resume_support.gd`：timeline cache refresh 后显式清空 entries cache（`processed_command_count=-1`），避免把过期 UI entries 标记为可用；UI entries 由 `OnlineResumeFullHistoryAdapter` / `StepTimelineBuildHelpers` 在渲染需要时构建并回写。
- `core/tests/online_resume_full_snapshot_bootstrap_test.gd`：更新 bootstrap 契约，要求 single full-engine 启动后 timeline cache ready，但 NetClient 不应预构建 UI 日志 entries cache。

验证：

- `rg -n "res://ui/scenes/game/timeline/log_entries_builder|GameTimelineLogEntriesBuilderClass" autoload/net_client_online_resume_support.gd autoload core/tests/online_resume_full_snapshot_bootstrap_test.gd`：无命中。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1 边界整改：联机恢复缓存层不再直接依赖 Game 场景日志 formatter/builder；autoload 只持有可独立于 UI 演进的 timeline 数据，日志 entries 回到 UI adapter 层生成。

### Fix 49：DedicatedServer 不再直接访问 NetClient 房间管理内部字段

日期：2026-05-01

对应问题：

- Step 1 `[P1] server/dedicated_server.gd 大量直接访问 NetClient._room_manager 与其内部 rooms`。

改动：

- `autoload/net_client.gd`：新增 server-side facade：`has_server_room_manager()`、`restore_server_room_manager_from_persistence(...)`、`create_server_room_persistence_snapshot(...)`、`save_server_room_manager_with_store(...)`、`get_server_room_by_code(...)`、`force_remove_server_room(...)`、`get_server_room_count()`、`list_active_server_room_codes()`、`build_empty_room_state()` 与 `broadcast_server_room_list(...)`。
- `server/dedicated_server.gd`：持久化恢复、round autosave、远端结束房间裁剪、目录同步、定时持久化和 heartbeat 房间列表全部改走 NetClient facade，不再读取 `NetClient._room_manager`、`rooms`、`_empty_room_state()` 或 `_broadcast_room_list(...)`。
- `core/tests/core_architecture_boundary_contract_test.gd`：新增守卫，禁止 `DedicatedServer` 回到 `NetClient._room_manager` / 私有 room-state helper / 私有 broadcast helper。

验证：

- `rg -n "NetClient\\._" server/dedicated_server.gd`：无命中。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1 边界整改：DedicatedServer 不再耦合 `NetClient` 的房间管理字段布局；后续 RoomManager 内部字段重命名或封装调整只需要维护 NetClient facade。

### Fix 50：服务端地图快照渲染不再复用 UI MapCanvas

日期：2026-05-01

对应问题：

- Step 1 `[P1] server/map_snapshot_cpu_canvas.gd 复用 UI map canvas/drawer 作为服务端渲染实现`。

改动：

- `server/map_snapshot_renderer.gd`：移除对 `server/map_snapshot_cpu_canvas.gd` 的依赖，默认使用 server 内部已有 schematic PNG renderer，返回 `renderer="map_snapshot_schematic"`。
- 删除 `server/map_snapshot_cpu_canvas.gd` 与对应 `.uid`，彻底移除 server 层对 `ui/visual/ui_skin_cache.gd`、`ui/scenes/game/map/indexer.gd`、`ui/scenes/game/map/drawer/drawer.gd` 的复用链路。
- `core/tests/online_round_autosave_test.gd`：更新 round autosave 截图契约，要求服务端地图截图使用独立 schematic renderer，而不是 UI MapCanvas CPU renderer。
- `core/tests/core_architecture_boundary_contract_test.gd`：新增守卫，禁止 `server/` 脚本直接引用 `res://ui/`。

验证：

- `rg -n "res://ui/" server --glob "*.gd"`：无命中。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1 边界整改：服务端快照导出不再受 Game 场景 MapCanvas、UI skin cache 或 UI drawer 内部重构影响；后续若要提升截图视觉质量，应在 server/shared renderer 内独立演进，而不是反向依赖 UI 节点绘制链路。

### Fix 51：OnlineSessionCoordinator 错误策略移出 UI 目录

日期：2026-05-01

对应问题：

- Step 1 `[P2] OnlineSessionCoordinator 依赖位于 UI 目录的错误分类策略`。

改动：

- `ui/scenes/online/online_resume_error_policy.gd` 迁移为 `autoload/online_resume_error_policy.gd`，保留原 `.uid` 到新路径；该策略是纯 `RefCounted` 静态分类逻辑，不再归属于 online lobby UI 场景。
- `autoload/online_session_coordinator.gd`：preload 改为 `res://autoload/online_resume_error_policy.gd`。
- `core/tests/online_resume_error_policy_test.gd`：测试 preload 同步改到新路径。
- 新策略文件不声明 `class_name`，避免 Godot global script class cache 在移动路径期间保留旧 UI class_name 造成隐藏冲突；调用方均通过 preload 常量使用。

验证：

- `rg -n "res://ui/scenes/online/online_resume_error_policy" . --glob "*.gd" --glob "!*.uid"`：无命中。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 边界整改：联机恢复编排层不再反向依赖 online UI 场景目录；UI 可继续复用 autoload 中立层的错误策略。

### Fix 52：运行期 RNG 约束写入架构并加守卫

日期：2026-05-01

对应问题：

- Step 2 `[P2] 运行期 RNG 约束目前依赖约定，没有在 command replay API 上显式表达`。

改动：

- `docs/architecture/35-core-data-random.md`：明确运行期 command/rules 路径当前不得直接消耗 RNG；若未来动作规则需要随机，必须先扩展 replay/rewind/archive 的 command application API，使 RNG 状态可记录、恢复和推进。
- `docs/architecture/32-core-actions-framework.md`：在 ActionExecutor 契约中补充确定性约束，禁止 `RandomNumberGenerator`、`randi()`、`randf()` 或 `engine.random_manager` 进入运行期 action executor / 模块规则。
- `core/tests/core_architecture_boundary_contract_test.gd`：新增静态守卫，扫描 `core/actions`、`core/rules`、`gameplay/actions`、`modules` 下的 `.gd`，发现直接 RNG 消耗时失败并提示先扩展 replay API。
- 同文件顺手修正 `server 不应直接引用 UI 资源` 守卫中的缩进漏 tab；此前编译失败已在本次验证前修复。

验证：

- `rg -n "RandomNumberGenerator|random_manager|randi\\(|randf\\(|randfn\\(|randomize\\(" gameplay/actions modules core/actions core/rules core/engine/game_engine/auto_advance*.gd --glob "*.gd" --glob "!modules/*/content/**"`：无命中。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1107`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 架构约束：运行期随机不再只靠口头约定；新增随机规则前必须先调整可回放命令执行契约，否则架构测试会阻断。

### Fix 53：历史命令应用逻辑收敛到 ReplayStepRunner

日期：2026-05-01

对应问题：

- Step 2 `[P1] 回放、事件历史重建、StepTimeline 与命令索引查询重复实现“应用一条历史命令”的核心流程`。

改动：

- 新增 `core/engine/game_engine/replay_step_runner.gd`，集中处理历史命令应用的 strict replay force policy、executor 查找、强制执行 actor 合法性校验、state 计算、warning 透传与 `GameState` 返回类型契约。
- `core/engine/game_engine/replay.gd`：`rewind_to_command(...)` 与 `full_replay(...)` 改用 `ReplayStepRunner`，只保留 checkpoint 恢复、auto-advance drain 与 replay 返回结构职责。
- `core/engine/game_engine/event_history_rebuild.gd`：事件历史重建改用同一单步应用 helper，保留事件生成、auto-advance 事件合并与 command_index 标注职责。
- `core/engine/game_engine/command_index_queries.gd`：按 replay 推导当前玩家回合起点时，复用同一单步应用 helper，避免单独维护 executor/force/state 计算分支。
- `gameplay/replay/step_timeline_build/build_full_impl.gd` 与 `build_append_impl.gd`：StepTimeline 全量/增量构建改用同一单步应用 helper，时间线层只负责 step/event 投影与 auto-advance 分段。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1108`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P1 去重整改：历史命令“如何从 old state 应用为 new state”的执行契约不再散落在 Replay、EventHistoryRebuild、CommandIndexQueries 与 StepTimeline 构建层；后续 force/replay 严格性、executor 查找或 state 类型约束只需要维护 `ReplayStepRunner`。

### Fix 54：auto-advance drain 循环收敛到统一 step runner

日期：2026-05-01

对应问题：

- Step 2 `[P2] auto-advance 存在三套 drain 契约，当前可工作，但职责边界需要文档化或收敛`。

改动：

- 新增 `core/engine/game_engine/auto_advance_drain_steps.gd`，统一负责 `try_advance_one(...)` 循环、`max_steps` safety、warning 汇总，以及每一步 `before/after` `GameState` 快照输出。
- `core/engine/game_engine/auto_advance_impl.gd`：基础 `AutoAdvance.drain(...)` 改用统一 drain step runner，只保留“是否推进到稳定态”的无事件契约。
- `core/engine/game_engine/command_runner.gd`：运行时命令执行的 auto-advance 改用统一 drain steps，再在 CommandRunner 层投影 phase/cash 事件。
- `gameplay/replay/step_timeline_build/auto_advance_drain.gd`：StepTimeline 不再自己循环 `try_advance_one(...)`，改消费统一 before/after step 序列，并继续只负责 step/event 归属、phase step 插入与特殊里程碑事件投影。
- `core/tests/core_architecture_boundary_contract_test.gd`：新增架构守卫，禁止 `core/engine/game_engine` 与 `gameplay/replay/step_timeline_build` 中除统一 runner/底层 wrapper 外再次复制 `try_advance_one` drain 循环或 `while safety < 32`。

验证：

- `rg -n "try_advance_one\\(|while safety < 32" core/engine/game_engine gameplay/replay/step_timeline_build -g "*.gd"`：仅命中 `auto_advance.gd`、`auto_advance_impl.gd`、`auto_advance_try_step.gd` 与 `auto_advance_drain_steps.gd`。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1109`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 收敛：auto-advance 的推进循环、safety 与快照边界只有一个实现；CommandRunner 与 StepTimeline 仍保留各自必要的事件/时间线投影职责，不再重复维护推进语义。

### Fix 55：headless 测试脚本增加严格退出码模式

日期：2026-05-01

对应问题：

- Step 10 `[P2] tools/run_headless_test.sh 对 Godot 退出码有多处 success fallback，作为测试工具可以理解，但 CI/架构验证需要更明确的严格模式`。

改动：

- `tools/run_headless_test.sh`：新增 `--strict-exit` 参数与 `STRICT_EXIT=1` 环境变量；严格模式要求 Godot 退出码与日志 outcome 同时成功，非 0 退出码不再被 PASS/SUMMARY 或已知 benign shutdown leak warning 兜底吞掉。
- `tools/run_headless_test.sh`：默认模式保留现有兼容行为，继续允许 macOS/Godot headless 退出阶段已知资源泄漏噪声的非 0 兜底，避免破坏日常本地测试。
- `tools/run_headless_test.sh`：修正“日志已 PASS 后等待 Godot 退出”的分支，原先 `! wait` 会拿到取反后的状态，可能丢失真实非 0 exit code；现在统一显式捕获真实退出码，再按 strict/default 策略判断。
- `tools/run_headless_test.sh --help` 文案补充严格模式用法与语义。

验证：

- `bash -n tools/run_headless_test.sh`：PASS。
- `tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 30 --strict-exit`：PASS。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1109`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 工具改进：日常测试仍兼容 Godot headless 退出噪声；架构/发布验证可显式开启 strict exit，避免“日志看似 PASS 但进程失败”的情况被静默视为成功。

### Fix 56：模块 placement overlay 控制器加载失败不再静默跳过

日期：2026-05-01

对应问题：

- main 增量 `[P2] 模块提供的 placement overlay 控制器按 best-effort 动态加载，新增 lobbyists 主放置 UI 已依赖这条不严格链路`。

改动：

- `ui/scenes/game/panel/placement_overlays.gd`：`_ensure_module_overlay_controllers_loaded(...)` 改为返回 `Result`；`module_plan_v2` 中缺 manifest、`provides.ui.placement_overlays` 类型错误、路径为空、路径非 `res://`、重复路径、资源不存在、资源不是 `Script`、controller 缺少 `sync/hide/dispose/get_context_overlay` 必需方法时，都会失败而不是 `continue`。
- `ui/scenes/game/panel/placement_overlays.gd`：模块 overlay 加载失败会记录一次 `_module_overlay_load_error`，后续不重复加载/刷屏；同时通过 `push_error` 与 `overlay_controller.show_toast(...)` 给出可见诊断。
- `get_active_context_overlay(...)`、`try_show_module_action_overlay(...)` 与 `_sync_module_overlays(...)` 改为消费加载 `Result`，失败时停止模块 overlay 路径，避免半加载状态继续运行。
- `ui/scenes/tests/placement_staff_picker_ui_test.gd`：新增负例，构造无效 `placement_overlays` 路径，验证不会被处理为成功，并且会产生包含失败路径的可见 toast。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1109`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P2 strict 化：Lobbyists 等模块的自定义 placement overlay 不再依赖静默 best-effort 加载；manifest 或脚本契约损坏会在 UI 初始化路径上明确暴露，避免隐藏动作入口与实际 overlay 缺失之间的漂移。

### Fix 57：Lobbyists road/park 动作接入权威 staff_id 校验与消耗

日期：2026-05-01

对应问题：

- main 增量 `[P2] Lobbyists 新 UI 选择具体 staff_id，但 road/park action 仍只按聚合次数计数，UI 表达的“具体员工选择”与权威规则不一致`。

改动：

- 新增 `modules/lobbyists/actions/lobbyists_staff_usage.gd`，集中派生当前玩家在岗、具备 `use:lobbyists` 能力的说客 staff provider，并按 `round_state.staff_usage[staff_id]["lobbyists"]` 计算 capacity/used/remaining。
- `place_lobbyists_road_action.gd` 与 `place_lobbyists_park_action.gd`：校验阶段改为解析并验证 `command.params.staff_id`；指定 staff 不存在、非当前玩家、非在岗说客或本子阶段已用完时直接失败。缺省 `staff_id` 时仍选择首个可用说客，保留历史命令兼容。
- 两个 action 的 `_apply_changes(...)` 在保持旧 `lobbyists_place_counts` 聚合计数的同时，新增权威 staff track 消耗；返回值与事件 payload 写入实际消耗的 `staff_id`。
- `modules/lobbyists/ui/lobbyists_placement_flow_controller.gd`：员工列表改为读取同一 `LobbyistsStaffUsage` provider，不再用 `lobbyists_place_counts` 把前 N 个 staff 推断为已用，也不再生成 synthetic staff id。
- `core/tests/lobbyists_road_state_access_test.gd`：新增 staff_id 契约测试，覆盖 road action 只消耗指定 staff、已使用 staff 被拒绝、park action 接受可用 staff 并拒绝不存在 staff。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1110`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：首次暴露新增测试中未装配 milestone handler 的干扰；测试改为预先标记 `first_lobbyist_used` 后重跑 PASS，`391/391`。

结论：

- 已完成该 P2 权威语义修复：Lobbyists UI 的具体 staff 选择已经与 core/module action 实际消耗一致；联机或坏客户端传入不可用 `staff_id` 不再能绕过权威校验。

### Fix 58：Lobbyists placement flow controller 拆出命令构造 helper

日期：2026-05-01

对应问题：

- main 增量 `[P3] Lobbyists placement flow controller 新增 523 行，集中处理 manifest UI 扩展、员工列表派生、地图高亮/预览、命令构造、ActionPanel context 绑定与 refresh`。

改动：

- 新增 `modules/lobbyists/ui/lobbyists_placement_command_builder.gd`，集中处理 Lobbyists road/park action 归一化、piece/position/rotation/staff 参数校验与 `Command` 创建。
- `modules/lobbyists/ui/lobbyists_placement_flow_controller.gd`：`_on_placement_confirmed(...)` 改为调用 command builder；移除本地 `_create_command(...)` 与内联 params 拼装，flow controller 继续只负责 overlay 生命周期、地图预览/高亮、员工列表同步与执行回调。
- 该拆分是低风险的第一步：员工列表 ViewModel 与 ActionPanel binder 暂未继续拆出，避免一次性重排 UI 控制器行为。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1111`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`391/391`。

结论：

- 已完成该 P3 的第一阶段职责拆分：命令构造不再散落在主 flow controller 中，后续如果继续扩展 staff UI 或 action panel context，可以在同一模式下继续拆 ViewModel/Binder，而不需要把规则参数继续塞回 overlay 控制器。

### Fix 59：server recovery delta 记录失败不再静默吞掉

日期：2026-05-01

对应问题：

- Step 9 `[P2] Server recovery delta store 是 best-effort：记录失败被静默吞掉，resync 服务再用 full snapshot 兜底，缺少诊断边界`。

改动：

- `server/room.gd`：`record_resume_delta(...)` 从 `void` 改为返回 `Result`；checkpoint 初始化失败、无法计算 `post_state_hash`、checkpoint 轮转失败都会返回 failure，不再直接 `return`。
- `autoload/net_client/server.gd`：`broadcast_command_applied(...)` 消费 `record_resume_delta(...)` 的返回值，失败时通过 `GameLog.error` 输出 room、command、state hash 与错误信息，避免 recovery store 损坏只表现为后续 snapshot fallback。
- 新增 `core/tests/online_resume_delta_store_contract_test.gd`，覆盖 checkpoint 初始化失败、正常 delta 记录、checkpoint rotate 失败三条契约，并接入 AllTests。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1112`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P2 的第一阶段收紧：server delta store 写入失败现在会成为明确诊断信号，而不是被普通 full snapshot fallback 掩盖。后续若继续拆分，可在 `server_resync_service` 层把 stale cursor、force snapshot 与 recovery store unhealthy 进一步区分为不同 fallback reason。

### Fix 60：恢复房启动使用 strict resume point 校验

日期：2026-05-01

对应问题：

- Step 9 `[P2] Online resume point validator 在常规恢复路径中直接修补 rules、checkpoint 与 Dinnertime pending guard，恢复链路继续承担运行期迁移职责`。

改动：

- `core/engine/game_engine/online_resume_point_validator.gd`：新增 `validate_resume_point_strict(...)`，只校验不修补；要求当前 state 与初始 checkpoint 都显式带有 `online_require_dinnertime_confirm`、`online_require_marketing_confirm` marker。
- `validate_resume_point_strict(...)` 在 Dinnertime 恢复点调用运行期 strict guard，缺失/错误的 `pending_phase_actions[Dinnertime]` 或 `online_dinnertime_confirmed_players` 会直接失败。
- `server/room.gd`：恢复房 `_prepare_effective_resume_start_engine(...)` 从 `prepare_and_validate_resume_point(...)` 改为 `validate_resume_point_strict(...)`，普通恢复房启动不再修补 rules/checkpoint/pending guard。
- 调整恢复房相关测试夹具：合法恢复房测试显式用 `prepare_engine_for_online_resume(...)` 生成在线恢复档；`OnlineResumeStartValidationTest` 改为断言缺失 Dinnertime pending 的恢复房会被拒绝。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1112`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：两轮调整测试夹具后 PASS，`392/392`。

结论：

- 已完成该 P2 的普通恢复路径 strict 化：恢复房启动现在只接受已显式准备好的在线恢复档；旧档/坏档需要走显式准备或迁移入口，不能在常规启动校验中被静默修补。

### Fix 61：Game 运行时日志链路增加 StepTimeline 单源守卫

日期：2026-05-01

对应问题：

- Step 8 `[P2] Game 日志仍有 StepTimeline 与 EventBus EventLog 双链路，靠 runtime 条件避免重复，职责划分仍不清晰`。

改动：

- `core/tests/core_architecture_boundary_contract_test.gd`：新增架构守卫，检查 `ui/scenes/game/game.gd` 与 `ui/scenes/game/controllers/builder.gd` 不得重新引用 `GameEventLogController`、`event_log/controller.gd` 或 `rebuild_from_history(...)`。
- 当前运行时 Game 控制器构建路径已经由 `GameTimelineController.apply_live_log_timeline_from_engine(...)` 驱动日志；`ui/scenes/game/event_log/controller.gd` 保留为 legacy/test fallback，避免历史恢复测试与 formatter 兼容性被一次性移除。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1112`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P2 的运行时边界收敛：Game 场景主链路现在有测试防止 EventBus flat log 被重新接入；剩余 `GameEventLogController` 只作为兼容/测试兜底存在，后续可单独清理旧文档和 legacy 测试入口。

### Fix 62：StepTimeline 清理里程碑延后改为事件 metadata 驱动

日期：2026-05-01

对应问题：

- Step 8 `[P2] StepTimeline 构建层硬编码具体规则/动作/里程碑，并在末尾用 flush 兜底补事件` 中的 cleanup delayed milestone 部分。

改动：

- 新增 `gameplay/replay/step_timeline_build/deferred_event_policy.gd`，定义 timeline defer metadata 与 `cleanup_after_discards` 策略。
- `gameplay/replay/command_runner_event_build/milestone_events.gd`：在规则事件 provider 边界为 `first_throw_away` 里程碑打 `_timeline_defer.kind = cleanup_after_discards` metadata。
- `gameplay/replay/step_timeline_build/helpers.gd`：移除对具体 `milestone_id` 的识别，改为 `filter_deferred_cleanup_milestone_events(...)` 读取通用 defer metadata。
- `gameplay/replay/step_timeline_build/build_full_impl.gd` 与 `build_append_impl.gd`：清理里程碑的释放条件改为“pending cleanup 事件已清空”，不再特判 `choose_fridge_keep` action。
- `gameplay/replay/step_timeline_build/phase_transition.gd` 与 `auto_advance_drain.gd`：复用同一个 metadata helper，避免 phase/auto-advance 分支重新理解具体里程碑。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1113`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P2 中 cleanup 延后里程碑的第一阶段收敛：`first_throw_away` 的展示延后策略现在由事件 metadata 表达，StepTimeline 构建层不再识别具体 milestone/action。剩余 Marketing enter effects 与构建末尾 flush 的归属策略仍需要后续按同一 metadata/strict attribution 方向继续清理。

### Fix 63：StepTimeline 延后事件归属策略由规则装配声明并持久化 pending meta

日期：2026-05-01

对应问题：

- Step 8 `[P2] StepTimeline 构建层硬编码具体规则/动作/里程碑，并在末尾用 flush 兜底补事件` 中的 Marketing enter effects 与末尾 flush 部分。

改动：

- `core/engine/phase_manager.gd`：新增 timeline settlement event policy 注册/查询入口，支持模块声明某个 `(phase, settlement point)` 的展示事件需要延后到 phase exit 后输出；同源同策略重复注册视为幂等，兼容 archive/resync 复用 PhaseManager 的装配路径。
- `core/modules/v2/ruleset*.gd`：Ruleset/registrar 增加 `register_timeline_settlement_event_policy(...)`，在 apply hooks 时把策略装配到 PhaseManager。
- `modules/base_rules/rules/phase_and_map.gd`：base_rules 显式声明 `Marketing:enter` 的 settlement effects 使用 `defer_settlement_effects_until_phase_exit` 策略，StepTimeline 不再内置 `Marketing enter effects` 特判。
- `gameplay/replay/step_timeline_build/*`：PhaseTransition 读取 PhaseManager policy 后把延后事件写入通用 `pending_phase_exit_effects`；full/append 不再在构建末尾把 pending Marketing/cleanup 事件强行 flush 到最后一个 step。
- `gameplay/replay/step_timeline_build/helpers.gd`：在 `_build_meta.pending_timeline_events` 中持久化未到归属点的 pending phase-exit effects 与 cleanup deferred events，使增量 append 可以在后续命令到达时继续正确归属，而不是依赖内存或末尾兜底。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1113`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：第一轮发现 PhaseManager policy 重复装配问题，修正为同源幂等后 PASS，`392/392`。

结论：

- 已完成该 P2 的剩余收敛：StepTimeline 构建层不再识别具体 Marketing enter 展示策略，也不再把无法归属的 pending 事件塞到最后一个 step；未到归属点的事件作为 timeline build meta 保留，等待后续 append/rebuild 在真实 phase/action 边界释放。

### Fix 64：server resync snapshot fallback 增加明确原因分类

日期：2026-05-01

对应问题：

- Step 9 `[P2] Server recovery delta store 是 best-effort：记录失败被静默吞掉，resync 服务再用 full snapshot 兜底，缺少诊断边界` 中的 fallback reason 分类部分。

改动：

- `server/room.gd`：新增 `_resume_delta_store_unhealthy_reason`，当 recovery checkpoint 创建、archive 创建或 delta post hash 获取失败时记录 unhealthy reason；成功重建 recovery store 后清空。
- `server/room.gd`：`build_delta_resume_payload(...)` 遇到 unhealthy recovery store 会显式失败为 `recovery store unhealthy: ...`，不再和普通 cursor stale/gap 混在一起。
- `autoload/net_client/server_resync_service.gd`：`build_best_effort_resume_transfer(...)` 为 snapshot fallback 增加 `fallback_reason_code`，区分 `force_snapshot_requested`、`cursor_missing`、`cursor_hash_mismatch`、`cursor_invalid`、`delta_gap`、`delta_too_large`、`recovery_store_unhealthy` 与通用 `delta_unavailable`。
- `autoload/net_client/server_resync_service.gd`：dispatch snapshot fallback 时记录 `class=<fallback_reason_code>`；`recovery_store_unhealthy` 升级为 error 日志，正常 stale/force snapshot 仍为 info。
- `core/tests/server_resync_guard_test.gd`：新增 force snapshot、hash mismatch、recovery store unhealthy 三类 fallback code 断言。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1113`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P2 的 fallback 边界收紧：server resync 仍允许在 delta 不可用时发 full snapshot，但调用方与日志现在能区分正常客户端请求/游标过期、delta 窗口问题和服务端 recovery store unhealthy，不再把健康问题伪装成普通 snapshot fallback。

### Fix 65：AllTests 聚合计划拆分为 domain suites

日期：2026-05-01

对应问题：

- Step 10 `[P3] AllTests 聚合文件过大，新增/迁移测试需要同时维护 refs 与 plan，容易漏接架构测试`。

改动：

- `ui/scenes/tests/all_tests_plan.gd`：从 1578 行缩减为 27 行，只保留 suite preload、按序聚合和 `_append_suite(...)`。
- 新增 `ui/scenes/tests/suites/` 下 8 个 suite：`all_tests_bootstrap_suite.gd`、`all_tests_core_architecture_suite.gd`、`all_tests_online_suite.gd`、`all_tests_ui_suite.gd`、`all_tests_core_rules_suite.gd`、`all_tests_runtime_timeline_suite.gd`、`all_tests_modules_suite.gd`、`all_tests_settlement_suite.gd`。
- 保持原 AllTests 执行顺序与 392 个测试条目不变；每个 suite 只承载一个 domain 的测试注册，后续新增 online/resync、timeline 或 module 测试时不再需要修改一个 1500+ 行聚合文件。
- `docs/testing.md`：将恢复房专项定向核验说明改为指向拆分后的 online/runtime timeline suites。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1121`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P3 的测试聚合治理：顶层 AllTests 现在只表达 suite 顺序，domain 注册分散到小文件中，降低后续迁移/新增测试漏接架构测试的概率；`all_tests_refs.gd` 仍作为统一 preload 表保留，后续若继续增长可再按 suite 拆 refs。

### Fix 66：复核客户端 snapshot 分片组装失败已有 failure channel

日期：2026-05-01

对应问题：

- Step 9 `[P2] 客户端 snapshot 分片组装失败只记录 error，不发失败信号或 force resync，恢复等待可能只能靠超时退出`。

复核结论：

- 当前 `autoload/net_client/client_resync_service.gd` 在 `assemble_snapshot(...)` 失败后会调用 `_emit_delta_failure("snapshot 恢复失败：分片组装失败...")`，不再只记录日志后返回。
- `_emit_delta_failure(...)` 会先调用 `request_resume_force_snapshot_once()`，再发 `resync_delta_failed`；启动恢复等待链路与游戏内 resync controller 都已经监听该 failure signal。
- `core/tests/online_client_resync_snapshot_chunk_test.gd` 已覆盖坏 chunk：不会发 `resync_archive_received`，会发一次 resync failure，清理 pending manifest/chunks，并设置 `resume_force_snapshot_requested = true`。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `OnlineClientResyncSnapshotChunkTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 67：复核 pending command flush 失败已改为 force resync

日期：2026-05-01

对应问题：

- Step 9 `[P2] Resync 后的 pending command flush 与实时 command_applied 路径不一致：解析/执行失败会移除 queued command，而不是立即 resync`。

复核结论：

- 当前 `ui/scenes/game/controllers/online_resync_controller.gd` 中 `_flush_online_pending_commands_after_resync(...)` 在 `Command.from_dict(...)` 失败时调用 `_request_online_force_resync("pending_command_parse_failed")` 并返回。
- 同一函数在 `engine.execute_command(...)` 失败时调用 `_request_online_force_resync("pending_command_apply_failed")` 并返回；失败路径不会继续移除后续 queued command，也不会执行成功路径的 UI refresh。
- `core/tests/game_online_resync_request_rejection_test.gd` 已覆盖 pending command 解析失败和执行失败，断言两者都会立刻请求 resync、携带 `force_snapshot`，并保持 resync in-progress 状态。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `GameOnlineResyncRequestRejectionTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 68：复核后端房间配置坏 JSON 不再回退为空配置

日期：2026-05-01

对应问题：

- Step 9 `[P2] 后端房间配置解析失败会退回 {}，可能把坏配置解释成非恢复房或允许观战`。

复核结论：

- 当前 `backend/app/room_config.py` 提供 `parse_room_config_json(...)`，空配置仍允许为 `{}`，但 JSON 解析失败或顶层不是 object 会抛 `RoomConfigParseError`。
- `backend/app/rooms.py` 将请求配置解析失败映射为 HTTP 400，将已存房间配置解析失败映射为 HTTP 409；恢复房判定、房间列表和观战策略都走该 strict parser。
- `backend/app/internal.py` 在 game server 同步房间目录时也会校验每个 `rooms[index].config_json`，坏配置不再进入同步路径。
- `backend/tests/test_rooms.py::test_spectate_room_rejects_corrupt_config_json` 已覆盖已存坏配置下观战请求返回 409，且不会把 `allow_spectators` 默认为 true。

验证：

- `pytest backend/tests/test_rooms.py::test_spectate_room_rejects_corrupt_config_json`：PASS，`1 passed`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 69：复核 PlatformApi 2xx 坏 JSON 不再伪装为成功

日期：2026-05-01

对应问题：

- Step 9 `[P2] PlatformApi.parse_http_json_response(...) 对 2xx 非 JSON 响应返回 {"ok": {}}，会把后端协议错误伪装成成功`。

复核结论：

- 当前 `autoload/platform_api.gd` 在 `JSON.parse(...)` 非 OK 时直接返回 `{"error": {...}}`，包含 `_http_status`、`parse_error`、`parse_error_line` 和 `body_text`。
- 当前实现不再把合法 JSON `null` 改写成 `{}`；2xx 合法 JSON 返回 `ok`，2xx 坏 JSON 返回 protocol error。
- `core/tests/platform_api_response_parse_test.gd` 已覆盖 200 invalid JSON 必须返回 error，并断言错误中保留 `_http_status` 与 `parse_error`。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `PlatformApiResponseParseTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 70：复核联机客户端模块目录配置不再回退默认目录

日期：2026-05-01

对应问题：

- Step 9 `[P2] Online client 从 server config 初始化 engine 时，modules_v2_base_dir 非法会回退默认目录，可能和 server 权威模块装配不一致`。

复核结论：

- 当前 `autoload/net_client/client.gd` 在 `_initialize_online_client_engine_from_config(...)` 中要求 `modules_v2_base_dir` 非空，并通过 `ModuleDirSpecClass.parse_base_dirs(...)` 校验；空值或非法路径都会返回 `Result.failure`。
- 失败路径发生在创建/绑定 engine 之前，不会把默认模块目录写入客户端 engine，也不会污染 `Globals.current_game_engine`。
- `core/tests/online_client_config_bootstrap_overrides_test.gd` 中 `_test_invalid_modules_base_dir_rejected()` 已覆盖非法 `/tmp/not_res_modules` 会失败、错误信息包含 `modules_v2_base_dir`、且不会写入全局 engine。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `OnlineClientConfigBootstrapOverridesTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 71：复核 Lobbyists 放置动作已校验并消耗具体 staff_id

日期：2026-05-01

对应问题：

- main 增量 `[P2] Lobbyists 新 UI 选择具体 staff_id，但 road/park action 仍只按聚合次数计数，UI 表达的“具体员工选择”与权威规则不一致`。

复核结论：

- 当前 `modules/lobbyists/actions/lobbyists_staff_usage.gd` 统一从 `StaffState` 派生可用说客，读取 `use:lobbyists` usage tag 与 working multiplier，并基于 `lobbyists` track 计算每个 staff 的剩余次数。
- `place_lobbyists_road_action.gd` 与 `place_lobbyists_park_action.gd` 在 validate/apply 阶段都调用 `_resolve_lobbyist_staff(...)`；显式 `staff_id` 不存在或次数用完会失败。
- apply 成功后两个 action 都调用 `increment_lobbyist_usage(...)`，在权威状态中消耗具体 staff 的 `lobbyists` track，同时事件 payload 带回被消耗的 `staff_id`。
- `core/tests/lobbyists_road_state_access_test.gd` 已覆盖指定第二个说客执行 road action 后只消耗第二个 staff，并覆盖已用完的指定 staff 会被拒绝。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `LobbyistsRoadStateAccessTest` 与 `LobbyistsParkStateAccessTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 72：复核模块 placement overlay 加载不再静默跳过坏配置

日期：2026-05-01

对应问题：

- main 增量 `[P2] 模块提供的 placement overlay 控制器按 best-effort 动态加载，新增 lobbyists 主放置 UI 已依赖这条不严格链路`。

复核结论：

- 当前 `ui/scenes/game/panel/placement_overlays.gd` 的 `_ensure_module_overlay_controllers_loaded()` 会要求 module plan 中的 manifest 为 `ModuleManifest`，`provides.ui.placement_overlays` 必须是 Array，路径不能为空、不能重复且必须以 `res://` 开头。
- `_instantiate_module_overlay_controller(...)` 会校验资源存在、资源是 Script、controller 能创建，并要求实现 `sync/hide/dispose/get_context_overlay`。
- 失败路径统一进入 `_fail_module_overlay_load(...)`，缓存错误，返回 `Result.failure`，并通过 `_report_module_overlay_load_error(...)` 触发 `push_error` 与 overlay toast。
- `ui/scenes/tests/placement_staff_picker_ui_test.gd` 中 `_case_invalid_module_overlay_controller_reports_error()` 已覆盖缺失 controller 路径不会被处理为成功，并会产生可见 toast 诊断。

验证：

- Fix 65 过程中已跑 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`，包含 `PlacementStaffPickerUiTest`。

结论：

- 该 P2 在当前代码中已完成，不需要额外运行时代码改动；本次更新仅把审查文档从旧证据状态修正为当前实现状态。

### Fix 73：Lobbyists placement flow controller 拆出 ViewModel 与 ActionPanel Binder

日期：2026-05-01

对应问题：

- main 增量 `[P3] Lobbyists placement flow controller 新增 523 行，集中处理 manifest UI 扩展、员工列表派生、地图高亮/预览、命令构造、ActionPanel context 绑定与 refresh`。

改动：

- 新增 `modules/lobbyists/ui/lobbyists_placement_view_model.gd`，集中负责从 state/action registry 派生可用 road/park piece sets、mode availability 与 lobbyist employee items。
- 新增 `modules/lobbyists/ui/lobbyists_placement_action_panel_binder.gd`，集中负责 ActionPanel context overlay 的 bind/clear。
- `modules/lobbyists/ui/lobbyists_placement_flow_controller.gd`：移除员工列表派生、piece set 派生、mode availability 判断与 ActionPanel bind/clear 细节；控制器保留 overlay 生命周期、地图 selection/preview/highlight、命令执行与成功后刷新。
- flow controller 从 449 行降到 345 行；加上 Fix 58 的 command builder 后，该 P3 建议中的三类 helper 已全部落地。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1123`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P3 的模块 UI 结构收敛：Lobbyists 主放置控制器不再直接承载 ViewModel 派生、命令构造和 ActionPanel context 绑定三个独立职责，后续 road/park 扩展可以优先落在对应 helper 中。

### Fix 74：OnlineRoom rollback proposal 状态拆出独立 helper

日期：2026-05-01

对应问题：

- Step 9 `[P3] Online/server 关键文件仍承担多个子系统职责，后续维护风险较高`。

改动：

- 新增 `server/room_rollback_proposal_store.gd`，集中管理 rollback proposal 的 pending 数据、公开 payload、投票推进、拒绝/清空/消费逻辑。
- `server/room.gd` 保留房间状态、engine 当前 command index/history 校验、参与玩家推导与 RPC-facing 方法，具体 proposal 状态变更委托给 helper。
- `OnlineRoom` 不再直接读写 `_pending_rollback_proposal` 字典，也移除了本地 `_public_rollback_proposal_payload()` 组装逻辑；房间公开状态协议保持 `rollback_proposal` 字段不变。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1123`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS，`392/392`。

结论：

- 已完成该 P3 的一个可独立落地拆分：rollback proposal 的生命周期状态从 `OnlineRoom` 主文件中移出，后续 server rollback/resync/start-session 继续拆分时可以沿用“小状态对象 + 房间入口校验”的模式。

### Fix 75：CI headless 测试启用 strict exit 模式

日期：2026-05-01

对应问题：

- Step 10 `[P2] tools/run_headless_test.sh 对 Godot 退出码有多处 success fallback，作为测试工具可以理解，但 CI/架构验证需要更明确的严格模式`。

改动：

- `.github/workflows/ci.yml`：发布 CI 的 AllTests 调用从普通模式改为 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`。
- 保留本地脚本默认的 benign shutdown warning 兼容；CI/发布验证链路要求 Godot exit code 与日志 outcome 同时成功。

验证：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`：PASS，`392/392`。

结论：

- 已完成该 P2 的验证链路收敛：本地开发仍可兼容 Godot 退出阶段的已知噪声，CI 则使用严格退出码，避免非 0 Godot 进程被 PASS 日志兜底掩盖。

### Fix 76：OnlineRoom start session pending 状态拆出独立 helper

日期：2026-05-01

对应问题：

- Step 9 `[P3] Online/server 关键文件仍承担多个子系统职责，后续维护风险较高`。

改动：

- 新增 `server/room_start_session_state.gd`，集中管理开局 bootstrap 的 pending session id、request id、phase、prepared engine/payload、目标 peer 与 ready peer 统计。
- `server/room.gd` 保留 can-start 校验、状态切到 `STATUS_STARTING`、构建/commit engine、回滚到 lobby 等房间职责，具体 pending start 字段读写委托给 helper。
- `OnlineRoom` 不再直接维护 `_pending_start_*` 字段；`get_pending_start_summary()` 与 `to_room_state_dict_for_peer()` 输出协议保持不变。

验证：

- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1123`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`：PASS，`392/392`。

结论：

- 已完成该 P3 的第二个可独立落地拆分：开局 bootstrap 的短生命周期状态从 `OnlineRoom` 主文件中移出，`OnlineRoom` 更集中于房间入口校验和 engine 提交。

### Fix 77：补齐 BankruptcyRules 的 CashReached 里程碑 fail-fast

日期：2026-05-01

对应问题：

- Step 6 `[P1] 多处关键里程碑触发失败被降级为 warning，结算仍成功`。
- Step 7 `[P1] MilestoneSystem.process_event(...) 失败被降级为 warning 的模式不只存在于 base_rules，已经扩散到 gameplay actions 与多个扩展模块`。
- 过度兜底复查补充发现：`core/rules/economy/bankruptcy_rules.gd` 中 `CashReached/20` 与 `CashReached/100` 仍把 `MilestoneSystem.process_event(...)` 失败追加为 warning，导致现金支付成功但 `first_have_20` / `first_have_100` 的规则副作用可能缺失。

改动：

- `core/rules/economy/bankruptcy_rules.gd`：`pay_bank_to_player(...)` 在触发 `CashReached/20` 或 `CashReached/100` 失败时直接返回 `Result.failure`，并保留此前累积 warnings 与 milestone warnings；成功路径继续透传 warnings。
- `core/tests/bankruptcy_test.gd`：新增 `CashReached` fail-fast 回归用例，通过临时移除 `MilestoneEffectRegistry` 验证失败不会被降级为 warning，也不会授予 `first_have_20` 或写入 `milestones_auto_awarded`。

验证：

- `rg -n "^[ ]+\S|\t +| +\t" core/rules/economy/bankruptcy_rules.gd core/tests/bankruptcy_test.gd`：无匹配，确认未引入空格缩进或 tab/space 混用。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1123`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`：PASS，`392/392`。

结论：

- 已补齐现金里程碑支付路径的 P1 strict 化：银行向玩家支付导致现金达到 $20 / $100 时，里程碑触发失败不再被吞为 warning，避免权威现金状态与里程碑副作用状态分离。

### Fix 78：Online resume 准备阶段不再修复 Dinnertime pending guard

日期：2026-05-01

对应问题：

- Fix 7 遗留：`prepare_engine_for_online_resume(...)` 内部尚未完全移除对 pending/confirmed_players 的修复逻辑。
- Step 6 `[P1] Dinnertime/Marketing confirmed_players 损坏时静默重建，并仅 warning pending mismatch`。
- Step 7 `[P2] Dinnertime/Marketing confirm action 仍保留 legacy global pending 和 confirmed_players 长度恢复路径`。

改动：

- `core/engine/game_engine/online_resume_point_validator.gd`：`prepare_engine_for_online_resume(...)` 在 Dinnertime 恢复点上改为调用 `_ensure_online_dinnertime_pending_guard(...)` 做 strict 校验；缺失、legacy、错位或类型错误的 `pending_phase_actions[Dinnertime]` / `online_dinnertime_confirmed_players` 会直接失败，不再修复后继续。
- `core/engine/game_engine/auto_advance_try_step.gd`：删除 `_repair_online_dinnertime_pending_guard_for_resume(...)` 以及其专用的 legacy/repair helper，移除恢复准备阶段的自动重建 pending 行为。
- `core/tests/online_dinnertime_confirm_enforced_test.gd`：新增回归用例，验证 Dinnertime 恢复准备遇到缺失 pending 时会失败，且不会重建 `pending_phase_actions[Dinnertime]`。

验证：

- `rg -n "^[ ]+\S|\t +| +\t" core/engine/game_engine/auto_advance_try_step.gd core/engine/game_engine/online_resume_point_validator.gd core/tests/online_dinnertime_confirm_enforced_test.gd`：无匹配。
- `rg -n "_repair_online_dinnertime_pending_guard_for_resume|online dinnertime resume repair|Repaired online dinnertime|_read_or_build_online_dinnertime_confirmed_players_for_resume" core ui gameplay server autoload --glob "*.gd"`：无匹配。
- `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`：PASS，`files=1123`。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`：PASS，`392/392`。

结论：

- 已完成 Fix 7 遗留的 strict 收敛：online resume 准备阶段只写入显式 online confirm marker，并校验现有 Dinnertime pending guard；损坏或旧格式 pending 不再被运行期修补。
