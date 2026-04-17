# 联机恢复房：快加载 + 完整历史双轨设计（D 完整版，2026-04-14）

> 历史文档：该双轨方案已被 `docs/online/online_resume_single_full_engine_startup_2026-04-17.md` 中的“单 full-engine 启动”方案取代。保留本文用于记录当时的权衡、术语与演进背景。

状态：**部分实施，持续演进中**。

实现更新（2026-04-17）：

- 客户端双轨模型已部分落地：
  - `runtime_engine` 用于 live 对局
  - `full_replay_engine` 用于按需完整历史 / History View / Replay
- `OnlineResumeSessionState` 已实际持有：
  - `full_replay_step_timeline`
  - `full_replay_step_timeline_entries`
  - `full_replay_live_tail_commands`
- `online_resume_full_history_adapter.gd` 已支持：
  - cached prebuilt timeline 复用
  - cached prebuilt entries 复用
  - incremental append
- 恢复房进入对局已改为 **快启动优先，完整历史后台加载**，不再默认等待完整历史完全 ready 后才进入游戏
- live command 热路径中，当前不再强制同步推进完整历史 engine，而是先记录 live tail，再在完整历史查看 / timeline 构建前按需补齐
- P0 第一阶段已落地：
  - **实时联机默认只绑定 `runtime_engine`**
  - **完整历史 timeline / log 只在 Replay / History View 等按需场景启用**
  - **完整历史 ready 后，不再自动把 live 热路径切到 full-history**

仍未完全闭合的部分：

- 本文中的部分“理想化接口 / 载荷结构”仍是目标设计，不代表字段名与当前实现 1:1 对应
- 存档下载 / 导出仍应以服务端完整权威历史为准，这一原则未变

本文用于细化“方案 D 完整版”：

- 恢复房进入游戏时，应显著降低客户端加载耗时；
- 历史绝对不能丢；
- 客户端回放/复盘时，仍应能从游戏最开头开始，随意点击任意历史时间点查看当时状态；
- 恢复房继续进行若干步后，下载/保存的存档必须仍是“完整起点历史”的标准 archive，与正常游戏存档在语义上没有区别。

本文是对现有联机恢复链路的专项设计补充；不替代 `docs/online/online_session_resume_redesign_2026-04-03.md`，而是聚焦“恢复房起局性能 + 完整历史保真 + UI 时间线/日志双源化”。

---

## 0. 当前实现与本文的关系

本文仍然是恢复房双轨方案的设计主文档，但现在已经不是“纯设计草案”。

更准确地说：

- **总体方向已落地**：
  - 快启动 runtime
  - 完整历史双源
  - 完整历史 timeline cache
  - 完整历史 entries cache
  - 增量 append
- **实现细节有演进**：
  - 当前实际代码更强调“热路径去重”和“后台按需补齐”
  - 而不是严格等待一份一次性完整 cache 全部 ready
- **最新结论有进一步收敛**：
  - 双轨本身是对的
  - “实时日志默认走 full-history”这件事会把完整历史成本重新带回热路径
  - 当前已先把 live / history 的默认读源边界切开，后续重点转向显式历史查看成本与通用 UI 成本
- **剩余工作仍存在**：
  - 通用日志 UI / descriptor / layout 成本仍在继续收敛
  - 部分归档 / 导出 / 下载链路的完整收口仍需继续验证

相关落地补充请同时对照：

- `docs/online/online_resume_hot_path_rebuild_plan_2026-04-16.md`
- `docs/architecture/42-gameplay-replay-timelines.md`
- `docs/architecture/70-online-multiplayer.md`

## 1. 问题定义

当前联机恢复房路径中，客户端与服务端都会以“完整 archive + 从头 replay 到目标恢复点”的方式启动。

这带来两个问题：

1. **长对局恢复慢**
   - 历史越长，`load_from_archive()` 的全量 replay 越慢；
   - 恢复房创建后，客户端首次进入游戏的等待时间明显增长。

2. **性能优化与历史保真存在天然冲突**
   - 如果直接把 archive 重基线成短链，启动会更快；
   - 但如果当前运行时 engine 就只持有短链历史，则：
     - timeline / log 默认只能看到短链；
     - 回放/复盘无法再从最开头任意跳转；
     - `create_archive()` 导出的也会变成短链 archive；
     - 最终破坏“历史绝对不能丢”的要求。

因此，本问题不能只做“archive 裁短”；必须同时解决：

