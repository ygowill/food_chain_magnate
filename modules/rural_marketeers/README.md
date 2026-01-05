# Rural Marketeers（模块12）

- 员工：`rural_marketeer`（salary=true，pool fixed=6）
- 乡村地区（Rural Area）：运行期作为一个“无需求上限”的房屋，且晚餐结算总是最后
- 巨型广告牌（Giant Billboard）：4 个固定槽位（N/E/S/W），放置后永久存在；每回合 Marketing 为该产品添加 2 个需求到乡村地区
- 里程碑：`first_rural_marketeer_used`（pool.count=5），触发后允许立即放置“高速公路出口（offramp）”
- 高速公路出口（offramp）：供给 3 个；棋盘外放置为外部板块，必须与道路连接；与飞机营销占用同一边时互斥

