# employee/executive_vice_president - 经理展示（executive_vice_president）

## 存档

- JSON: `res://.savings/manual_cases/employees/executive_vice_president.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Restructuring/ (round=2 current_player=0)

## 目的

- 验证该经理卡可存在于本局员工池，并可在重组阶段纳入公司结构（手工复核 UI/容量）。

## 复核步骤

1. 载入后应处于 Restructuring 阶段，且玩家 0 预备区包含 executive_vice_president。
2. （可选）在重组界面将其激活/纳入公司结构并提交。

## 预期结果

- 提交成功；公司结构容量/空槽变化符合该卡 manager_slots 描述（手工核对）。

## 关联单元测试

- `core/tests/company_structure_test.gd`
