# marketing/marketing_phase_animation_review - 营销阶段动画复核

## 存档

- JSON: `res://testdata/saves/manual_cases/marketing/marketing_phase_animation_review.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Marketing/ (round=1 current_player=0)

## 目的

- 载入后直接停在 Marketing 阶段，用于手工复核营销广告按 board_number 顺序自动播放结算动画。

## 情景设计

- 存档已冻结在 Marketing 阶段，并保留 confirm_marketing pending；图形界面载入后应启动营销结算动画，而不是立刻跳过。
- 本场景包含四种基础广告：radio #1、airplane #4、mailbox #7、billboard #11，结算顺序按 board_number 升序。
- 右侧房屋在结算前已预填到普通需求上限，用于复核 mailbox/封顶反馈；其他房屋用于复核飞行动画、范围高亮和持续时间变化。

## 复核步骤

1. 从主菜单载入本存档，进入游戏画面后不要手动推进阶段。
2. 观察营销结算控制条与地图动画：广告牌应按 #1 radio、#4 airplane、#7 mailbox、#11 billboard 的顺序播放。
3. 等待动画自动结束，确认游戏会执行 confirm_marketing 并继续推进到后续阶段。

## 预期结果

- #1 radio：soda 需求以扩散动画飞向覆盖范围内房屋，并显示持续时间 2 > 1。
- #4 airplane：beer 沿第 10 行的飞机条带生效，随后显示失效。
- #7 mailbox：目标房屋已达到需求上限，应显示封顶/未增加的反馈，随后显示失效。
- #11 billboard：burger 飞向相邻房屋，并显示持续时间 2 > 1。
- 动画结束后 pending_phase_actions[Marketing] 被清除，阶段不再卡在 Marketing。

## 关联单元测试

- `core/tests/marketing_campaigns_test.gd`
- `core/tests/confirm_marketing_availability_test.gd`
- `ui/scenes/tests/marketing_animation_orders_builder_test.gd`
