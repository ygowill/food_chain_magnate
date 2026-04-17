# 联机（Online Multiplayer）

状态：已落地 **平台化房间联机链路**。平台后端负责账号 / 房间目录 / `connect_token`，Godot 房间服负责实时权威对局。客户端当前支持：

- 平台房间创建 / 加入 / 恢复
- 游戏内 resync / rewind
- 启动恢复
- 恢复房快启动 + 完整历史后台构建

## 模块关系图（联机的主要对象与依赖）

```mermaid
flowchart TB
  subgraph Client["Client（ONLINE_CLIENT）"]
    Lobby["OnlineLobby\nui/scenes/online/online_lobby.gd"]
    Game["Game scene\nui/scenes/game/game.gd"]
    Resume["OnlineSessionCoordinator"]
    Bootstrap["OnlineMatchBootstrap"]
    PlatformSession["PlatformSession"]
    PlatformApi["PlatformApi"]
    NetClientC["NetClient"]
    NetCtx["NetContext"]
    ResyncCtl["controllers/online_resync_controller.gd"]
    Runtime["runtime_engine"]
    FullReplay["full_replay_engine"]
    SessionState["OnlineResumeSessionState"]
  end

  subgraph Backend["Platform Backend（HTTP）"]
    Auth["/v1/auth/*"]
    Rooms["/v1/rooms/*"]
    Matches["/v1/matches/*"]
    Internal["/internal/*"]
  end

  subgraph Server["Game Server（ONLINE_SERVER）"]
    Dedicated["dedicated_server.gd"]
    NetClientS["NetClient(server mode)"]
    RoomMgr["server/room_manager.gd"]
    Room["server/room.gd"]
    EngineS["GameEngine(authoritative)"]
  end

  Lobby --> PlatformSession --> PlatformApi --> Backend
  Lobby --> NetClientC
  Resume --> PlatformApi
  Resume --> NetClientC
  NetClientC --> NetCtx
  NetClientC --> Bootstrap
  Bootstrap --> Game
  Game --> ResyncCtl --> Runtime
  NetClientC --> SessionState
  SessionState --> Runtime
  SessionState --> FullReplay

  Dedicated --> NetClientS --> RoomMgr --> Room --> EngineS
  NetClientS --> Internal
  Backend -->|"connect_token / room directory"| NetClientC
```

## 模块关系图（房间创建 / 实时命令 / Resync / 恢复房双轨）

```mermaid
sequenceDiagram
  participant Lobby as OnlineLobby
  participant API as PlatformApi
  participant NC as NetClient(Client)
  participant NS as NetClient(Server)
  participant Room as OnlineRoom
  participant ES as GameEngine(Server)
  participant RC as OnlineResyncController
  participant Runtime as runtime_engine
  participant Full as full_replay_engine

  Lobby->>API: create_room / join_room / resume_room
  API-->>Lobby: { ws_url, connect_token }
  Lobby->>NC: connect_to_server(ws_url?token=...)
  NC->>NS: WebSocket handshake + RPC

  alt StartGame
    NS->>Room: start_game()
    Room->>ES: initialize(...)
    NS-->>NC: game_started(payload)
    NC->>Runtime: initialize / fast-start restore
    NC-->>Full: deferred full-history bootstrap
  end

  alt ActionRequest
    Lobby->>NC: request_action(cmd)
    NC->>NS: rpc_action_request
    NS->>ES: execute_command(cmd)
    NS-->>NC: command_applied(cmd_dict, state_hash)
    NC-->>RC: signal
    RC->>Runtime: execute_command(cmd, is_replay=true)
    NC-->>Full: record live tail only
  end

  alt Resync / Rewind
    NC->>NS: request_resync / request_rewind_to_turn_start
    NS->>ES: create_archive / rewind_to_command
    NS-->>NC: resync_archive_received(...)
    RC->>Runtime: load_from_archive / rewind_to_command
  end

  alt History / Replay View
    Game->>Full: ensure_full_history_current()
    Full-->>Game: timeline / entries / append
  end
```

## 当前已落地内容

- 房间服：
  - `server/dedicated_server.gd`
  - `server/room_manager.gd`
  - `server/room.gd`
- WebSocket 会话层：
  - `autoload/net_client.gd`
  - `autoload/net_client/client.gd`
  - `autoload/net_client_internal.gd`
- 联机大厅：
  - `ui/scenes/online/online_lobby.gd`
- 游戏内重同步：
  - `ui/scenes/game/controllers/online_resync_controller.gd`
- 启动自动恢复：
  - `autoload/online_session_coordinator.gd`
  - `autoload/online_match_bootstrap.gd`
  - `ui/scenes/game/controllers/startup_online_resume_controller.gd`
- 恢复房完整历史双轨：
  - `autoload/net_client_online_resume_support.gd`
  - `autoload/online_resume_session_state.gd`
  - `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

## 恢复房双轨模型（当前实现）

### 1. 服务器权威轨

- `OnlineRoom.game_engine`
- 持有完整命令历史
- 负责权威执行、resync、archive 导出

### 2. 客户端 runtime 轨

- `runtime_engine`
- 用于当前 live 对局
- 接收 `command_applied` 后立即更新
- 是玩家操作与 UI 主视图的实时数据源

### 3. 客户端 full history 轨

- `full_replay_engine`
- 用于日志、timeline、回放、复盘
- 恢复房中不再要求每条 live 命令都同步推进到这个 engine
- 当前做法是：
  - 先记录 `live_tail`
  - 在完整历史查看 / timeline 构建前按需补齐

## OnlineResumeSessionState

代码：`autoload/online_resume_session_state.gd`

这是当前恢复房双轨状态的中心存储，主要持有：

- `runtime_engine`
- `full_replay_engine`
- `full_archive`
- `runtime_anchor`
- `full_replay_live_tail_commands`
- `full_replay_step_timeline`
- `full_replay_step_timeline_entries`

补充说明：

- `snapshot()` 现在会基于 engine/state signature 缓存 `runtime_state_hash` / `full_replay_state_hash`
- `full_replay_step_timeline_entries` 用于避免恢复房每次都重新格式化完整日志 entries

## 恢复房进入策略

当前恢复房已不是“必须等完整历史 ready 才能进游戏”的模式。

现状：

- 快启动优先把 `runtime_engine` 拉起
- 进入对局后，完整历史在后台继续准备
- `OnlineSessionCoordinator` / `OnlineMatchBootstrap` 仍保留完整历史 ready 的状态通知
- 但默认不再把它作为进入主对局的硬 gate

## timeline / log 的数据源选择

恢复房中，日志与时间线默认优先走完整历史侧：

- `ui/scenes/game/timeline/controller.gd`
- `ui/scenes/game/timeline/online_resume_history_view_support.gd`
- `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

适配层会优先复用：

- cached full-history timeline
- cached full-history timeline entries
- incremental append

## 补充说明

- 当前已不再走“纯直连大厅”模式；房间创建、加入、恢复都以平台后端返回的 `connect_token` 为入口
- 客户端对局内 hash / index 不一致时，会优先走 resync，而不是直接强退回大厅
- `NetContext.online_resume_state` 会持续记录 room_code、cursor、state_hash，用于冷恢复 / 场景切换恢复
- 联机热路径性能分析统一使用 `core/debug/online_perf_trace.gd`
