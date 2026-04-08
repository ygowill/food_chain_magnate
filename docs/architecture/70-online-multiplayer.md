# 联机（Online Multiplayer）

状态：已落地 **平台化房间联机链路**：平台后端负责账号/房间目录/connect_token，Godot 房间服负责实时权威对局，客户端支持 resync、rewind 与启动恢复。

## 模块关系图（联机的主要对象与依赖）

```mermaid
flowchart TB
  subgraph Client["Client（ONLINE_CLIENT）"]
    Lobby["OnlineLobby\nui/scenes/online/online_lobby.gd"]
    Game["Game scene\nui/scenes/game/game.gd"]
    Resume["OnlineSessionCoordinator"]
    PlatformSession["PlatformSession"]
    PlatformApi["PlatformApi"]
    NetClientC["NetClient"]
    NetCtx["NetContext"]
    ResyncCtl["controllers/online_resync_controller.gd"]
    EngineC["GameEngine"]
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
  NetClientC --> Game
  Game --> ResyncCtl --> EngineC

  Dedicated --> NetClientS --> RoomMgr --> Room --> EngineS
  NetClientS --> Internal
  Backend -->|"connect_token / room directory"| NetClientC
```

## 模块关系图（房间创建 / 实时命令 / Resync / Reconnect）

```mermaid
sequenceDiagram
  participant Lobby as OnlineLobby
  participant API as PlatformApi
  participant NC as NetClient(Client)
  participant NS as NetClient(Server)
  participant Room as OnlineRoom
  participant ES as GameEngine(Server)
  participant RC as OnlineResyncController
  participant EC as GameEngine(Client)

  Lobby->>API: create_room / join_room / resume_room
  API-->>Lobby: { ws_url, connect_token }
  Lobby->>NC: connect_to_server(ws_url?token=...)
  NC->>NS: WebSocket handshake + RPC

  alt StartGame
    NS->>Room: start_game()
    Room->>ES: initialize(...)
    NS-->>NC: game_started(payload)
    NC->>EC: initialize(... same config ...)
  end

  alt ActionRequest
    Lobby->>NC: request_action(cmd)
    NC->>NS: rpc_action_request
    NS->>ES: execute_command(cmd)
    NS-->>NC: command_applied(cmd_dict, state_hash)
    NC-->>RC: signal
    RC->>EC: execute_command(cmd, is_replay=true)
  end

  alt Resync / Rewind
    NC->>NS: request_resync / request_rewind_to_turn_start
    NS->>ES: create_archive / rewind_to_command
    NS-->>NC: resync_archive_received(...)
    RC->>EC: load_from_archive / rewind_to_command
  end
```

当前已落地内容：

- 房间服：`server/dedicated_server.gd`、`server/room_manager.gd`、`server/room.gd`
- WebSocket 会话层：`autoload/net_client.gd`
- 联机大厅：`ui/scenes/online/online_lobby.gd`
- 游戏内重同步：`ui/scenes/game/controllers/online_resync_controller.gd`
- 启动自动恢复：`autoload/online_session_coordinator.gd` + `ui/scenes/game/controllers/startup_online_resume_controller.gd`
- 旁观 / rewind_to_turn_start / forfeit_player / delta & snapshot 恢复链路

补充说明：

- 当前已不再走“纯直连大厅”模式；房间创建、加入、恢复都以平台后端返回的 `connect_token` 为入口
- 客户端对局内 hash / index 不一致时，会优先走 resync，而不是直接强退回大厅
- `NetContext.online_resume_state` 会持续记录 room_code、cursor、state_hash，用于冷恢复 / 场景切换恢复
