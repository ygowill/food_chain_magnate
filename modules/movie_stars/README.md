# Movie Stars（电影明星）

## 玩法

- 新员工：`movie_star_b` / `movie_star_c` / `movie_star_d`（电影明星），可从 `waitress` 培训而来（由本模块对 `waitress` 做受控 patch 注入培训链）。
- 限制：每位玩家最多拥有 1 张电影明星（B/C/D 任意其一）。
- 效果：
  - 决定顺序阶段：拥有在岗电影明星的玩家优先选择顺序；多名明星按 B > C > D；其余玩家按空槽数排序。
  - 晚餐阶段：电影明星作为更高优先级的平局裁决（B > C > D），并自动赢得“女服务员数量”平局链路。

## 技术说明

- 跨模块培训链通过 `RulesetRegistrarV2.register_employee_patch()` 实现：对 `waitress` 追加 `train_to=["movie_star_b","movie_star_c","movie_star_d"]`。
- 晚餐平局通过 `EffectRegistry` 的 `:dinnertime:tiebreaker:` segment 实现：`movie_stars:dinnertime:tiebreaker:movie_star_{b|c|d}`。
- OrderOfBusiness 通过 Phase hook 在 `OrderOfBusiness:after_enter` 重排 `selection_order/turn_order` 实现（Strict：同级别明星出现直接失败）。
