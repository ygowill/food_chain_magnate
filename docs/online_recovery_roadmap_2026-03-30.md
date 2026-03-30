# 联机长期恢复开发设计（2026-03-30）

## 目标

当前项目已具备“同进程内、`InGame` 阶段的断线自动重连”雏形，但还不具备以下能力：

- 客户端重启后继续原对局
- Dedicated Server 重启后继续原对局
- Lobby / 切场 / Resync / 中间确认阶段的统一恢复
- 以持久化权威态为基础的无感恢复

本设计的最终目标是把联机恢复从“进程内补丁”升级为“权威会话恢复系统”。

## 恢复语义

### 目标语义

- 短时断线：客户端停留在当前流程中，只显示轻量 loading。
- 客户端重启：启动后自动探测可恢复对局并自动恢复。
- 服务器重启：房间与对局从持久化权威态恢复，客户端自动重新接回。
- 任意阶段恢复：Lobby、开局切场、InGame、Resync、确认弹窗阶段都以同一套恢复模型处理。

### 非目标

- 不追求“本地旧内存场景直接续跑”。
- 不允许客户端以本地缓存覆盖服务端状态。
- 不允许通过“重复发 action”猜测恢复状态。

## 总体架构

### 当前部署假设

当前实现按“单点 Dedicated Server”推进，不考虑多实例负载均衡与 failover 调度。

### 1. 服务端权威持久化

服务端需要把“房间元数据 + 对局权威快照 + 恢复索引”落到持久层。

核心对象：

- `RoomSession`：房间级元数据，包含 `room_code`、状态、成员、座位、角色、所在 game server。
- `MatchCheckpoint`：权威快照，至少能完整重建 `GameEngine`。
- `CommandLog`：checkpoint 之后的命令尾部，用于减少全量快照频率。
- `MemberResumeState`：成员恢复信息，绑定 `user_id / role / seat_index / room_code`。

### 2. 客户端恢复状态

客户端需要把“可恢复联机会话”持久化到本地，而不是只保存在 `NetContext` 内存里。

最小字段：

- `room_code`
- `role`
- `platform_base_url`
- `session_id`
- `user_id`
- `target_scene`
- `last_known_room_status`
- `last_ack_command_index`
- `last_ack_state_hash`

### 3. 统一恢复编排

恢复编排不能只写在 game scene controller 中，而应抽成统一的联机会话协调器。

它负责：

- 启动探测是否存在可恢复会话
- 调用平台 `resume_room`
- 连接新的 websocket target
- 与服务端协商“增量恢复 / 全量快照恢复”
- 在正确场景落地恢复结果

## 分阶段实施

### Phase 1：服务端 `InGame` 房间权威快照落盘与重启恢复

目标：

- Dedicated Server 周期性把 `InGame` 房间落盘
- 重启后自动恢复 `InGame` 房间和 `GameEngine`
- 恢复后玩家可通过现有 token + seat + user_id 重新接回

本阶段不覆盖：

- Lobby 恢复
- 客户端重启恢复
- command log 增量恢复
- 跨机器 / 多 server 迁移

### Phase 2：客户端冷启动恢复

目标：

- 本地持久化恢复上下文
- 启动自动探测和自动恢复
- 恢复后自动进入正确场景

### Phase 3：服务端重启后的平台分配与恢复

目标：

- 平台后端持久化 room -> game_server 关系
- server 重启后重新领取 active rooms
- client `resume_room` 不依赖旧 server 进程

### Phase 4：统一任意阶段恢复

目标：

- Lobby / 开局切场 / InGame / Resync / 确认阶段统一恢复
- 去掉 game scene 特判式恢复逻辑

## 数据设计（Phase 1）

### 房间快照文件

第一版使用单文件 JSON 快照，优先保证实现简单和恢复正确。

```json
{
  "version": 1,
  "saved_at_unix_sec": 0,
  "rooms": [
    {
      "room_code": "ROOM01",
      "status": "InGame",
      "config": {},
      "join_policy": "password",
      "password_hash": "",
      "updated_at_ms": 0,
      "started_at_iso": "",
      "started_at_unix_sec": 0,
      "seat_profiles": {},
      "user_ids_by_seat": {},
      "archive": {}
    }
  ]
}
```

