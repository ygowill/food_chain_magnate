# 规则教学模式 / 新手引导设计（MVP）

## 目标

- 在主菜单提供独立的**规则教学**入口，与普通“本地游戏”分离。
- 优先解决两个问题：
	1. 玩家**不知道界面各区域/按钮是做什么的**。
	2. 玩家**不知道当前阶段接下来应该做什么**。
- 为第一次接触规则的玩家提供一个**预定义教学局**：
	- 2 人
	- 固定种子
	- 教学预设
	- 局内按流程给出更短、更具体的阶段提示
- 复用现有系统：
	- `ui/components/help_tooltip/help_tooltip_manager.gd`
	- `ui/components/action_panel/action_panel.gd`
	- `ui/scenes/game/overlay/controller.gd`
	- `ui/components/module_selector/module_selector.gd`

## 分层方案

### 1. 主菜单独立入口

触发时机：

- 玩家在主菜单点击“规则教学”
- 入口位置：位于“本地游戏”按钮下方

能力：

- 直接进入 `res://ui/scenes/setup/game_setup.tscn`
- 自动应用教学局预设
- 自动开始 Setup Tour
- 普通“本地游戏”入口不再自动弹出教学相关内容

### 2. 设置页导览（Setup Tour）

导览目标：

1. 玩家数量区
2. 游戏选项 / 教学局预设
3. 模块区
4. 开始游戏按钮

目标：

- 让玩家理解：
	- 当前已进入规则教学模式
	- 教学局会自动应用固定配置
	- 设置完成后从哪里开始游戏

### 3. 局内界面导览（Game UI Tour）

触发时机：

- 玩家从主菜单进入“规则教学”，并在 Setup 中点击“开始游戏”
- 进入 `res://ui/scenes/game/game.tscn`
- 首个本地新局的 startup intro 结束后

导览目标：

1. 顶部状态栏（回合 / 阶段 / 银行）
2. 左上角玩家概览（所有玩家现金 / 员工 / 餐厅 / 里程碑）
3. 左侧库存区
4. 左侧员工 / 公司结构摘要区
5. 左侧里程碑区
6. 中央地图
7. 右侧动作面板
8. 右侧日志按钮
9. 右侧里程碑按钮
10. 右侧升级路线按钮
11. 右侧供应堆按钮
12. 右侧储备卡按钮
13. 右侧距离工具按钮
14. 右侧工具栏总览

目标：

- 让玩家知道“看哪里”“从哪里做事”
- 不试图一次讲完所有规则
- 只高亮当前布局下**真实可见**的 UI，不引用默认隐藏的旧面板/宿主容器
- 不主动展开当前布局中默认隐藏的底部容器；公司结构相关说明放到后续重组阶段教学中处理

### 3.1 重组阶段补充导览（新增）

触发时机：

- 首次进入 `Restructuring` 阶段
- 重组弹窗已经真实打开
- 仅限本地局 / 热座模式

导览目标：

1. 上方玩家切换区
2. 左侧待命员工 / 可用卡牌区
3. 右侧公司结构编辑区
4. 底部确认 / 一键填充按钮

目标：

- 把“公司结构 / 员工卡牌”的教学放到**真正操作它们的时机**
- 明确说明它们不会在正常主界面底部常驻显示

### 4. 分阶段流程教练（后续迭代）

建议后续补齐：

- Setup：放初始餐厅
- Restructuring：安排本回合上岗员工
- Order of Business：选择顺位
- Working：招聘 / 培训 / 营销 / 生产 / 采购 / 放置
- Dinnertime：解释顾客如何选择餐厅

当前已经补上：

- 顺位选择弹窗导览
- 餐厅放置导览（合法点、高亮、旋转、确认前可修改）
- 教学局模式下按子阶段推进的流程提示

### 4.1 当前已升级为“阶段目标清单卡”

当前实现不再只给一段说明文字，而是补充：

- 阶段标题
- 先看哪里（地图 / 动作面板 / 日志 / 重组弹窗等）
- 2~3 条本阶段建议操作清单

这样玩家进入首轮关键阶段时，可以更快知道：

- 现在主要目标是什么
- 应该先看哪个区域
- 接下来先做哪几件事

