# 联机游客账号与身份稳定性设计

最后更新：2026-04-04

## 1. 背景与目标

当前联机系统把房间归属、占座、重连、恢复都建立在 `user_id` 之上。如果同一台机器上的游客两次进入得到不同 `user_id`，那么下列能力都会退化：

- 断线重连无法稳定认回原座位
- 冷启动恢复会被视为“换了一个人”
- 房主归属与房间成员归属会失真
- 玩家会感知到“我明明还是我，但系统当成新号了”

本设计的目标是：

- 同一安装实例上的游客，多次进入应稳定映射到同一个游客账号
- `session_id` 可以过期，但游客身份本身不能因为 session 过期而丢失
- 游客升级正式账号时，保留原 `user_id`，而不是新建新号
- 显式退出正式账号后，不应被“游客自动登录”偷偷重新登录回正式账号
- 兼容当前项目已存在的 `device_id`、`user_id`、`session_id` 与联机恢复逻辑

## 2. 现状总结

当前项目已经有三块基础设施：

- 客户端会在本地持久化 `device_id`
- 客户端把平台主身份保存在 `user_id`
- 平台会话保存在 `session_id`

从职责上看，这已经接近成熟方案，但还没有彻底分层：

- `device_id` 目前更像“安装实例锚点”，不是硬件设备标识
- `user_id` 已经承担“房间身份主键”的职责
- `session_id` 是登录态，但当前客户端对它的有效性校验不足

因此真正缺失的不是“更随机的游客 ID”，而是：

- 稳定游客主身份的后端映射规则
- session 失效后的静默恢复策略
- 游客升级后的账号语义与退出语义
- UI 层对 guest/member 身份的统一展示规则

## 3. 业界成熟做法

业界成熟产品一般遵循同一原则：

- 先给低摩擦匿名身份，降低进入门槛
- 匿名身份本身是一个真实账号主体，而不是一次性临时 token
- 会话失效和账号身份失效是两回事
- 后续通过 link/bind 把匿名身份升级为正式身份，保留原数据和主账号
- 匿名账号通常只保证“同一安装实例/同一缓存环境”可恢复，不承诺跨卸载永久恢复

可参考的官方资料：

- Firebase Anonymous Auth: <https://firebase.google.com/docs/auth/flutter/anonymous-auth>
- Unity Authentication Anonymous Sign-In: <https://docs.unity.com/en-us/authentication/use-anon-sign-in>
- PlayFab Login Best Practices: <https://learn.microsoft.com/en-us/gaming/playfab/identity/player-identity/login/login-basics-best-practices>
- Android User Data IDs Best Practices: <https://developer.android.com/identity/user-data-ids>
- EOS Connect / Device ID related guidance: <https://onlineservices.epicgames.com/news/accessing-eos-game-services-with-the-connect-interface>
- OAuth 2.0 Device Authorization Grant: <https://www.rfc-editor.org/rfc/rfc8628>

## 4. 推荐的身份模型

推荐将当前平台身份明确拆成三层：

### 4.1 稳定账号主体 `user_id`

用途：

- 房间成员归属
- 房主归属
- 占座/重连/恢复
- 战绩和历史归属
- 账号升级前后的统一玩家主体

要求：

- guest 与 member 都必须有 `user_id`
- guest 升级为 member 时，`user_id` 不变
- 任何联机权限判断都只依赖 `user_id`，不依赖 `session_id`

### 4.2 短期会话 `session_id`

用途：

- API 认证
- 平台请求授权
- 可失效、可轮换

要求：

- 过期后允许重新签发
- session 失效不代表账号主体失效
- guest session 失效后，允许通过安装锚点静默恢复到同一 `user_id`

### 4.3 安装实例锚点 `installation_id`

用途：

- 用于找回“这台机器这个本地实例”的游客身份
- 不参与联机权限判断
- 只用于匿名登录与恢复游客主身份

实现建议：

- 直接复用当前客户端 `device_id`
- 在命名上改为 `installation_id` 更准确
- 服务端只存其 hash，不存原值

要求：

- 本地持久化
- 清缓存/删存档/重装后允许丢失
- 不使用硬件指纹、MAC、IMEI、序列号等高风险标识
- 支持你们当前的多开 profile 机制，不把“同机多开”强行视为同一游客

## 5. 推荐的账号状态机

