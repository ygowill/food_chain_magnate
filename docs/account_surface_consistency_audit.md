# 账号展示与登录逻辑一致性审计

最后更新：2026-04-04

## 范围

本审计对比以下四个面：

- Godot 游戏客户端
- Godot Web 游戏
- Portal 网站前端 `web/portal`
- 平台后端 `backend/app/auth.py`

重点检查：

- 账号显示是否一致
- 游客/正式账号判定是否一致
- 邮箱绑定状态是否可见且一致
- 网站与游戏共享登录态时是否会产生错配

## 结论概览

当前四个面的账号语义并不完全一致，问题主要集中在三类：

1. 网站端与游戏端共享 localStorage，但同步字段不完整
2. 网站端游客登录锚点不持久化，导致同一浏览器多次游客进入会变成不同账号
3. 游戏端完全没有拉取 `/auth/me`，所以无法知道邮箱绑定状态，也无法和网站“账号设置”页面保持一致

## 1. 后端实际账号字段

后端 `/v1/auth/me` 当前返回：

- `user_id`
- `display_name`
- `email`
- `email_verified`
- `email_verification_pending`
- `is_guest`
- `is_admin`
- `created_at`

代码位置：

- [backend/app/auth.py](/Users/qinkai/Documents/FCM_new/backend/app/auth.py#L500)

这意味着平台层已经具备“邮箱是否已绑定”和“账号类型”的标准事实来源。

## 2. 网站端实际展示

Portal 设置页当前会显示：

- 昵称
- 用户 ID
- 邮箱
- 账号类型（游客/正式）
- 注册时间

并提供：

- 游客绑定邮箱
- 正式账号修改昵称
- 正式账号修改邮箱
- 正式账号修改密码

代码位置：

- [SettingsView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/SettingsView.vue#L7)

因此“网站端”对账号信息的展示是相对完整的。

## 3. 游戏端实际展示

游戏端当前账号 UI 主要在联机大厅：

- 账号状态栏只显示 `账号：游客 <short user_id>` 或 `账号：已登录 <short user_id>`
- 玩家名输入框对 guest 显示“游客昵称自动生成”
- 对 member 允许修改昵称
- 没有任何地方显示邮箱、绑定状态、邮箱验证状态

代码位置：

- [online_lobby.gd](/Users/qinkai/Documents/FCM_new/ui/scenes/online/online_lobby.gd#L649)
- [online_lobby.gd](/Users/qinkai/Documents/FCM_new/ui/scenes/online/online_lobby.gd#L1276)

也就是说，游戏端当前只能区分：

- 是否已登录
- 是否 guest

但看不到：

- 绑定邮箱是什么
- 是否已经绑定邮箱
- 是否正式账号但未验证邮箱
- 注册时间

## 4. 明确不一致：游戏端根本没有消费 `/auth/me`

虽然客户端 API 里已经有 `get_me(session_id)`：

- [platform_api.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_api.gd#L222)

但项目内没有任何地方调用它：

- 全局检索结果仅定义，无使用

结果：

- 游戏端拿不到 `email`
- 游戏端拿不到 `email_verified`
- 游戏端拿不到 `email_verification_pending`
- 游戏端也不会用它来校验已有 session 是否仍有效

因此就目前实现来说，游戏端不可能与网站“账号设置”页在邮箱绑定状态上保持一致，因为游戏端根本不知道这个状态。

## 5. 明确不一致：Portal 只同步了部分 localStorage 字段

Portal 登录态 store 当前只处理：

- `fcm_session_id`
- `fcm_user_id`
- `fcm_is_guest`

代码位置：

- [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts#L11)

Godot Web 会读取：

- `fcm_session_id`
- `fcm_user_id`
- `fcm_is_guest`
- `fcm_display_name`
- `fcm_device_id`

代码位置：

- [platform_session.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_session.gd#L269)
- [platform_session.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_session.gd#L277)

所以当前网站与 Godot Web 的共享登录态是不完整的。

直接后果：

- 网站登录后打开网页游戏，Godot Web 能看到 session，但看不到 Portal 当前用户的 `display_name`
- 网站游客登录后打开网页游戏，Godot Web 看不到当次游客登录所用的 `device_id`

## 6. 严重不一致：Portal 游客登录每次都生成新的随机设备 ID

Portal 当前游客登录逻辑：

- 每次 `guestLogin()` 都执行 `crypto.randomUUID()`
- 不持久化
- 调完接口后也不保存到 localStorage

代码位置：

- [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts#L40)

这会导致：

1. 同一浏览器两次在 Portal 点“游客试玩”，得到两个不同 guest 账号
2. 这与游戏原生端“本地持久化 `device_id`”的设计不一致
3. 这甚至与后端测试预期相冲突，后端明确测试了“同一 device_id 返回同一 user_id”

后端测试位置：

- [test_auth.py](/Users/qinkai/Documents/FCM_new/backend/tests/test_auth.py#L17)

这说明：

- 后端契约本来支持“同 device_id 稳定同 guest”
- 但 Portal 前端把这个契约绕开了

## 7. 更严重的不一致：Portal 到 Godot Web 的游客身份会断裂

这是当前最值得优先修的跨端问题。

现有链路如下：

1. 用户在 Portal 中点击“游客试玩”
2. Portal 生成一次性 `device_id = A`
3. 后端据此创建/恢复 guest `user_id = U1`
4. Portal 只把 `session_id / user_id / is_guest` 写到 localStorage
5. 用户从 Portal 打开 Godot Web
6. Godot Web 读到 `session_id = S1`、`user_id = U1`、`is_guest = true`
7. 但 Godot Web 读不到 `fcm_device_id`，于是本地新生成一个 `device_id = B`

代码位置：

- Portal guest login: [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts#L40)
- Godot Web 缺失 `device_id` 时会生成新值: [platform_session.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_session.gd#L32)

后果：

- 在同一次会话里也许还能先用 `session_id = S1`
- 但一旦这个 session 过期，Godot Web 后续拿 `device_id = B` 去 guest 登录时，后端会把它当成另一个游客
- 用户会从 `U1` 漂移到 `U2`

这正是“网站和游戏共享账号时身份不连续”的核心 bug。

## 8. 显示不一致：Portal 会显示昵称，游戏账号栏显示短 user_id

Portal 设置页展示昵称：

- `auth.user.display_name`

代码位置：

- [SettingsView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/SettingsView.vue#L9)

游戏联机大厅账号栏展示：

- `游客 <short user_id>` 或 `已登录 <short user_id>`

代码位置：

- [online_lobby.gd](/Users/qinkai/Documents/FCM_new/ui/scenes/online/online_lobby.gd#L649)

因此用户在网站上看到的是昵称，在游戏里看到的是账号 ID 缩写，这两个面向用户的信息不一致。

## 9. 显示不一致：Portal 注册可填写昵称，游戏注册没有昵称输入

Portal 注册页支持可选昵称：

- [RegisterView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/RegisterView.vue#L1)

游戏认证弹窗注册页只有：

- 邮箱
- 密码
- 确认密码

代码位置：

- [auth_dialog.gd](/Users/qinkai/Documents/FCM_new/ui/dialogs/auth_dialog.gd#L34)

因此：

- 网站注册时可以直接定昵称
- 游戏注册后只能得到默认 `账号#xxxx`，再手动改昵称

这属于功能不对齐。

## 10. 显示不一致：Portal 有邮箱与账号类型视图，游戏没有

Portal 设置页会显示：

- 邮箱
- 账号类型

代码位置：

- [SettingsView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/SettingsView.vue#L10)

游戏里没有任何对应展示位。

即使用户已经从游客升级为正式账号：

- 网站会显示邮箱和“正式”
- 游戏只会显示“账号：已登录 <short uid>”

因此“邮箱绑定状态”目前在游戏内是不可见的。

## 11. 文案不一致：Portal 承诺“游戏客户端将自动使用该昵称”，但 Web 路径下并不可靠

Portal 设置页文案：

- “联机昵称与账号绑定。修改后，游戏客户端将自动使用该昵称。”

代码位置：

- [SettingsView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/SettingsView.vue#L20)

但 Web 路径下，Portal 并不会把 `display_name` 写入 `fcm_display_name`，Godot Web 又不会主动调用 `/auth/me`。

因此：

- 如果该昵称不是默认 `账号#xxxx`
- 从 Portal 打开 Godot Web 时，游戏未必能自动显示这个昵称

这条文案在当前实现下不完全成立。

## 12. 登录逻辑不一致：Portal 退出登录不会调用后端 `/logout`

Portal 的退出登录只是本地清空 store 与 localStorage：

- [AppLayout.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/components/AppLayout.vue#L23)
- [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts#L59)

游戏客户端的 `PlatformSession.logout()` 则会调用后端 `/auth/logout`：

- [platform_session.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_session.gd#L157)

这意味着：

- 网站端“退出登录”只是本地登出
- 游戏端“退出登录”是服务端 revoke session

虽然两者都能让当前端失去登录态，但语义并不一致。

## 13. 绑定邮箱状态本身在后端是稳定的，但游戏端没接

后端 `/auth/bind` 与 `/auth/me` 的行为是一致的：

- bind 后 `is_guest` 变为 `false`
- `/auth/me` 会返回 `email`
- `/auth/me` 会返回 `email_verified`

代码位置：

- [backend/app/auth.py](/Users/qinkai/Documents/FCM_new/backend/app/auth.py#L460)
- [backend/app/auth.py](/Users/qinkai/Documents/FCM_new/backend/app/auth.py#L500)

所以“网站和后端”在邮箱绑定状态上是一致的。

真正不一致的是：

- 游戏端没有接入这套事实源

## 14. 风险排序

### P0

- Portal 游客登录不持久化 `device_id`
- Portal 与 Godot Web 未同步 `fcm_device_id`
- Godot Web 不调用 `/auth/me`，导致 session 校验与账号详情脱节

### P1

- Portal 与 Godot Web 未同步 `fcm_display_name`
- 游戏端账号栏显示短 `user_id` 而不是昵称
- 游戏端完全不可见邮箱绑定状态

### P2

- Portal 与游戏的注册流程能力不一致
- Portal 与游戏的 logout 语义不一致
- Portal 未展示 `email_verified/email_verification_pending`

## 15. 建议修复顺序

1. 先让 Portal 持久化 `fcm_device_id`，游客登录改为复用而不是每次 `crypto.randomUUID()`
2. Portal 在 `fetchUser()` 后同步写入 `fcm_display_name`
3. Godot Web `PlatformSession` 增加 `ensure_session/get_me` 校验逻辑
4. 游戏端补一个最小账号信息展示：
   - 昵称
   - 账号类型
   - 邮箱是否已绑定
5. 统一 Portal 与游戏端的退出登录语义

## 16. 可验证结论

可以明确确认的结论：

- 网站端当前有邮箱绑定状态展示，游戏端没有
- 网站端当前 guest 登录不稳定，游戏原生端相对稳定
- 网站端与 Godot Web 共享登录态的 localStorage 同步不完整
- 后端字段已经足够支持统一展示，但游戏端没有接

当前无法仅靠这份仓库确认的事项：

- 线上部署版本是否已经额外做了 localStorage 同步修补
- 线上 Portal 是否有 CDN/反代层注入额外脚本

但从仓库源码本身看，以上不一致是明确存在的。
