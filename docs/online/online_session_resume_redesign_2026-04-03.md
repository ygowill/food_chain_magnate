# 联机会话与断线恢复重构设计（2026-04-03）

状态：**设计文档，部分思路已被后续实现吸收，但本文本身不代表逐条已落地**。

补充说明（2026-04-15 / 2026-04-17）：

- 恢复房“快加载 + 完整历史双轨”已在 `docs/online/online_resume_fastload_full_history_design_2026-04-14.md` 单列设计与实现补充；
- 当前凡是涉及恢复房启动性能、完整历史回放、完整 archive 导出的问题，应优先对照该补充文档。
- 恢复房热路径的最近实现收敛，请对照：
  - `docs/online/online_resume_hot_path_rebuild_plan_2026-04-16.md`
  - `docs/architecture/70-online-multiplayer.md`
  - `docs/architecture/42-gameplay-replay-timelines.md`

换句话说：

- 本文更偏向 **会话 / seat / recovery 模型重构背景**
- 而恢复房 runtime/full-history 双轨、timeline cache、entries cache、incremental append 的当前实现，应优先看上面的新文档

本文目标不是继续修补现有“全量 archive 重连”链路，而是给出一套更稳定、更容易验证的联机会话方案，用来替换当前把 `seat`、`peer`、房间目录、恢复流程耦合在一起的实现。

## 1. 问题定义

过去几轮排查中，已经反复暴露出以下现象：

- 玩家刷新或短时掉线后，服务端与客户端对“这个座位是否还在线”看法不一致。
- 玩家主动退出后，本地仍会检测到“未完成对局”，再次自动恢复进房。
- 房间列表会出现“房间满员但实际上没人在线”或“遗留密码房无法加入”的脏数据。
- 房主和重连玩家对同一房间的成员状态感知不同，一端看到已连接，另一端卡在恢复中。
- 进入游戏后刷新虽能回到对局，但本地输入权限会退化成类似本地双人控制。
- 当前恢复依赖一次性发送完整 archive，大包传输、时序竞争、旧连接残留都会放大问题。

这些问题不是单点 bug，而是当前模型本身存在结构性缺陷。

## 2. 当前实现的结构性根因

### 2.1 `seat` 和 `connection` 混在一起

当前 `OnlineRoom` 同时用以下结构表达多种概念：

- `_seat_profile_by_seat_index` 表示“这个座位是否被占”
- `_peer_id_by_seat_index` 表示“这个座位当前连着哪个 peer”
- `_seat_by_player_peer_id` 表示“这个 peer 对应哪个座位”
- `_user_id_by_seat_index` 表示“这个座位归谁”

这会导致一个座位的以下几种状态没有被显式区分：

- 已入座且在线
- 已入座但临时断线，等待恢复
- 已主动离开，应立即释放
- 已弃权，座位仍保留但不可恢复为可操作玩家
- 已被新连接顶替，旧连接应失效

当前代码只能通过若干字典是否有值来“猜”状态，因此容易出现：

- 房间列表统计错误
- `seat already connected`
- 旧连接未完全失效，新连接又已被视为成功

### 2.2 房间目录和恢复资格没有从同一权威状态派生

房间列表、房间状态、重连资格、主动退出后的 resume 检测，并不是从同一个状态机推导出来的。

典型后果：

- Lobby 里断线保留了 seat，占位仍在，因此目录看起来满员。
- 客户端主动退出时，本地和服务端对“是否还能 resume”清理时机不同。
- 后端 `RoomMember` 与游戏服房间内 seat 生命周期不同步时，会出现“平台允许恢复，但游戏服不该允许”或反过来的情况。

### 2.3 恢复协议过于粗暴

当前主链路是：

1. 重新拿 token
2. 重连 WebSocket
3. 直接下发 `GameStarted + ResyncArchive`

这有三个核心问题：

