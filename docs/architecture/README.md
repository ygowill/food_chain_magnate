# 架构解析文档（索引）

阅读建议（从上到下）：

1. `docs/architecture/00-system-overview.md`：系统级总览（组件/时序/阶段状态机 + 关键设计要点）
2. `docs/architecture/10-autoload.md`：全局单例（Globals / SceneManager / EventBus）与跨层依赖
3. `docs/architecture/20-ui.md`：UI 场景如何创建/驱动引擎并刷新界面
4. `docs/architecture/30-core-engine.md`：GameEngine（命令入口、历史、存档、回放、校验点、不变量）
5. `docs/architecture/31-core-phase-manager.md`：PhaseManager（七阶段 + Working 子阶段状态机与钩子）
6. `docs/architecture/32-core-actions-framework.md`：ActionRegistry / ActionExecutor（动作分发、校验、事件生成）
7. `docs/architecture/33-core-state-model.md`：GameState / StateUpdater（状态 schema、序列化、深拷贝与一致性）
8. `docs/architecture/34-core-events.md`：EventBus（事件发布订阅与历史）
9. `docs/architecture/35-core-data-random.md`：GameData / RandomManager（确定性输入：数据与随机）
10. `docs/architecture/36-core-map.md`：MapBaker / PlacementValidator / RoadGraph（地图烘焙、放置校验、缓存）
11. `docs/architecture/40-gameplay-actions.md`：gameplay/actions（规则动作实现范式与典型例子）
12. `docs/architecture/41-gameplay-validators.md`：gameplay/validators（动作前置校验：公司结构等）
13. `docs/architecture/50-tools-replay.md`：tools/replay_runner（确定性/回放验证工具）
14. `docs/architecture/60-modules-v2.md`：模块系统 V2（严格模式：内容/规则/结算全模块化）
