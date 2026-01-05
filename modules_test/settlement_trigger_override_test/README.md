# Settlement Trigger Override Test

用于验证“Settlement 触发点映射可由模块覆盖”的测试模块。

- 为 `OrderOfBusiness` 注册一个主结算器（ENTER）。
- 通过 settlement_triggers_override 让 PhaseManager 在进入 `OrderOfBusiness` 时触发该结算点。
