# 模块1：新区域（New Districts）

本模块提供：

- 公寓楼板块 `tile_x` / `tile_y`（印刷公寓：营销放置需求时 *2，且无需求上限）。
- 额外地图板块 `tile_u` / `tile_v` / `tile_w`（包含预置花园/多饮品等）。

实现说明（V2 严格模式）：

- 本模块将 `apartment` 建筑件与对应 tile 一并打包；禁用模块时，公寓在运行期完全不存在。
- 公寓的“营销翻倍/无上限”通过 tile 的 `printed_structures[].house_props` 数据驱动：
  - `no_demand_cap=true`
  - `marketing_demand_multiplier=2`

