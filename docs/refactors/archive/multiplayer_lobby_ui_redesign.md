# 联机大厅 UI 改版方案（公开房间列表 / 配置优先 / 复用 Hotseat 模块选择）

状态：已落地（M5），并通过 headless 验收测试。

目标：解决当前 `ui/scenes/online/online_lobby.tscn` “创建/加入/房间信息/配置”挤在同一页、排版拥挤、模块配置不可用的问题；并明确“房主配置 → 广播/同步”的交互与实现落点。

---

## 0. 已确认决策（来自你最新回复）

- “房间列表”是 **服务器公开房间列表**
- `room_password` **可以为空**（空=无密码）
- 房主配置广播采用 **自动同步（debounce）**
- seed_mode=随机 时 **需要展示最终 seed**
- `modules_v2_base_dir` 只放在“高级/开发”里隐藏
- 房间列表 **展示密码房间**（用锁图标标识）
- 观战：列表展示 InGame 房间并允许观战；若房间有密码则 **输入密码可观战**；房主可配置 **不允许观战**
- 排序：房间列表按 **更新时间倒序（最新在前）**
- 不需要 Listed/Unlisted：默认所有房间都在列表中

---

## 1. 背景与当前问题

现状（已实现但可用性弱）：

- 当前联机大厅是单页 `VBoxContainer`：连接区 + 创建房间 + 加入房间 + 房间配置（种子/模块）+ 房间操作 + 纯文本状态输出。
- “创建房间”与“房间信息（玩家列表/配置）”同屏且没有层级区分，用户在未入房间时也能看到大量“房间配置”字段，认知负担大。
- 启用哪些 module 目前靠 `TextEdit` 手工填写 `enabled_modules_v2`（一行一个），不满足“复用 hotseat 的 UI”诉求，也容易产生非法配置（拼写错误/冲突/依赖缺失）。
- 房主“可配置并广播”的路径不够清晰：UI 上虽然有“同步配置”按钮，但缺少“编辑态/未同步/已同步/无效配置”这套明确反馈；非房主的只读体验也较弱。

---

## 2. 目标与非目标

### 2.1 目标（本次 UI 改版必须达成）

- **拆分信息架构**：把联机大厅拆成 3–4 个清晰页面/状态（连接、房间列表、创建、房间内 Lobby），避免同屏堆叠。
- **服务器公开房间列表**：连接后可浏览房间（含状态/人数/是否需要密码），并从列表直接加入/观战。
- **创建房间支持模块选择**：在创建房间流程中，房主可通过 UI 勾选启用模块；并且 **复用 Hotseat 的模块选择 UI/逻辑**（依赖/冲突/分组/全选）。
- **房主可配置并广播**：房主在“房间内 Lobby”中可编辑配置（人数/seed/模块）；配置变更通过自动同步广播给所有人；其他人只读、可感知变更。
- **更可读的房间信息**：房间 code、玩家列表（含连接/弃权状态）、旁观者列表、当前配置摘要应结构化展示，而不是仅在纯文本中打印。

### 2.2 非目标（本次不做/不承诺）

- 不做复杂动效/皮肤化；优先可用性与可维护性。
- 不做断线重连体验改造（阶段 1 不要求）。当前断线弃权/旁观者语义保持不变。
- 不做跨服务器聚合/匹配；房间列表仅展示“本服务器上的房间”。

---

## 3. 信息架构与导航（推荐方案）

建议把 `OnlineLobby` 视为一个小状态机，根据连接/是否在房间内切换页面。推荐两种 UI 结构（二选一）：

### 方案 A（推荐）：`TabContainer` 分页 + 状态驱动启用/跳转

- 顶部固定：返回 + 标题 + 连接状态提示（可选）
- 主体：`TabContainer`
	- Tab1：连接（Connect）
	- Tab2：房间列表（Rooms）
	- Tab3：创建房间（Create）
	- Tab4：房间（Room）——只有在已加入/已创建后才启用，并自动切换到该页

优点：实现简单、结构清晰；不需要额外导航组件。

### 方案 B：左侧导航（Sidebar）+ 右侧内容（Content）

适合未来扩展更多入口（比如“观战/最近房间/本地服务器管理”等），但实现成本略高。

本文件后续以 **方案 A** 作为落地基线描述。

---

## 4. 页面设计（Wireframe）

### 4.1 Connect（连接页）

目的：把“联网前置配置”与“房间操作”解耦。

内容（由上到下）：

