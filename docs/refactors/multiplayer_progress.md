# 多人联机开发进度与问题追踪

本文件用于追踪“多人联机（Dedicated Server + WebSocket）”的开发进度、验收结果与问题记录。

关联文档：
- 计划与改造点：`docs/refactors/multiplayer_websocket_plan.md`
- 公网部署（Nginx + `wss://`）：`docs/refactors/multiplayer_public_deployment.md`
- 实现指南（文件/RPC 清单）：`docs/refactors/multiplayer_implementation_guide.md`
- 联机大厅 UI 改版（配置/模块选择）：`docs/refactors/multiplayer_lobby_ui_redesign.md`

---

## 0. 总体约束（已确认）

- 公网部署：`wss://`，由 Nginx 终止 TLS。
- 房间列表：服务器公开房间列表（大厅可浏览）。
- 房间加入：`room_password`（可空；空=无密码）。
- 观战：InGame 允许作为 spectator 加入；若房间有密码则需输入密码；房主可关闭观战（`allow_spectators=false`）。
- 保密范围：仅银行储备卡（UI/日志/导出不得泄露 `select_reserve_card.selected_index` 给非本人且未揭示时）。
- 断线重连：已支持同进程内自动重连（保留 seat + grace period + resume token + archive 恢复）。
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

### M5：联机大厅 UI/配置改版（拆分页面 + 复用模块选择）

状态：已落地（2026-01-29）。验收：`game_smoke_test`/`all_tests` 通过。

- [x] UI：Connect/Rooms/Create/Room 分页，避免单页堆叠
- [x] Server：公开房间列表 `RoomList`（创建/人数变化/开始等触发更新）
- [x] UI：Rooms 页展示房间列表 + 通过房间码加入（`room_password` 可空；密码房间 lock 标识）
- [x] UI：Rooms 页支持观战（InGame 且房主允许观战；密码房间需输入 password）
- [x] UI：CreateRoom 使用“模块选择面板”（复用 Hotseat UI/逻辑），不再手填 `enabled_modules_v2`
- [x] UI：Room 页结构化展示房间信息/玩家列表/旁观者列表；房主编辑配置并自动广播（debounce）
- [x] UI：seed_mode=随机 时展示最终 seed（由 server 分配并广播；StartGame 不重复随机）
- [x] UI：`modules_v2_base_dir` 仅放“高级/开发”隐藏
- [x] UI：房主可配置“是否允许观战”（对所有房间生效；观战仍需 password 鉴权）
- [x] Refactor：抽取可复用组件 `ModuleSelector` / `RoomConfigEditor`（Hotseat/Online 共用）
- [x] Tests：`OnlineRoomListTest`/`OnlineRoomSeedRandomStableTest` 等加入 `AllTests`
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