### 4.2 教学局模式（当前版本）

当前不是完全自定义脚本关卡，而是一个**固定配置的教学局**：

- Setup 勾选后自动应用：
	- `2` 人
	- 固定 seed：`20260411`
	- 默认模块
	- 教学预设 patch：
		- `bank.default_per_player = 75`
		- `rules.salary_cost = 0`
		- `rules.bankruptcy_max_breaks = 1`
		- `rules.bankruptcy_extra_reserve_per_player = 0`
		- `setup.auto_select_reserve_cards = true`
		- `milestones.enabled = false`
- 局内改用 `tutorial_match_content.gd`
	- 主界面导览更短
	- 按阶段与 Working 子阶段逐步提示
	- 重点解释员工作用、营销、库存、放置与结算观察点
- 开始游戏时会再次强制应用该预设
	- 避免玩家中途改动人数、seed 或规则后，导致教学内容与局面脱节
- 除了阶段提示卡外，还会在关键面板出现时补充上下文导览：
	- 招聘面板
	- 培训面板
	- 营销面板
	- 食物生产面板
	- 饮料采购面板
- 第一轮结束、第二轮开始时，会给一张总结卡，明确告诉玩家已经掌握哪些基础概念
这让首局体验更接近“边玩边学”，而不是一开始塞给玩家大量静态说明。

### 4.3 当前版本新增补充

- 招聘教学不再建议玩家先看供应堆，而是先打开员工升级路线。
- 员工升级路线导览开始前，会先自动执行“适应宽度”，保证卡片与连线足够清晰。
- 员工升级路线新增独立导览：
	- 说明员工树用途
	- 说明卡片顶部色条与名称
	- 说明右上角剩余数量
	- 说明左下角 `1` / `1x`
	- 说明底部中间距离图标与右下角薪水标志
	- 说明正文能力描述
	- 说明连线代表培训方向
- 员工卡剩余信息统一改为只显示右上角数字，不再额外显示“剩余”文字。
- 供应堆按钮的说明改为公共组件与 token 的剩余情况，不再误导为员工卡供应；员工卡剩余数量统一从升级路线查看。
- 放置餐厅前，先补充距离算法说明：
	- 距离通常沿道路计算
	- 统计的是跨过的地图板块边界数
	- 从餐厅出发时，以入口为起点
	- 顾客优先去最近且能满足需求的餐厅
	- 若距离相同，再按回合顺序决定
- 当当前阶段已经没有更多可执行动作时，动作面板会显示说明卡，明确告知：
	- 当前不是界面错误
	- 可以点击“确认结束”继续流程
	- 或使用“回退到回合开始”重新安排
- 教学局流程提示与上下文导览，现已补齐以下规则口径：
	- 重组公司：CEO 必在岗，经理层级限制，超卡槽回待命
	- 决定顺位：按空余卡槽决定先选，平手按上一轮顺位，补充飞机广告里程碑例外
	- 招聘：只招入门员工，进入待命区，本轮不能直接上岗，补充“空堆先招后立刻培训”例外
	- 培训：来源卡回供应区，只要求最终岗位有卡，招聘与培训是两个独立动作
	- 营销：每名营销员一次一项营销，只宣传单一产品，持续时间与忙碌状态说明
	- 食物与饮料：全公司共享库存，补充采购员不能 U 型折返及同图标取货限制
	- 房屋与花园：补充房屋需求上限、花园需求上限与花园结算加成
	- 餐厅放置与移动：补充起始餐厅限制、Working 阶段不再受入口板块限制，以及 drive-thru 规则
	- 晚餐结算：补充房屋编号顺序、完整比较链、花园、女服务员、CFO 与银行破产说明
	- 发薪 / 营销 / 清理：补充解雇顺序、薪水折扣、广告持续结算、库存清理、员工回手牌与里程碑移除
	- 员工卡与里程碑：补充 `1`、`1x`、经理、薪水、距离图标、剩余数量、里程碑立即生效与关键示例
	- 组件与储备卡：补充现金公开、纸板组件有限、储备卡按当前卡面与当前模式说明解释

## 当前代码结构（已落地）

当前教学实现已经按“通用层 + 场景层”拆分：

- 通用导览容器
	- `ui/tutorial/tutorial_controller.gd`
