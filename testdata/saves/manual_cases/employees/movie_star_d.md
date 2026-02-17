# employee/movie_star_d - 电影明星（movie_star_d）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/movie_star_d.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: OrderOfBusiness/ (round=2 current_player=0)

## 目的

- 验证 movie_star_* 会在 OrderOfBusiness 使持有者优先选顺序。

## 复核步骤

1. 载入后应处于 OrderOfBusiness 阶段。
2. 观察 selection_order/turn_order：拥有电影明星的玩家应排在前面。

## 预期结果

- 玩家 0 应优先于玩家 1 进行顺序选择（由 movie_star_* 模块重排）。

## 关联单元测试

- `core/tests/movie_stars_v2_test.gd`
