# Gourmet Food Critics（模块13）

## 内容

- 员工：`gourmet_food_critic`（需要薪水，供应池 6 张）
- 营销板件：`gourmet_guide`（board_number：17–20）

## 规则要点

- 培训：`marketer` 可培训为 `gourmet_food_critic`（由模块 patch 注册）。
- 放置：`gourmet_food_critic` 在 Working/Marketing 子阶段发起 `gourmet_guide` 营销，必须放在棋盘边缘（与 airplane/offramp 同格互斥）。
- 数量限制：全局最多同时存在 3 个 `gourmet_guide`。
- 结算：每回合按 board_number 顺序结算，向“所有有花园的房屋”各添加 1 个需求。