- Setup 场景教学编排
	- `ui/scenes/setup/controllers/tutorials_controller.gd`
	- `ui/scenes/setup/controllers/tutorial_content.gd`
	- `ui/scenes/setup/controllers/tutorial_targets_resolver.gd`
- Game 场景教学编排
	- `ui/scenes/game/controllers/tutorials_controller.gd`
	- `ui/scenes/game/controllers/tutorial_content.gd`
	- `ui/scenes/game/controllers/tutorial_match_content.gd`
	- `ui/scenes/game/controllers/tutorial_targets_resolver.gd`
- Spotlight UI
	- `ui/components/tutorial/tutorial_spotlight_overlay.tscn`
	- `ui/components/tutorial/tutorial_spotlight_overlay.gd`
- Flow hint UI
	- `ui/components/tutorial/tutorial_flow_hint_card.tscn`
	- `ui/components/tutorial/tutorial_flow_hint_card.gd`
- 主菜单入口
	- `ui/scenes/main_menu.tscn`
	- `ui/scenes/menus/main_menu.gd`

更详细的职责边界见：

- `docs/architecture/22-ui-onboarding-tutorials.md`

## 持久化字段

建议统一存入 `user://settings.cfg`：

### `tutorial` section

- `progress_version: int`
- `setup_tour_seen: bool`
- `game_ui_tour_seen: bool`
- `flow_hints_seen: Array[String]`

### 运行时（不持久化）

- `tutorial_pending_setup_tour`
- `tutorial_pending_game_ui_tour`
- `tutorial_pending_flow_tutorial`
- `tutorial_match_enabled`

## MVP 落地范围

本次先实现：

1. 文档落盘到 `docs/`
2. 教学设置持久化
3. 主菜单独立规则教学入口
4. Setup Tour
5. Game UI Tour
6. 设置页开关 + 重置教学进度
7. 轻量流程提示卡（首轮关键阶段）
8. 教学局预设 + 分阶段教学内容切换

暂不实现：

- 分阶段流程教练完整内容（例如逐动作互动式剧本）
- 完全自定义初始状态的独立教学脚本局
- 晚餐结算的因果解释卡

## 文件落点

### 新增

- `ui/components/tutorial/tutorial_spotlight_overlay.tscn`
- `ui/components/tutorial/tutorial_spotlight_overlay.gd`
- `ui/components/tutorial/tutorial_flow_hint_card.tscn`
- `ui/components/tutorial/tutorial_flow_hint_card.gd`
- `ui/tutorial/tutorial_controller.gd`
- `ui/scenes/setup/controllers/tutorials_controller.gd`
- `ui/scenes/setup/controllers/tutorial_content.gd`
- `ui/scenes/setup/controllers/tutorial_targets_resolver.gd`
- `ui/scenes/game/controllers/tutorials_controller.gd`
- `ui/scenes/game/controllers/tutorial_content.gd`
- `ui/scenes/game/controllers/tutorial_match_content.gd`
- `ui/scenes/game/controllers/tutorial_targets_resolver.gd`
- `ui/scenes/tests/setup_tutorial_targets_contract_test.gd`
- `ui/scenes/tests/game_tutorial_targets_contract_test.gd`
- `ui/scenes/tests/tutorial_scene_boundary_contract_test.gd`
- `docs/tutorial_onboarding_design.md`

### 修改

- `autoload/globals.gd`
- `ui/scenes/main_menu.tscn`
- `ui/scenes/menus/main_menu.gd`
- `ui/scenes/setup/game_setup.gd`
- `ui/components/module_selector/module_selector.gd`
- `ui/scenes/game/game.gd`
- `ui/dialogs/settings_dialog.gd`
- `ui/dialogs/settings_dialog.tscn`
- `ui/scenes/game/overlay/controller.gd`

## 设计原则

- **先讲界面，再讲规则**：MVP 先让用户不迷路。
- **可跳过、可关闭、可重置**：不强制灌输。
- **一次只讲一个焦点**：避免大段文字。
- **优先复用现有系统**：帮助提示、guided action、设置持久化。
- **不影响联机 / 回放 / 恢复局**：只针对主菜单显式进入的规则教学模式。
