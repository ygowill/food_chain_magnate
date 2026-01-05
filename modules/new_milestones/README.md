# 模块：全新里程碑（New Milestones）

来源：`docs/FCM_ketchup_Regels_English_web_2.pdf_by_PaddleOCR-VL.md` 的 “New Milestones” 章节。

## 内容

- `content/milestones/*.json`：替换基础里程碑的一套新里程碑（不包含 ketchup/coffee/rural/lobbyist 的里程碑；这些由各自模块提供）。

## 已实现

- `first_marketeer_used`：Marketing 每放置 1 个需求 +$5（仅由营销员放置的营销板件）；Dinnertime 距离 -2 且允许为负（可与番茄酱叠加）。
- `first_new_restaurant`：首次在 Working 阶段放置新餐厅后，可在 Working/PlaceRestaurants 放置一个“免费永久 mailbox”（占用 mailbox #5-#10，不绑定营销员，必须与自家餐厅在同一 mailbox block）。
- `first_marketing_trainee_used`：获得 `kitchen_trainee` 与 `errand_boy` 各 1 张（进入储备区，无法立刻培训）。
- `first_campaign_manager_used`：获得里程碑的同回合内可额外放置第二张同类型（billboard/mailbox）板件（同商品/同持续时间）；第二张通过动作 `place_campaign_manager_second_tile` 放置；营销员在两张板件都到期后才返回。
- `first_brand_manager_used`：获得里程碑的同回合内，若 brand_manager 放置 airplane，可通过动作 `set_brand_manager_airplane_second_good` 为该飞机追加第二种商品（A→B 顺序结算，不可叠加/不可保存）。
- `first_brand_director_used`：你放置的 radio 永久（duration=-1）；brand_director 忙碌到游戏结束（营销到期也不返回）。
- `first_burger_sold`：首次在晚餐中卖出汉堡后，CEO 卡槽至少为 4（不受储备卡影响；本实现每次晚餐结算后修正为 `max(current, 4)`）。
- `first_coke_sold`：首次在晚餐中卖出可乐（本项目产品为 `soda`）后获得 freezer（复用 `gain_fridge=10`）。
- `first_pizza_sold`：首次在晚餐中卖出披萨后：按晚餐房屋顺序筛出“购买了 pizza 的房屋”并取前 3 个；对每个购买事件的卖家，必须在晚餐阶段通过动作 `place_pizza_radio` 选择一个合法位置放置 1 张 base radio（#1-#3，不绑定营销员，持续 2 回合）；未放完前禁止推进到下一阶段；放置范围限制在对应房屋所在的 tile 内。

## 严格模式

- 启用本模块时必须 **禁用** `base_milestones`（通过 `conflicts` 实现），否则初始化失败。
- 同时与 `hard_choices` 冲突（规则原文要求 Hard Choices 只能搭配基础里程碑）。