- 不区分“只差几条命令”和“必须全量快照恢复”。
- 重连成功与恢复完成之间没有清晰的阶段确认。
- 旧连接与新连接没有 `generation` 栅栏，容易产生时序竞争。

### 2.4 输入权限依赖瞬时映射，不依赖稳定身份

在线玩家可操作谁，本质上应该取决于“当前客户端被授权控制哪个 seat”。

如果这件事继续依赖：

- 当前这条 WebSocket 恰好是谁
- `player_id_by_peer_id`
- 某次 `GameStarted` 是否重新初始化了本地 engine

那么刷新、重连、替换连接之后，就很容易出现“本地像本地模式一样能操作两名玩家”的退化问题。

## 3. 设计目标

- 让 `seat` 成为稳定身份，`connection` 只是一层可替换的传输绑定。
- 让房间目录、可加入性、恢复资格、弃权状态都从同一套权威 seat 状态推导。
- 将恢复链路拆成“Attach -> 判定恢复方式 -> Resume 完成确认”三个明确阶段。
- 优先走增量恢复，只有必要时才走快照恢复。
- 主动退出、弃权、超时掉线，都有明确的终态，不再残留“可恢复但不该恢复”的幽灵状态。
- 客户端输入权限只依赖稳定 `seat_index` 和显式授权，不依赖瞬时 peer 映射。
- 在现有单点 Dedicated Server 架构下即可落地，不要求先引入多实例调度。

## 4. 非目标

- 本方案不先解决多机房、多游戏服迁移。
- 本方案不要求客户端本地缓存覆盖服务端状态。
- 本方案不要求“任何 UI 场景都完全无缝恢复”；第一优先级是状态正确。
- 本方案不追求与旧协议长时间双栈共存；应分阶段迁移，并最终删除旧恢复链路。

## 5. 新的权威模型

### 5.1 核心对象

建议引入四个清晰的对象层次。

#### `RoomSession`

房间级权威对象，包含：

- `room_code`
- `status`: `Lobby | InGame | Ended`
- `config`
- `join_policy`
- `password_hash`
- `seats`
- `spectators`
- `recovery_store`
- `updated_at_ms`

#### `SeatSlot`

稳定的座位对象，贯穿 Lobby 到 InGame 全周期。

建议字段：

- `seat_index`
- `role`: `host | player`
- `user_id`
- `profile`
- `seat_state`
- `current_connection_id`
- `connection_generation`
- `reconnect_deadline_ms`
- `forfeited`
- `left`

#### `ConnectionLease`

一次实际连接的租约对象，只描述“当前哪条连接绑定到哪个 seat”。

建议字段：

- `connection_id`
- `peer_id`
- `room_code`
- `seat_index`
- `generation`
- `connected_at_ms`
- `last_seen_ms`
- `status`: `Active | Superseded | Closed`

#### `RecoveryStore`

恢复所需的数据面，不和连接生命周期耦合。

建议字段：

- `latest_sequence`
- `latest_hash`
- `checkpoints`
- `delta_log`
- `active_checkpoint_id`

### 5.2 Seat 状态机

建议把玩家 seat 状态收敛为以下几种：

| 状态 | 含义 | 是否占用公开名额 | 是否可恢复 | 是否可操作 |
| --- | --- | --- | --- | --- |
| `EMPTY` | 座位空闲 | 否 | 否 | 否 |
| `CONNECTED` | 玩家在线 | 是 | 是 | 是 |
| `RECONNECTING` | 非预期断线，保留短暂恢复窗口 | 是 | 是 | 否 |
| `FORFEITED` | 已弃权 | 是 | 否 | 否 |
| `LEFT` | 主动离开 Lobby，或主动退出后不再保留 seat | 否 | 否 | 否 |

设计要求：

