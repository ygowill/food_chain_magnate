# core/ 架构审计与改造路线图

最后更新：2026-03-08
审计范围：`core/` 目录（含 `engine/ state/ actions/ modules/ rules/ map/ data/ utils/ random/ types/ debug/`）

---

## 1. 执行摘要

本次审计结论可以概括为一句话：

> `core/` 的主干方向是对的，已经具备“确定性、可回放、可模块化扩展”的优秀基础；但当前仍处于**功能快速演进期架构**，还没有完全进入**长期维护、多人协作、服务端复用**所需的边界稳定状态。

整体判断：

- **总体评价：良好，且有明确演化潜力。**
- **核心优势：** 引擎唯一写入口、回放/回退/存档链路完整、严格解析与 fail-fast 文化明确、模块系统 V2 已初步形成内容与规则分离。
- **主要问题：** 核心域、模块扩展机制、UI 元数据、运行时外部依赖仍存在混杂；一些关键能力仍通过 static registry、autoload 或 provider 路径注入来完成，导致边界未完全收口。
- **优先级最高的结构债务：**
  1. `RulesetV2` 过大且职责过多。
  2. `core/` 中仍存在 UI 语义与运行时平台依赖泄漏。
  3. “当前对局内容”大量保存在 static registry 中，不利于并行对局、批量仿真和服务端复用。
  4. `GameState` 仍是高度 Dictionary-heavy 的动态模型，导致 schema 契约更多依赖运行时校验而非类型边界。

本报告建议的改造原则是：

- **优先修边界，再修算法。**
- **优先将会话态与全局态分离。**
- **优先把 UI/平台依赖从 core 域模型中抽走。**
- **避免大重写，采用阶段化、可回归、可落盘跟踪的渐进重构。**

---

## 2. 审计方法与样本

本次审计主要通过以下方式完成：

