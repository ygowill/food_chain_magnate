# 模块包目录（Module Packages）

本目录用于存放模块系统 V2 的模块包：

- 路径约定：`res://modules/<module_id>/`
- 每个模块包至少包含：
  - `module.json`：manifest（依赖/冲突/入口脚本/能力声明等，严格解析）
  - `README.md`：模块描述文件（玩法、包含内容、版本、注意事项）

测试专用模块包请放在 `res://modules_test/`（避免污染可发布内容）。

详细设计见：`docs/architecture/60-modules-v2.md`
