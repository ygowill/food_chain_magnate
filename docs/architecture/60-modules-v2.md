# 模块系统 V2（Strict Mode）：当前实现说明

本仓库已落地“模块系统 V2（Strict Mode）”：内容与规则均由**启用模块集合**装配，缺失依赖/重复注册/引用不存在的内容会直接初始化失败。

## 目录结构

模块目录示例：`modules/<module_id>/`

- `module.json`：manifest（见 `core/modules/v2/module_manifest.gd`）
- `content/*`：内容 JSON（employees/products/milestones/tiles/maps/pieces/visuals...）
- 规则入口脚本（可选，由 `entry_script` 指定；示例：`modules/base_rules/rules/entry.gd`）

base 目录支持多个，用 `;` 分隔：

- `Globals.modules_v2_base_dir`
  - 示例：`res://modules` 与 `res://modules_test`
  - 存档中会保存为单个字符串：`res://modules;res://modules_test`

## 运行时装配入口

装配入口：`core/engine/game_engine/modules_v2.gd`

初始化新局时（`core/engine/game_engine/initializer.gd`）会调用：

- `engine.apply_modules_v2(enabled_modules_v2, modules_v2_base_dir)`

装配会完成：

1. 解析 base dirs（`core/modules/v2/module_dir_spec.gd`）
2. 加载所有 `module.json`（`core/modules/v2/module_package_loader.gd`）
3. 构建 module plan（依赖闭包/冲突检查/稳定排序）（`core/modules/v2/module_plan_builder.gd`）
4. 加载 `ContentCatalog`（`core/modules/v2/content_catalog_loader.gd`）
5. 加载并执行 rules entry，构建 `RulesetV2`（`core/modules/v2/ruleset_loader.gd`）
6. 配置各类 registry（员工/里程碑/产品/营销、tile/piece 等）
7. 把结算/效果 registry 注入 `PhaseManager`，并应用 hooks/顺序覆盖/结算触发点覆盖
8. strict 校验（例如：必需 settlement、content 引用的 effect handler 必须存在等）

## module.json（当前 schema）

manifest 由 `core/modules/v2/module_manifest.gd` 解析，示例（取自 `modules/base_rules/module.json`）：

```json
{
  "schema_version": 1,
  "id": "base_rules",
  "name": "Base Rules",
  "version": "0.1.0",
  "priority": 50,
  "dependencies": [],
  "conflicts": [],
  "entry_script": "res://modules/base_rules/rules/entry.gd",
  "provides": {
    "settlements": ["settlement:phase:Dinnertime:enter"]
  }
}
```

## RulesetV2：模块可注册的扩展点（节选）

规则集合类型：`core/modules/v2/ruleset.gd`

模块可通过 rules entry 注册（节选）：

- 结算器：`settlement_registry`（`core/rules/settlement_registry.gd`）
- effects：`effect_registry`、`milestone_effect_registry`
- phase/subphase hooks（含 named subphase hooks）
- action executors / validators / availability overrides
- map generation providers（`map_generation_registry`）
- 规则 providers：营销发起、破产、晚餐需求、路上购买、放置冲突等
- 顺序覆盖：phase/subphase order overrides、settlement trigger overrides
- 状态扩展：
  - `state_initializers`：在 map bake 后补充 state 字段
  - `state_int_key_dict_schemas`：注册“int-key Dictionary 归一化路径”（供读档）

## 与 core/data 的关系

- `GameConfig` 仍来自 `data/config/game_config.json`
- 模块系统 V2 会校验 `GameConfig` 的起始库存/产品是否都存在于当前 `ContentCatalog`（避免“配置引用不存在内容”）

内容 JSON 的字段规范与约束见：`docs/architecture/61-content-catalog-schema.md`