- Server URL（支持 `ws://` / `wss://`，默认给出示例 `wss://<domain>` 或 `ws://127.0.0.1:7000`）
- Profile：昵称、颜色（现有字段保持）
- Connect / Disconnect 按钮
- 连接状态与错误提示（Toast/Label）

交互要点：

- 未连接时，只允许在此页连接；Rooms/Create/Room Tab 应 disabled 或显示“请先连接”提示。
- 连接成功后自动切换到 Rooms（或保留当前页由用户选择）。

### 4.2 Rooms（公开房间列表页）

内容：

- 房间列表（建议表格/列表卡片）：
	- `room_code`
	- `status`（Lobby/InGame/Ended）
	- `players_count / desired_player_count`
	- 是否需要密码（Lock 图标/“需要密码”文字）
	- 房主昵称（可选）
	- 配置摘要：seed、模块数量（可选）
	- 操作：
		- `加入`（Lobby 且未满）
		- `观战`（InGame 且允许观战；见下方规则）
		- `进入`（已在该房间）
- 列表刷新（两种其一即可，优先实现简单可用）：
	- A. 服务器广播：room create/join/leave/start/end 时推送全量列表
	- B. 客户端请求：进入此页时/点击刷新时调用 `ListRooms`
- “通过房间码加入”（列表页内的次要区域）：
	- Room Code 输入（自动大写，支持粘贴）
	- Room Password 输入（可空，`secret=true`）
	- Join 按钮
- 失败提示区（展示 `RequestRejected` 的 code/message）

观战按钮规则（已确认）：

- 只有当 `status == "InGame"` 且 `allow_spectators == true` 时，展示/启用 `观战`。
- 若 `password_required == true`：
	- 点击 `观战` 时提示输入 `room_password`（可复用“通过房间码加入”的密码输入，或弹出一个小对话框）
	- 密码正确后执行 `JoinRoom(room_code, room_password)`（server 侧将其作为 spectator 加入）
	- 密码缺失/错误时提示失败（不进入房间）

可选增强（不影响阶段 1）：

- “最近加入”列表（本地记忆最近 N 个 `room_code`，不从服务器拉取）
- “粘贴邀请码”按钮（解析形如 `ROOMCODE#password` 的文本；密码仍不在 UI 明文展示）
- 搜索/过滤（按状态/人数/是否需要密码）

### 4.3 Create（创建房间页）——重点改造

内容分区建议：

**A. 基础信息**

- 人数 `desired_player_count`（2–5）
- `room_password`（可空；空=无密码）
- （高级/开发）是否允许观战（`allow_spectators`，默认 true）

**B. 房间配置（可折叠“高级”）**

- Seed：
	- seed_mode：随机 / 固定
	- seed_value：仅在“固定”时启用输入
	- seed 展示：seed_mode=随机 时也展示“最终 seed”（由 server 分配并广播）
- Modules：
	- 这里不再使用 `TextEdit` 输入 `enabled_modules_v2`
	- 改为嵌入一个“模块选择面板”（复用 Hotseat 的模块选择 UI；见第 5 节）
- 高级设置（默认折叠）：
	- `modules_v2_base_dir`（公网对战通常应固定为 `res://modules`；此项更像开发选项）

**C. 创建按钮**

- CreateRoom 按钮
- 创建前做一次本地校验（至少：player_count 范围、模块选择可 build_plan）
- 创建成功后自动切换到 Room Tab；并在 Room 页展示 server 回传的 `room_code` 与最终 `seed`

### 4.4 Room（房间内 Lobby 页）——房主可配置并广播

内容建议分两栏（宽屏）或上下布局（窄屏 + ScrollContainer）：

**左栏：房间信息 / 玩家列表**

- 房间 Code（大字显示）+ “复制”按钮
- 房主标记（Host badge）
- 玩家列表（结构化行，而不是 RichText 输出）：
	- `seat_index`、昵称、颜色（或色块）、连接状态（Connected/Disconnected）、弃权状态（Forfeited）
	- 本机玩家高亮
- 旁观者列表（Spectators）：
	- 昵称、连接状态

**右栏：房间配置摘要 / 房主编辑区**

- 当前配置摘要（只读）：
	- player_count、seed_mode/seed、模块数量与列表摘要（可折叠展开详细模块清单）
- 房主编辑区（仅房主可见或仅房主可交互）：
	- 复用与 Create 页同一套“RoomConfigEditor”（同一 UI/同一校验逻辑）
	- 明确 “未同步/已同步/无效” 状态
	- 自动同步（debounce），并显示“同步中/失败/已同步”（见第 6 节）
	- （高级/开发）观战开关：允许/不允许观战

