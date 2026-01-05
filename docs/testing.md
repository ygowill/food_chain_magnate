# 测试与验证规范（Godot CLI / Headless）

本文档约定**后续测试文件的编写与执行方式**，以保证：

- 能在 Godot CLI（含 `--headless`）下自动运行并退出（用于 CI/脚本）
- 输出可被终端/日志解析（PASS/FAIL）
- 规避“交互式 alias 只在 zsh 中生效”等环境差异
- 尽量保持确定性（determinism）

---

## 1. Godot CLI 约定（避免 alias 陷阱）

### 1.1 为什么你在终端里能用，脚本里却找不到 `godot`

- `alias` 通常写在 `~/.zshrc`，只在**交互式 shell**生效。
- Codex/脚本常用 `zsh -lc`（login + 非交互），不会加载 `~/.zshrc`，因此看不到 alias。
- `command -v godot` 只查找 PATH 中的可执行文件，不会把 alias 当作命令路径。

### 1.2 推荐做法：让 `godot` 成为真正的 CLI

把 Godot 可执行文件放进 PATH（推荐软连接到常见 bin 目录）：

- macOS（Homebrew 前缀通常为 `/opt/homebrew/bin`）：
  - `ln -s /Applications/Godot.app/Contents/MacOS/Godot /opt/homebrew/bin/godot`

验证：

- `command -v godot`
- `godot --version`

---

## 2. Headless 测试场景规范（推荐形式）

测试以“可运行场景”的形式落地，便于：

- 在编辑器中手动点按钮跑（开发调试）
- 在 CLI 中 headless 自动跑并退出（自动化验证）

### 2.1 文件命名与位置

- 主入口场景：`ui/scenes/tests/all_tests.tscn` + `ui/scenes/tests/all_tests.gd`
- 纯逻辑（可被多个场景复用）：`core/tests/*_test.gd`（RefCounted / 纯函数风格）
- 历史/手动测试场景：`ui/scenes/tests/legacy/*`（不作为默认 headless 入口）

示例：

- `ui/scenes/tests/all_tests.tscn`
- `ui/scenes/tests/all_tests.gd`
- `core/tests/replay_determinism_test.gd`

### 2.2 CLI 执行方式（统一命令）

使用 `--scene` 指定测试场景，并用 `--` 分隔用户参数：

```bash
godot --headless --path /path/to/project \
  --scene res://ui/scenes/tests/replay_test.tscn -- --autorun
```

如果运行环境对 `user://`（用户目录）写入受限，Godot 可能会在初始化日志时崩溃。此时建议显式指定日志文件到项目目录内：

```bash
godot --headless --log-file /path/to/project/.godot/replay_test.log \
  --path /path/to/project --scene res://ui/scenes/tests/replay_test.tscn -- --autorun
```

**带超时控制的执行方式（推荐）**：

macOS 没有 `timeout` 命令，使用后台进程 + 手动超时控制：

```bash
# 单个测试（带 20 秒超时）
godot --headless --path /path/to/project \
  --scene res://ui/scenes/tests/legacy/initial_company_test.tscn -- --autorun &
PID=$!
sleep 20
if ps -p $PID > /dev/null 2>&1; then
  kill $PID 2>/dev/null
  echo "Test timed out after 20 seconds"
  exit 1
else
  wait $PID
  echo "Exit code: $?"
fi
```

### 2.2.1 本仓库脚本化执行（统一带超时）

仓库内提供了统一脚本 `tools/run_headless_test.sh`（包含：

- `HOME` 指向项目内 `.tmp_home`（规避 `user://` 权限/崩溃）
- `--log-file` 写入项目内 `.godot/*.log`
- 每次运行会清空对应的 `.godot/<name>.log`（避免旧日志干扰）
- **硬超时**：超时后 kill 进程并返回 `124`
- **脚本错误检测**：日志出现 `SCRIPT ERROR:` 时返回非 0（即使场景退出码为 0）
- **结果判定**：优先解析日志中的 `[$name] PASS/FAIL/SUMMARY`（避免个别环境 Godot 退出码不稳定）