- `Lobby` 中主动离开必须立即变为 `LEFT -> EMPTY`。
- `Lobby` 中非预期断线可短暂进入 `RECONNECTING`，超时后释放成 `EMPTY`。
- `InGame` 中主动弃权立即进入 `FORFEITED`。
- `InGame` 中非预期断线进入 `RECONNECTING`，超时后自动 `FORFEITED`。
- `FORFEITED` seat 仍显示在对局中，但不能再恢复为可操作玩家。

这样房间列表、恢复资格、弃权 UI、自动结算都可以从这张表直接推导，而不再依赖多个字典的组合判断。

### 5.3 连接代次 `connection_generation`

每个 seat 维护一个单调递增的 `connection_generation`。

规则：

- 每次新连接成功 `attach` 到该 seat，都将 generation 加一。
- 服务端只接受“当前 generation 对应连接”的操作消息。
- 被替换的旧连接即使晚到、补发消息、延迟断开，也会因 generation 落后而被拒绝。

这一步是解决 `seat already connected`、双连接竞争、旧连接残留最关键的栅栏。

### 5.4 目录统计统一派生

房间列表不再直接用“seat_profile 数量”表示占位，而应从 seat 状态推导。

建议派生字段：

- `capacity`
- `occupied_count = CONNECTED + RECONNECTING + FORFEITED`
- `joinable_count = capacity - count(CONNECTED + RECONNECTING)`
- `connected_count = count(CONNECTED)`
- `forfeited_count = count(FORFEITED)`
- `password_required = (join_policy == "password" and password_hash != "")`

关键语义：

- Lobby 中主动离开的 seat 不再占名额。
- Lobby 中失联但仍在重连窗口内的 seat 占名额，但有明确超时释放。
- InGame 中弃权 seat 仍显示在对局内，但房间列表可以根据 `status=InGame` 单独展示，不影响“能否新加入玩家”判断。

## 6. 恢复数据设计

### 6.1 不再以“每次都发完整 archive”作为主路径

推荐恢复分为两层：

- `checkpoint`: 较低频的完整快照
- `delta_log`: checkpoint 之后的命令增量

优先策略：

- 客户端仅落后少量命令时，直接走 `delta resume`
- 客户端太旧、hash 不匹配、或日志窗口已被截断时，再走 `snapshot resume`

### 6.2 Checkpoint

第一版可以直接复用现有 `GameEngine.create_archive()` 结果作为 checkpoint 内容，不必先设计新的状态格式。

建议增加：

- `checkpoint_id`
- `base_sequence`
- `state_hash`
- `archive_size_bytes`
- `created_at_ms`

生成时机建议：

- 开局后初始 checkpoint
- 每回合开始
- 每 N 条命令
- 关键结构变化后（如 rewind、批量自动步骤结束后）

### 6.3 Delta Log

建议把服务端权威执行过的命令按顺序记录为：

- `sequence`
- `command_dict`
- `post_state_hash`
- `created_at_ms`

恢复时客户端上报：

- `last_applied_sequence`
- `last_state_hash`
- `checkpoint_id`

服务端判定：

- 若客户端 hash 与对应 sequence 一致，且缺失命令仍在日志中，走 `delta resume`
- 否则走 `snapshot resume`

### 6.4 Snapshot 分块传输

完整快照仍然需要，但应改为显式的 manifest + chunk 协议，而不是单条大 RPC。

建议：

- `SnapshotResumePlan`
- `SnapshotChunk`
- `SnapshotChunkAck`
- `SnapshotComplete`

收益：

- 避免单条 WebSocket 消息过大
- 客户端能明确知道自己在“连接成功”还是“快照下载中”
- 恢复失败时可以定位是 attach 失败、快照失败、还是应用失败

## 7. 新协议草案

### 7.1 后端 HTTP

后端仍保留“用户是否有资格拿到本房间连接票据”的职责，但不再承担实时 seat 生命周期判断。

建议接口语义：

- `POST /rooms/{room_code}/join`
  - 为新玩家分配 seat
  - 返回 `attach_ticket`