建议把账号主体状态定义为：

- `guest_active`
- `member_active`
- `disabled`

同时把安装锚点状态定义为：

- `guest_auto_login_enabled`
- `guest_auto_login_disabled`

关键规则如下：

### 5.1 游客首次进入

- 客户端本地无 session，携带 `installation_id`
- 服务端若找不到映射，则创建新 guest `user_id`
- 返回新的 `session_id`

### 5.2 游客再次进入

- 客户端 session 失效或不存在
- 服务端根据 `installation_id` 找到原 guest `user_id`
- 返回同一 `user_id` 的新 `session_id`

### 5.3 游客升级正式账号

- 不新建用户
- 在原 guest `user_id` 上绑定邮箱/设备授权/第三方登录
- `is_guest` 从 `true` 切为 `false`
- 保留原玩家数据、房间归属、历史归属

### 5.4 正式账号显式退出

这是最容易做错的部分。

若游客升级成功后仍保留“安装锚点自动找回该账号”，那么用户点击“退出登录”后，下次进入联机又会被自动登录回原正式账号，这会让“退出登录”失去意义。

因此建议：

- guest 升级为 member 后，默认关闭该 `installation_id` 的 guest 自动找回能力
- 用户显式退出 member 后，本地只保留 `installation_id`
- 下次自动进入联机时，如果产品仍要“自动游客进入”，应创建新的 guest 或恢复仍处于 guest 状态的账号
- member 重新登录应依赖明确的登录凭据，而不是游客自动找回

这条规则可以兼顾：

- 游客体验低摩擦
- 正式账号退出语义清晰
- 不会“悄悄自动把正式账号重新登上去”

## 6. 推荐的数据模型

推荐的后端最小数据结构如下。

### 6.1 `users`

- `user_id`
- `is_guest`
- `display_name`
- `created_at`
- `upgraded_at`
- `status`

### 6.2 `auth_sessions`

- `session_id`
- `user_id`
- `issued_at`
- `expires_at`
- `revoked_at`
- `client_meta`

### 6.3 `identity_links`

- `link_id`
- `user_id`
- `provider_type`
- `provider_key_hash`
- `provider_key_last4`
- `auto_login_enabled`
- `created_at`
- `disabled_at`

其中：

- `provider_type = installation` 用于游客找回
- `provider_type = email` 用于邮箱账号
- 后续可扩展 `steam`、`apple`、`google`、`epic` 等

### 6.4 索引与约束

- `users.user_id` 唯一
- `auth_sessions.session_id` 唯一
- `identity_links(provider_type, provider_key_hash)` 唯一
- 一个 `installation` 链接最多绑定一个当前有效账号主体

## 7. 推荐接口契约

## 7.1 `POST /v1/auth/guest`

请求：

```json
{
  "installation_id": "local-guid",
  "previous_guest_user_id": "u_xxx",
  "profile_id": "optional-local-profile"
}
```

说明：

- `installation_id` 为必填
- `previous_guest_user_id` 为可选，用于迁移旧客户端与冲突恢复
- `profile_id` 仅用于排障与多开观测，不应用作最终身份主键

响应：

```json
{
  "user_id": "u_xxx",
  "session_id": "s_xxx",
  "is_guest": true,
  "display_name": "游客#1234",
  "session_expires_at": "2026-04-05T12:34:56Z"
}
```

服务端行为建议：

1. 若 `installation_id` 已绑定到一个仍为 guest 的账号，则返回该账号的新 session。
2. 若 `previous_guest_user_id` 存在且合法，且当前没有冲突映射，可把该安装锚点认领回这个 guest。
3. 若锚点已绑定到已升级 member 的账号，则不要自动把该 member 重新登录回来。
4. 若以上都不满足，则新建 guest。

## 7.2 `POST /v1/auth/bind`

语义必须是：

- 给当前 `session_id` 所代表的同一个 `user_id` 绑定新登录方式
- 不生成新的 `user_id`

成功响应中应明确返回：

- 同一 `user_id`
- 新的 `session_id`
- `is_guest = false`
- 更新后的 `display_name`

## 7.3 `GET /v1/auth/me`

建议把这个接口真正纳入客户端会话校验流程。

用途：

- 校验本地缓存的 `session_id` 是否仍有效
- 拉取服务端标准化后的 `display_name` 与 `is_guest`
- 避免客户端把过期 session 错当“已登录”