示例：

```bash
# 跑全部测试（60 秒超时）
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60

# 跑单个测试（20 秒超时）
tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 20
```

### 2.2.2 脚本编译/预加载扫描（可选）

用于快速发现“脚本语法错误导致 preload/load 失败”的问题（尤其是某脚本未被测试场景覆盖时）。

```bash
PROJECT_PATH="/path/to/project"
mkdir -p "$PROJECT_PATH/.tmp_home" "$PROJECT_PATH/.godot"

HOME="$PROJECT_PATH/.tmp_home" godot --headless \
  --log-file "$PROJECT_PATH/.godot/CheckCompile.log" \
  --path "$PROJECT_PATH" \
  --script res://tools/check_compile.gd
```

可选：限制扫描根目录（默认扫描常用脚本目录）：

```bash
HOME="$PROJECT_PATH/.tmp_home" godot --headless \
  --log-file "$PROJECT_PATH/.godot/CheckCompile.log" \
  --path "$PROJECT_PATH" \
  --script res://tools/check_compile.gd -- res://core res://gameplay res://modules
```

**批量运行所有测试**：

**推荐：单命令触发所有测试（单进程聚合场景）**：

```bash
godot --headless --path /path/to/project \
  --scene res://ui/scenes/tests/all_tests.tscn -- --autorun
```

说明：

- 该场景会按固定顺序依次调用所有 `core/tests/*_test.gd` 并在结束后退出（0=全部通过，1=存在失败）。

```bash
#!/bin/bash
PROJECT_PATH="/path/to/project"
TIMEOUT=30

run_test() {
  local scene=$1
  local name=$2

  godot --headless --path "$PROJECT_PATH" --scene "$scene" -- --autorun &
  local pid=$!
  sleep $TIMEOUT

  if ps -p $pid > /dev/null 2>&1; then
    kill $pid 2>/dev/null
    echo "[$name] TIMEOUT"
    return 1
  else
    wait $pid
    local code=$?
    if [ $code -eq 0 ]; then
      echo "[$name] PASS"
    else
      echo "[$name] FAIL (exit code: $code)"
    fi
    return $code
  fi
}

# 运行所有测试
run_test "res://ui/scenes/tests/replay_test.tscn" "ReplayTest"
run_test "res://ui/scenes/tests/legacy/employee_test.tscn" "EmployeeTest"
run_test "res://ui/scenes/tests/legacy/payday_salary_test.tscn" "PaydaySalaryTest"
run_test "res://ui/scenes/tests/legacy/initial_company_test.tscn" "InitialCompanyTest"
run_test "res://ui/scenes/tests/legacy/mandatory_actions_test.tscn" "MandatoryActionsTest"
run_test "res://ui/scenes/tests/legacy/produce_food_test.tscn" "ProduceFoodTest"
run_test "res://ui/scenes/tests/legacy/procure_drinks_test.tscn" "ProcureDrinksTest"
run_test "res://ui/scenes/tests/legacy/company_structure_test.tscn" "CompanyStructureTest"
run_test "res://ui/scenes/tests/legacy/order_of_business_test.tscn" "OrderOfBusinessTest"
```

说明：

- `--` 之后的参数属于 `OS.get_cmdline_user_args()`
- 实际拿到的参数通常是 `"--autorun"`（带 `--`），所以脚本中应同时兼容 `"autorun"` 与 `"--autorun"`

### 2.3 Autorun 与退出码（必须满足）

每个测试场景必须满足：

- CLI + `--autorun` 时自动开始测试，而不需要用户进行点击
- 测试完成后立刻退出：
  - 通过：`get_tree().quit(0)`
  - 失败：`get_tree().quit(1)`

注意：

