# 联机（Online Multiplayer）

状态：已落地 **M1（网络骨架 + 单房间大厅）**，尚未实现进入游戏/命令回放（M2 及之后）。

已实现内容（M1）：
- Dedicated Server（ws）：`server/dedicated_server.tscn`、`server/dedicated_server.gd`
- 房间逻辑（纯逻辑类）：`server/room_manager.gd`、`server/room.gd`
- Client 会话层（共用 RPC 节点）：`autoload/net_client.gd`、`autoload/net_context.gd`
- 联机大厅 UI：`ui/scenes/online/online_lobby.tscn`

本项目的 `core/` 已具备“命令广播回放”所需的关键基础设施：

- `core/types/command.gd`：命令可序列化/可严格反序列化
- `core/engine/game_engine/command_runner.gd`：支持 `is_replay=true` 的回放执行
- `core/state/game_state.gd`：`compute_hash()` 可用于联机一致性校验

联机设计/改造计划请见：

- `docs/refactors/multiplayer_websocket_plan.md`（整体方案、协议、UI 改造点、里程碑）
- `docs/refactors/multiplayer_public_deployment.md`（公网 `wss://` 部署与最小鉴权建议）
- `docs/refactors/multiplayer_implementation_guide.md`（按文件与 RPC 列表的实现指南）