**底部操作**

- LeaveRoom
- StartGame（仅房主 & 人数满足 & 配置已同步且有效）

---

## 5. 模块选择 UI：复用 Hotseat 的方案（必须）

### 5.1 Hotseat 现有实现来源

Hotseat 的模块选择 UI/逻辑目前集中在：

- `ui/scenes/setup/game_setup.gd`
	- `_load_modules()`：根据 `Globals.modules_v2_base_dir` 加载模块清单（`ModulePackageLoader.load_all_from_dirs`）
	- `_build_modules_ui()` / `_build_module_group_box()`：按分组构建 checkbox
	- `_recompute_modules_and_apply_to_ui()`：处理依赖/冲突、更新禁用态与提示
	- `_apply_module_selection_to_globals()`：把选择结果写回 `Globals.enabled_modules_v2` 并用 `ModulePlanBuilder.build_plan` 校验

这套 UI 已支持：

- 分组展示（`MODULE_GROUPS`）
- 全选/全不选、组选/组不选
- 依赖闭包（自动勾选依赖、并在被依赖时锁定不可取消）
- 冲突/兼容性：`new_milestones` 优先；自动取消 `hard_choices`；并自动取消（直接或间接）依赖 `base_milestones` 的模块

### 5.2 抽取为可复用组件（建议落地方式）

为满足“复用 hotseat 的 UI”，建议把上述模块选择 UI 抽取成独立组件，供 Hotseat 与 Online 共用：

- 新增组件（建议命名）：
	- `ui/components/module_selector/module_selector.tscn`
	- `ui/components/module_selector/module_selector.gd`
- 抽取原则：
	- **组件不直接读写 `Globals`**；由调用方提供 base_dir / 初始选择，并在需要时读取输出。
	- 依赖/冲突/有效性校验逻辑保留在组件内部，避免 Online 与 Hotseat 走两套分叉逻辑。

建议对外 API（示例，便于后续实现对齐）：

- `func set_modules_base_dir(base_dir: String) -> Result`：设置并加载 manifests（内部调用 `ModuleDirSpec.parse_base_dirs` + `ModulePackageLoader.load_all_from_dirs`）
- `func set_initial_enabled_modules_v2(enabled: Array[String]) -> void`：从一份完整 enabled_modules_v2 反推出可选模块勾选态（忽略 `base_*`）
- `func get_enabled_modules_v2() -> Array[String]`：返回“最终完整 enabled_modules_v2”（base + effective optional；处理 new_milestones 移除 base_milestones）
- `func validate_selection() -> Result`：使用 `ModulePlanBuilder.build_plan(_available_modules, enabled_modules_v2)` 做强校验
- `signal selection_changed(enabled_modules_v2: Array[String], notes: Array[String])`

### 5.3 Online 场景中的复用点

Online 需要两个地方使用同一组件：

1) Create 页：创建房间时生成 `config.enabled_modules_v2`
2) Room 页（房主编辑区）：更新房间配置时生成 patch 的 `enabled_modules_v2`

因此建议再包一层复用 UI：

- `RoomConfigEditor`（建议组件名）
	- 负责 player_count、seed_mode/seed_value、modules_base_dir、ModuleSelector 组合布局
	- 负责“dirty 状态/校验结果展示”
	- 提供 `get_config_patch()` / `set_from_room_config(config)` 之类方法

---

## 6. 房主配置并广播：交互与同步策略

采用 **自动同步（debounce）+ 可见的“同步中/失败/已同步”状态**，避免房主手动点按钮。

### 6.1 状态机与规则（建议）

房主编辑区维护三类状态：

- `valid`：当前本地配置能通过 `RoomConfigEditor.validate()`
- `sync_state`：
	- `synced`（本地与 server 一致）
	- `dirty`（本地有改动但尚未同步/正在等待 debounce）
	- `syncing`（已发 `UpdateRoomConfig`，等待 server `RoomState.config` 回显）
	- `error`（收到 `RequestRejected` 或本地校验失败）

同步策略（建议）：

- 任意字段变化（人数/seed/模块/base_dir）：
	- 先本地校验：
		- 若校验失败：进入 `error`，显示原因，不发送网络请求
		- 若校验通过：进入 `dirty`，启动/重置 debounce 计时器（例如 500ms）