- 盘点 `core/` 目录结构与文件分布。
- 抽读核心入口与大文件：`GameEngine`、`PhaseManager`、`GameState`、`ActionRegistry`、`RulesetV2`、`modules_v2.apply(...)`、`RandomManager` 等。
- 统计非测试脚本规模与热点文件。
- 抽查 `preload("res://core/...`)` 显式依赖，观察耦合集中区。
- 抽查 `AutoloadAccess` 和 provider path 注入点，评估运行时依赖边界。
- 浏览 `core/tests/` 覆盖面，用测试分布反推哪些能力相对稳定。

### 2.1 规模快照

非测试脚本约：

- `core/` 非测试 `.gd` 文件：**200 个**
- 非测试代码行数：**24,324 行**

按子目录粗略统计：

- `core/rules/`：49 文件 / 5,070 行
- `core/engine/`：34 文件 / 5,042 行
- `core/map/`：35 文件 / 4,629 行
- `core/modules/`：21 文件 / 3,114 行
- `core/state/`：19 文件 / 2,297 行
- `core/data/`：18 文件 / 1,647 行
- `core/utils/`：15 文件 / 1,092 行
- `core/actions/`：5 文件 / 841 行

测试情况：

- `core/tests/` 顶层纯逻辑测试脚本：**121 个**

### 2.2 热点文件（非测试）

按行数看，当前最值得重点关注的维护热点包括：

- `core/modules/v2/ruleset.gd`
- `core/rules/economy/bankruptcy_rules.gd`
- `core/engine/game_engine/auto_advance_try_step.gd`
- `core/engine/game_engine.gd`
- `core/map/map_baker/tile_baking.gd`
- `core/engine/game_engine/initializer.gd`
- `core/engine/game_engine/command_runner.gd`
- `core/engine/phase_manager/advance_sub_phase.gd`

这些文件不一定都“设计错误”，但它们已经是未来最容易积累复杂度和回归风险的区域。

---

## 3. 现状总评

### 3.1 主干设计是健康的

当前 `core/` 的底层架构并不是混乱状态，相反，它已经形成了一条相当清晰的主干：

- `GameEngine` 作为命令执行与状态推进的统一入口。
- `GameState` 作为唯一事实来源。
- `Command` 作为唯一可回放的状态变化记录。
- `RandomManager` 保证确定性随机。
- `Archive` / `Replay` / `Checkpoint` 构成完整的回放与恢复闭环。
- `Modules V2` 提供内容与规则的装配机制。

这条主干是当前项目最大的资产，不建议推翻重来。

### 3.2 真正的问题不在“能不能跑”，而在“以后怎么继续扩”

现在的架构已经足以支撑：

- 新规则持续开发
- 内容模块持续扩展
- headless 回放和 deterministic 测试
- 相对复杂的状态机推进

但当目标升级为以下场景时，当前结构会逐渐吃力：

- 同进程多房间/多局并行
- 服务端化复用 core
- UI 与规则分头演进
- AI 搜索 / 批量模拟 / Monte Carlo
- 多人团队长期维护

换句话说，当前架构的主要风险不是“今天会坏”，而是“明天会越来越贵”。

---

## 4. 当前架构的优点

### 4.1 命令式主线清楚，确定性意识强

`GameEngine` 将状态变更集中到命令执行路径，这是非常正确的设计：

- 状态写入入口单一。
- 回放与回退有稳定载体。
- 校验点和哈希验证有意义。
- 对未来 online / replay / debugging 都友好。

这是典型的“桌游/规则引擎”正确方向。

### 4.2 Fail Fast 文化已经形成

可以看出项目已经明确拒绝“静默兼容”“默认容错”“坏数据继续带病运行”的做法：

- `Result` 统一失败传播
- `Command.from_dict(...)` 严格校验
- `GameStateSerialization` 严格校验
- registry 初始化时严格校验类型与引用

这对复杂规则游戏尤其重要，应继续坚持。

### 4.3 模块系统 V2 的总体方向是对的

模块系统已具备几个关键特征：

- manifest / 依赖 / 冲突 / 稳定顺序
- content catalog 与 ruleset 分离
- registry 装配集中处理
- strict mode 明确

这说明当前架构已经不是“写死规则 + 局部 patch”的阶段，而是真正在向“可组合扩展平台”演进。

### 4.4 地图子系统相对成熟

`map/` 目录是当前边界感较强的部分之一：

- bake 与 runtime 分离
- placement validation 独立
- road graph 独立
- map context 有统一构建器

这说明团队在地图问题上已经有比较稳的领域分层意识。

### 4.5 测试覆盖面体现出架构意识

`core/tests/` 不只是动作和规则测试，还覆盖了：

- replay determinism
- timeline
- archive roundtrip
- module bootstrap
- schema warnings
- online / room / rewind

这类测试说明项目并不是只在补功能，而是在主动保护架构行为。

---

## 5. 关键问题与结构债务

以下问题按“结构风险”排序，不等于 bug 严重度，而是等于“未来维护成本”的严重度。

### 5.1 高优先级问题一：`RulesetV2` 已经是超大职责聚合对象

当前 `RulesetV2` 同时承载：

- settlement registry
- effect registry
- milestone effect registry
- map generation registry
- phase hooks / sub-phase hooks
- action executors / validators / availability overrides
- marketing / bankruptcy / dinnertime provider 注册
- state initializers / state schema
- phase order overrides
- UI modal / piece UI hint / effect UI text / overlay provider

这意味着它实际上已经不是“规则集合”，而是：

> 规则扩展协议 + 状态扩展协议 + UI 扩展协议 + 模块入口生命周期承载器

#### 风险

- 新增扩展能力时，几乎一定要继续往 `RulesetV2` 塞字段和方法。
- 规则扩展与 UI 扩展开始共用一个对象，边界日后会越来越难收。
- review 难度高；新同学很难快速判断“某个新增字段是否应该进 Ruleset”。

#### 判断

这是当前 `core/` 最优先需要收敛的架构问题。

### 5.2 高优先级问题二：core 与 UI 的边界存在泄漏

从当前设计看，`core/` 已经努力避免直接依赖 `ui/`，但仍存在明显的 UI 语义泄漏：

- `RulesetV2` 中存在 `phase_action_ui_modals`
- `RulesetV2` 中存在 `piece_ui_hints`
- `RulesetV2` 中存在 `effect_ui_texts`
- `RulesetV2` 中存在 `map_overlay_providers`
- `ActionExecutor` 中存在 `ui_hide_if_not_initiatable`、`ui_piece_ids`

#### 风险

- 模块开发会倾向于把 UI 适配也塞到 core 扩展协议里。
- core 的测试与领域模型会逐渐被展示层需求牵引。
- 未来若做 server-only 运行，会发现 core 中还夹带大量“只对客户端 UI 有意义”的元数据。

#### 判断

这类设计在早期是可接受的，但如果项目要持续扩张，应该尽快把“UI 元数据”和“领域规则”拆层。

### 5.3 高优先级问题三：registry 普遍采用 static 当前会话态

目前多个 registry 采用 static 缓存：

- `EmployeeRegistry`
- `ProductRegistry`
- `MilestoneRegistry`
- `MarketingRegistry`
- `TileRegistry`
- `PieceRegistry`
- 以及若干 rules registry

它们被 `modules_v2.apply(...)` 在初始化时统一 reset/configure。

#### 风险

- “当前局内容”实际上变成了“进程级全局内容”。
- 不适合多局并行。
- 不适合服务端多个房间共享同一进程。
- 不适合离线批量模拟和 AI 搜索。
- 测试虽然现在可控，但未来更容易被全局态相互污染。

#### 判断

这是当前影响“架构可扩展性”的第二大问题，仅次于 `RulesetV2` 职责膨胀。

### 5.4 高优先级问题四：core 仍依赖运行时平台环境

当前 `core/` 中仍有若干关键能力通过外部环境读取：

- 动作注册 provider 路径
- command event build provider 路径
- restaurant logo assignment provider 路径
- `Globals` autoload 的 config override
- `GameLog` / `DebugFlags` / `EventBus` 等 autoload 访问

#### 风险

- core 作为纯逻辑库的可移植性不足。
- 初始化链存在隐式依赖，降低可理解性。
- 某些能力看似“可选”，实则成为隐藏的启动前置条件。

#### 判断

当前已经比直接硬编码 UI/path 好很多，但还没有做到“真正显式依赖注入”。

### 5.5 中高优先级问题五：`GameState` 仍过于动态

当前 `GameState` 的关键结构包括：

- `bank: Dictionary`
- `players: Array[Dictionary]`
- `map: Dictionary`
- `round_state: Dictionary`

这带来两个特征：

- 优点：非常灵活，模块扩展容易。
- 缺点：类型边界更模糊，需要大量运行时验证与 accessor 补洞。

当前已经出现的“补洞组件”包括：

- `PlayerStateAccess`
- `MapStateAccess`
- `StateSchemaRegistry`

这说明团队已经感知到：

> 结构自由度太高，会把复杂度转移到访问和序列化阶段。

#### 判断

短期不建议全面静态化，但建议逐步把最稳定的子结构强约束化。

### 5.6 中优先级问题六：装配链偏长，系统集成集中在引擎层

当前新游戏启动链路大致是：

1. reset modules
2. load config
3. apply modules
4. configure registries
5. build action registry
6. create initial state
7. bake map
8. initialize supplies / invariants / checkpoint
9. emit started event

这条链本身是合理的，但现在太多步骤都集中在 `GameEngine` 周边 orchestrator 中。

#### 风险

- 新增启动步骤时，往往继续堆到 initializer / modules_v2.apply 里。
- 集成点多，理解成本高。
- 对新同学来说，系统启动路径过长。

#### 判断

这里不需要重写，只需要进一步分层 orchestrator。

---

## 6. 逐模块分析与建议

## 6.1 `core/types/`

### 现状评价

- `Result` 和 `Command` 是非常关键且设计较成功的基础协议。
- `Result` 已具备错误码、警告、链式处理等能力。
- `Command` 作为回放载体，字段完整且语义清楚。

### 问题

- `Result.ErrorCode` 目前偏少，未来如果更多地方仍然依赖错误字符串做流程判断，会逐渐失控。

### 建议

- 保持结构不动。
- 只在确有需要时扩展 `ErrorCode`，例如：`INVALID_PHASE`、`INVALID_ACTOR`、`CONFLICT`、`MISSING_DEPENDENCY` 等。
- 保持 `Command` 为纯结构对象，不要继续往里塞 UI 或调试专用语义。

---

## 6.2 `core/random/`

### 现状评价

- `RandomManager` 设计成熟，且与 replay/archive 配套良好。
- seed + state + call_count 的思路正确。

### 问题

- 基本没有结构性问题。

### 建议

- 保持稳定。
- 后续若做服务端或 AI，大概率仍可复用当前实现。

---

## 6.3 `core/state/`

### 现状评价

- 已经分成状态模型、工厂、序列化、schema registry、updater、accessor，结构方向是好的。
- `GameStateSerialization` 与 `StateSchemaRegistry` 的组合说明项目已经开始系统性处理读档和 schema 漂移问题。

### 问题

- `GameState` 仍然过于依赖 Dictionary，运行时约束成本较高。
- `PlayerStateAccess` / `MapStateAccess` 是积极信号，但还没有形成统一的 typed substate 模式。

### 建议

- 第一阶段不要大改 `GameState` 根结构。
- 先挑 3 个“高频、稳定、跨模块写入多”的子结构做强约束化：
  - `bank`
  - `round_state`
  - `player.inventory / player.company_structure`
- 可采用两种渐进方式之一：
  1. 新建 typed wrapper / accessor 层，先不改底层存储。
  2. 新建 `BankState` / `RoundStateFacade` / `PlayerStateFacade`，逐步替换直接字典访问。

### 建议优先级

- `round_state` 优先级最高，因为它最容易被模块和阶段流程共同写入。

---

## 6.4 `core/actions/`

### 现状评价

- `ActionExecutor` + `ActionRegistry` + `ActionAvailabilityRegistry` 的职责划分是合理的。
- phase/sub-phase gating 已经开始抽离，不再靠各执行器自己分散判断，这是加分项。

### 问题

- `ActionExecutor` 中已有 UI 展示相关字段。
- 未来 UI 想要更多展示 metadata 时，动作层很可能继续被侵入。

### 建议

- 保留动作层的领域元数据：`action_id`、`requires_actor`、`is_mandatory`、`is_internal`。
- 把 UI 相关字段迁出到单独注册表，例如：
  - `ActionPresentationRegistry`
  - 放在 `gameplay/` 或 `ui/` 装配层，而不是 `core/`

### 目标状态

- `ActionExecutor` 只表达“能做什么”和“怎么做”。
- UI 自己决定“怎么展示这个动作”。

---

## 6.5 `core/engine/`

### 现状评价

- 这是当前项目最强的主干。
- 命令执行、自动推进、回放、回退、存档、checkpoint、事件输出都有清晰主线。
- 从“游戏核心引擎”角度看，这部分已经具备不错的产品化基础。

### 问题

- 引擎层承担了太多系统装配与环境协调职责。
- `initializer` 和 `modules_v2.apply` 形成长链路。
- provider/adapter 的注入方式仍是路径 + `load()` + `ProjectSettings`。

### 建议

- 保留 `GameEngine` 作为 orchestrator，不建议推翻。
- 进一步拆出更明确的 bootstrap 步骤：
  - `ModuleBootstrap`
  - `RegistryBootstrap`
  - `ActionBootstrap`
  - `StateBootstrap`
  - `MapBootstrap`
  - `DiagnosticsBootstrap`
- 这样做的目标不是减少行数，而是让“启动链路可以被看懂、被测试、被替换”。

### 额外建议

- 把 provider path 注入从 core 内部读取改为：
  - `GameEngineDeps`
  - 或 `EngineAdapters`
  - 由上层场景/入口在初始化时显式传入

---

## 6.6 `core/modules/v2/`

### 现状评价

- 模块依赖闭包、冲突检测、稳定排序都很成熟。
- `ContentCatalogLoader` 与 `RulesetBuilder` 的分工是对的。

### 问题

- `RulesetV2` 已经成为平台总线式对象。
- 模块扩展协议缺少“领域扩展”和“UI 扩展”的清晰分层。
- `modules_v2.apply(...)` 目前是一个偏重的“全局注册大管家”。

### 建议

建议把现有 `RulesetV2` 拆成三个逻辑层：

1. **DomainRuleset**
   - settlement
   - effect
   - action executors / validators
   - phase hooks
   - dinnertime / marketing / bankruptcy provider

2. **StateExtensionSet**
   - state initializers
   - state int-key dict schema
   - state contract / namespacing 约束

3. **UiExtensionSet**
   - phase action ui modal
   - piece ui hints
   - effect ui texts
   - overlay providers

短期不一定要改类名，但至少要改“字段归属”和“装配责任”。

---

## 6.7 `core/rules/`

### 现状评价

- 已有明显的子域拆分趋势，例如员工、经济、采购、营销。
- registry 模式使模块扩展更容易落地。

### 问题

- registry 数量较多，扩展点是按“技术能力种类”长出来的，而不完全按“业务边界”长出来。
- 随着模块增多，“新增一个机制”常常要同时理解多个 registry。

### 建议

- 下一阶段重构不必先按文件继续切碎，而是按业务边界组织：
  - `economy/`
  - `marketing/`
  - `dinnertime/`
  - `working/`
  - `company_structure/`
- 目标是把“同一业务闭环”的规则、provider、计算、状态写入靠拢，而不是散在不同 registry 文件中。

---

## 6.8 `core/data/`

### 现状评价

- 数据定义、解析、注册表、聚合容器分层是合理的。
- `GameData` 当前作为便捷聚合器而不是系统事实源，这个定位是正确的。

### 问题

- registry 使用 static 会话态，是这一层最主要的问题。

### 建议

- 中期改造为实例型 registry bundle：
  - `CatalogRegistryBundle`
  - `RulesRegistryBundle`
- 由 `GameEngine` 或 `GameSessionContext` 持有 bundle。
- 现有 static registry 保留一层 compatibility facade，但底层改为委托当前 bundle。

---

## 6.9 `core/map/`

### 现状评价

- 这是当前最适合成为“领域示范模块”的部分之一。
- bake/runtime/graph/validation 已形成较自然边界。

### 问题

- 仍依赖 `state.map` 的动态结构，扩展虽然灵活，但契约成本高。

### 建议

- 将 `map` 作为 typed substate 试点：
  - 先不改存储格式
  - 增加更完整的 `MapRuntimeFacade`
  - 收敛对 `state.map[...]` 的散落访问
- 若阶段性效果好，再复制到 `round_state` / `player`。

---

## 6.10 `core/utils/`

### 现状评价

- 多数工具是正常的。
- `AutoloadAccess` 在过渡期很实用。

### 问题

- `AutoloadAccess` 实际上承担的是“平台适配器入口”，而不是普通 utils。

### 建议

- 中期将其从 `utils/` 概念上迁出，转入：
  - `platform/`
  - 或 `app_adapters/`
- 这样能够明确告诉维护者：
  - 这里不是纯工具
  - 这里是在做运行时环境接入

---

## 7. 目标架构建议（建议的中期目标）

建议把项目演化到如下分层：

### 7.1 建议分层

1. **Core Domain**
   - `types/`
   - `state/`
   - `actions/`
   - `rules/`（纯领域部分）
   - `map/`
   - `random/`

2. **Core Runtime / Orchestrator**
   - `engine/`
   - checkpoint / replay / archive / bootstrap

3. **Module Domain Extensions**
   - content catalog
   - domain ruleset
   - state extensions

4. **App / Platform Adapters**
   - autoload access
   - event sink adapter
   - action provider
   - UI metadata adapters

5. **UI / Gameplay Layer**
   - 展示逻辑
   - 面板/scene path
   - overlay / textual hints / modal selection

### 7.2 关键目标

目标不是“文件更少”或“类更多”，而是以下几点：

- core domain 不知道 scene path
- core domain 不读 autoload
- 当前对局内容不是 static 全局态
- ruleset 不再承担 UI 扩展总线
- state 的高频子结构有更强契约

---

## 8. 详细改造建议

## 8.1 建议一：拆分 `RulesetV2` 的职责

### 目标

将当前 `RulesetV2` 中的字段按责任拆层，而不是继续堆大对象。

### 建议拆法

- `RulesetV2` 保留为 facade
- 内部分为：
  - `_domain_rules`
  - `_state_extensions`
  - `_ui_extensions`

### 第一阶段实现方式

无需马上改所有 API，可先：

- 新建子对象类
- 把原字段迁入子对象
- `RulesetV2` 对外继续转发

### 收益

- review 更容易
- 未来可单独移除 UI 扩展出 `core/`
- 模块扩展能力更可组合

---

## 8.2 建议二：引入 `GameSessionContext` / `RegistryBundle`

### 目标

消除“当前对局内容 = static 全局态”的问题。

### 建议结构

```text
GameSessionContext
├── catalog_bundle
│   ├── employee_registry
│   ├── product_registry
│   ├── milestone_registry
│   ├── marketing_registry
│   ├── tile_registry
│   └── piece_registry
└── rules_bundle
    ├── settlement_registry
    ├── effect_registry
    ├── milestone_effect_registry
    └── ...
