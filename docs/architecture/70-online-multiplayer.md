# 联机（Online Multiplayer）

状态：**当前仓库未实现联机模式**（没有 `server/` 目录，也没有网络会话层代码）。本文件仅保留为“未来设计入口”，避免旧文档误导读者以为已落地。

若你要推进该方向，现有的设计/改造计划在：

- `docs/refactors/multiplayer_websocket_plan.md`

建议联机方案仍复用本项目的“命令广播 + 客户端回放 + state_hash 校验”模式（`GameEngine`/`Command`/`GameState.compute_hash` 已满足基础条件）。