- Godot 4.5 中**不存在** `OS.set_exit_code()`（会导致脚本解析错误）。
- 退出码由 `SceneTree.quit(exit_code)` 负责。

### 2.4 输出规范（便于 grep / 日志解析）

必须 `print()` 一行可机器解析的结果：

- `"[TestName] START args=..."`
- `"[TestName] PASS ..."`
- `"[TestName] FAIL ..."`

同时在 FAIL 时用 `push_error()` 输出错误原因，便于编辑器/日志定位。

### 2.5 不要让 headless 卡住

常见“卡住”原因与规避：

- autorun 参数没匹配到（最常见）：确保兼容 `"--autorun"`。
- 只在 UI 按钮回调里跑测试，但 headless 没人点：autorun 必须在 `_ready()` 触发。
- 依赖某些 UI 节点才能跑：autorun 路径尽量调用纯逻辑函数（`core/tests/*_test.gd`），UI 只负责展示结果。
- 限制总运行时长，避免某些脚本load失败导致无动作

---

## 3. 确定性（Determinism）要求

测试用例应尽量做到可重放、可复现：

- 固定 `seed`，不要直接用 `randi()` 影响执行路径。
- 若需要随机，优先通过工程内的受控随机（例如 `RandomManager`）并记录调用计数/状态。
- 用 “初始状态 + 命令序列” 验证最终 `state_hash`（或关键值），避免依赖 UI/帧时间。

---

## 4. 本项目当前实践（以回放测试为基准）

现有 headless 测试场景：

- 全部测试聚合：`ui/scenes/tests/all_tests.tscn`
- 游戏场景地图视图接入：`ui/scenes/tests/game_map_view_test.tscn`（验证 GameArea 已渲染 `state.map.cells`）
- 回放确定性：`ui/scenes/tests/replay_test.tscn`（纯逻辑：`core/tests/replay_determinism_test.gd`）
- 员工额度 smoke test：`ui/scenes/tests/employee_test.tscn`（纯逻辑：`core/tests/employee_action_test.gd`）
- 发薪日 smoke test：`ui/scenes/tests/payday_salary_test.tscn`（纯逻辑：`core/tests/payday_salary_test.gd`）
- 初始公司结构：`ui/scenes/tests/initial_company_test.tscn`（纯逻辑：`core/tests/initial_company_test.gd`）
- 强制动作测试：`ui/scenes/tests/mandatory_actions_test.tscn`（纯逻辑：`core/tests/mandatory_actions_test.gd`）
- 生产食物测试：`ui/scenes/tests/produce_food_test.tscn`（纯逻辑：`core/tests/produce_food_test.gd`）
- 采购饮料测试：`ui/scenes/tests/procure_drinks_test.tscn`（纯逻辑：`core/tests/procure_drinks_test.gd`）
- 采购饮料路线规则：已加入 `ui/scenes/tests/all_tests.tscn`（纯逻辑：`core/tests/procure_drinks_route_rules_test.gd`）
- 清理阶段库存清理：已加入 `ui/scenes/tests/all_tests.tscn`（纯逻辑：`core/tests/cleanup_inventory_test.gd`）
- 解雇动作：已加入 `ui/scenes/tests/all_tests.tscn`（纯逻辑：`core/tests/fire_action_test.gd`）
- 公司结构测试：`ui/scenes/tests/company_structure_test.tscn`（纯逻辑：`core/tests/company_structure_test.gd`）
- 决定顺序测试：`ui/scenes/tests/order_of_business_test.tscn`（纯逻辑：`core/tests/order_of_business_test.gd`）
- 里程碑系统测试：已加入 `ui/scenes/tests/all_tests.tscn`（纯逻辑：`core/tests/milestone_system_test.gd`）

这些测试统一遵循：

- `-- --autorun` headless 自动跑
- `SceneTree.quit(exit_code)` 返回退出码
- stdout 打印 `[TestName] START/PASS/FAIL`