- debounce 到期：
	- 若仍 `dirty` 且 `valid=true`：发送 `UpdateRoomConfig(patch)`，进入 `syncing`
- 收到 server 广播的 `RoomState.config`：
	- 若与本地期望一致：进入 `synced`
	- 若不一致：以 server 为准刷新 UI（并显示“已按 server 配置更新”提示）
- StartGame 允许条件：
	- 仅房主
	- `sync_state == synced`
	- 人数满足（players == desired_player_count）
	- status == Lobby

### 6.2 非房主体验

- 非房主始终只读显示“当前房间配置”。
- 当 `RoomState.config` 发生变化：
	- 在页面顶部或配置区显示一次轻量提示：“房主已更新房间配置”

---

## 7. 公开房间列表：协议与展示字段（设计补全）

为支持“服务器公开房间列表”，建议新增一个“房间摘要列表”广播/请求接口。该列表与 `RoomState` 的区别是：

- `RoomState`：某个房间的完整状态（只对房间内成员/旁观者有意义）
- `RoomList`：用于大厅浏览的轻量摘要（对所有已连接客户端可见）

### 7.1 RoomSummary（建议字段）

`RoomSummary`（Dictionary）建议包含：

- `room_code: String`
- `status: String`（"Lobby"/"InGame"/"Ended"）
- `desired_player_count: int`
- `player_count: int`（当前坐席人数，不含 spectators）
- `spectator_count: int`
- `password_required: bool`（true 表示需要输入 password 才能加入/观战）
- `allow_spectators: bool`（房主是否允许观战）
- `updated_at_ms: int`（服务端更新时间戳，用于按更新时间倒序排序）
- `host_name: String`（可选；来自 host 的 profile）
- `config_digest: Dictionary`（可选，便于列表显示）：
	- `seed: int`
	- `seed_mode: String`
	- `enabled_modules_count: int`

### 7.2 RPC（建议）

两种实现路径二选一即可：

- A. 服务器推送（推荐体验）：
	- server 在以下事件触发时向所有连接的客户端广播 `RoomListUpdated`：
		- create room / destroy room
		- join/leave room（人数变化）
		- start game / end game（status 变化）
- B. 客户端请求（推荐先做最小可用）：
	- client→server：`ListRooms { request_id }`
	- server→client：`RoomList { request_id, rooms: Array[RoomSummary] }`

无论 A/B，均需要：

- 不泄露敏感字段：不包含 `room_password`/hash
- 限流：对 `ListRooms` 与 JoinRoom 失败尝试做节流（防刷）
- 排序：服务端返回 `rooms` 默认按 `updated_at_ms` 倒序（最新在前）；客户端也可用该字段二次排序

---

## 8. 兼容性与边界（实现时注意）

- 模块缺失：加入房间后，如果本机缺少房主配置的模块包（manifest 不存在），应在 Room 页提示“缺少模块：...”，并在进入游戏前阻止/明确告警（避免进游戏后初始化失败）。
- `modules_v2_base_dir`：公网对局建议固定为 `res://modules`；对外 UI 可默认隐藏在“高级”中，避免普通玩家误改导致不一致。
- 旁观者：Room 页应展示 spectators；但 Join 流程仍是 `JoinRoom(room_code, room_password)`，是否提供“以旁观者加入”的显式开关可后续再加（当前实现是 InGame join 才会作为 spectator）。
- 公开房间列表：InGame 房间默认可观战；密码房间观战需输入密码；房主可关闭观战。
- 观战开关语义建议：
	- `allow_spectators=false`：仅阻止“新的观战加入”；已在房间内的旁观者继续保持旁观（不强制踢出）。
	- 密码房间：观战与加入一致，都需要通过 `room_password` 鉴权。

---

## 9. 验收与测试结果

本里程碑新增/更新的联机测试已加入 `AllTests`，并按固定流程验收通过：

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`：PASS
- 关键覆盖：
	- `RoomList` 摘要字段与排序（含 `password_required/allow_spectators/updated_at_ms`）
	- 无密码房间 JoinRoom 行为
	- `seed_mode=random` 时 seed 稳定（创建/更新时生成；StartGame 不覆盖）

---

## 10. 落地清单（已完成）

- 房间列表展示密码房间（lock 标识）；加入时允许输入空/非空 password
- 观战：InGame 且 `allow_spectators=true` 才可观战；密码房间输入密码可观战
- 排序：按 `updated_at_ms` 倒序（最新在前）
- 不做 Listed/Unlisted，默认全展示
