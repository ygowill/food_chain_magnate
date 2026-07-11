> **只读历史归档（2026-07-11）**：本文是早期掉线重连实施记录，阶段状态和“待提交”文字均不再代表当前仓库。当前状态与证物见 [F-002](../../features/F-002-online-resume-bootstrap.md)。

# 联机掉线重连实施计划（2026-03-15）

## 背景

当前联机对局在服务端已经具备以下基础能力：

- InGame 断线后保留 seat，占位仍存在
- grace period 内允许同 `user_id + seat_index` 恢复玩家身份
- 重连后可由服务端下发 `GameStarted + ResyncArchive`

但客户端现状仍会在网络断开后立即清空 `NetContext`、销毁传输层，并在游戏场景中直接返回联机大厅，导致“服务端能重连，客户端不会重连”。

本次实现目标是把现有雏形补成可用流程：

- 对局中断线后不再直接返回主页面/大厅
- 客户端自动向平台后端申请新的 `connect_token`
- 客户端在原游戏场景内重连并恢复对局
- grace 超时或恢复失败时，再回退到明确的失败路径

## 目标范围

本次只处理“同进程内的联机掉线重连”：

- 支持平台模式房间的自动 resume
- 支持密码房重连时无需再次手输密码
- 支持游戏场景内保持当前场景并恢复 archive
- 支持失败后的明确提示与回退

暂不覆盖：

- 跨进程冷启动后恢复到旧对局
- 服务端重启后的房间恢复
- 专门的“断线后转观战”流程

## 任务拆分

### T1. 文档与实施基线

状态：`[进行中]`

交付物：

- 本文档：任务拆分、进度记录、验证记录
- 相关架构文档的最终同步

验收：

- 文档中能清楚看出每个阶段的状态、测试与结论

### T2. 平台后端 Resume 接口

状态：`[已完成]`

改动目标：

- 新增 `POST /v1/rooms/{room_code}/resume`
- 通过 `session_id` 查找现有 `RoomMember`
- 为 host/player/spectator 重新签发 `connect_token`
- 密码房 resume 不再要求重新提供 password

测试：

- 新增/修改 `backend/tests/test_rooms.py`
- 覆盖普通房 resume、密码房 resume、非成员 resume

验收：

- 已在房间中的用户能稳定拿到新的 token
- 非成员或非法房间得到明确错误

### T3. 客户端会话保留与 Resume 数据模型

状态：`[已完成]`

改动目标：

- 为客户端增加“可恢复联机会话”状态
- 非预期断线时保留 room/platform/resume 必要信息
- 手动退出、返回大厅、主动断开时清理恢复状态
- 为重连流程提供统一入口

测试：

- 新增 Godot 纯逻辑测试
- 覆盖 URL/token 解析、resume 状态保留/清理、重连路径下 `GameStarted` 不重建 engine

验收：

- 非预期断线后，客户端仍知道要恢复哪个房间
- 重连路径不会错误清空上下文

### T4. 游戏内自动重连与恢复

状态：`[已完成]`

改动目标：

- 游戏场景断线后不立即离场
- 显示“正在重连/正在恢复对局”状态
- 自动调用平台 `resume_room`
- 重连成功后在原场景内应用 `ResyncArchive`
- 多次尝试失败后再退出到大厅

测试：

- 新增 Godot 测试覆盖重连成功/失败路径
- 补充现有联机重连测试，覆盖客户端恢复语义

验收：

- 游戏场景在掉线时保持不变
- 服务端恢复后客户端回到可操作状态
- 失败时不会卡死在 loading 或半连状态

### T5. 文档收尾、全量验证与提交

状态：`[已完成]`

改动目标：

- 同步架构文档中的断线重连说明
- 运行必需 headless 测试
- 检查工作树并提交

测试：

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
- 必要的 backend 测试命令

验收：

- 必需 Godot 测试通过
- 新增 backend 测试通过
- 工作树仅包含预期改动并完成提交

## 进度记录

### 2026-03-15

- `T1`：已建立实施计划文档，待后续逐段更新
- `T2`：已完成
  - 新增 `POST /v1/rooms/{room_code}/resume`
  - resume 通过 `session_id -> RoomMember` 重新签发 token，不再要求密码房重复输入 password
  - 补充 backend 测试：普通房 resume、密码房 resume、非成员 resume
- `T3`：已完成
  - `NetContext` 新增在线 resume 状态与生命周期方法
  - `NetClient`/client 断线时支持按场景保留上下文，重连路径不再立即 `reset`
  - `rpc_game_started` 在重连恢复路径下复用现有 `GameEngine`
  - 补充 Godot 测试：`NetContextOnlineResumeTest`、`OnlineClientDisconnectPreserveContextTest`、`OnlineClientGameStartedReconnectTest`
- `T4`：已完成
  - `GameOnlineResyncController` 新增自动重连流程：resume token -> 重新连接 -> 等待/请求 archive 恢复 -> 失败回退
  - 游戏场景新增重连 loading、resume 请求、网络恢复桥接方法
  - 联机大厅在建房/入房时记录 resume 上下文，手动退出与致命错误时清理
  - 补充 Godot 测试：`GameOnlineResyncReconnectFlowTest`
- `T5`：已完成
  - 同步架构/部署/进度文档中的断线重连现状
  - 按仓库要求跑 `GameSmokeTest`、`AllTests`
  - 回跑 backend `test_rooms.py`
  - 待提交

## 最终验证记录

- `T2` 局部验证：
  - `.venv-backend/bin/python -m pytest backend/tests/test_rooms.py`
  - 结果：`14 passed`
- `T3/T4` 局部验证：
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
  - 结果：`passed=282/282 failed=[]`
- `T5` 最终验证：
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
  - 结果：`PASS`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
  - 结果：`passed=282/282 failed=[]`
  - `.venv-backend/bin/python -m pytest backend/tests/test_rooms.py`
  - 结果：`14 passed`