## 8. 客户端推荐改造

## 8.1 客户端术语调整

建议在代码语义上逐步把：

- `device_id` 视为 `installation_id`

短期内可不改字段名，以避免大规模改动；但文档和接口语义建议统一成“安装实例锚点”。

## 8.2 `PlatformSession.auto_guest_login()`

推荐改成如下流程：

1. 若存在 `session_id`，先调用 `get_me(session_id)`。
2. 若 `get_me` 成功：
   - 同步 `user_id`
   - 同步 `is_guest`
   - 同步 `display_name`
   - 返回成功
3. 若 `get_me` 失败且是 401：
   - 若当前是 guest，则清除本地 `session_id`，保留 `installation_id` 与 guest `user_id`
   - 重新调用 `guest_login(installation_id, previous_guest_user_id)`
4. 若 `get_me` 失败且当前是 member：
   - 清除失效 session
   - 不做游客静默重登
   - 返回“登录已失效，需要重新登录”
5. 若本地根本没有 `session_id`：
   - 直接走 `guest_login`

这样做后，session 与身份主键就彻底分离了。

## 8.3 冷启动恢复与大厅恢复

当前恢复逻辑保存了 `resume_context.user_id`，这是正确方向。

推荐改成：

1. 先保证拿到有效 session
2. 再比较 `resume_context.user_id` 与当前激活 `user_id`
3. 若 guest 因 session 失效而被静默恢复回同一 `user_id`，继续恢复
4. 只有在“当前真实激活账号主体不同”时，才清理恢复上下文

## 8.4 玩家名展示规则

建议统一如下：

- 账号条显示“账号类型 + display_name”，必要时附短 `user_id`
- 房间内玩家名显示 `profile.name`
- 对 guest，如后端已返回 `display_name`，优先使用服务端值，不再本地二次拼接

建议的展示优先级：

1. `PlatformSession.display_name`
2. 本地 profile 中用户明确设置的名字
3. 基于 `user_id` 后缀的本地兜底名

## 8.5 显式退出与重置游客

建议拆分两个动作：

- `退出登录`
- `重置本地游客身份`

语义如下：

- `退出登录`：清掉当前 session，但保留本地 `installation_id`
- `重置本地游客身份`：清掉本地 `installation_id`、guest `user_id`、session，下一次进入会创建新 guest

这样用户才知道自己是在：

- 退出正式账号
- 还是主动放弃当前游客身份

## 9. 迁移方案

建议分两阶段上线。

### 阶段 A：后端先兼容

- 后端给 `/v1/auth/guest` 增加稳定映射逻辑
- 接收 `installation_id`
- 接收可选 `previous_guest_user_id`
- 不改客户端 UI，也能让同安装游客稳定回到同一账号

### 阶段 B：客户端补齐会话恢复

- `auto_guest_login()` 接入 `get_me`
- guest 401 后静默重登
- member 401 后提示重新登录
- 修正恢复策略和 UI 展示逻辑

### 阶段 C：语义清理

- 文档与接口逐步从 `device_id` 迁移为 `installation_id`
- 增加“重置本地游客身份”
- 补测试覆盖

## 10. 建议的服务端伪代码

```text
guest_login(installation_id, previous_guest_user_id):
  assert installation_id not empty
  link = find_active_installation_link(hash(installation_id))

  if link exists:
    user = find_user(link.user_id)
    if user.status != active:
      disable link
    else if user.is_guest:
      return issue_session(user)
    else:
      return create_fresh_guest_or_require_explicit_login()

  if previous_guest_user_id exists:
    user = find_user(previous_guest_user_id)
    if user exists and user.is_guest and user.status == active:
      attach_installation_link(user, installation_id)
      return issue_session(user)

  user = create_guest_user()
  attach_installation_link(user, installation_id)
  return issue_session(user)
```

## 11. 当前实现检查

以下是基于当前代码的检查结论。

### 11.1 严重问题：本地 session 未校验就被视为“已登录”

现状：

- `PlatformSession.auto_guest_login()` 只要本地有 `session_id` 就直接返回成功，不调用 `get_me`
- 大厅和冷启动恢复的 `ensure_session` 都依赖这个行为

结果：

- UI 可能显示“平台已就绪”，但后续任何平台请求才暴露 401
- 游客本可静默恢复到原 `user_id`，却被晚一点的请求判成登录失效

