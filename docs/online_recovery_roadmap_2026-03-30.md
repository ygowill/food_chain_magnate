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
