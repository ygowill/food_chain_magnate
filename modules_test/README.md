# modules_test/

该目录用于 **测试专用** 的 V2 模组包（例如覆盖/重排阶段、结算触发点、动作可用性等）。

原则：

- 正常游戏只使用 `modules/`。
- Headless/CI 测试需要时，可在初始化时将模块根目录设置为 `res://modules;res://modules_test`（多根目录用 `;` 分隔）。
- `modules_test/` 中的模组禁止被打包进“可发布内容”的默认模块列表中。