影响：

- 房间列表刷新失败
- 创建/加入房间失败
- 冷启动恢复误判失败

### 11.2 严重问题：恢复流程把 401 当永久失败，但前面并没有先做 guest 静默重登

现状：

- 恢复错误策略把 401 直接判为永久失败并清理恢复上下文
- 但 `ensure_session` 并不会在 401 前先验证/刷新 guest session

结果：

- guest 仅仅因为 session 过期，就可能被清掉本地恢复资格
- 这与“同一玩家同一台机器应认回原账号”的目标冲突

### 11.3 明确 bug：认证对话框会泄漏“绑定邮箱”状态

现状：

- `open_for_bind()` 会隐藏 tab、改标题、切到绑定态
- 普通 `open()` 没有把这些 UI 状态恢复成默认登录/注册态

结果：

- 先打开过“绑定邮箱”后，下次再打开认证对话框，有概率仍停留在绑定态

### 11.4 显示问题：游客 `display_name` 被大厅逻辑忽略

现状：

- 大厅玩家名解析只对 member 使用 `PlatformSession.display_name`
- 对 guest 一律本地拼 `游客#xxxx`

结果：

- 后端若返回统一规范的 guest `display_name`，前端不会使用
- 客户端和服务端可能各自拼不同名字
- 后续若要做“游客昵称稳定化”会被前端逻辑抵消

### 11.5 显示问题：账号栏显示的是短 `user_id`，不是面向用户的名字

现状：

- 账号状态栏当前显示“游客 xxxxxxxx”或“已登录 xxxxxxxx”
- 这里的值来自 `user_id` 截断，而不是 `display_name`

结果：

- 对玩家来说不够直观
- 已升级账号也看不到自己的昵称

### 11.6 状态一致性问题：logout 未清理 `NetContext.player_profile.user_id`

现状：

- 登录时会把 `user_id` 写入 `NetContext.player_profile`
- logout 时不会清掉该字段

结果：

- 本地 profile 中可能残留过期账号标识
- 当前大部分联机路径会被 connect token 覆盖，所以短期风险有限
- 但这是不必要的脏状态源

### 11.7 不是 bug，但属于产品缺口：注册流程不采集昵称

现状：

- 注册接口支持可选 `display_name`
- 当前认证对话框注册页没有昵称输入

结果：

- 新注册用户首次看到的昵称通常仍是默认名
- 需要登录后再改昵称

这不是正确性问题，但会影响体验。

## 12. 建议修复顺序

建议按下面顺序实施。

### P0

- 后端 `/v1/auth/guest` 改为稳定 guest 主身份映射
- 客户端 `auto_guest_login()` 接入 `get_me` 与 guest 401 静默重登
- 恢复流程在 guest session 过期时不再直接清理 resume context

### P1

- 修复认证对话框 bind 状态泄漏
- logout 时同步清理 `NetContext.player_profile.user_id`
- 账号栏改为优先显示 `display_name`

### P2

- guest 也优先显示服务端 `display_name`
- 增加“重置本地游客身份”
- 视需要在注册页加入昵称输入

## 13. 建议补充测试

至少补下列自动化测试：

- 同一 `installation_id` 两次 guest 登录返回同一 `user_id`
- guest session 过期后 `auto_guest_login()` 能回到同一 `user_id`
- member session 过期后不会被游客自动重新登录为原 member
- guest bind 后 `user_id` 不变、`is_guest` 变为 `false`
- 恢复上下文中的 `user_id` 与静默恢复后的 guest `user_id` 一致时，应继续恢复
- 认证对话框 `open_for_bind()` 后再次普通 `open()` 应回到默认登录态
- logout 后 `NetContext.player_profile` 不残留旧 `user_id`

## 14. 对当前项目的直接映射

就当前仓库而言，建议把现有字段理解为：

- `PlatformSession.user_id` = 稳定账号主体
- `PlatformSession.session_id` = 短期会话
- `PlatformSession.device_id` = 安装实例锚点

也就是说，当前代码不是方向错了，而是只差最后一步：

- 把 `device_id -> guest user_id` 的稳定映射做完整
- 把 `session_id` 从“主身份”彻底降级为“可刷新登录态”

一旦完成这一步，你们的联机占座、断线恢复、冷启动恢复都会自然稳定下来。
