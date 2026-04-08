# 账号展示与登录逻辑一致性审计

最后更新：2026-04-04

## 范围

本审计对比以下四个面：

- Godot 游戏客户端
- Godot Web 游戏
- Portal 网站前端 `web/portal`
- 平台后端 `backend/app/auth.py`

重点检查：

- 游客与正式账号身份是否一致
- 网站与游戏共享登录态是否稳定
- 邮箱绑定状态是否一致
- 游戏内账号设置与网站账号设置是否对齐

补充说明：

- 当前产品定义中，邮箱只作为登录凭据与绑定信息使用
- 不引入邮箱验证流程
- 因此账号状态只区分“未绑定邮箱”和“已绑定邮箱”

## 结论概览

截至本次审计，账号一致性的核心问题已经完成收敛：

1. Portal 与 Godot Web 共享登录态所需字段已经补齐，并具备跨标签页/回到前台同步能力
2. 游客身份已经基于持久化 `device_id` 稳定映射，不会因为再次进入而漂移成新账号
3. 游戏端已经消费 `/auth/me`，能够正确显示昵称、账号类型、邮箱状态、`user_id` 与注册时间
4. 游戏端与网站端都支持游客绑定邮箱、正式账号修改昵称/邮箱/密码，以及显式退出登录

当前剩余的事项不再是产品逻辑缺口，而是运维与历史数据层面的收尾：

- 历史数据库中的“已升级账号仍残留 guest identity”需要按运维窗口执行清理脚本

## 1. 后端账号事实源

后端 `/v1/auth/me` 当前返回：

- `user_id`
- `display_name`
- `email`
- `is_guest`
- `is_admin`
- `created_at`

代码位置：

- [auth.py](/Users/qinkai/Documents/FCM_new/backend/app/auth.py)

这组字段已经足够支撑当前产品定义下的账号展示，不再依赖额外的“邮箱验证态”。

## 2. 游客身份稳定性

当前游客身份模型已经满足“同一安装实例/同一浏览器缓存环境内稳定复用”的目标：

- 原生客户端会持久化 `device_id`
- Portal 会持久化 `fcm_device_id`
- Portal 游客登录会复用已有 `device_id`
- 后端会基于同一 `device_id` 返回同一游客 `user_id`
- 游客绑定邮箱后会移除 guest identity，后续再以游客进入时会创建新的游客账号

相关实现位置：

- [platform_session.gd](/Users/qinkai/Documents/FCM_new/autoload/platform_session.gd)
- [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts)
- [auth.py](/Users/qinkai/Documents/FCM_new/backend/app/auth.py)

## 3. 网站与游戏共享登录态

当前 Portal 与 Godot Web 已共享以下关键字段：

- `session_id`
- `user_id`
- `is_guest`
- `display_name`
- `device_id`
- `email`
- `is_admin`
- `created_at`

同步策略：

- Portal 监听 `storage`、`focus`、`visibilitychange`
- Godot Web 监听浏览器 `storage` 与应用回到前台
- 游戏端会在已有 `session_id` 时调用 `/auth/me` 刷新资料，并在 session 失效时正确清理状态

这意味着：

- 在网站登录后打开网页游戏，昵称和账号资料能够正确继承
- 在网站退出登录后，网页游戏也会同步失去登录态
- session 过期时，不会再出现“本地看起来还登录，但实际后端已失效”的错配

## 4. 网站端账号展示

Portal 账号设置页当前展示：

- 昵称
- 用户 ID
- 邮箱
- 邮箱状态（未绑定/已绑定）
- 账号类型（游客/正式）
- 注册时间

并提供：

- 游客绑定邮箱
- 正式账号修改昵称
- 正式账号修改邮箱
- 正式账号修改密码
- 退出登录

代码位置：

- [SettingsView.vue](/Users/qinkai/Documents/FCM_new/web/portal/src/views/SettingsView.vue)
- [auth.ts](/Users/qinkai/Documents/FCM_new/web/portal/src/stores/auth.ts)

## 5. 游戏端账号展示

联机大厅当前分成两层展示：

### 5.1 大厅状态栏

展示紧凑摘要：

- 昵称
- 账号类型
- 邮箱绑定状态
- 管理员标记（如适用）

代码位置：

- [online_lobby.gd](/Users/qinkai/Documents/FCM_new/ui/scenes/online/online_lobby.gd)

### 5.2 账号详情面板

点击账号按钮后，游戏内会打开统一的账号详情面板：

- 游客账号：
  - 昵称
  - 用户 ID
  - 账号类型
  - 邮箱
  - 邮箱状态
  - 注册时间
  - 绑定邮箱入口
- 正式账号：
  - 昵称
  - 用户 ID
  - 账号类型
  - 邮箱
  - 邮箱状态
  - 注册时间
  - 修改邮箱
  - 修改密码
  - 退出登录

代码位置：

- [account_settings_dialog.gd](/Users/qinkai/Documents/FCM_new/ui/dialogs/account_settings_dialog.gd)
- [auth_dialog.gd](/Users/qinkai/Documents/FCM_new/ui/dialogs/auth_dialog.gd)

## 6. 注册与登录能力对齐情况

当前网站端与游戏端已经完成以下对齐：

- 注册支持可选昵称
- 游客可升级绑定邮箱
- 正式账号可修改密码
- 正式账号可修改邮箱
- 登录态失效后可自动刷新或清理
- 退出登录会调用后端 `/auth/logout`

这意味着“网站能做、游戏不能做”的账号基础操作已经基本消除。

## 7. 剩余问题

当前仅剩一个需要线下处理的事项：

- 历史清理：
  - 旧数据里可能仍存在“账号已升级，但 guest identity 尚未清掉”的记录
  - 代码侧已经提供清理脚本与测试，但是否执行 `--apply` 需要按运维窗口决定

相关文件：

- [guest_identity_cleanup.py](/Users/qinkai/Documents/FCM_new/backend/app/guest_identity_cleanup.py)
- [cleanup_guest_identities.py](/Users/qinkai/Documents/FCM_new/backend/scripts/cleanup_guest_identities.py)

## 8. 验证记录

与本轮账号一致性修复直接相关的验证已经通过：

- `backend/.venv/bin/python -m pytest -q backend/tests/test_auth.py`
- `npm run build` in `web/portal`
- Godot `check_compile.gd`
- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 90`

## 9. 最终判断

从仓库当前源码看：

- 账号事实源已经统一到后端 `/auth/me`
- 游客身份稳定性问题已经修复
- 网站与游戏的共享登录态问题已经修复
- 游戏内账号展示与网站账号设置已经基本对齐
- 当前不再存在必须继续开发的账号一致性 P0 / P1 缺口

后续如果要继续扩展，优先级应转向：

- 运维执行历史 guest identity 清理
- 如果未来产品需要，再补充更多账号提供商接入，而不是继续扩展邮箱语义