设计取舍：

- 本阶段直接保存完整 `archive`，不先引入 command log。
- 只保存 `InGame` 房间，避免把 Lobby 的“已占座但未连接” reclaim 逻辑一起拉进来。
- 恢复后所有 peer 映射清空，等待客户端按现有 resume/token 流程重新接回。

## 测试计划

### Phase 1 focused tests

- `OnlineRoomPersistenceRecoveryTest`
  - 创建在线对局
  - 保存房间快照
  - 新建 `RoomManager` 恢复
  - 校验 `GameEngine` hash 一致
  - 校验 seat/user_id 保留
  - 校验玩家可按 `seat_index + user_id` 重新连接

### 后续集成测试

- Dedicated Server 启动 -> 建房开局 -> 落盘 -> 重启进程 -> 恢复 -> 客户端重新接回
- 客户端启动探测未完成对局 -> 自动进入游戏场景 -> 继续操作

## 风险

- 完整 `archive` 周期性落盘的 IO 成本较高，但在当前项目规模下可接受。
- Lobby 恢复需要单独设计 reclaim 语义，不能直接复用 `join_room_with_seat`。
- 真正做到“任意阶段无感恢复”前，必须把恢复编排从 UI 控制器中抽离。

## 进度记录

### 2026-03-30

- 新建设计文档，明确长期目标与分阶段实施顺序。
- 确认第一阶段只做“服务端 `InGame` 房间权威快照落盘与重启恢复”。
- Phase 1 第一刀已完成：
  - 新增 `RoomPersistenceStore`，把 `InGame` 房间快照保存到 `user://dedicated_server/online_room_snapshots.json`。
  - `OnlineRoom` 新增 `to_persistence_dict()` / `from_persistence_dict()`，支持权威 archive 的落盘与恢复。
  - `RoomManager` 新增快照导出/恢复接口。
  - `DedicatedServer` 启动时自动加载快照，运行中每 2 秒周期性持久化，并在退出时再刷一次。
  - 新增 `OnlineRoomPersistenceRecoveryTest`，覆盖“保存 -> 恢复 -> hash 一致 -> 按 seat/user_id 重连成功”。
- 本次顺手修复了一个已有一致性问题：
  - `OnlineRoom.start_game()` 在写入在线规则位后，没有同步 `checkpoint0`，导致刚开局且尚无命令时导出的 archive 初始态与当前态不一致。
- 当前验证结果：
  - `godot --headless --script res://tools/check_compile.gd`：`PASS files=932`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：`passed=285/285 failed=[]`
- Phase 1 仍未覆盖：
  - Lobby 恢复
  - 客户端重启后的自动恢复
  - command log 增量恢复
  - 平台后端对 room -> game_server 的持久分配

### 2026-03-30（第二次更新）

- Phase 2 基础设施第一刀已完成：
  - `NetContext` 新增 `user://online_resume_state.cfg` 持久化。
  - `set_online_resume_context` / `clear_online_resume_context` / `mark_online_resume_in_game` / `set_online_reconnecting` 现在会同步写盘。
  - 启动时 `NetContext._ready()` 会尝试从磁盘恢复上次的 resume 状态。
  - 额外持久化 `session_id` / `user_id`，为后续“客户端重启后自动 resume_room”做准备。
  - 新增 `NetContextOnlineResumePersistenceTest`，覆盖“写盘 -> 清空内存 -> 重新加载 -> clear 后不再恢复”的流程。
- 当前验证结果：
  - `godot --headless --script res://tools/check_compile.gd`：`PASS files=933`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：`passed=286/286 failed=[]`
- Phase 2 仍未完成：
  - 启动后的自动恢复入口
  - 自动切回 Lobby / Game 正确场景
  - 对 `resume_room` 的冷启动编排

### 2026-03-30（第三次更新）

- Phase 2 主链路第一刀已完成：
  - 主菜单启动时若发现本地存在可恢复联机会话，会自动跳转到联机大厅。
  - 联机大厅新增冷启动恢复控制器，负责：
    - 自动登录平台
    - 调用 `resume_room`
    - 使用返回的 `ws_url/connect_token` 自动连接
    - 让现有 `RoomState/GameStarted` 流程继续决定留在 Lobby 还是进入 Game
  - 这一步已经把“客户端重启后自动开始恢复”接上。
