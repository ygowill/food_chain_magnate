# base_rules

基础规则模块（Strict Mode 基线）。

## 提供内容

- Primary settlements（缺失将导致初始化失败）：
  - `Dinnertime` enter
  - `Payday` exit
  - `Marketing` enter
  - `Cleanup` enter

> 说明：当前阶段仅接入“结算注册”，内部仍复用现有 `core/rules/phase/*_settlement.gd` 规则实现；后续会继续模块化拆分与效果系统迁移。