- 2026-01-30：Online 的顺位选择（OrderOfBusiness）原先只在轮到本地玩家时显示，导致其他玩家看不到实时选位进度（需要等到自己回合才看到）。修复：`TurnOrderSelectionModal` 复用游戏内 `TurnOrderDisplay` 组件，并支持等待态（非当前玩家只读）；`GamePanelController` 在联机模式下对所有客户端显示顺位选择弹窗，但仅当前玩家可交互。新增 `TurnOrderSelectionModalOnlineVisibilityTest` 并加入 `AllTests`。
- 2026-01-30：Setup 阶段从 `ReserveCards` 进入起始餐厅放置后，“回退到当前玩家回合开始”会把时间线回到储备卡选择（观感像按钮失效/回退过头）。修复：`find_current_player_turn_start_command_index()` 在 Setup 且不处于 `ReserveCards` 时，将回合起点定位为 `ReserveCards` 的最后一条命令索引（即放置流程开始）。新增 `RewindTurnStartSetupTurnSwitchTest` 并加入 `AllTests`。
- 2026-01-30：Online 回合交接时，非当前玩家的 ActionPanel 会被 “联机：等待其他玩家操作” 全局禁用；当轮到自己时虽然解禁，但按钮仍停留在 `disabled=true` 导致无法行动。原因：`set_globally_disabled("")` 只清理 reason 不恢复按钮 enabled 状态；而联机 UI 刷新顺序为“先 refresh 再 set_globally_disabled”，会触发该残留。修复：`ActionPanel.set_globally_disabled()` 在从禁用→解禁时主动 `refresh()` 一次恢复按钮状态。新增 `ActionPanelGlobalDisabledRestoreTest` 并加入 `AllTests`。
- 2026-01-30：Restructuring 阶段隐私：Online 不允许查看其他玩家公司结构（仅展示提交进度/状态）；Hotseat 模式已提交玩家不可再切换查看（用于保密）。实现：`RestructuringModal.set_player_switcher` 禁用他人/已提交按钮；`GamePanelController` 在 Restructuring 强制 view_player（online=local；hotseat=未提交）并屏蔽非法切换；旁观者在 Restructuring 隐藏结构内容。新增 `RestructuringPrivacyTest` 并加入 `AllTests`。
- 2026-01-30：Online 下“回退到当前玩家回合开始”曾为本地 rewind，导致不同客户端状态不一致。修复：新增 `rpc_rewind_to_turn_start`，由 server 执行 rewind + truncate，并广播 `ResyncArchive` 给房间内所有在线成员；同时联机模式禁用本地 ReplayBar/日志 seek（避免本地时间线回退造成不一致）。新增 `OnlineRewindToTurnStartTest` 并加入 `AllTests`。
- 2026-01-30：Online 下 ActionPanel 以 `current_player_id` 为上下文，导致非当前玩家看到/触发的是“他人的动作”，在联机校验（只能操作自己）下会直接失败，出现“无动作可用/无法继续”。修复：ActionPanel 在 `ONLINE_CLIENT` 模式固定使用 `local_player_id`；`GamePanelController` 创建命令时也使用 `local_player_id` 作为 actor；新增 `ActionPanelOnlineLocalPlayerTest` 并加入 `AllTests`。
- 2026-01-30：LeftPanel 的玩家 Tab 选择曾向外 emit `player_selected` 并被 `GamePanelController` 监听，导致“左侧信息面板的选择”影响全局 `view_player`（进而出现 ActionPanel 可用动作跟着变化的错觉/误导）。修复：LeftPanel 不再暴露 `player_selected` 信号，选择仅影响 LeftPanel 自身展示；新增 `LeftPanelSelectionIsolationTest` 防回归并加入 `AllTests`。
- 2026-01-29：`HashingContext.update()` 传入空 `PackedByteArray` 会报错（`len == 0`），导致“无密码房间”计算 password_hash 时 `AllTests` 失败。修复：对空字符串直接返回 `""`（表示无密码），避免对空 buffer 调用 `update()`。
- 2026-01-29：`GameEngine.load_from_archive` 会在“已初始化的 engine”上执行 `reset_modules_v2()`；由于 `PhaseManager` hooks 未清理，旧 hooks 的 Callable target 可能已被释放，导致回放时出现 `null::_on_restructuring_before_enter`。修复：在 `ModulesV2.reset` 中调用 `PhaseManager.reset_hooks()` 清空 hooks。
- 2026-01-29：`AllTests` 开启 warnings-as-errors；测试中对 `Variant` 返回值使用 `:=`（例如 `max(...)`）会触发 “typed as Variant” 警告并当作错误。修复：改用显式类型或 `maxi/mini` 等确定类型函数。
- 2026-01-29：`CommandPrivacy.sanitize_params` 必须复制 `params`（`duplicate(true)`），否则会在 UI/调试视图中“污染”原始 `Command.params`（导致后续显示/导出/测试错误）。
- 2026-01-29：Godot headless 下新加 `class_name` 脚本不会自动进入 Global Class Cache；避免在新脚本上使用 `RoomManager`/`OnlineRoom` 等类型注解（会触发 Parse Error），改用无类型变量或显式 `Script`/`Dictionary`/`Result`。
- 2026-01-29：GDScript 中使用 `:=` 时需要可推导类型；对未显式类型的对象（例如 `var server_engine = ...`）再调用方法返回值时，可能触发 “Cannot infer the type” 解析错误。测试代码里优先用 `=`（Variant）或补齐类型注解。