- 运行时快加载；
- 完整历史保留；
- UI 可继续查看全历史；
- 导出的存档仍为完整标准 archive。

---

## 2. 设计目标

### 2.1 必达目标

- 恢复房客户端进入游戏时，默认使用**快加载路径**，避免长局全量 replay 卡顿。
- 恢复房客户端仍可在**回放 / 复盘模式**中：
  - 从游戏最开头开始查看历史；
  - 点击任意历史时间点；
  - 恢复到该时间点对应的只读状态展示。
- 恢复房继续进行若干步后，客户端下载/保存的存档必须：
  - 从游戏最开头开始；
  - 包含恢复前完整历史 + 恢复后新增历史；
  - 仍然是现有标准 archive 格式；
  - 与正常游戏存档在语义上无差别。
- 联机权威状态不因客户端本地回放/复盘而受到影响。

### 2.2 非目标

- 不在本方案中改变 archive schema 的对外格式。
- 不要求“历史浏览状态”下允许客户端直接本地分叉继续操作。
- 不优先解决“服务端多实例迁移 / 跨房间转移”。
- 不要求一次性把所有 timeline / log UI 完全重写；优先通过适配层兼容现有组件。

---

## 3. 关键约束与当前事实

### 3.1 当前 archive 导出依赖当前 engine

当前 `GameEngine.create_archive()` 直接序列化：

- `checkpoints[0].state_dict` -> `initial_state`
- `command_history` -> `commands`
- `current_command_index`
- `random_manager`

所以：

> 当前 engine 持有什么历史，导出的 archive 就只有什么历史。

这意味着：

- 如果把当前运行时 engine 变成“短链 engine”；
- 那么直接调用 `create_archive()` / `save_to_file()` 导出的就是短链 archive；
- 这与本方案目标冲突。

### 3.2 当前 timeline / log 默认绑定“当前 engine 的完整历史”

现有关键链路：

- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`
  - 通过 `StepTimelineBuild.build_full(engine)` 从当前 engine 构建 step timeline；
- `ui/scenes/game/timeline/controller.gd`
  - 默认把 seek / replay / history 模式建立在“当前 engine 对应的 timeline”之上；
- `ui/scenes/game/event_log/controller.gd`
  - 默认从 `EventBus.history` 恢复历史日志；
- `core/engine/game_engine/loader.gd`
  - 加载 archive 时会先清空 EventBus.history，再根据当前 archive replay 重建。

因此：

> 如果当前加载的是短链 runtime archive，UI 默认只能看到短链历史。

### 3.3 当前“查看历史”本来就是只读语义

现有 `ui/scenes/game/timeline/controller.gd` 中，seek 历史点时主要通过 step 快照恢复 state，并保持 UI 禁止操作。

所以本方案不需要为“历史浏览态”引入新的交互语义；只需保证：

- 历史浏览的数据源变成完整历史源；
- live 对局的数据源仍是快加载运行时；
- 两者在 UI 上能够正确切换与映射。

---

## 4. 总体方案概述

本方案采用**双轨模型**：

1. **服务器完整权威轨（Full Authority Track）**
2. **客户端快加载运行轨（Fast Runtime Track）**
3. **客户端完整历史回放轨（Full Replay Track）**

### 4.1 核心原则

- **服务器永远保留完整权威历史**。
- **客户端正常对局使用短链 runtime engine**，以提升进入游戏速度。
- **客户端回放 / 复盘使用完整历史源**，而不是依赖短链 runtime engine。
- **保存 / 下载 archive 一律来自服务器完整权威历史**，不能直接从客户端短链 runtime 导出。

### 4.2 一句话描述

> 客户端“玩”用短链，客户端“看历史”用完整历史，服务器“存/导出”永远用完整历史。

---

## 5. 架构分层

### 5.1 服务器：完整权威层

服务器 `OnlineRoom.game_engine` 保持当前语义：

- 从原始 archive 开头开始；
- 完整持有 `command_history`；
- 完整持有 checkpoint；
- 接收新命令后继续在线性时间线上追加。

这意味着：

- 服务器仍可直接 `create_archive()`；
- 恢复房继续进行若干步后，新的 archive 天然包含“恢复前历史 + 恢复后新历史”；
- 服务端房间持久化逻辑可以最大程度复用现有实现。

### 5.2 客户端：快加载运行时层

客户端新增一个“快加载运行 engine”（下文简称 `runtime_engine`）：

- 基于某个恢复锚点构造短链 archive；
- 只包含锚点之后到当前恢复点的必要命令链；
- 用于首次进入游戏、继续联机、接收新命令、继续操作。

要求：

- `runtime_engine` 必须足够快地完成 `load_from_archive()`；
- 它不是完整历史真相；
- 它只负责“当前能不能玩”。

### 5.3 客户端：完整历史层

客户端新增一个“完整历史回放源”（下文简称 `full_history_source`）。

它的职责是：

- 持有从游戏最开头到当前最新的完整历史事实；
- 支持构建完整 step timeline / 完整 log timeline；
- 支持任意历史点的只读 seek；
- 随着后续联机命令到来持续增长。

注意：

- `full_history_source` 可以是一个完整 `GameEngine`；
- 也可以是“完整 archive + 预构建 timeline cache + 按需 engine”；
- 第一版建议优先做成**完整 replay engine + timeline cache**，便于复用现有逻辑并降低实现风险。

---

## 6. 推荐的第一版实现口径

为了降低风险，D 完整版的第一版建议采用：

### 6.1 服务器

- 保持现有完整 `game_engine` 作为权威状态；
- 新增“为客户端启动构造 fast runtime archive”的能力；
- 新增“导出完整 archive”的显式接口。

### 6.2 客户端

同时维护两个 engine / 数据源：

#### A. `runtime_engine`

- 短链 engine；
- 绑定当前游戏 UI 的 live 操作；
- 接收后续联机命令并持续推进；
- 退出回放后，界面回到这个 engine 的最新状态。

#### B. `full_replay_engine`

- 完整历史 engine；
- 用于 step timeline / event timeline / log / replay seek；
- 平时不用于联机出牌；
- 收到新命令时同步追加，以保持“完整历史始终最新”。

#### C. `timeline cache`

为避免每次点击历史点都重新全量构建：

- 维护完整历史对应的 `step_timeline` 缓存；
- 维护 timeline index 到 command index / runtime 区间的映射；
- 命令追加后增量失效或局部重建。

这版虽然会在客户端多保留一份完整 engine，但仍有价值：

- 首次可玩路径来自 `runtime_engine`，首屏加载更快；
- 完整历史 engine 可以稍后后台就绪；
- UI 与逻辑实现最稳妥，最接近现有代码结构。

---

## 7. 数据模型设计

### 7.1 新增概念：ResumeFastStartBundle

服务端在恢复房 `game_started` / bootstrap 时，向客户端下发一个复合对象：

```text
ResumeFastStartBundle {
  runtime_archive,
  runtime_anchor,
  full_archive_meta,
  full_archive_payload?,
  full_history_timeline_cache?,
}
```

### 7.2 字段语义

#### `runtime_archive`

短链 archive，用于客户端快速构建 `runtime_engine`。

要求：

- archive 格式仍与现有标准 archive 相同；
- `initial_state` 为锚点 checkpoint 对应状态；
- `commands` 仅保留锚点之后到当前恢复点的必要短链；
- `current_index` 指向短链当前末端；
- `final_hash` 与服务端当前恢复点一致。

#### `runtime_anchor`

描述短链在完整历史中的锚点位置。

建议字段：

```text
{
  global_command_start_index,
  global_command_end_index,
  global_step_start_index_hint,
  global_step_end_index_hint,
  checkpoint_id,
  state_hash,
}
```

作用：

- 帮助客户端把 runtime 短链映射回完整历史坐标；
- 让 UI 知道 runtime 区间在完整时间线中的后缀位置。

#### `full_archive_meta`

完整 archive 的元信息。

建议字段：

```text
{
  full_command_count,
  full_final_hash,
  schema_version,
  byte_size,
  source,
}
```

#### `full_archive_payload`

完整 archive 本体。

第一版建议：

- 可以在恢复启动时直接下发；
- 也可以先仅下发 runtime_archive，让客户端进入游戏；
- 然后异步推送 / 拉取完整 archive，用于构建 `full_replay_engine`。

### 7.3 客户端会话状态

建议在 `NetContext` 或新的会话对象中维护：

```text
OnlineResumeSessionState {
  runtime_engine,
  full_replay_engine,
  full_replay_engine_ready,
  full_archive,
  runtime_anchor,
  full_timeline_cache,
  full_timeline_ready,
  live_tail_start_global_command_index,
  latest_global_command_index,
}
```

---

## 8. 服务端设计

### 8.1 为什么服务器不能也切成短链权威

如果服务器权威 engine 也被裁成短链：

- `create_archive()` 将只导出短链；
- 房间持久化 `to_persistence_dict()` 将只持久化短链；
- 掉线恢复、重启恢复、最终结算历史上报都会变复杂；
- 一旦完整历史只剩旁路资产，系统复杂度和一致性风险都会上升。

因此本方案明确要求：

> 服务器 `game_engine` 继续保持完整历史权威，不做短链化替代。

### 8.2 服务端新增职责

#### A. 构造 runtime 短链 archive

建议新增 builder，例如：

- `core/engine/game_engine/online_resume_fast_runtime_archive_builder.gd`

输入：

- 完整权威 engine
- 目标恢复点
- 锚点选择策略

输出：

- `runtime_archive`
- `runtime_anchor`

#### B. 继续维护完整 recovery store

现有 recovery store / delta log 继续以完整权威 engine 为准。

#### C. 新增完整 archive 导出 RPC

建议新增房间级接口：

- `request_full_archive_export()`
- `full_archive_export_ready`

语义：

- 客户端请求导出完整 archive；
- 服务端从完整权威 engine 执行 `create_archive()`；
- 返回标准 archive 给客户端下载保存。

### 8.3 锚点选择策略

D 完整版里，锚点只影响客户端快加载，不影响权威历史。

推荐策略：

1. 优先选择目标恢复点之前最近、且能保住当前回合/玩家回合语义的 checkpoint；
2. 尽量让 runtime 短链覆盖“当前玩家回合开始”到当前点；
3. 如果可选 checkpoint 太近导致短链过长，可增加上限策略；
4. 最差情况下退化为完整 archive（不牺牲正确性）。

---

## 9. 客户端设计

## 9.1 启动阶段

客户端进入恢复房时，分两段完成：

### 阶段 1：先进入可玩状态

- 使用 `runtime_archive` 构建 `runtime_engine`；
- 调用现有联机恢复校验和 prepare 流程；
- UI 先绑定 `runtime_engine`；
- 玩家可以更快看到当前对局并继续游戏。

### 阶段 2：后台补齐完整历史

- 客户端加载 `full_archive_payload`；
- 构建 `full_replay_engine`；
- 基于它构建完整 `step_timeline` / `event timeline` / `log entries`；
- 完成后开放完整历史视图的数据源；
- **不要求实时联机日志默认立即切到完整历史轨**。

要求：

- 阶段 2 失败时，不影响 live 对局继续；
- 但应禁用“完整历史回放”入口，并提供可重试机制。

## 9.2 新命令到达后的双轨追加

每当服务端下发新的联机命令：

### 对 `runtime_engine`

- 按现有链路执行增量命令；
- 推进 live 状态。

### 对 `full_replay_engine`

- 同步把同一命令追加到完整引擎；
- 更新完整 timeline cache；
- 保证“恢复后又玩的一段历史”也能在完整回放中从最开头连续看到。

若 `full_replay_engine` 暂未 ready：

- 可先缓存待追加命令；
- 在完整引擎就绪后按序补放。

### 9.3 回放 / 复盘模式

#### 基本原则

- 回放 / 复盘的点击 seek 一律基于 `full_replay_engine` 对应的 timeline；
- 进入历史点后展示的是只读状态；
- 不改动服务器权威状态；
- 不把本地历史浏览误当成可继续操作的 live runtime。

#### 退出回放

- 退出回放后，UI 回到 `runtime_engine` 的最新状态；
- 若回放期间有新命令到达，退出后直接落到最新 live 状态。

---

## 10. Timeline / Log 详细设计

### 10.1 为什么必须改 UI 数据源

当前 UI 默认假设：

- timeline 来源 = 当前 engine；
- log 来源 = 当前 engine 派生 timeline / 当前 EventBus.history。

在 D 完整版中，这个假设不成立：

- 当前 live engine 是短链；
- 完整历史来自 `full_replay_engine`。

所以必须把 UI 改成：

- **live 视图**：绑定 `runtime_engine`
- **历史视图**：绑定 `full_replay_engine`

### 10.2 推荐做法：加适配层，不重写所有 UI 组件

建议新增一个适配器，例如：

- `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