- 新增测试：
  - `OnlineLobbyResumeControllerTest`
- 当前验证结果：
  - `godot --headless --script res://tools/check_compile.gd`：`PASS files=935`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：`passed=287/287 failed=[]`
- 仍未完成：
  - 冷启动后直接恢复到 Game 场景的完整 UX 打磨（目前复用现有 Lobby -> Game 事件链路）
  - `resume_room` 失败后的分级处理与更细的错误恢复策略
  - Lobby 房间在 server restart 后的 reclaim 语义

### 2026-03-30（第四次更新）

- Phase 1 范围进一步扩大：
  - 服务端快照恢复不再只支持 `InGame`，现在 `Lobby` 房间也会持久化。
  - `OnlineRoom` / `RoomManager` 新增 Lobby reclaim 路径：server 重启后，host/player 可以按 `seat_index + user_id` 重新认领原座位。
  - 平台 `connect_token + ClientHello` 自动入房链路已接到这条 reclaim 路径，恢复后的 Lobby 房间可继续正常使用。
- 新增测试：
  - `OnlineLobbyPersistenceRecoveryTest`
- 当前验证结果：
  - `godot --headless --script res://tools/check_compile.gd`：`PASS files=936`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：`passed=288/288 failed=[]`
- 仍未完成：
  - 平台后端对 room -> game_server 的持久分配
  - server 重启后的 active room 自动认领
  - 客户端恢复过程中的更细粒度错误恢复策略

### 2026-03-30（第五次更新）

- 平台后端 / Dedicated Server 协调能力继续前推：
  - backend heartbeat 现在支持携带并刷新 `ws_url`。
  - backend 新增内部接口：按 `game_server_id` 查询当前 active rooms。
  - Dedicated Server 在未显式配置 `GAME_SERVER_ID` 时，会把生成的 `game_server_id` 持久化到 `user://dedicated_server/server_identity.cfg`，跨重启保持稳定。
  - Dedicated Server 恢复本地房间快照时，会优先参考 backend 返回的 active room 列表做筛选，避免恢复 backend 已不认的旧房间。
- 新增测试：
  - `ServerIdentityStoreTest`
  - backend `test_heartbeat_updates_room_ws_url`
  - backend `test_list_active_rooms_for_server`
- 当前验证结果：
  - `godot --headless --script res://tools/check_compile.gd`：`PASS files=937`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：`passed=289/289 failed=[]`
  - `backend/.venv/bin/python -m pytest -q backend/tests/test_internal.py`：`9 passed`
  - `backend/.venv/bin/python -m pytest -q backend/tests/test_rooms.py`：`14 passed`
- 仍未完成：
  - backend 真正的“active room 重新分配 / failover”调度
  - 不同 game server 间迁移房间时的权威恢复流程
  - 客户端恢复失败后的更细粒度分级重试

### 2026-03-30（第六次更新）

- 单点模式下的 backend 房间目录继续收口：
  - `create_room` 现在会优先选择“最新健康 heartbeat 的唯一 game server”的 `ws_url`，而不是一律回退到静态默认地址。
  - `join_room` / `resume_room` / `spectate_room` 会在返回前尝试用当前健康 server 的 `ws_url` 刷新房间目录，确保客户端拿到的是最新连接入口。
  - 这一步让“单点 server 重启后目录地址同步”更稳，不依赖人工同步 `default_ws_url`。
- 新增 backend 测试：
  - `test_create_room_prefers_latest_healthy_game_server_ws_url`
  - `test_resume_room_refreshes_ws_url_from_healthy_game_server`
- 当前验证结果：
  - `backend/.venv/bin/python -m pytest -q backend/tests/test_rooms.py`：`16 passed`
  - `backend/.venv/bin/python -m pytest -q backend/tests/test_internal.py`：`9 passed`
- 仍未完成：
  - 单点 server 启动时主动把 backend 房间目录状态和本地快照做更强一致性校对
  - 冷启动恢复直接进入游戏场景后的细节 UX 收口
