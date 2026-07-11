# 联机开局统一 Loading 手测清单

适用范围：当前仓库中“Lobby -> Starting -> InGame”联机开局流程；历史设计背景见 [联机开局统一 Loading 改造](archive/online_match_bootstrap_loading_redesign.md)，当前状态以 [F-002](../features/F-002-online-resume-bootstrap.md) 和 [Online Architecture](../architecture/70-online-multiplayer.md) 为准。

## 目标

确认以下体验已经成立：

- 房主点击开始后，房主和玩家都**立刻进入统一 loading 状态**；
- loading 文案和进度由真实启动流程驱动；
- 本地已完成初始化的一方会进入“等待其他玩家”状态，而不是无反馈卡住；
- 只有全员 ready 后才一起进入游戏；
- 任一关键失败会统一回滚到 Lobby，并结束 loading。

## 手测前准备

- 启动一台服务端和两个客户端；
- 两个客户端都进入同一房间；
- 优先使用双人房，避免额外变量；
- 若需要观察日志，重点关注：
	- `TX StartGame`
	- `rpc_game_started`
	- `TX MatchBootstrapReady`
	- `TX MatchBootstrapFailed`
	- `Match bootstrap committed`

## 场景 1：标准开局

### 步骤

1. 房主和玩家都停留在 Lobby 房间页；
2. 房主点击“开始游戏”；
3. 观察房主与玩家 UI；
4. 等待双方进入 Game 场景。

### 预期

- 房主点击后 1 帧内进入 loading；
- 玩家在收到 `Starting` 房态后也立刻进入同一套 loading；
- 两侧都能看到阶段文案，不应出现“玩家侧长时间无反应”；
- 本地 bootstrap 完成较早的一侧，会显示“等待其他玩家 x/y”；
- 最终双方都在接近同时刻进入 Game；
- Game 首屏 ready 之前，loading 不应提前消失。

## 场景 2：一方初始化更慢

### 步骤

1. 让其中一个客户端在本地制造较慢的初始化环境；
2. 房主再次开始游戏；
3. 观察较快一侧的 loading 表现。

### 预期

- 较快一侧不会直接黑等；
- 会停留在 waiting 区间，并显示等待文案；
- 较慢一侧完成后，双方才一起进入 Game。

## 场景 3：Starting 期间玩家离开房间

### 步骤

1. 房主点击开始游戏；
2. 在双方仍处于 loading 时，让玩家主动离开房间。

### 预期

- 本次开局被取消；
- 房主和剩余客户端收到失败提示；
- 房间状态回到 Lobby；
- loading 结束，不会残留遮罩；
- 后续仍可再次点击开始游戏。

## 场景 4：Starting 期间玩家掉线

### 步骤

1. 房主点击开始游戏；
2. 在 loading 期间断开其中一个玩家连接。

### 预期

- 行为与“主动离开房间”一致；
- 房间回到 Lobby；
- 文案提示为“有玩家掉线，本次开局已取消”或等价表达；
- 不应有一端继续卡在 loading。

## 场景 5：本地 bootstrap 失败

### 步骤

1. 人为制造某个客户端本地初始化失败；
2. 房主点击开始游戏；
3. 观察双方表现。

### 预期

- 失败客户端会上报 `match_bootstrap_failed`；
- 服务端 abort 本次 session；
- 所有参与者都回到 Lobby；
- 失败端能看到明确错误；
- 其他端不会误进 Game。

## 场景 6：Starting 期间禁止晚加入

### 步骤

1. 房主点击开始游戏；
2. 在房间处于 `Starting` 时，第三个客户端尝试：
	- 作为玩家加入；
	- 作为观战者加入。

### 预期

- 两种加入都被拒绝；
- 不应插入本次 bootstrap；
- 房间当前成员列表保持不变。

## 场景 7：重复点击开始

### 步骤

1. 房主快速连续点击开始游戏；
2. 观察服务端和房主 UI。

### 预期

- 不会创建多个并发开局流程；
- 同一 request 的重复触发应被忽略或合并；
- 不同 request 的并发启动应被拒绝；
- UI 不应闪烁或重置进度。

## 观察重点

- loading 是否跨场景连续，不出现“大厅一段 + 游戏一段”的双重等待；
- 玩家是否能在房主点击后立刻看到反馈；
- `room_state.bootstrap.self_ready` 是否只对当前 peer 显示为 `true`；
- commit 后 `room_state` 是否移除 `bootstrap` 字段；
- abort 后是否能无残留地重新开始下一局。