```

### 渐进改法

阶段 1：

- 新建 bundle 类。
- `modules_v2.apply(...)` 输出 bundle。
- `GameEngine` 持有 bundle。

阶段 2：

- static registry 变 facade。
- facade 内部委托当前 bundle。

阶段 3：

- 核心逻辑逐步直接依赖 bundle，不再依赖 static facade。

### 收益

- 多局并行成为可能。
- headless 仿真与 AI 搜索更自然。
- registry 生命周期更清晰。

---

## 8.3 建议三：把 provider / autoload 依赖显式注入

### 当前问题

目前多个关键能力由 `ProjectSettings` / `load(path)` / `AutoloadAccess` 注入。

### 建议目标

改为由上层显式传入：

- `ActionRegistryProvider`
- `CommandEventBuilder`
- `RestaurantLogoAssignmentProvider`
- `EventSink`
- `DebugOptions`
- `GameConfigOverrides`

### 实施方式

新增：

- `EngineAdapters`
- 或 `GameEngineDependencies`

由 UI 入口、headless 测试入口或 online server 入口自行组装。

### 收益

- core 不再偷偷依赖运行时环境。
- 初始化前提更显式。
- 更容易做 server-only / test-only / benchmark-only 启动。

---

## 8.4 建议四：将 UI 元数据移出 core 领域协议

### 当前问题

模块现在可以在 ruleset 中注册 UI modal、overlay、effect 文案等，这让模块功能很方便，但混淆了领域层和展示层。

### 建议

- 新增 `ModuleUiMetadataCatalog`
- 或 `ModulePresentationRegistry`
- 装配位置放在 `gameplay/` 或 `ui/`，而不是 `core/engine/modules_v2.apply(...)`

### 渐进策略

第一步：

- 保留原注册 API
- 但装配路径改到 gameplay/ui bootstrap

第二步：

- 从 `RulesetV2` 中彻底剥离 UI 字段

### 收益

- 域模型更纯
- server-only 运行无需加载 UI 扩展
- 模块作者更清楚“规则扩展”和“表现扩展”是两类能力

---

## 8.5 建议五：逐步强化 `GameState` 契约

### 当前问题

`GameState` 灵活，但读写成本高，依赖运行时校验与命名约定。

### 建议优先顺序

1. `round_state`
2. `bank`
3. `player` 子结构
4. `map`

### 方法

- 先引入 facade / accessor / validator，不立即替换存储。
- 在关键路径中禁止裸写新 key。
- 模块自有字段继续 namespaced，但必须通过统一 helper 写入。

### 收益

- schema drift 降低
- 反序列化告警更少
- 写状态的位置更容易审查

---

## 8.6 建议六：把启动链路切成可测试 bootstrap 步骤

### 当前问题

初始化逻辑虽然完整，但较长，很多逻辑集中在 `initializer.gd` 与 `modules_v2.gd` 周围。

### 建议拆分

- `bootstrap/module_bootstrap.gd`
- `bootstrap/registry_bootstrap.gd`
- `bootstrap/action_bootstrap.gd`
- `bootstrap/state_bootstrap.gd`
- `bootstrap/map_bootstrap.gd`
- `bootstrap/diagnostics_bootstrap.gd`

### 收益

- 每一步更容易单测。
- 错误更容易定位。
- 启动链更适合多人协作修改。

---

## 9. 可执行路线图

以下路线图采用“逐阶段收口边界”的方式，避免一次性重构过大。

## 阶段 0：冻结边界与补文档（1 周）

### 目标

先把“未来不希望继续恶化的方向”冻结住。

### 工作项

1. 落盘本审计报告。
2. 增加架构规则说明：
   - `core/` 不新增 UI scene path 依赖
   - `core/` 不新增新的 autoload 直连
   - 新模块 UI 元数据不得继续塞入 domain ruleset
3. 为现有结构补“边界型测试/检查脚本”。

### 产出物

- 本文档
- 一份简短的架构约束补充文档或 ADR
- 最低限度的架构守卫测试

### 验收标准

- 后续 PR 能明确判断：是否又把 UI 逻辑带回 core

---

## 阶段 1：拆分 UI 扩展职责（1~2 周）

### 目标

将 `RulesetV2` 中最明显的 UI 元数据职责剥离出去。

### 工作项

1. 新建 UI metadata 容器：
   - `module_ui_metadata.gd`
   - 或 `module_presentation_registry.gd`
2. 迁移以下字段：
   - `phase_action_ui_modals`
   - `piece_ui_hints`
   - `effect_ui_texts`
   - `milestone_effect_ui_texts`
   - `map_overlay_providers`
3. 将装配位置从 `core/engine/game_engine/modules_v2.gd` 挪到 `gameplay/` 或 `ui/` bootstrap。

### 目标文件

- `core/modules/v2/ruleset.gd`
- `core/engine/game_engine/modules_v2.gd`
- 对应 UI / gameplay 装配入口

### 验收标准

- `core/` 不再承担 scene path / UI text / overlay provider 注册装配职责
- 行为保持不变
- 全量 headless 测试通过

### 实施进度（截至 2026-03-08）

- `refactor(gameplay): route UI registries through module metadata bootstrap`
  - 扩展 `ModuleUiMetadata`，让 `piece_ui_hints`、`effect_ui_texts`、`milestone_effect_ui_texts` 与 `map_overlay_providers` 也随 phase action modal 一并从 `RulesetV2.ui_extensions` 提取并缓存到 gameplay 层容器。
  - 为 `PieceUiHintsRegistry`、`EffectUiTextRegistry`、`MapOverlayProviderRegistry` 增加 `configure_from_module_ui_metadata(...)`，并让 `ModuleUiMetadataBootstrap.apply()` 改走这条新链路，避免 UI registry 装配继续沿着 core protocol 直接读取 `ruleset.get_ui_extensions()`。
  - 扩展 `ruleset_ui_extensions_facade_test` 与 `module_ui_metadata_bootstrap_test`，补充 metadata 缓存与 bootstrap 装配回归，确保行为保持不变且 UI metadata 读取链已切到 gameplay bootstrap。

- `refactor(core): separate module UI extensions from ruleset build output`
  - 调整 `RulesetBuilderV2` / `RulesetLoaderV2`，让模块 entry 注册得到的 UI 扩展改为单独产出 `ui_extensions` bundle，并由 `GameEngine.module_ui_extensions_v2` 持有，而不是继续挂在正常初始化得到的 `ruleset_v2` 上。
  - 扩展 `ModuleUiMetadata` 增加 `configure_from_ui_extensions(...)`，并让 `ModuleUiMetadataBootstrap.apply()` 优先消费 `engine.module_ui_extensions_v2`，进一步减少 gameplay UI bootstrap 对 `RulesetV2` 的直接依赖。
  - 扩展 `module_ui_metadata_bootstrap_test`，补充“engine 持有独立 ui_extensions bundle、而 `ruleset_v2` 不再承载 kimchi modal”回归，确保阶段 1 的 UI 元数据存储边界继续外移。

- `refactor(core): remove UI facade from ruleset`
  - 删除 `RulesetV2` 中残留的 `get_ui_extensions()`、phase action modal / piece hint / effect text / overlay provider facade，让 ruleset 重新聚焦领域规则与状态扩展职责。
  - 将 `ModuleUiMetadataBootstrap.apply()` 收紧为只消费 `engine.module_ui_extensions_v2`，并让 `ModuleUiMetadata` 的独立入口仅保留 `configure_from_ui_extensions(...)`，不再沿 gameplay 链路回退到 ruleset。
  - 重写 `ruleset_ui_extensions_facade_test`，改为校验独立 `RulesetV2UiExtensions` holder 仍保持原有注册/查询/清理行为，同时断言 `RulesetV2` 不再暴露对应 UI facade。

- `refactor(core): drop legacy UI registry ruleset loaders`
  - 删除 `PieceUiHintsRegistry`、`EffectUiTextRegistry`、`MapOverlayProviderRegistry` 中已无调用的 `configure_from_ruleset(...)` 兼容入口，彻底切断 UI registry 对 ruleset UI holder 的旧依赖。
  - 让阶段 1 的 gameplay UI 链路统一收口到 `ModuleUiMetadata` / `module_ui_extensions_v2`，避免后续改动再绕回 core ruleset。
  - 通过 headless compile、`GameSmokeTest` 与 `AllTests` 复核删兼容入口后无残留静态调用，确保 phase 1 的 UI metadata 装配边界完整闭合。

### 风险

- UI 读取路径要同步调整
- 需要补 2~3 个 regression test 保护模块 UI 展示不回归

---

## 阶段 2：引入 `GameSessionContext`（2~3 周）

### 目标

把会话态 registry 从 static 全局态迁到实例态。

### 工作项

1. 新建 `GameSessionContext` / `RegistryBundle`
2. `modules_v2.apply(...)` 产出 bundle
3. `GameEngine` 持有 bundle
4. static registry 改为 facade，底层委托 bundle

### 目标文件

- `core/engine/game_engine/modules_v2.gd`
- `core/data/*_registry.gd`
- `core/map/*_registry.gd`
- `core/rules/*_registry.gd`

### 验收标准

- 单进程内可并行创建两个 `GameEngine` 实例且 registry 不互相污染
- 现有核心测试不回归

### 实施进度（截至 2026-03-08）

- `refactor(core): switch milestone effect registry with active engine bundle`
  - 将 `MilestoneEffectRegistry` 的当前会话切换接入 `GameEngine.activate_registry_bundles()`，让多引擎场景下的里程碑 effect handler 会随当前激活引擎一起切换，减少 static current 在回放/联机并行场景中的串扰风险。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 engine A / engine B 之间来回切换 milestone effect registry 的回归断言，确保多实例切换时不会继续残留上一局的里程碑 effect registry。

- `refactor(core): bundle marketing type registry per engine session`
  - 新增 `RulesRegistryBundle` 并让 `GameEngine` 持有 `rules_registry_bundle`，再把 `MarketingTypeRegistry` 的当前会话切换接入 `activate_registry_bundles()`，让营销类型定义不再停留在进程级 static 字典。
  - 调整 `modules_v2.reset/apply`，在清空每局 rules bundle 后重新 `reset()` `MarketingTypeRegistry`，确保 headless / UI 启动链里的模块装配顺序仍然稳定。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `gourmet_guide` marketing type 在 engine A / engine B 之间切换时的隔离断言，确保多引擎并行场景下营销类型注册不会串局。

- `refactor(core): bundle bankruptcy registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `BankruptcyRegistry` 的 first-break handler/source 改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换。
  - 调整 `modules_v2.apply`，在清空每局 rules bundle 后同步 `reset()` `BankruptcyRegistry`，避免 UI/Headless 启动链里出现“bundle 已清空但 registry 未重新置为 loaded”的顺序回归。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `reserve_prices` 的 bankruptcy handler/source 在 engine A / engine B 间切换的隔离断言，确保多引擎并行场景下破产处理器不会串局。

- `refactor(core): bundle marketing initiation registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `MarketingInitiationRegistry` 的 provider 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换。
  - 为 registry 增加 `get_provider_ids()` 调试查询，并在 `modules_v2.apply` 清空每局 rules bundle 后同步 `reset()` `MarketingInitiationRegistry`，避免 UI/Headless 启动链再出现 bundle 已清空但 registry 未重新置为 loaded 的顺序回归。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `new_milestones` 的 3 个 marketing initiation provider 在 engine A / engine B 间切换时的隔离断言，确保多引擎并行场景下发起营销扩展逻辑不会串局。

- `refactor(core): bundle placement conflict registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `PlacementConflictRegistry` 的 provider 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换，避免跨模块放置冲突检查继续依赖进程级 static 当前会话态。
  - 调整 `modules_v2.reset/apply`，在清空每局 rules bundle 后同步 `reset()` `PlacementConflictRegistry`，修复 headless / UI 启动链里 bundle 已清空但 registry 未重新置为 loaded 时的初始化顺序回归。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `rural_marketeers:placement_conflicts` provider 在 engine A / engine B 间切换、以及 engine A dispose 后 engine B 重新激活时的隔离断言；同时把测试模块集补齐 `rural_marketeers`，确保这条新增覆盖真正命中放置冲突 provider 的注册链路。

- `refactor(core): bundle range origin registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `RangeOriginRegistry` 的 provider 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换，避免 coffee 等模块扩展的额外 range 起点继续依赖进程级 static 当前会话态。
  - 调整 `modules_v2.apply`，在清空每局 rules bundle 后同步 `reset()` `RangeOriginRegistry`，保证 headless / UI 启动链在 bundle 已清空后仍能按既定顺序重新装配 range origin provider。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `coffee:range_origins:coffee_shops` provider 在 engine A / engine B 间切换、以及 engine A dispose 后 engine B 重新激活时的隔离断言，并把测试模块集补齐 `coffee` 以命中真实注册链路。

- `refactor(core): bundle employee pool patch registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `EmployeePoolPatchRegistry` 的 patch 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换，避免 coffee 等模块对初始员工池的受控 patch 继续停留在进程级 static 会话态。
  - 为 registry 增加 `get_patch_ids()` 调试查询，并在 `modules_v2.apply` 清空每局 rules bundle 后同步 `reset()` `EmployeePoolPatchRegistry`，保证 headless / UI 启动链在重新装配模块时不会丢失 loaded 状态。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `extra_luxury_manager` patch 在 engine A / engine B 间切换、以及 engine A dispose 后 engine B 重新激活时的隔离断言，确保多引擎并行场景下 employee pool patch 不会串局。

- `refactor(core): bundle dinnertime route purchase registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `DinnertimeRoutePurchaseRegistry` 的 provider 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换，避免 coffee 等模块的晚餐路上购买/结算逻辑继续依赖进程级 static 会话态。
  - 为 registry 增加 `get_provider_ids()` 调试查询，并在 `modules_v2.apply` 清空每局 rules bundle 后同步 `reset()` `DinnertimeRoutePurchaseRegistry`，保证模块重新装配后 route purchase provider 仍能稳定进入 loaded 状态。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `coffee:route:coffee` provider 在 engine A / engine B 间切换、以及 engine A dispose 后 engine B 重新激活时的隔离断言，确保多引擎并行场景下晚餐 route provider 不会串局。

- `refactor(core): bundle dinnertime demand registry per engine session`
  - 继续扩展 `RulesRegistryBundle`，把 `DinnertimeDemandRegistry` 的 provider 列表改为每局持有，并在 `GameEngine.activate_registry_bundles()` 中跟随当前引擎切换，避免 sushi / noodles / kimchi 这类晚餐需求变体继续依赖进程级 static 当前会话态。
  - 为 registry 增加 `get_provider_ids()` 调试查询，并在 `modules_v2.apply` 清空每局 rules bundle 后同步 `reset()` `DinnertimeDemandRegistry`，保证模块重新装配后 demand provider 仍能稳定进入 loaded 状态。
  - 扩展 `catalog_registry_bundle_isolation_test`，补充 `sushi:demand_variants` provider 在 engine A / engine B 间切换、以及 engine A dispose 后 engine B 重新激活时的隔离断言，并把测试模块集补齐 `sushi` 以命中真实注册链路。

### 风险

- 改动面较大
- 需要 careful 迁移 compatibility facade

---

## 阶段 3：显式依赖注入（1~2 周）

### 目标

移除 core 对 `ProjectSettings` / autoload 的关键隐式依赖。

### 工作项

1. 新建 `EngineAdapters` / `GameEngineDependencies`
2. 注入：
   - action registry provider
   - event build provider
   - logo assignment provider
   - debug options
   - config overrides
   - event sink
3. `AutoloadAccess` 仅保留在 app adapter 层

### 目标文件

- `core/engine/game_engine/action_setup.gd`
- `core/engine/game_engine/command_runner.gd`
- `core/state/game_state_factory.gd`
- `core/engine/game_engine/initializer.gd`

### 验收标准

- headless 启动不依赖 `Globals`
- server-like 启动可在不挂 UI autoload 的条件下运行

### 实施进度（截至 2026-03-08）

- `refactor(core): inject restaurant logo assignment provider`
  - 将新局初始化的餐厅 Logo 分配接入 `GameEngineDependencies.restaurant_logo_assignment_provider`，让 `initializer` / `GameStateFactory` 优先消费显式注入的 provider，同时保留原有 `ProjectSettings` path 作为兼容桥。
  - 扩展 `engine_dependencies_injection_test`，补充 logo provider 的调用入参与 `restaurant_logo_id` 写回断言，确保 headless 初始化不必依赖全局 path 配置也能稳定完成 Logo 分配。

- `refactor(core): inject config override dependencies`
  - 将新局初始化对 `game_config_overrides` / `game_option_overrides` 的消费接入 `GameEngineDependencies`，让 `initializer` 优先使用显式注入的覆盖字典，并仅在未注入时回退到现有全局桥接。
  - 扩展 `engine_dependencies_injection_test`，补充规则薪资与起始现金覆盖断言，确保 headless 初始化在不依赖 `Globals` 的情况下也能稳定应用配置覆盖。

- `refactor(core): inject command runner debug options`
  - 将 `command_runner` 对 `debug_mode` / `force_execute_commands` / `validate_invariants` / `verbose_logging` 的读取接入 `GameEngineDependencies.command_runner_debug_options`，让运行时命令开关优先使用显式注入配置，并仅在未注入时回退到现有 debug bridge。
  - 扩展 `engine_dependencies_injection_test`，补充运行时 `debug_force` 命令的成功回归，确保 headless 场景无需依赖 `DebugFlags` autoload 也能稳定走强制执行路径。

- `refactor(core): align event sink with engine dependencies`
  - 将 `GameEngine` 的事件输出来源收口到 `GameEngineDependencies.event_sink`，并让 `rewind_ops` / 初始化历史清理 / 事件发送统一走同一条 sink 读取路径，减少显式依赖注入链里的双份状态。
  - 扩展 `engine_dependencies_injection_test`，补充初始化清理、`game_started` 与 `command_executed` 事件写入断言，确保 headless 场景下自定义 sink 会稳定接管事件输出。

---

## 阶段 4：强化状态契约（2~4 周）

### 目标

逐步收紧 `GameState` 的高频子结构契约。

### 工作项

1. 为 `round_state` 建立统一 facade / helper
2. 为 `bank` 建立统一 facade / helper
3. 收敛对 `player[...]` 和 `state.map[...]` 的裸访问
4. 模块字段统一走 namespaced helper

### 验收标准

- 关键路径中不再直接散落大量 `state.round_state[...] = ...`
- schema warning 数量下降

### 风险

- 改动点多且分散
- 要靠测试与小步提交控制风险

### 实施进度（截至 2026-03-08）

已完成的阶段 4 小步收口如下：

- `refactor(core): harden map context builder contract`
  - 收紧 `MapContextBuilder` 的 `state.map` 契约入口。
  - 以 focused state-access 测试覆盖 map context fail-fast 分支。
- `refactor(core): tighten base marketing map access`
  - 收紧基础营销放置查询对 `state.map` 的读取。
  - 通过 headless compile + `all_tests` 回归验证。
- `refactor(core): tighten drinks procurement state access`
  - 收紧饮料采购路径上的动态 state 访问。
  - 为 fail-fast 行为补充 focused 回归测试。
- `refactor(core): tighten order of business state access`
  - 新增统一 helper，减少 `round_state.order_of_business` 裸访问。
  - 补充纯逻辑回归测试，覆盖缺字段与类型错误分支。
- `refactor(core): tighten sub phase passed access`
  - 新增统一 helper，减少 `round_state.sub_phase_passed` 裸访问。
  - 补充 focused 测试并跑全量回归。
- `refactor(modules): tighten rural offramp state access`
  - 收紧 `rural_marketeers` offramp 地图字段读取。
  - 为 map optional/required 字段分支补 focused 测试。
- `refactor(modules): tighten rural module entry state access`
  - 收紧 `rural_marketeers` entry 对模块命名空间状态的读取。
  - 以 focused module test 保护 fail-fast 行为。
- `refactor(modules): unify rural offramp pending flags`
  - 统一 offramp pending flag 到 `RoundStatePlayerBoolFlags`。
  - 增补 pending flag 兼容/类型测试。
- `refactor(core): tighten rural offramp supply access`
  - 为 `MapStateAccess` 增加 optional int/array/dict helper。
  - 收紧 offramp supply 访问并覆盖成功/失败/不提前写入场景。
- `refactor(modules): tighten lobbyists supply initialization`
  - 收紧 `lobbyists` restructuring 阶段 road/park supply 初始化。
  - 新增 focused test 覆盖缺省初始化、类型错误和负数 fail-fast。
- `refactor(modules): tighten lobbyists action supply access`
  - 收紧 `place_lobbyists_road` / `place_lobbyists_park` 的 supply validate/apply 读取。
  - 补充 focused 测试，覆盖缺失 supply 时不提前写入结构或 pending。
- `refactor(modules): tighten milestone marketing used flags`
  - 将 `new_milestones` 的 `*_used_this_turn` 收口到 `RoundStatePlayerBoolFlags`。
  - 新增 focused test，覆盖 int-key 契约和 string key fail-fast。
- `refactor(modules): tighten pizza pending phase actions`
  - 将 pizza 里程碑对 `pending_phase_actions` 的写入收口到 `RoundStatePendingPhaseActions`。
  - 补 focused test，确保 `pending_phase_actions` 类型错误时不提前写入 pizza pending。
- `refactor(modules): tighten pizza radio pending updates`
  - 收紧 `place_pizza_radio` apply 阶段的 pending / pending_phase_actions 更新顺序。
  - 补 focused test，确保失败时不提前写入 placement、instance 或消耗 pending。
- `refactor(modules): tighten campaign manager pending access`
  - 收紧 `place_campaign_manager_second_tile` apply 阶段的 pending 读取。
  - 补 focused test，确保 pending 类型错误时无 partial mutation。
- `refactor(modules): tighten brand manager pending access`
  - 收紧 `set_brand_manager_airplane_second_good` apply 阶段的 pending 读取。
  - 补 focused test，确保 pending 类型错误时无 partial mutation。
- `refactor(gameplay): tighten restaurant opening-soon access`
  - 将 `place_restaurant` 的 `opening_soon_restaurants` 校验前移到 apply 变更之前。
  - 补 focused test，确保 key 类型错误时不提前写入格子、`player.restaurants` 或 `next_restaurant_id`。
- `refactor(gameplay): tighten add garden apply state access`
  - 收紧 `add_garden` apply 阶段对 `state.map.houses`、房屋锚点结构和 `house_placement_counts` 的读取。
  - 补 focused test，确保 `anchor_pos` / 计数器类型异常时不提前改写房屋、格子或花园供给。
- `refactor(gameplay): tighten place house apply state access`
  - 收紧 `place_house` apply 阶段对 `state.map.houses` 和 `house_placement_counts` 的读取顺序。
  - 补 focused test，确保计数器类型异常时不提前消耗编号供给或写入房屋结构。
- `refactor(modules): tighten rural billboard query access`
  - 将 `place_giant_billboard.can_initiate()` 的 `houses` 读取收口到 `MapStateAccess`，保持 fail-closed。
  - 扩 focused test，覆盖缺失 `houses` / 非法 `rural_area` 时 query 路径返回 `false`。
- `refactor(gameplay): tighten kimchi cleanup pending access`
  - 将 `choose_kimchi_storage` 的 cleanup pending 预检前移到 inventory 变更之前，并让 pending setter 显式返回失败。
  - 补 focused test，确保 `pending_phase_actions` 类型错误时不提前改写 `inventory` 或 `cleanup.inventory_discarded`。
- `refactor(gameplay): tighten fridge cleanup pending access`
  - 将 `choose_fridge_keep` 的 cleanup pending 预检前移到 inventory 变更之前，并让 pending setter 显式返回失败。
  - 补 focused test，确保 `pending_phase_actions` 类型错误时不提前改写 `inventory` 或 `cleanup.inventory_discarded`。
- `refactor(modules): tighten marketing initiation pending access`
  - 将 `new_milestones` 的 campaign / brand manager 发起营销 pending 读写收口到 fail-fast helper，拒绝字符串玩家 key。
  - 扩 focused test，确保 `round_state` pending 字典 key 非法时不提前写入 used flag 或补写 int-key pending。
- `refactor(modules): tighten coffee cleanup pending access`
  - 将 `coffee_first_coffee_sold` 的 Cleanup pending 解析收口到 fail-fast helper，并统一使用 `RoundStatePendingPhaseActions` 写回。
  - 新增 focused test，覆盖 legacy fridge pending 合并与非法 pending 项时无 partial mutation。
- `refactor(gameplay): tighten restructuring pending access`
  - 将重组阶段的 pending 写回统一到 `RoundStatePendingPhaseActions`，并在 `submit_restructuring` apply 前预检 `pending_phase_actions[Restructuring]`。
  - 新增 focused test，确保 pending 类型错误时不提前改写玩家结构、submitted 标记或 finalized。
- `refactor(modules): tighten kimchi cleanup pending access`
  - 将 `kimchi` 模块 Cleanup 阶段的 pending 解析收口到 fail-fast helper，并统一使用 `RoundStatePendingPhaseActions` 切换到 kimchi pending。
  - 新增 focused test，覆盖 legacy fridge pending 提升与非法 pending 项时无 partial mutation。
- `refactor(gameplay): tighten forfeit pending access`
  - 将 `forfeit_player` 对 `pending_phase_actions` / `online_dinnertime_confirmed_players` 的更新改为先规划再落地，避免坏状态下先发生资产清理。
  - 新增 focused test，确保 `pending_phase_actions` 类型错误时不提前标记 forfeited、清空资产或改写银行累计。
- `refactor(gameplay): tighten dinnertime confirmed access`
  - 将 `confirm_dinnertime` 对 `online_dinnertime_confirmed_players` 的读取改为 fail-fast，并把 confirmed / pending 的写回顺序调整为先更新 pending 再落地 confirmed。
  - 新增 focused test，确保 `online_dinnertime_confirmed_players` 元素类型错误时不提前改写 `pending_phase_actions` 或 confirmed 列表。
- `refactor(gameplay): tighten skip mandatory access`
  - 将 `skip` / `skip_sub_phase` 对 `mandatory_actions_completed` 的读取统一收口到 `RoundStatePlayerStringLists`，拒绝字符串玩家 key。
  - 新增 focused test，确保两条动作在 `mandatory_actions_completed` 使用字符串玩家 key 时都返回 fail-fast 错误。
- `refactor(gameplay): tighten price modifier access`
  - 新增 `RoundStatePlayerIntMaps`，并将 `set_price` / `set_discount` / `set_luxury_price` 的 `price_modifiers` 写入统一收口到 helper。
  - 调整三条动作的 apply 顺序，先校验并写入 `price_modifiers`，再标记 `mandatory_actions_completed`，避免坏状态下留下半提交。
  - 新增 focused test，确保 `price_modifiers` 使用字符串玩家 key 时不提前标记 mandatory action，也不补写 int-key modifier。
- `refactor(gameplay): tighten train event access`
  - 将 `train` 对 `round_state.train_events` 的预检前移到实际培训变更之前，避免坏状态下先改写员工、供应池或 `round_state` 其它字段后才失败。
  - 新增 focused test，确保 `train_events` 类型错误时不提前改写玩家员工状态、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten train phase start count access`
  - 扩展 `RoundStatePlayerIntMaps` 以支持整张 per-player int map 写回，并将 `train_phase_start_counts` 的读写统一收口到 helper。
  - 新增 focused test，确保 `train_phase_start_counts` 使用字符串玩家 key 时 fail-fast，且不补写 int-key 回填。
- `refactor(gameplay): tighten train lock target access`
  - 将 `train_employee_locks` 对 `to_employee` token 桶的校验前移到 `plan_training`，避免坏锁表在培训动作后半程才失败。
  - 扩展 focused `train` 状态访问测试，确保 `to_employee` token 桶类型错误时不提前改写玩家员工状态、`employee_pool` 或 `round_state`。
- `refactor(modules): tighten night shift multiplier access`
  - 扩展 `RoundStatePlayerIntMaps` 以支持整张 per-player int map 的 fail-fast 校验/写回，并将 `night_shift_managers` 的 `working_employee_multipliers` 写回统一收口到 helper。
  - 新增 focused test，确保已有 `working_employee_multipliers` 使用字符串玩家 key 时 `_on_working_before_enter()` fail-fast，且不会静默覆盖坏状态。
- `refactor(modules): tighten reserve price bankruptcy access`
  - 将 `reserve_prices` 第一次破产对 `round_state.bankruptcy.events` 的校验前移到实际揭示储备卡、改写银行与规则状态之前，并把事件写回改为显式 `Result` 失败返回。
  - 新增 focused test，确保 `bankruptcy.events` 类型错误时第一次破产会 fail-fast，且不会提前揭示储备卡、改写 bank、rules 或 `round_state`。
- `refactor(modules): tighten mass marketeers round access`
  - 将 `mass_marketeers` 对 `round_state.marketing_rounds` 的覆盖写回改为先校验已有值，拒绝非法旧状态被静默覆盖。
  - 新增 focused test，确保 `marketing_rounds` 类型错误时 `_on_marketing_before_primary()` fail-fast，且不会覆盖已有坏状态。
- `refactor(gameplay): tighten train usage mandatory access`
  - 将 `train_employee_usage` 的 mandatory action 使用判定改为显式 `Result` fail-fast，并把 `train` apply 路径的校验前移到 `train_employee_locks` 初始化与 slot 分配之前。
  - 扩展 focused `train` 状态访问测试：临时打开 `pricing_manager -> luxury_manager` 训练路径，确保 `mandatory_actions_completed` 使用字符串玩家 key 时 fail-fast，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(modules): tighten coffee cleanup metadata access`
  - 将 `coffee_cleanup` 对 `round_state.coffee` 既有元数据的校验前移到实际清空库存之前，避免坏状态被静默覆盖。
  - 扩展 focused test，确保 `round_state.coffee` 类型错误时 cleanup 会 fail-fast，且不会提前清空 `inventory.coffee` 或覆盖旧元数据。
- `refactor(replay): tighten cleanup pending access`
  - 为 `StepTimelineBuild` 增加 `read_has_pending_cleanup_actions()`，并将 replay 构建链路中对 `pending_phase_actions` / `pending_phase_actions[Cleanup]` 的坏状态改为显式失败传播。
  - 新增 focused helper test，覆盖缺失 pending、合法 cleanup pending，以及两类非法 pending 结构。
- `refactor(gameplay): tighten dinnertime pending item access`
  - 将 `confirm_dinnertime` 对 `pending_phase_actions[Dinnertime]` 项的解析改为显式校验，拒绝非法 `kind` / `player_id` 被静默跳过，并统一先规划 remaining pending 再落地。
  - 扩展 focused 状态访问测试，确保非法 pending player_id 会 fail-fast，且不会提前改写 `pending_phase_actions` 或 `online_dinnertime_confirmed_players`。
- `refactor(modules): tighten coffee shop train event access`
  - 将 `place_or_move_coffee_shop` 对 `round_state.train_events` 的读取改为显式校验，拒绝非法事件项或坏 `player_id` / `to_employee` 被静默忽略。
  - 扩展 focused 状态访问测试，确保非法 `train_events` 会 fail-fast，且不会提前递增 `next_coffee_shop_id`、消耗 token 或写入咖啡店结构。
- `refactor(gameplay): tighten train recruit-used access`
  - 将 `train_employee_usage` 对 `round_state.recruit_used` 的读取统一收口到 `RoundStateCounters.get_player_count()`，拒绝字符串玩家 key 或坏计数被静默当作 0。
  - 扩展 focused `train` 状态访问测试，临时打开 `recruiting_girl -> recruiting_manager` 训练链，确保非法 `recruit_used` 会 fail-fast，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(modules): tighten payday recruit-used access`
  - 将 `PaydaySettlement` 对 `round_state.recruit_used` 的读取统一收口到 `RoundStateCounters.get_player_count()`，避免手写 per-player int map 校验分叉。
  - 新增 focused 状态访问测试，确保 `recruit_used` 使用字符串玩家 key 时 `PaydaySettlement.apply()` 会 fail-fast，且不会提前改写 `players`、`bank` 或 `round_state`。
- `refactor(modules): tighten coffee shop trigger usage access`
  - 将 `place_or_move_coffee_shop` 对 `round_state.coffee_shop_triggers_used` 的读写统一收口到 `RoundStateCounters`，避免重复实现 per-player int 计数契约。
  - 扩展 focused 状态访问测试，确保 `coffee_shop_triggers_used` 使用字符串玩家 key 时动作会 fail-fast，且不会提前递增 id、消耗 token 或写入咖啡店结构。
- `refactor(gameplay): tighten train usage counter access`
  - 将 `train_employee_usage` 对 `production_counts`、`procurement_counts`、`marketing_used` 的读取统一收口到 `RoundStateCounters.get_player_key_count()`，拒绝坏的 per-player/per-item 计数结构被静默忽略。
  - 扩展 focused `train` 状态访问测试，覆盖三类非法计数结构，确保 helper 读取路径会显式 fail-fast。
- `refactor(gameplay): tighten fire recruit-used access`
  - 将 `fire_action` 的 Payday 忙碌营销员判定里对 `round_state.recruit_used` 的读取统一收口到 `RoundStateCounters.get_player_count()`，保持既有 fail-soft 语义。
  - 扩展 focused 状态访问测试，确保 `recruit_used` 损坏时 `_can_fire_busy_marketer()` 仍安全返回 `false`。
- `refactor(gameplay): tighten train phase pending baseline access`
  - 将 `train_phase_start_counts` 对 `round_state.immediate_train_pending` 的字符串玩家 key 检查从 `assert` 改为显式 `Result` 失败，避免坏状态在读基线计数时触发硬断言。
  - 扩展 focused 状态访问测试，确保非法 `immediate_train_pending` 会 fail-fast，且不会提前写入 `train_phase_start_counts`。
- `refactor(gameplay): tighten train lock pending baseline access`
  - 将 `train_employee_locks` 对 `round_state.immediate_train_pending` 的字符串玩家 key 检查从 `assert` 改为显式 `Result` 失败，避免坏状态在构建 token 基线时触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `immediate_train_pending` 会 fail-fast，并返回可诊断的契约错误。
- `refactor(gameplay): tighten train lock round-state access`
  - 将 `train_employee_locks` 对 `round_state.train_employee_locks` 的字符串玩家 key 检查统一改为显式 `Result` 失败，避免坏锁表在读取、初始化或写回路径触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `train_employee_locks` 在 helper 读取与初始化路径都会 fail-fast，且不会覆盖既有坏状态。
- `refactor(core): tighten train slot usage instance access`
  - 将 `train_slot_usage_storage` 对 `round_state.train_slot_usage_instances` 的字符串玩家 key 检查统一改为显式 `Result` 失败，避免坏状态在按实例读取或写回培训 slot 用量时触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `train_slot_usage_instances` 在读取与写回路径都会 fail-fast，且不会覆盖既有坏状态。
- `refactor(core): tighten train slot usage fallback access`
  - 将 `train_slot_usage_storage` 对旧版 `round_state.train_slot_usage` fallback 读取从 `assert` 改为显式 `Result` 失败，避免坏计数结构在按实例补算 slot 用量时触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `train_slot_usage` 会沿 fallback 读取路径 fail-fast，并返回可诊断错误。
- `refactor(gameplay): tighten train phase start array access`
  - 将 `train_phase_start_counts` 计算阶段对 `reserve_employees` / `employees` 元素类型检查从 `assert` 改为显式 `Result` 失败，避免坏玩家数组在建立起始计数时触发硬断言。
  - 扩展 focused 状态访问测试，确保非法 reserve/active 员工条目会 fail-fast，且不会提前写入 `train_phase_start_counts`。
- `refactor(gameplay): tighten train max-step validation access`
  - 为 `train_slot_usage` 增补 `Result` 版 max-step 读取 helper，并让 `train_action` 在计算多步培训上限时对损坏的 `train_slot_usage_instances` 显式 fail-fast，避免 query helper 内部硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `train_slot_usage_instances` 会在验证阶段失败，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten recruit on-credit validation access`
  - 复用 `train_slot_usage` 的安全 max-step helper，让 `recruit_action` 在缺货预支验证时对损坏的 `train_slot_usage_instances` 显式 fail-fast，避免旧 query 路径吞掉状态错误。
  - 扩展 focused `train` 状态访问测试，确保非法 `train_slot_usage_instances` 会在 recruit 验证阶段失败，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten train usage multiplier access`
  - 为 `working_multiplier` 增补 `Result` 版读取 helper，并让 `train_employee_usage` 在招聘/培训推导与 inferred-use 写回前对损坏的 `working_employee_multipliers` 显式 fail-fast。
  - 扩展 focused `train` 状态访问测试，确保非法 `working_employee_multipliers` 会在读取与 inferred-use 路径失败，且不会提前改写 `round_state`。
- `refactor(gameplay): tighten train pending validation access`
  - 为 `immediate_train_pending` 增补 `Result` 版 count/total 读取 helper，并让 `train_action` 在验证阶段对损坏的 pending 结构显式 fail-fast，避免旧读取路径触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `immediate_train_pending` 会在验证阶段失败，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten recruit pending validation access`
  - 复用 `immediate_train_pending` 的安全 total 读取 helper，让 `recruit_action` 在缺货预支验证时对损坏的 pending 结构显式 fail-fast，避免旧读取路径触发硬断言。
  - 扩展 focused `train` 状态访问测试，确保非法 `immediate_train_pending` 会在 recruit 验证阶段失败，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(modules): tighten base rules pending exit access`
  - 为 `immediate_train_pending` 增补 `Result` 版 any-pending 读取 helper，并让 `base_rules` 的 Working/Train before-exit hook 对损坏的 pending 结构显式 fail-fast，避免旧查询路径触发硬断言。
  - 新增 focused phase-hook 状态访问测试，确保非法 `immediate_train_pending` 会在两条 before-exit 路径失败，并返回可诊断错误。
- `refactor(gameplay): tighten pending apply access`
  - 为 `immediate_train_pending` 增补 `Result` 版 add/consume helper，并让 `recruit_action` / `train_action` 在缺货预支登记与清账阶段对损坏的 pending 结构显式 fail-fast。
  - 扩展 focused `train` 状态访问测试，确保非法 `immediate_train_pending` 会在 recruit/train apply 路径失败，且不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten working limit validation access`
  - 为 `employee_rules/limits` 增补 `Result` 版 recruit/train limit helper，并让 `train_action` / `recruit_action` 在 query / validation 阶段对损坏的 `working_employee_multipliers` 显式 fail-fast / fail-closed，避免旧限制计算路径吞掉状态错误。
  - 扩展 focused `train` 状态访问测试，覆盖 `train` / `recruit` 的 `can_initiate()` 与 validate 路径，确保非法 `working_employee_multipliers` 不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(core): tighten train provider allocation access`
  - 为 `train_slot_usage_providers` 增补 `Result` 版 provider 读取 helper，并让 `train_slot_usage_allocator` 在 provider / max-step / slot allocation 链路上对损坏的 `working_employee_multipliers` 显式 fail-fast。
  - 扩展 focused `train` 状态访问测试，覆盖 provider 读取、max-step 计算、slot 规划与分配路径，确保非法 `working_employee_multipliers` 不会提前改写 `round_state`。
- `refactor(core): tighten salary milestone access`
  - 为 `salary` 增补 `Result` 版 `requires_salary` helper，并让布尔包装器在损坏的 `player.milestones` 上 fail-closed，避免营销免薪里程碑查询触发硬断言。
  - 扩展 marketing focused 测试，确保非法 `player.milestones` 会让 `try_requires_salary()` 返回可诊断错误，而 `requires_salary()` 保持保守返回需薪。
- `refactor(gameplay): tighten train recruit action count access`
  - 为 `action_counts` 增补 `Result` 版读写 helper，并让 `train_action` / `recruit_action` 及 `train_employee_usage` 在 query、validate、apply、推导用工路径上对损坏的 `round_state.action_counts` 显式 fail-fast / fail-closed。
  - 扩展 focused `train` 状态访问测试，覆盖 train/recruit 的 `can_initiate()`、validate、apply 以及训练用工推导路径，确保非法 `action_counts` 不会提前改写玩家、`employee_pool` 或 `round_state`。
- `refactor(gameplay): tighten restaurant action count access`
  - 复用 `action_counts` 的安全读写 helper，让 `place_restaurant` / `move_restaurant` 在 query、validate、apply 阶段对损坏的 `round_state.action_counts` 显式 fail-fast / fail-closed，避免共享次数统计吞掉状态错误。
  - 新增 focused 餐厅状态访问测试，覆盖放置/移动餐厅的 `can_initiate()`、validate、apply 路径，确保非法 `action_counts` 不会提前改写玩家、`map` 或 `round_state`。
- `refactor(gameplay): tighten move restaurant record access`
  - 为 `move_restaurant` 增补显式餐厅记录读取 helper，并让 validate/apply 在 `state.map.restaurants[rest_id]` 的 `owner` / `cells` 结构损坏时返回可诊断错误，避免旧路径触发硬断言。
  - 新增 focused `move_restaurant` 状态访问测试，覆盖非法餐厅记录在 validate/apply 路径的 fail-fast 行为，确保不会提前改写玩家、`map` 或 `round_state`。
- `refactor(gameplay): tighten move restaurant cell array access`
  - 继续收紧 `move_restaurant` 对旧餐厅 `cells` 数组元素的读取，让 `Vector2i` 元素契约在 validate/apply 阶段走显式 `Result` 失败，而不是在清理旧格时触发硬断言。
  - 扩展 focused `move_restaurant` 状态访问测试，覆盖 `cells` 数组元素损坏时的 validate/apply fail-fast 行为，确保不会提前改写玩家、`map` 或 `round_state`。
- `refactor(gameplay): tighten move restaurant placement payload access`
  - 为 `move_restaurant` 增补 placement payload 读取 helper，并让 apply 阶段在 `validate_restaurant_placement()` 返回值、`footprint_cells` 或 `entrance_pos` 契约损坏时显式 fail-fast，而不是触发硬断言。
  - 扩展 focused `move_restaurant` 状态访问测试，通过注入坏 payload 覆盖三类失败分支，确保不会提前改写玩家、`map` 或 `round_state`。
- `refactor(gameplay): tighten place restaurant placement payload access`
  - 为 `place_restaurant` 增补 placement payload 读取 helper，并让 apply 阶段在 `validate_restaurant_placement()` 返回值、`footprint_cells` 或 `entrance_pos` 契约损坏时显式 fail-fast，而不是在写入新餐厅前触发硬断言。
  - 新增 focused `place_restaurant` 状态访问测试，通过注入坏 payload 覆盖三类失败分支，确保不会提前改写 `next_restaurant_id`、`player.restaurants`、`map` 或 `round_state`。
- `refactor(gameplay): tighten place restaurant player access`
  - 将 `place_restaurant` 在立即开业路径上对 `player.restaurants` 的写回改为走 `PlayerStateAccess`，让坏玩家结构返回可诊断错误，而不是在追加餐厅 id 时触发硬断言。
  - 扩展 focused `place_restaurant` 状态访问测试，确保 `player.restaurants` 类型损坏时 apply 会 fail-fast，且不会提前改写 `next_restaurant_id`、`map` 或 `round_state`。
- `refactor(gameplay): tighten place house placement payload access`
  - 为 `place_house` 增补 placement payload 读取 helper，并让 apply 阶段在 `validate_placement()` 返回值或 `footprint_cells` 契约损坏时显式 fail-fast，而不是在消耗房屋编号前依赖隐式 payload 结构。
  - 扩展 focused `place_house` 状态访问测试，通过注入坏 payload 覆盖两类失败分支，确保不会提前改写房屋编号供给、`map.houses`、格子结构或 `round_state`。
- `refactor(gameplay): tighten submit restructuring player access`
  - 将 `submit_restructuring` 对玩家、`employees`、`reserve_employees`、`company_structure` 的 apply 读取统一改为走 `PlayerStateAccess`，让坏玩家结构返回可诊断错误，而不是在重组修复/归一化前触发硬断言。
  - 扩展 focused `submit_restructuring` 状态访问测试，覆盖非法 `player.employees` 与 `player.company_structure`，确保失败时不会提前改写玩家结构或 `round_state.restructuring`。
- `refactor(gameplay): tighten submit restructuring round-state access`
  - 将 `submit_restructuring` 对 `round_state.restructuring` 的 apply 读取前移到玩家改写之前，并改为显式 `Result` 失败，避免坏重组状态在标记提交阶段触发晚期硬断言。
  - 扩展 focused `submit_restructuring` 状态访问测试，确保非法 `round_state.restructuring` 会 fail-fast，且不会提前改写玩家结构或 `round_state`。
- `refactor(gameplay): tighten submit restructuring ceo slots access`
  - 将 `submit_restructuring` 对 `player.company_structure.ceo_slots` 的 apply 读取收口到显式 helper，避免 fractional / negative `ceo_slots` 在结构归一化前触发硬断言。
  - 扩展 focused `submit_restructuring` 状态访问测试，覆盖 fractional / negative `ceo_slots`，确保失败时不会提前改写玩家结构或 `round_state`。
- `refactor(gameplay): tighten add garden attachment payload access`
  - 为 `add_garden` 增补 attachment payload 读取 helper，并让 apply 阶段在 `validate_garden_attachment()` 返回值、`garden_cells` 或 `merged_cells` 契约损坏时显式 fail-fast，而不是在更新房屋/花园结构前触发硬断言。
  - 扩展 focused `add_garden` 状态访问测试，通过注入坏 attachment payload 覆盖两类失败分支，确保不会提前改写房屋数据、花园供给、格子结构或 `round_state`。
- `refactor(gameplay): harden fire employee array access`
  - 将 `fire_action` 对 `employees` / `reserve_employees` / `busy_marketers` 数组元素的读取从硬断言改为 fail-soft，避免坏玩家数组在位置推断与 Payday 忙碌营销员例外判断里触发崩溃。
  - 扩展 focused `fire_action` 状态访问测试，确保数组元素损坏时 `_find_employee_location()` 返回空字符串、`_can_fire_busy_marketer()` 保守返回 `false`。
- `refactor(gameplay): tighten direct company structure access`
  - 将 `set_company_structure_direct` 的 apply 阶段参数、玩家读取、`employees` / `reserve_employees` / `company_structure` 访问与 `ceo_slots` 校验统一收口到显式 helper，避免在直属槽写回前触发硬断言。
  - 新增 focused `company_structure` 状态访问测试，覆盖非法 `slot_index`、`player.employees`、`player.company_structure` 与 fractional `ceo_slots`，确保失败时不会提前改写玩家结构。
- `refactor(gameplay): tighten report company structure access`
  - 将 `set_company_structure_report` 的 apply 阶段参数、玩家读取、`employees` / `reserve_employees` / `company_structure` 访问与 `ceo_slots` 校验统一收口到显式 helper，避免在追加下属前触发硬断言。
  - 扩展 focused `company_structure` 状态访问测试，覆盖非法 `manager_slot_index`、`player.employees`、`player.company_structure` 与 fractional `ceo_slots`，确保失败时不会提前改写玩家结构。
- `refactor(gameplay): tighten restructure employee access`
  - 将 `restructure_employee` 的 apply 阶段参数解析与玩家数组读取收口到显式失败返回，并改为通过 `PlayerStateAccess` 读取 `player[pid]` / `employees` / `reserve_employees`，避免在转入待命前触发硬断言。
  - 新增 focused `restructure_employee` 状态访问测试，覆盖缺失/错误 `to_reserve`、移动 CEO 与非法 `player.employees`，确保失败时不会提前改写玩家结构。
- `refactor(gameplay): tighten produce food inventory payload access`
  - 为 `produce_food` 增补 `StateUpdater.add_inventory()` 返回值读取 helper，并将库存写入器改成可注入依赖，避免在读取 `new_amount` 前触发硬断言。
  - 新增 focused `produce_food` 状态访问测试，通过注入坏 inventory payload 覆盖返回值类型、缺失 `new_amount` 与坏 `new_amount` 类型三类失败分支，确保失败时不会提前改写 `inventory` 或 `round_state`。
- `refactor(gameplay): harden procure drinks event param access`
  - 将 `procure_drinks` 的事件生成参数读取从硬断言改为 fail-soft：缺失/错误 `employee_type` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `drinks_procurement` 状态访问测试，覆盖缺失与错误 `employee_type` 两类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden recruit event param access`
  - 将 `recruit` 的事件生成参数读取从硬断言改为 fail-soft：缺失/错误 `employee_type` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `train_state_access` 测试，覆盖缺失与错误 `employee_type` 两类分支，确保 `RecruitAction._generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden train event param access`
  - 将 `train` 的事件生成参数读取从硬断言改为 fail-soft：缺失/错误 `from_employee` / `to_employee` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `train_state_access` 测试，覆盖缺失 `from_employee` 与缺失 `to_employee` 两类分支，确保 `TrainAction._generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden fire event param access`
  - 将 `fire` 的事件生成参数读取从硬断言改为 fail-soft：缺失/错误 `employee_id`、坏 `location` 参数或无法推断 location 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `fire_action` 状态访问测试，覆盖缺失 `employee_id`、错误 `location` 与无法推断 location 三类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden produce food event param access`
  - 将 `produce_food` 的事件生成参数读取从硬断言改为 fail-soft：缺失/错误 `employee_type`、未知/不可生产员工，或灵活生产者缺失 `food_type` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `produce_food` 状态访问测试，覆盖缺失 `employee_type`、未知员工与灵活生产者缺失 `food_type` 三类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden add garden event and anchor access`
  - 将 `add_garden` 的事件生成参数读取从硬断言改为 fail-soft，并将 `_compute_anchor_for_merged_cells()` 从硬断言改成显式 `Result` 失败，避免坏 payload 在更新房屋结构前触发崩溃。
  - 扩展 focused `add_garden` 状态访问测试，覆盖空 `merged_cells`、非法 rotation、缺失 `house_id` 与错误 `employee_type`，确保 apply / 事件生成都不会提前改写状态。
- `refactor(gameplay): harden place house event access`
  - 将 `place_house` 的事件生成参数与新房屋读取从硬断言改为 fail-soft：错误 `employee_type`、缺失新房屋、坏 `house_number` / `anchor_pos` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `place_house` 状态访问测试，覆盖错误 `employee_type`、未找到新房屋与坏 `anchor_pos` 三类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden move restaurant event access`
  - 将 `move_restaurant` 的事件生成参数与新餐厅读取从硬断言改为 fail-soft：错误 `employee_type` / `restaurant_id`、缺失餐厅或坏 `anchor_pos` / `rotation` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `move_restaurant` 状态访问测试，覆盖错误 `employee_type`、错误 `restaurant_id`、缺失餐厅、坏 `anchor_pos` 与坏 `rotation` 五类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden place restaurant event access`
  - 将 `place_restaurant` 的事件生成参数与新餐厅读取从硬断言改为 fail-soft：错误 `employee_type`、未找到新餐厅、坏 `anchor_pos`，以及 opening-soon 记录缺失 `anchor_pos` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `place_restaurant` 状态访问测试，覆盖错误 `employee_type`、未找到新餐厅、坏 `anchor_pos` 与 opening-soon 缺失 `anchor_pos` 四类分支，确保 `_generate_specific_events()` 安全返回空列表。
- `refactor(gameplay): harden initiate marketing event access`
  - 将 `initiate_marketing` 的事件生成参数读取从硬断言改为 fail-soft：错误 `employee_type` / `board_number` / `product` / `position`、未知产品或板件、未知/不可营销员工、非法 `duration`，以及 airplane 缺失/错误 `axis` 时直接返回空事件列表，避免坏命令在日志路径触发崩溃。
  - 扩展 focused `initiate_marketing` 状态访问测试，覆盖上述 11 类 event 参数坏分支，确保 `_generate_specific_events()` 安全返回空列表。

当前阶段性结果：

- `round_state` 方向：已补齐 `order_of_business`、`sub_phase_passed`、player-bool flags、pending phase actions 等 helper，并开始在模块热路径中替换。
- `map` 方向：已为 `MapStateAccess` 增补 optional helper，并在 `rural_marketeers`、`lobbyists`、营销相关动作中持续替换裸访问。
- 验证方式：上述每个小点均采用“focused 测试 + headless compile + all_tests + 独立 commit”的节奏推进。

---

## 阶段 5：按业务边界重组规则域（3~6 周，可并行推进）

### 目标

让规则组织更接近 bounded context，而不是继续按 registry/扩展点碎片化。

### 建议优先顺序

1. `marketing`
2. `dinnertime`
3. `economy`
4. `working`

### 目标

- 同一业务闭环中的计算、provider、settlement、报告写入尽量靠拢
- 新人可以按业务主题定位代码，而不是先理解所有 registry

### 实施进度（截至 2026-03-08）

- `refactor(marketing): centralize marketing initiation board helpers`
  - 在 `MarketingRules` 中收口营销产品、板件定义、rotation 与 footprint helper，并先将 `initiate_marketing` 的 validation/apply 切到统一业务入口，减少营销发起主链路里的元数据分叉。
  - 新增 focused `marketing_rules_domain` 测试，覆盖板件移除、未知产品、rotation 与 footprint 旋转 helper，确保 marketing 领域元数据契约可直接回归。

- `refactor(marketing): centralize initiation employee and axis helpers`
  - 继续将 `initiate_marketing` 中散落的员工能力校验、duration 解析与 airplane axis 推断收口到 `MarketingRules`，让 validation / apply / event 生成共享同一份营销发起约束。
  - 扩展 focused `marketing_rules_domain` 测试，覆盖未知员工、错误 usage、duration 溢出，以及 airplane axis fallback/坏类型，确保营销发起参数 helper 的失败语义稳定可回归。

- `refactor(marketing): reuse mailbox domain helpers`
  - 将 `place_new_restaurant_mailbox` 中重复的产品、板件、rotation 与 footprint 解析切到 `MarketingRules`，让永久邮箱动作和主线营销发起共享同一份营销元数据入口。
  - 扩展 focused `new_restaurant_mailbox_state_access` 测试，覆盖未知产品与非法 rotation 的早失败路径，确保动作层仍会在进入地图校验前返回稳定错误。

- `refactor(marketing): reuse pizza radio domain helpers`
  - 将 `place_pizza_radio` 中对 pending 商品、radio 板件、rotation 与 footprint 的重复校验切到 `MarketingRules`，让晚餐阶段的里程碑营销与主线营销共享同一份领域约束。
  - 扩展 focused `pizza_radio_state_access` 测试，覆盖未知 pending.product 与非法 rotation 的早失败路径，确保动作层仍先返回稳定业务错误，再进入地图占地校验。

- `refactor(marketing): reuse campaign manager domain helpers`
  - 将 `place_campaign_manager_second_tile` 中对 pending 商品、campaign_manager 能力、板件、rotation 与 footprint 的重复校验切到 `MarketingRules`，让追加营销板件与主线营销共用同一份领域 helper。
  - 扩展 focused `campaign_manager_second_tile_state_access` 测试，覆盖未知 pending.product 与非法 rotation 的早失败路径，确保动作层先返回稳定业务错误，再进入地图与距离校验。

- `refactor(marketing): harden giant billboard product validation`
  - 将 `place_giant_billboard` 的商品校验切到 `MarketingRules.require_marketable_product()`，并让 `_apply_changes()` 先复用 `_validate_specific()` 的结果，避免坏 product 在 apply 路径绕过营销约束并产生部分写入。
  - 扩展 focused `rural_giant_billboard_state_access` 测试，覆盖未知 product 的 validate/apply 早失败与无副作用路径，确保乡村广告牌动作在失败时不会提前写入 board 或迁移员工状态。

- `refactor(marketing): harden brand manager second product validation`
  - 将 `set_brand_manager_airplane_second_good` 对 pending.product_a 与命令 product_b 的校验切到 `MarketingRules.require_marketable_product()`，让飞机追加第二商品和主线营销共享同一份产品约束。
  - 扩展 focused `brand_manager_airplane_second_good_state_access` 测试，覆盖未知 pending.product_a 与未知 product_b 的早失败/无副作用路径，确保失败时不会提前改写 marketing_instance、placement 或清空 pending。

- `refactor(marketing): reuse board helpers in action events`
  - 将 `initiate_marketing_action` 的可发起判定与事件生成里残留的板件可用性读取切到 `MarketingRules.require_board_spec()`，让 UI 可发起判断、事件生成与 validation/apply 共用同一份板件可用性约束。
  - 扩展 focused `initiate_marketing_action_state_access` 测试，覆盖 2 人局已移除 board_number 的空事件路径，确保事件生成不会为不可用营销板件写出日志事件。

- `refactor(marketing): reuse billboard product helper in rural entry`
  - 将 `rural_marketeers` 的 marketing enter 扩展里对 giant_billboards.product 的裸注册表校验切到 `MarketingRules.require_marketable_product()`，让乡村广告牌需求生成与动作层共享同一份营销商品约束。
  - 扩展 focused `rural_marketeers_marketing_state_access` 测试，覆盖未知 giant billboard product 的早失败路径，确保坏商品不会继续写入 rural demands。

- `refactor(marketing): reuse board helpers in settlement validation`
  - 将 `marketing_instances_validation` 对 board_number 的存在性/可用性判断切到 `MarketingRules.require_board_spec()`，让结算前的营销实例校验与发起阶段共享同一份板件可用性约束。
  - 扩展 focused `marketing_settlement_fail_fast` 测试，覆盖未知 board_number 的 fail-fast 路径，确保结算不会静默吞掉非法营销实例。

- `refactor(marketing): reuse airplane board helpers in offramp conflict checks`
  - 将 `rural_marketeers` 的 airplane/offramp 冲突校验里残留的板件与 footprint 读取切到 `MarketingRules.require_board_spec()`，让模块级冲突校验与主线营销共享同一份 airplane 板件元数据约束。
  - 扩展 focused `rural_marketeers_state_access` 测试，覆盖已移除非 airplane board 的忽略路径，确保冲突校验不会在无关板件上额外触发地图字段校验。

- `refactor(marketing): reuse board helpers in pizza milestone settlement`
  - 将 `new_milestones` 的 pizza pending radio 选板逻辑从 `MarketingRegistry.get_def()` 切到 `MarketingRules.require_board_spec()`，让里程碑晚餐结算与主线营销共享同一份板件可用性与营销类型约束，并保持板件不可用时的 fail-soft 语义。
  - 扩展 focused `new_milestones_pizza_pending_state_access` 测试，覆盖 radio 板件已占满时不写入 pending 的回归路径，确保晚餐阶段在无可用 radio 板件时不会产生部分状态写入。

- `refactor(marketing): reuse board helpers in gourmet guide validator`
  - 将 `gourmet_food_critics` 的 `_validate_initiate_marketing()` 从 `MarketingRegistry.get_def()` 切到 `MarketingRules.require_board_spec()`，让模块级 gourmet board 识别与主线营销共享同一份板件可用性与类型约束，并继续保持非法/已移除 board 的 fail-soft 语义。
  - 扩展 focused `gourmet_food_critics_state_access` 测试，覆盖未知 board 与 2 人局已移除 board 的忽略路径，确保模块 validator 不会因领域 helper 的早失败而误拒绝无关命令。

- `refactor(dinnertime): centralize settlement definition helpers`
  - 新增 `DinnertimeRules`，将晚餐结算里散落的产品、员工与里程碑定义读取统一收口，并让 `dinnertime_inventory` / `dinnertime_effects` 复用同一份 Result 风格失败语义。
  - 新增 focused `dinnertime_rules_domain` 测试并接入 `AllTests`，覆盖纯饮品需求、未知产品、未知员工与未知里程碑路径，确保晚餐域 helper 的早失败契约可独立回归。

- `refactor(dinnertime): reuse product helper in pricing pipeline`
  - 将 `PricingPipeline.calculate_marketing_bonus()` 对产品定义的裸读取切到 `DinnertimeRules.require_product_def()`，让晚餐收入计算与 `dinnertime_inventory` 共享同一份产品存在性/类型失败语义。
  - 扩展 `milestone_effect_values` 测试，补充未知 product 的早失败回归，确保营销奖励计算在遇到坏产品 id 时会稳定返回领域错误。

- `refactor(economy): centralize salary token eligibility helper`
  - 新增 `EconomyRules.is_salary_token_eligible_product()`，并让 `payday_salary_token_payment` 的统计/扣减两条路径共享同一份 token 资格判定，避免 Payday 资格规则继续散落。
  - 扩展 focused `payday_salary_token_eligibility` 测试，覆盖未知 product id 被忽略且不会被扣减的回归路径，确保经济域 helper 保持原有 fail-soft 语义。

- `refactor(economy): reuse employee helper in payday salary discount`
  - 扩展 `EconomyRules` 增加 Result 风格的员工定义读取，并让 `payday_salary_discount` 复用同一份员工存在性/类型失败语义，避免薪资折扣计算继续直接触达员工 registry。
  - 扩展 `payday_salary_test`，补充未知 active employee 的早失败回归，确保发薪折扣路径在遇到坏员工 id 时稳定返回领域错误。

- `refactor(working): reuse employee array helpers in mandatory actions`
  - 将 `MandatoryActionsRules` 中 provider 查找与 required action 推导两处员工定义读取切到 `EmployeeArrayHelpers.require_employee_def()`，让 working 域的强制动作推导共享同一份 assert 风格员工契约。
  - 扩展 `mandatory_actions_test`，补充 `find_provider_employee_id()` 的回归断言，确保强制动作 provider 查找与 required action 推导保持一致。

- `refactor(working): reuse result-style employee lookup in train validation`
  - 为 `EmployeeArrayHelpers` 补充 Result 风格的 `lookup_employee_def()`，并让 `train_company_validation` 复用同一份员工存在性/类型失败语义，避免培训颜色校验继续散落员工 registry 读取。
  - 扩展 `train_action_state_access` 测试，补充未知 `to_employee` 的早失败回归，确保培训颜色校验在遇到坏员工 id 时稳定返回领域错误。

- `refactor(working): reuse employee lookup in company structure validator`
  - 将 `CompanyStructureValidator` 的卡槽/唯一员工校验中的 3 处员工定义读取切到 `EmployeeArrayHelpers.lookup_employee_def()`，同时保留原有“未知的员工类型”错误语义，减少招聘/培训共享校验里的重复 lookup 样板。
  - 扩展 `company_structure_test`，补充未知 employee 的 fail-fast 回归，确保公司结构校验在遇到坏员工 id 时仍返回稳定错误。

- `refactor(working): reuse employee lookup in train usage inference`
  - 将 `train_employee_usage` 中培训前使用推导与 inferred-use 候选筛选里的 4 处员工定义读取切到 `EmployeeArrayHelpers.lookup_employee_def()`，让 working/train 域共享同一份 Result 风格 lookup，同时保留未知员工的既有 fail-soft/ignore 语义。
  - 扩展 `train_state_access_test`，补充未知 `employee_id` 读取应返回 `ok=true/value=false` 的回归，确保培训前员工使用推断在坏员工 id 下不会误报已使用。

---

## 10. 快速收益项（建议尽快做）

如果只想先做“小投入高收益”的动作，建议按以下顺序执行：

1. **先落本报告并冻结边界规则**
2. **先把 UI 元数据从 `RulesetV2` 装配链中拆出去**
3. **再做 provider 显式注入**
4. **最后推进 registry 会话态改造**

原因：

- 前两项能最快减少“继续恶化”的概率。
- 后两项虽然收益更大，但迁移成本更高。

---

## 11. 不建议现在做的事

- 不建议大重写 `GameEngine`
- 不建议重写 replay / archive / random 主链
- 不建议为了“看起来优雅”立即把所有 Dictionary 改成 class
- 不建议再扩一个更大的“万能 registry 框架”

这些动作要么风险过高，要么不是当前主要矛盾。

---

## 12. 建议的落地方式

为了保证改造可执行，建议采用以下交付节奏：

### 每阶段固定输出

- 1 份落盘设计/计划文档
- 1 组 focused 代码修改
- 1 组新的架构回归测试
- 1 次 `game_smoke_test` + `all_tests` headless 回归

### 每个阶段的 commit 建议

- `docs(core): add architecture audit and roadmap`
- `refactor(core): split module ui metadata from ruleset`
- `refactor(core): introduce session registry bundle`
- `refactor(core): inject engine adapters explicitly`
- `refactor(core): tighten round_state access contract`

### 每阶段验收问题

在合并前至少回答以下问题：

1. 这次改动是否让 core 更纯，还是更依赖运行时环境？
2. 这次改动是否减少了 static 全局态？
3. 这次改动是否让 UI 责任更靠近 UI，而不是更靠近 core？
4. 这次改动是否让状态结构更可验证？
5. 这次改动是否便于多局并行或服务端复用？

---

## 13. 最终结论

当前 `core/` 的真实状态不是“需要推倒重来”，而是：

> 已经拥有可靠主干，但边界正在承压，必须进入一次有纪律的结构收口期。

最重要的不是继续拆几个大文件，而是完成以下三个结构动作：

1. **拆掉 `RulesetV2` 中的 UI 职责**
2. **把 static registry 会话态迁到实例态上下文**
3. **把 provider/autoload 依赖变成显式注入**

只要这三件事做好，当前 `core/` 就能从“功能中心”升级成“真正可演化的领域平台”。

