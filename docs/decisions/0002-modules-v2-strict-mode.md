# ADR 0002：模块系统 V2（严格模式 + 结算全模块化）

- 状态：已采纳
- 日期：2026-01-01

## 背景

现有模块系统（`data/modules/*.json` + `core/modules/*`）可以注册钩子，但仍存在：

- 员工/里程碑等内容以全局 registry 方式加载，**禁用模块时内容仍可能存在于运行期**
- 多处规则与结算逻辑写死在核心编排中（PhaseManager 直接调用具体结算脚本）
- `GameConfig` 承担了过多“卡池硬编码列表”的职责（例如 `one_x_employee_ids`）

补充：旧模块系统 V1 已于 2026-01-01 移除（`data/modules/*` + `core/modules/*`）。

这些都不符合“严格模式（禁用=完全不存在）”与“零 fallback（fail fast）”的目标。

## 决策

### D2.1 模块包目录化

- 统一采用模块包目录：`res://modules/<module_id>/`
- 每个模块包至少包含：
  - `module.json`（manifest）
  - `README.md`（模块描述）
  - 可选 `content/`（员工/里程碑等 JSON）
  - 可选 `rules/entry.gd`（规则注册入口）

### D2.2 严格模式：禁用模块内容在运行期完全不存在

- 每局游戏只从启用模块集合（含依赖闭包）构建 `ContentCatalog` 与 `Ruleset`
- 未启用模块的员工/里程碑/规则注册不会被加载
- 任意“引用不存在内容/能力”的情况 → 初始化失败（Fail Fast）

### D2.3 结算全模块化（你已确认）

- Dinnertime/Payday/Marketing/Cleanup 等阶段结算不再由核心硬编码调用
- 引入 `SettlementRegistry`，由模块注册结算实现；PhaseManager 只负责编排调用

### D2.4 缺失主结算器的行为（你已确认）

- 若必需阶段点位缺少 primary settlement → **初始化直接失败**

### D2.5 供应池从模块内容推导（路线B）

- 员工/里程碑池由启用模块内容推导
- 移除 `GameConfig.employee_pool.one_x_employee_ids` 等“列表型硬编码配置”

## 影响

- 优点：真正做到“禁用=不存在”；规则/结算可插拔；错误更早暴露；更利于做模块组合与测试。
- 代价：需要重构全局 registry 与 PhaseManager；需要补齐能力校验与更细粒度测试；旧数据/旧存档不兼容。

## 参考

- 详细设计：`docs/architecture/60-modules-v2.md`
