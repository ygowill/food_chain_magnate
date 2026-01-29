# 多人联机开发进度与问题追踪

本文件用于追踪“多人联机（Dedicated Server + WebSocket）”的开发进度、验收结果与问题记录。

关联文档：
- 计划与改造点：`docs/refactors/multiplayer_websocket_plan.md`
- 公网部署（Nginx + `wss://`）：`docs/refactors/multiplayer_public_deployment.md`
- 实现指南（文件/RPC 清单）：`docs/refactors/multiplayer_implementation_guide.md`

---

## 0. 总体约束（已确认）

- 公网部署：`wss://`，由 Nginx 终止 TLS。
- 房间加入：默认 `room_password`。
- 保密范围：仅银行储备卡（UI/日志/导出不得泄露 `select_reserve_card.selected_index` 给非本人且未揭示时）。
- 断线重连：阶段 1 不要求。
- 掉线处理（InGame）：其余玩家继续；掉线玩家弃权：
  - 移除：餐厅 + 营销板件（`marketing_instances` / `marketing_placements`）+ 员工/库存/里程碑等玩家资产
  - 现金也属于玩家资产：弃权时清零（并计入 `bank.removed_total`）
  - 不移除：房屋/花园
  - 弃权玩家不得获胜
  - 服务器自动代为执行 `skip/end_turn`（以及必要的阶段动作）以保证流程继续
  - 弃权玩家保留在房间内作为“旁观者”（只读）

---

## 1. 里程碑进度（M1–M4）

### M1：网络骨架 + 单房间大厅（不进游戏）

- [x] Server：WebSocket server 启动（ws，TLS 由 Nginx 负责）
- [x] Server：CreateRoom/JoinRoom/LeaveRoom + RoomState 广播（password）
- [x] Client：联机大厅 UI（创建/加入/玩家列表/配置同步）
- [x] Tests：新增房间鉴权/状态机测试并加入 `AllTests`
- [x] 验收：运行 `game_smoke_test.tscn` 与 `all_tests.tscn` 通过
- [x] Docs：更新本文件与计划文档
- [x] Git：提交变更

### M2：启动对局 + 命令广播回放（先不做保密门禁）

- [x] Server：StartGame 后创建 `GameEngine` + peer→player_id 映射
- [x] Client：进入 Game 场景；通过 `CommandApplied` 回放更新 UI
- [x] Tests：新增“命令广播回放一致性”测试并加入 `AllTests`
- [x] 验收：`game_smoke_test`/`all_tests` 通过
- [x] Docs + Git

### M3：输入权限收口 + 储备卡保密（UI/日志/导出）

- [x] Client：local_player_id 输入权限（禁止代操）
- [x] Client：ReserveCards 弹窗仅本人可交互；其他人只显示等待
- [x] Client：History/导出脱敏 `select_reserve_card.selected_index`
- [x] Tests：隐私脱敏 + 交互门禁测试加入 `AllTests`
- [x] 验收：`game_smoke_test`/`all_tests` 通过
- [x] Docs + Git

### M4：Resync + 稳定性 + 掉线弃权（其余继续）

- [x] Client：index/hash mismatch 自动 resync（含 pending queue）
- [x] Server：ResyncArchive（`engine.create_archive()`）+ Join mid-game 观战（spectator）
- [x] Server：掉线玩家执行 `forfeit_player`（移除餐厅/营销/玩家资产；保留房屋/花园；不得获胜；只读旁观者）
- [x] Server：弃权玩家自动推进（`select_reserve_card/submit_restructuring/choose_turn_order/skip(_sub_phase)` 等）
- [x] Tests：resync + forfeit + room spectator 行为测试加入 `AllTests`
- [x] 验收：`game_smoke_test`/`all_tests` 通过
- [x] Docs + Git

---

## 2. 每次开发的固定检查清单

每次新增联机功能点后：

1) 补充/更新测试，并加入 `ui/scenes/tests/all_tests.gd`
2) 运行：
   - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
   - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
3) 更新相关文档（计划/实现指南/本文件）
4) `git status` 确认变更，提交到 git（按 `type(scope): summary` 约定）

---

## 3. 问题记录（Issues Log）

（按时间倒序追加）

- 2026-01-29：`GameEngine.load_from_archive` 会在“已初始化的 engine”上执行 `reset_modules_v2()`；由于 `PhaseManager` hooks 未清理，旧 hooks 的 Callable target 可能已被释放，导致回放时出现 `null::_on_restructuring_before_enter`。修复：在 `ModulesV2.reset` 中调用 `PhaseManager.reset_hooks()` 清空 hooks。
- 2026-01-29：`AllTests` 开启 warnings-as-errors；测试中对 `Variant` 返回值使用 `:=`（例如 `max(...)`）会触发 “typed as Variant” 警告并当作错误。修复：改用显式类型或 `maxi/mini` 等确定类型函数。
- 2026-01-29：`CommandPrivacy.sanitize_params` 必须复制 `params`（`duplicate(true)`），否则会在 UI/调试视图中“污染”原始 `Command.params`（导致后续显示/导出/测试错误）。
- 2026-01-29：Godot headless 下新加 `class_name` 脚本不会自动进入 Global Class Cache；避免在新脚本上使用 `RoomManager`/`OnlineRoom` 等类型注解（会触发 Parse Error），改用无类型变量或显式 `Script`/`Dictionary`/`Result`。
- 2026-01-29：GDScript 中使用 `:=` 时需要可推导类型；对未显式类型的对象（例如 `var server_engine = ...`）再调用方法返回值时，可能触发 “Cannot infer the type” 解析错误。测试代码里优先用 `=`（Variant）或补齐类型注解。