- `POST /rooms/{room_code}/resume`
  - 仅对 `member_status in {active, reconnecting}` 返回 `attach_ticket`
  - 对 `left` / `forfeited` / `ended` 明确返回不可恢复
- `POST /rooms/{room_code}/leave`
  - 主动离开 Lobby
  - 后端把成员状态置为 `left`
- `POST /rooms/{room_code}/forfeit`
  - 主动弃权
  - 后端把成员状态置为 `forfeited`

`attach_ticket` 建议包含：

- `room_code`
- `role`
- `seat_index`
- `user_id`
- `ticket_id`
- `ticket_expire_at`
- `protocol_version`

### 7.2 WebSocket Attach

客户端连上 WebSocket 后，不再隐式“自动入房 + 自动发 full archive”，而是先走 attach。

客户端发送：

```json
{
  "type": "AttachRoom",
  "ticket_id": "T123",
  "room_code": "ROOM01",
  "seat_index": 1,
  "resume_cursor": {
    "checkpoint_id": "cp_17",
    "last_applied_sequence": 241,
    "last_state_hash": "abcd"
  }
}
```

服务端返回：

- `AttachAccepted`
  - 包含 `seat_index`
  - 包含新的 `connection_generation`
  - 包含当前 `room_status`
  - 包含后续恢复计划
- 或 `AttachRejected`
  - 明确错误码：`seat_released`、`seat_forfeited`、`ticket_expired`、`room_ended`、`generation_conflict`

### 7.3 Resume 计划

服务端在 `AttachAccepted` 后返回二选一的恢复计划。

#### 路径 A：`DeltaResume`

适用于客户端只落后少量命令。

服务端返回：

- `ResumePlan { mode: "delta", from_sequence, to_sequence }`
- 若干 `DeltaBatch`
- `ResumeFinished`

客户端应用成功后回：

- `ResumeApplied { final_sequence, final_hash, generation }`

#### 路径 B：`SnapshotResume`

适用于客户端太旧、hash 不一致、或 delta 缺口过大。

服务端返回：

- `ResumePlan { mode: "snapshot", checkpoint_id, chunk_count, base_sequence }`
- 若干 `SnapshotChunk`
- `SnapshotComplete`
- 如有需要，再补若干 `DeltaBatch`
- `ResumeFinished`

客户端流程：

1. 收完所有 chunk
2. 组装 checkpoint
3. `load_from_archive`
4. 应用后续 delta
5. 回 `ResumeApplied`

### 7.4 主动退出与弃权

#### Lobby 主动退出

目标语义：

- 立即释放 seat
- 清除本地 resume 上下文
- 后端成员状态改为 `left`
- 房间列表立即更新

#### InGame 主动弃权

目标语义：

- 立即写入 `forfeit_player`
- 立即切 seat 为 `FORFEITED`
- 立即清除该成员的 resume 资格
- 如果只剩一名未弃权玩家，立刻结束对局并弹结算

### 7.5 非预期断线

#### Lobby

- seat 进入 `RECONNECTING`
- 设置 `reconnect_deadline_ms`
- 到期无人恢复则释放 seat

#### InGame

- seat 进入 `RECONNECTING`
- UI 立刻广播该 seat 网络异常状态
- 到期无人恢复则自动 `FORFEITED`
- 若因此只剩一名有效玩家，则立刻结算

## 8. 客户端架构调整

### 8.1 把恢复编排从 `GameOnlineResyncController` 中抽离

建议新增统一会话协调器，例如：

- `OnlineSessionCoordinator`

职责：

- 管理连接状态机
- 管理 attach / resume / leave / forfeit
- 持久化本地 resume context
- 向 Lobby / Game 场景分发统一状态

场景控制器只做两件事：

- 渲染
- 调用协调器提供的明确动作

不再由游戏场景自己驱动整条重连协议。