职责：

- 统一向 `GameLogPanel` 提供完整 timeline / entries；
- 维护 global step index 与 runtime tail 的映射；
- 判断当前 cursor 属于：
  - 完整历史前缀只读区；
  - 还是 live 最新区。

这样可以尽量少改：

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/game_log/game_log_unified_timeline_builder.gd`

而把复杂度收口在 controller / adapter 层。

### 10.3 Timeline 坐标设计

建议引入“全局历史坐标”，至少包括：

- `global_command_index`
- `global_step_index`

规则：

- `full_replay_engine` 的 timeline 使用全局坐标；
- `runtime_engine` 内部仍可使用本地短链坐标；
- adapter 维护映射：
  - `global_command_index -> runtime_local_command_index?`
  - `global_step_index -> runtime_local_step_index?`

其中：

- 位于 runtime tail 之外的全局历史点：只读可看，不可作为 live 操作点；
- 位于 runtime tail 内且等于最新状态：可回到 live；
- 不允许联机客户端在历史点直接本地分叉继续执行。

### 10.4 Log 数据源设计

建议把 log 分成两部分：

#### A. 历史日志

- 来源：`full_replay_engine` 对应的完整 event timeline / step timeline
- 用于展示从开局到当前的全部历史

#### B. 实时 UI-only 日志

- 来源：当前会话中的即时错误、提示、同步失败提示等
- 继续走 `GameLogPanel._extra_entries` 语义

要求：

- 完整历史 ready 后，**Replay / History View / 完整历史 seek** 必须切换为完整历史源；
- 实时联机日志在 P0 下仍默认走 runtime 侧，不能因为完整历史 ready 就自动把 live 热路径切到 full-history；
- EventBus.history 不再是恢复房历史展示的唯一真相来源；
- EventBus 仍可用于 live 运行期即时事件，但不能再单独决定“完整历史长什么样”。

---

## 11. 保存 / 下载完整 archive 设计

### 11.1 原则

> 恢复房下载/保存存档时，不能直接从客户端 `runtime_engine` 调用 `save_to_file()`。

否则导出的只会是短链 archive。

### 11.2 正确路径

#### 客户端

点击保存 / 下载时：

- 若当前是普通本地/单机/非恢复房：沿用现有本地 `engine.save_to_file()`；
- 若当前是“联机恢复房 + D 完整版模式”：
  - 发送“请求导出完整 archive”到服务端；
  - 收到完整 archive 后再本地写文件。

#### 服务端

- 从完整权威 `game_engine` 执行 `create_archive()`；
- 返回 archive 字典；
- 客户端再调用 `Archive.save_archive_to_file()` 或现有下载逻辑落盘。

### 11.3 导出结果要求

导出的 archive 必须满足：

- `initial_state` 仍是开局状态；
- `commands` 为从游戏最开头到当前最新的完整命令历史；
- `current_index` 指向最新状态；
- `final_hash` 与服务端当前状态一致；
- 可被现有 `load_from_file()` 直接加载；
- 加载后 timeline / replay / log 的行为与普通完整存档一致。

---

## 12. 回放点击任意时间点的能力保证

### 12.1 需求口径

客户端应支持：

- 从游戏最开头开始看到完整历史；
- 在回放 / 复盘模式中点击任意历史点；
- UI 恢复到该点对应的只读状态展示；
- 再退出回放回到当前最新 live 对局。

### 12.2 方案保证方式

这项能力由 `full_replay_engine + full timeline cache` 保证，而不是由 `runtime_engine` 保证。

也就是说：

- `runtime_engine` 只负责“现在能玩”；
- `full_replay_engine` 负责“从最开头到当前任意一点都能看”。

### 12.3 与“从历史点继续玩”区分

必须区分两种操作：

#### A. 查看历史点

- 本地只读 seek；
- 不影响服务器权威状态；
- 属于回放 / 复盘。

#### B. 从历史点继续玩

- 这是权威状态变更；
- 联机下不能仅靠本地点击实现；
- 必须走显式服务器动作，例如：
  - 请求服务器 rewind；
  - 或从该点创建新的恢复房。

本方案只保证 A；B 不作为默认 timeline 点击行为。

---

## 13. 实现拆分建议

### 13.1 Phase 1：服务端快启动包

目标：先让客户端具备“快进入当前局”的数据面。

建议改动：

- `server/room.gd`
  - 新增 fast runtime archive builder 接入；
  - 新增 resume fast-start bundle 输出；
- 新增 builder：
  - `core/engine/game_engine/online_resume_fast_runtime_archive_builder.gd`

交付结果：

- 服务端能同时提供：
  - 完整权威历史；
  - 客户端快启动所需短链 archive。

### 13.2 Phase 2：客户端双 engine 初始化

目标：客户端同时持有 `runtime_engine` 和 `full_replay_engine`。

建议改动：

- `autoload/net_client/client.gd`
- `ui/scenes/game/controllers/online_resync_controller.gd`
- `ui/scenes/game/game.gd`
- 新增会话状态对象

交付结果：

- 客户端能先用 runtime engine 进入；
- 后台补齐完整历史 engine。

### 13.3 Phase 3：timeline / log 双源化

目标：UI 改为以完整历史为主、以 runtime 为 live。

建议改动：

- `ui/scenes/game/timeline/controller.gd`
- `ui/components/game_log/game_log_panel.gd`
- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`
- 新增 adapter：
  - `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

实现备注：

- 第一版主路径以 `timeline/controller.gd + online_resume_full_history_adapter.gd + game_log_panel.gd` 收口完整历史读源切换；
- `ui/scenes/game/event_log/controller.gd` 继续负责 runtime `EventBus` 历史恢复/格式化，不再作为恢复房完整历史主数据源。

交付结果：

- 回放 / 复盘可从最开头任意点击；
- 退出后回到 live runtime。

### 13.4 Phase 4：保存 / 下载完整 archive

目标：恢复房导出 archive 不再误用短链 runtime。

建议改动：

- `ui/dialogs/save_load_dialog.gd`
- `ui/scenes/game/controllers/save_load_controller.gd`
- `autoload/net_client/client.gd`
- `server/room.gd`

交付结果：

- 客户端下载的 archive 与普通游戏 archive 语义一致。

### 13.5 Phase 5：增量同步完整历史尾部

目标：恢复后继续玩时，完整历史轨也持续增长。

建议改动：

- 联机命令应用链路
- `full_replay_engine` 命令追加与 timeline cache 刷新逻辑

交付结果：

- “恢复后又玩了一段”的历史也能从最开头连续回放。

---

## 14. 风险与取舍

### 14.1 客户端内存占用上升

因为第一版建议保留两份 engine：

- `runtime_engine`
- `full_replay_engine`

这是可接受的第一阶段取舍，原因是：

- 正确性优先；
- 功能语义最清晰；
- 复用现有代码最多；
- 风险显著低于“只保留 timeline cache，不保留完整 replay engine”的高级优化版。

后续若确有必要，再考虑把 `full_replay_engine` 进一步压缩成：

- archive + timeline cache + 按需临时 engine。

### 14.2 完整历史后台加载完成前的体验

在 `full_replay_engine` 还没 ready 时：

- live 对局可继续；
- 但完整历史回放能力应暂时禁用或显示“历史加载中”；
- 避免用户误以为只能看到短链历史。

### 14.3 timeline index 兼容性

由于引入全局历史坐标，相关 controller 和 panel 需要小心处理：

- 当前 cursor / head
- timeline seek target
- 日志点击跳转
- read-only 状态提示

这一块需要专门回归测试。

### 14.4 对联机同步与断线重连的影响评估

本方案会影响客户端联机状态模型，但**不应改变服务端权威同步语义**。

正确实施时，应保持以下原则：

- 服务端仍只有一条权威时间线；
- 联机同步、delta、rewind、resync 仍只围绕 live runtime 状态工作；
- 完整历史轨只用于客户端回放 / 日志 / 历史浏览，不参与权威同步判定。

因此，本方案对联机系统的影响主要集中在客户端：

1. **活动 engine 的唯一性被打破**
   - 当前系统默认 `Globals.current_game_engine` 就是“当前联机 engine”；
   - 引入 `full_replay_engine` 后，必须显式区分：
     - `runtime_engine`：联机 live
     - `full_replay_engine`：只读历史

2. **恢复完成判定需要拆层**
   - 断线重连成功的最低条件，应当是 `runtime_engine` 恢复完成；
   - `full_replay_engine` / 完整 timeline 后台补齐，不应阻塞“恢复完成”的 loading 结束；
   - 否则会出现“已经能继续玩，但 UI 仍显示正在恢复”的错误体验。

3. **回放模式不能再通过切换当前联机 engine 实现**
   - 当前项目里部分回放/复盘语义依赖“当前 engine 的 timeline”；
   - D 完整版下，联机回放必须改成“只读显示态切换”，不能把网络主链路绑定对象切到 `full_replay_engine`。

4. **客户端状态一致性难度上升**
   - 除 live 同步外，还要保证完整历史轨能随着新命令持续增长；
   - 一旦 live 轨和 full history 轨分叉，就会导致 timeline/log 与当前权威状态不一致。

结论：

> 本方案不会天然破坏联机同步与断线重连；真正的风险来自“没有把 live runtime 和 full replay 的职责隔离清楚”。

### 14.5 高风险点

以下问题若处理不当，会直接影响联机正确性：

#### A. 把 `full_replay_engine` 误当成联机活动 engine

后果：

- `command_applied` / `resync_archive` / `delta` / `rewind meta` 打到错误对象；
- `NetContext` 记录的 resume progress 来源错误；
- 客户端后续恢复游标失真。

风险级别：**高**

#### B. 背景加载完整历史时污染全局 `EventBus`

当前 `GameEngine.load_from_archive()` 会清理/重建事件历史。

若 `full_replay_engine` 背景构建时直接使用全局 `EventBus`，可能导致：

- live 对局日志被清空；
- 完整历史重建事件混入实时 UI；
- timeline / log 显示错乱。

风险级别：**高**

#### C. `NetContext` 的 resume progress 错绑到历史浏览态

当前 `NetContext.sync_online_resume_progress_from_engine()` 依据 engine 的：

- `current_command_index`
- `command_history`
- `state_hash`

更新断线恢复游标。

若把 `full_replay_engine` 或历史浏览态 state 用于该同步，会导致：

- `last_applied_sequence` 错误；
- `last_state_hash` 错误；
- delta 恢复起点错误，进而触发异常 resync 或恢复失败。

风险级别：**高**

#### D. 服务端权威回退/截断后，完整历史轨没有同步失效或重建

当服务端执行：

- rewind 到回合开始；
- truncate future；
- full resync；

若客户端只更新 `runtime_engine`，却保留旧的 `full_replay_engine` 未来历史，则会出现：

- timeline 仍能看到已被服务器撤销的未来；
- log 展示与当前 live 时间线不一致；
- 用户点击到“幽灵历史点”。

风险级别：**高**

#### E. 恢复后后台补完整历史时，新命令继续到达

若 `full_replay_engine` 尚未 ready，而 live 命令已经继续推进：

- runtime 轨会比 full history 轨更靠前；
- 完整 timeline/log 会短暂落后；
- 若不做队列补放，最终会永久缺历史尾巴。

风险级别：**中高**

#### F. 传输协议混淆 live resync 与 full-history 传输

如果完整历史下载复用现有：

- `resync_archive`
- `resync_snapshot_manifest/chunk`
- `pending_resync_*`

容易引发：

- 包被错误归类；
- room mismatch / late packet 处理混乱；
- reconnect 期间时序竞争。

风险级别：**中高**

#### G. 恢复房保存/下载仍误走本地 `runtime_engine.save_to_file()`

后果：

- 导出短链 archive；
- 直接违背“下载后仍是完整标准 archive”的目标。

风险级别：**高**

#### H. 客户端资源占用与后台带宽压力上升

双轨第一版默认会多保留：

- 一个 `runtime_engine`
- 一个 `full_replay_engine`
- 一套完整 timeline / log cache

同时若进入对局后立即下发 full archive，还会提高后台带宽占用。

风险级别：**中**

### 14.6 实施硬约束

若实施 D 完整版，以下约束必须写入实现设计并作为代码 review 检查项：

1. **服务器 `game_engine` 永远保持完整权威历史**
   - 不能把服务器权威态替换成短链 engine。

2. **`Globals.current_game_engine` 永远指向 `runtime_engine`**
   - `full_replay_engine` 不得进入现有联机 active-engine 主链路。

3. **所有联机网络消息只作用于 `runtime_engine`**
   - 包括：
     - `command_applied`
     - `resync_archive`
     - `resync_delta`
     - `rewind_to_turn_start_meta`

4. **`NetContext` 的 resume progress 只能从 `runtime_engine` 同步**
   - 禁止从 `full_replay_engine` 或历史浏览态同步恢复游标。

5. **`full_replay_engine` 必须使用独立 `event_sink`**
   - 不得读写全局 `EventBus.history`；
   - 不得清空 live 对局的 EventBus 状态。

6. **联机回放/复盘不得切换联机 active engine**
   - 回放只能改变只读显示态，不能改写 live 网络绑定对象。

7. **断线重连成功判定只看 `runtime_engine` 恢复**
   - `full_replay_engine` / 完整历史 cache 的后台补齐不能阻塞恢复成功提示消失。

8. **服务端权威回退后，完整历史轨必须同步重建或显式失效**
   - 不允许客户端保留已被服务器撤销的未来历史。

9. **完整历史传输必须有独立消息语义或独立 pending 状态**
   - 不应直接与现有 live resync snapshot 通道混用。

10. **恢复房导出 archive 必须走服务端完整权威导出**
    - 不能直接调用本地 `runtime_engine.save_to_file()` 作为最终导出结果。

### 14.7 推荐的实现策略

为了降低对现有联机同步与重连链路的冲击，推荐按以下策略实施：

#### 第一原则：少动服务端权威同步主链路

- 保持现有 `OnlineRoom.game_engine` 权威语义；
- 保持现有 `delta/resync/rewind` 基本协议；
- 新增的是“快启动包”和“完整历史导出/传输”旁路能力。

#### 第二原则：在客户端显式区分两类完成状态

- `runtime_restore_completed`
- `full_history_ready`

前者决定“能不能继续玩”，后者决定“能不能完整回放历史”。

#### 第三原则：把复杂度收口在 adapter / controller 层

- `runtime_engine` 继续复用现有联机 controller；
- `full_replay_engine` 与 timeline/log 通过独立 adapter 接入；
- 避免把双轨复杂度扩散到所有 UI 组件与网络层。

---

## 15. 测试方案

### 15.1 核心正确性测试

1. **快加载正确性**
   - 恢复房客户端使用 runtime archive 进入后，当前状态 hash 与服务器一致。

2. **完整历史加载正确性**
   - full replay engine 就绪后，完整历史末端 hash 与服务器一致。

3. **任意历史点回放**
   - 从最开头、中间、恢复点之前、恢复点之后、新增命令之后多个位置点击历史点；
   - UI 恢复到对应状态；
   - 退出回放后回到最新 live 状态。

4. **继续游戏后完整历史增长**
   - 恢复房进入后继续执行若干命令；
   - full replay engine 的历史长度随之增长；
   - timeline 能看到新增历史。

5. **导出 archive 完整性**
   - 恢复房继续进行若干步后下载 archive；
   - 新 archive 加载后：
     - `initial_state` 仍为开局；
     - `commands` 包含完整旧历史 + 新历史；
     - 从最开头可回放到当前；
     - 与普通完整 archive 语义一致。

### 15.2 UI / 交互测试

1. 完整历史 ready 前，ReplayBar / 历史点击入口的禁用状态、tooltip 与“完整历史加载中”文案正确。
2. 完整历史 ready 后，log panel 显示完整历史，而不是仅短链尾部。
3. 在历史只读态下，ActionPanel 仍保持禁用。
4. 退出回放后回到 live 最新状态，不残留旧 cursor。

### 15.3 回归测试

1. 现有在线 resync / reconnect / rewind 到回合开始链路不被破坏。
2. 普通非恢复房保存/加载路径不变。
3. 本地单机 / 主菜单回放路径不变。

---

## 16. 与当前方案的关系

### 16.1 已有修复仍然保留

以下能力与本方案兼容，应继续保留：

- 恢复点合法性校验；
- Dinnertime pending confirm 修复；
- 服务端 prepare/cache，避免 resume 起局重复 replay；
- 客户端 / resync 后统一执行在线恢复 prepare。

### 16.2 本方案不是方案 C 的替代，而是更高要求版本

- 方案 C 的重点是“checkpoint 重基线 archive，降低 replay 长度”；
- 方案 D 完整版的重点是“在保留完整历史能力的同时，让 live 启动更快”。

可以理解为：

- **C**：单轨优化，适合接受“当前运行时历史变短”的场景；
- **D 完整版**：双轨设计，适合“历史绝对不能丢”的场景。

---

## 17. 最终建议

如果确认以“历史绝对不能丢”为硬约束，建议采用以下实施原则：

1. **服务器完整权威历史不裁短**。
2. **客户端正常对局使用快加载 runtime engine**。
3. **客户端回放 / 复盘使用完整历史 engine / cache**。
4. **保存 / 下载 archive 一律从服务器完整权威历史导出**。
5. **恢复后新增命令必须同步进入完整历史轨**。

这五条同时成立时，才能同时满足：

- 恢复房进入更快；
- 客户端仍可从最开头任意点击历史点；
- 导出的 archive 与普通游戏 archive 无语义差别。
