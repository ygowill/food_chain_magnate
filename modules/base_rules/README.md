# base_rules

基础规则模块（Strict Mode 基线）。

## 提供内容

- Primary settlements（缺失将导致初始化失败）：
  - `Dinnertime` enter
  - `Payday` exit
  - `Marketing` enter
  - `Cleanup` enter

> 说明：阶段结算实现位于 `modules/base_rules/rules/phase/**`，由本模块注册为 primary settlements。core 层仅保留注册表/引擎编排等可复用机制，不再直接承载 base_rules 的阶段结算实现。