### 8.2 客户端输入权限只看 seat 授权

客户端应始终持有明确的：

- `local_role`
- `local_seat_index`
- `connection_generation`

游戏内“我能控制谁”只取决于 `local_seat_index`，而不是当前 peer 映射是否刚好正确。

这能直接规避“重连后本地像本地模式一样能操作两名玩家”的问题。

### 8.3 本地 resume 上下文要有终态

本地持久化不应只保存“还能恢复什么”，还要保存“为什么不能再恢复”。

建议字段：

- `room_code`
- `seat_index`
- `role`
- `last_applied_sequence`
- `last_state_hash`
- `target_scene`
- `resume_allowed`
- `terminal_reason`

关键点：

- 主动退出后立刻把 `resume_allowed=false`
- 主动弃权后立刻把 `resume_allowed=false`
- 对局正常结束后立刻清空

这样即使退出请求和页面刷新发生竞争，也不会再次误判成“存在未完成联机对局”。

## 9. 服务端架构调整

### 9.1 `OnlineRoom` 不再直接把字典当状态机

建议把当前 `OnlineRoom` 中散落的以下概念拆开：

- seat registry
- connection registry
- spectator registry
- recovery store
- directory projection

推荐改为：

- `RoomSession` 维护权威状态
- `RoomDirectoryProjection` 专门负责输出房间列表/房间状态摘要
- `RoomRecoveryStore` 专门负责 checkpoint + delta

### 9.2 所有房间对外展示都走 projection

不要再在多个地方直接拼：

- `password_required`
- `player_count`
- `connected`
- `forfeited`

而是统一由 projection 派生，确保：

- 房间列表
- 房间详情
- 游戏内玩家连接状态
- 结算资格

全部来自同一套权威 seat 状态。

### 9.3 旧连接必须被显式 supersede

当新连接 attach 到同一个 seat 时：

1. generation 加一
2. 旧连接标记 `Superseded`
3. 旧连接后续消息全部拒绝
4. 如有条件，主动通知旧连接关闭原因

这样不再依赖“旧 peer 先不先断开”来维持正确性。

## 10. 后端数据模型建议

后端仍然有必要保留 `RoomMember`，但它表示的是“房间成员资格”，不是实时连接。

建议增加成员状态：

- `active`
- `reconnecting`
- `left`
- `forfeited`
- `ended`

语义：

- `resume_room` 只允许 `active` / `reconnecting`
- `left` 和 `forfeited` 不能再 resume
- 结算后统一置为 `ended`

这样可以从根本上解决：

- 主动退出后仍被提示可恢复
- 弃权后仍拿到恢复票据
- 历史遗留房间成员状态未终结，导致幽灵房间继续存在

## 11. 推荐迁移顺序

不建议一次性推翻重写，建议分四阶段。

### Phase 1：座位状态与 generation 栅栏

先做：

- 引入显式 `seat_state`
- 引入 `connection_generation`
- 明确主动离开、主动弃权、掉线重连窗口
- 目录统计改为基于 seat_state 派生

完成后即可先消灭当前最常见的：

- `seat already connected`
- 主动退出后仍可恢复
- 房间列表满员/空房脏数据

### Phase 2：统一客户端会话协调器

再做：

- 把恢复流程从游戏场景抽出
- 统一 attach / leave / forfeit / resume
- 统一本地 resume 持久化与终态清理

完成后可明显减少：

- 场景间状态竞争
- “一端已连上，另一端仍卡恢复中”
- 主动退出与自动恢复打架

### Phase 3：Delta Resume

再做：

- 引入 `sequence + post_hash + delta_log`
- 默认走增量恢复
- archive 只作为 fallback

完成后可显著降低：

- 重连耗时
- 大包同步失败
- 大量不必要的全量 archive 下发

### Phase 4：Chunked Snapshot + 删除旧 Resync 主链路

最后做：

