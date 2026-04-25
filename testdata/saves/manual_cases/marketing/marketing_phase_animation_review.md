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
- 本场景使用项目真实随机板块地图（保留 tile_placements），避免极简测试地图在 UI 中缺少正常地图渲染上下文。
- 本场景包含四种基础广告：radio #1、airplane #6、mailbox #7、billboard #14，结算顺序按 board_number 升序。
- 四个广告均设置为 3 回合，结算后仍剩余 2 回合并保留在 map.marketing_placements 中，便于复核广告件本体渲染。
- 自动选择的放置参数：[{ "label": "radio #1", "params": { "employee_type": "brand_director", "board_number": 1, "product": "soda", "duration": 3, "position": [6, 5], "rotation": 0 }, "affected_houses": ["2", "12", "4", "5", "15"] }, { "label": "airplane #6", "params": { "employee_type": "brand_manager", "board_number": 6, "product": "beer", "duration": 3, "position": [0, 9], "rotation": 0 }, "affected_houses": ["12", "5", "4", "15"] }, { "label": "mailbox #7", "params": { "employee_type": "campaign_manager", "board_number": 7, "product": "pizza", "duration": 3, "position": [10, 8], "rotation": 0 }, "affected_houses": ["12"] }, { "label": "billboard #14", "params": { "employee_type": "campaign_manager", "board_number": 14, "product": "burger", "duration": 3, "position": [6, 11], "rotation": 90 }, "affected_houses": ["5"] }]

## 复核步骤

1. 从主菜单载入本存档，进入游戏画面后不要手动推进阶段。
2. 确认地图为正常随机板块地图，且地图上能看到四类营销广告件。
3. 观察营销结算控制条与地图动画：广告牌应按 #1 radio、#6 airplane、#7 mailbox、#14 billboard 的顺序播放。
4. 等待动画自动结束后，点击右侧动作区的「确认营销结算」继续推进到后续阶段。

## 预期结果

- #1 radio：电波动画在需求发射期间持续循环，soda 需求逐个飞向覆盖范围内房屋。
- #6 airplane：飞机广告板件缓慢飞过地图，并在飞行途中以投放方式向覆盖房屋丢下 beer 需求。
- #7 mailbox：pizza 对同街区房屋生效，不再额外显示持续时间变化提示。
- #14 billboard：burger 对相邻房屋生效，不再额外显示持续时间变化提示。
- 动画结束前右侧动作区可跳过营销结算；动画结束后才可确认营销结算，确认后 pending_phase_actions[Marketing] 被清除。

## 关联单元测试

- `core/tests/manual_marketing_review_save_test.gd`
- `core/tests/marketing_campaigns_test.gd`
- `core/tests/confirm_marketing_availability_test.gd`
- `ui/scenes/tests/marketing_animation_orders_builder_test.gd`
