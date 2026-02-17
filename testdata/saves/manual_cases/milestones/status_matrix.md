# milestone/status_matrix - 里程碑状态矩阵（status_matrix）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/status_matrix.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=3 current_player=0)

## 目的

- 用于验收里程碑全屏面板：可获得/不可获得/已获得 + 拥有者图标 + 过期提示 + 5列布局。

## 复核步骤

1. 载入后打开顶部栏「里程碑」面板。
2. 检查三态样式：可获得=浅绿色边框；已获得=浅绿色背景；不可获得=保持默认颜色。
3. 定位以下里程碑卡片并核对：
4. - first_billboard：应为「已获得」（浅绿色背景），右下角显示玩家1 logo。
5. - first_burger_produced：应为「可获得」（浅绿色边框），右下角显示玩家2 logo（用于验证“有人拥有但仍可获得”）。
6. - first_burger_marketed：应为「不可获得」且显示「已过期」。
7. - first_hire_3：应为「可获得」且显示「剩余 0 回合」。
8. 检查：默认每行 5 个；窄屏放不下时自动降列/换行。

## 预期结果

- first_billboard/first_burger_produced/first_burger_marketed/first_hire_3 的状态与文案符合预期。
- 拥有者图标显示正确（玩家1/玩家2）。
- 过期提示显示正确（剩余/已过期）。

## 关联单元测试

- （暂无）