- checkpoint manifest + chunk
- 删除“单条 ResyncArchive 即恢复”的主链路
- 让恢复协议变成独立可测试模块

完成后，恢复链路的可观测性和可测性会明显好于现在。

## 12. 本地验证方案

由于完整构建和部署成本高，后续实施必须配套本地可重复验证链路。

### 12.1 纯逻辑测试

新增表驱动测试，覆盖 seat 生命周期：

- Lobby join -> leave -> refresh list
- Lobby disconnect -> reconnect within grace
- Lobby disconnect -> grace expire -> seat release
- InGame disconnect -> reconnect
- InGame disconnect -> timeout -> auto forfeit
- Active forfeit -> remaining one player -> immediate game over
- Old connection superseded -> stale message rejected

### 12.2 Headless 集成测试

建议增加一个本地联机场景测试入口，例如：

- `tools/run_online_session_matrix.gd`

测试矩阵至少应包含：

- Host 建房，player 加入，player 刷新恢复
- Host 刷新恢复
- 双方同时刷新
- 主动 leave 后不再 resume
- 主动 forfeit 后不再 resume
- 只剩一名未弃权玩家时立刻结算
- 密码房 join / resume / wrong password
- 房间列表在 leave / disconnect / expire 后的正确统计

### 12.3 本地脚本建议

建议最终提供两个脚本：

- `tools/run_online_local_server.sh`
  - 本地起 dedicated server
- `tools/run_online_session_suite.sh`
  - 运行联机恢复测试矩阵

这样可以把大部分联机回归从“完整部署验证”前移到本地。

## 13. 可复用部分

本方案不是推倒重来，以下资产可以直接复用。

### 13.1 可直接复用

- `GameEngine.execute_command()`
- `GameEngine.create_archive()`
- `GameEngine.load_from_archive()`
- 现有命令序列化能力
- 现有房间配置模型
- 现有 backend 登录/会话/token 基础设施
- 现有 headless 测试基础设施
- 现有联机回归测试框架和日志系统

### 13.2 需要重构但可保留主体

- `OnlineRoom`
- `RoomManager`
- `NetClient` server/client RPC 外壳
- `NetContext` 本地 resume 持久化
- `GameOnlineResyncController` 中的 UI 展示部分

### 13.3 应逐步淘汰

- “连接上就自动下发 full archive”作为默认恢复路径
- 由多个字典组合推断 seat 在线状态
- 由场景控制器自己维护整条恢复协议

## 14. 风险与取舍

### 14.1 短期复杂度会上升

在迁移期内，代码不会立刻变少，因为需要先把旧模型拆开。

这是必要成本，因为当前复杂度不是功能复杂，而是状态耦合导致的隐式复杂。

### 14.2 Delta Resume 需要更严格的测试

一旦引入 `sequence` 和 `post_hash`，测试必须覆盖：

- 正常增量恢复
- hash 不一致回退快照
- checkpoint 丢失
- 日志截断
- 重复 batch

### 14.3 需要明确协议版本

因为恢复协议会显著变化，建议在 `attach_ticket` 和 WS attach 中都携带 `protocol_version`，避免旧客户端/旧服务端交错时出现模糊错误。

## 15. 结论

继续沿着当前“full archive 重连 + 局部修补”路线推进，仍会反复遇到同一类问题：

- seat 与 peer 状态不一致
- 房间目录脏数据
- 主动退出与 resume 语义冲突
- 旧连接与新连接竞争
- 恢复流程阶段不清导致的一端成功、一端卡死

更可靠的方向，是把联机模型改成：

- `seat` 是稳定身份
- `connection` 是可替换租约
- `generation` 负责旧连接栅栏
- `checkpoint + delta` 负责恢复
- 房间目录和恢复资格全部从显式 seat 状态派生

这套方案短期不是最省事的，但它比继续补丁更接近“可验证、可维护、可收敛”的终态。
