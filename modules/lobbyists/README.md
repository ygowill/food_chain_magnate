# Lobbyists（说客）

本模块实现扩展“Lobbyists（说客）”的核心规则：

- Working 9-5 新子阶段：`Lobbyists`（位于 `PlaceHouses` 之后、`PlaceRestaurants` 之前）
- 说客可放置“道路（建设中）”或“公园”
- “首个使用说客”里程碑：允许立刻扩边放置一张新的地图板块（从本局剩余 tile 中选择）

严格模式说明：

- 本模块禁用时：相关员工/里程碑/规则/动作完全不存在
- 所有效果与结算均由本模块注册；缺失会在初始化阶段 fail-fast

