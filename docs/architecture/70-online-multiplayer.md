# 联机（Online Multiplayer）

状态：已落地 **M3（输入权限收口 + 储备卡保密）**；尚未实现 Resync/掉线弃权（M4）。

已实现内容（M1–M3）：
- Dedicated Server（ws）：`server/dedicated_server.tscn`、`server/dedicated_server.gd`
- 房间逻辑（纯逻辑类）：`server/room_manager.gd`、`server/room.gd`
- Client 会话层（共用 RPC 节点）：`autoload/net_client.gd`、`autoload/net_context.gd`
- 联机大厅 UI：`ui/scenes/online/online_lobby.tscn`
- StartGame：server 创建 `GameEngine` 并广播 `GameStarted`，client 初始化并进入 `ui/scenes/game/game.tscn`
- ActionRequest：client 发送 `ActionRequest`，server 广播 `CommandApplied`，client 回放执行更新 UI
- 输入权限收口（禁止代操）：`ui/scenes/game/game.gd`、`ui/scenes/game/game_panel_controller.gd`
- 储备卡保密：非本人显示等待、历史/导出脱敏：`ui/components/modal_panel/reserve_card_selection_modal.gd`、`core/utils/command_privacy.gd`

本项目的 `core/` 已具备“命令广播回放”所需的关键基础设施：

- `core/types/command.gd`：命令可序列化/可严格反序列化
- `core/engine/game_engine/command_runner.gd`：支持 `is_replay=true` 的回放执行
- `core/state/game_state.gd`：`compute_hash()` 可用于联机一致性校验

联机设计/改造计划请见：

- `docs/refactors/multiplayer_websocket_plan.md`（整体方案、协议、UI 改造点、里程碑）
- `docs/refactors/multiplayer_public_deployment.md`（公网 `wss://` 部署与最小鉴权建议）
- `docs/refactors/multiplayer_implementation_guide.md`（按文件与 RPC 列表的实现指南）
