## 电子版《快餐连锁大亨》（Godot）技术设计文档

本设计文档基于 `docs/rules.md` 的精简规则，给出可实现、可扩展的模块化架构与文件组织，尽量数据驱动，便于后续扩展与调优。若规则存在歧义，优先以 `docs/rules.md` 为准；仍无法确定时将在文末“需要确认”中列出。

---

### 目标与范围

- 目标：在 Godot 中实现电子版桌游，支持基础规则全流程、可插拔扩展模块、回放与存档、清晰的 UI 引导。
- 范围：
  - 基础七阶段流程与子阶段动作、公司结构、员工/里程碑/营销/库存/销售/银行破产。
  - 关键扩展模块的插件化接口与参考实现骨架（功能详解在“扩展模块”章节）。
  - 数据驱动的资源定义（员工、里程碑、地图板块、模块清单）。
  - 事件溯源的存档/复盘。

---

### 已确认配置/实现约定

- 基础单价默认值：10（可被定价/折扣/奢侈品经理与模块影响）。
- 员工卡表：按原版“全卡表”完整实现（路线、距离、卡槽、唯一性、薪资等）。
- 营销板编号：与资源编号一致；按玩家人数在设置阶段移除指定编号（2人：#12/#15/#16；3人：#15/#16；4人：#16；5人：不移除）。
- 饮品来源：标志无限产量；同回合可被多个采购员依次拾取；同一采购员对同一来源每回合仅一次。
- 本地化：支持中/英双语切换（默认中文）。
- 入门模式：一键开关，按 rules.md 入门建议执行（禁用储备卡；银行初始每人 75；禁用里程碑；跳过发薪日；首次破产即终局）。
- 营销结算（当前实现）：在营销阶段按“营销板编号（board_number）升序”结算，支持按玩家人数移除的编号过滤（`removed_board_numbers`）。
  - 持续时间：普通营销每次结算后持续时间 -1，到 0 则到期回收；`remaining_duration=-1` 表示永久（`first_billboard` 之后放置的营销）。
  - 里程碑：`first_radio` 使 radio 每次对命中房屋放置 2 个需求标记（否则为 1）；`first_billboard` 使营销员免薪且后续营销永久。
  - 范围算法：billboard（邻接四向）、mailbox（同街区，依赖 `BlockRegions`）、radio（九宫格 3×3 板块）、airplane（按板块行/列整线）。
  - 需求上限：普通房屋需求上限 3，带花园上限 5。

---

## 架构总览

### 分层结构

- 核心系统：
  - 状态机（FSM）与规则引擎：严格推进七阶段；校验与自动推进。
  - 行动系统与校验器：所有规则变化以原子行动建模；可撤销、可重放。
  - 地图与路径：板块拼接、道路图、距离/路径计算、放置校验。
  - 公司与员工：公司结构（金字塔）、招聘/培训/薪资/忙碌状态。
  - 库存与营销：生产/采购、广告放置与持续时间、需求生成与上限。
  - 销售与经济：晚餐阶段分配、价格计算、CFO与里程碑影响、银行结算与破产。
  - 里程碑：触发、授予、移除机制与全局效果。
- 插件扩展：各模块以插件注入数据/校验/钩子，不改动核心代码。
- 横切：事件总线、存档/回放、本地化、日志与调试。

### 核心数据驱动原则

- 员工、里程碑、地图板块、营销板件与游戏配置统一以 JSON 定义（见 `docs/decisions/0001-data-format-json.md`）；规则参数尽量外置（如距离、卡槽、薪资标记、营销范围、奖励数值）。
- 动作序列与随机决策（如地图朝向）统一记录到事件流，保证重放一致性。
- 初始化阶段产生的“随机地图拼接”不额外记录为命令：由本局 `seed` 驱动的 `RandomManager` 生成 `state.map.tile_placements`，并随存档/回放序列化，从而保证确定性复盘。
- 开局读取 `data/config/game_config.json`，并将解析后的规则常量写入 `GameState.rules`（随存档/回放序列化），避免外部配置变更导致复盘不一致。

---

## 回合流程与状态机（FSM）

### 阶段与子阶段

1. 重组公司（Restructuring）
2. 决定顺序（Order of Business）
3. 工作时间（Working 9-5）
   - 招聘（Recruit）
   - 培训（Train）
   - 发起营销（Initiate Marketing）
   - 获取食物与饮品（Produce/Procure）
   - 放置房屋与花园（Place Houses & Gardens）
   - 放置或移动餐厅（Place/Move Restaurants）
4. 晚餐时间（Dinnertime）
5. 发薪日（Payday）
6. 营销活动（Marketing Campaigns 结算持续时间与新增需求）
7. 清理（Cleanup）

每个阶段是一个状态，状态提供：

- 可用行动清单；
- 阶段内强制/可选动作提示；
- 进入/退出钩子（结算副作用）；
- 自动推进条件（例如：所有玩家完成子阶段或没有可行动作）。

### 阶段钩子系统（Phase Hooks）

- 设计目标：允许模块在不修改核心状态机的情况下，插入自定义逻辑到阶段流程中。
- 钩子点：每个阶段支持以下钩子
  - `before_enter`: 阶段开始前执行（可修改初始状态，如设置标志位）
  - `after_enter`: 阶段开始后执行（如"夜班经理"在工作阶段复制无薪员工行动）
  - `before_exit`: 阶段结束前执行（如晚餐阶段应用 CFO、清理阶段移除里程碑）
  - `after_exit`: 阶段结束后执行（如记录日志、触发成就）
- 注册方式：

  ```gdscript
  PhaseManager.register_hook(
      phase: String,           # "Working", "Dinnertime", "Marketing" 等
      hook_type: String,       # "before_enter", "after_enter", "before_exit", "after_exit"
      callback: Callable,      # func(state, context) -> void
      priority: int            # 执行优先级（小的先执行）
  )
  ```

- 执行顺序：同一钩子点的多个回调按 `priority` 升序执行。
- 模块示例：

  ```gdscript
  # 夜班经理：在工作阶段结束前，让无薪员工再工作一次
  class ModuleNightShift:
      func on_enable():
          PhaseManager.register_hook("Working", "after_enter",
              func(state, ctx):
                  if has_night_shift_manager(state):
                      duplicate_no_salary_actions(state)
              , priority: 100)

  # 大众营销员：在营销阶段开始时，设置额外轮次
  class ModuleMassMarketer:
      func on_enable():
          PhaseManager.register_hook("Marketing", "before_enter",
              func(state, ctx):
                  var count = count_mass_marketers(state)
                  ctx.marketing_rounds = 1 + count
              , priority: 50)

  # 艰难抉择：在清理阶段结束前，移除过期里程碑
  class ModuleHardChoices:
      func on_enable():
          PhaseManager.register_hook("Cleanup", "before_exit",
              func(state, ctx):
                  remove_expired_milestones(state, ctx.round_number)
              , priority: 200)
  ```

### 关键校验与规则要点（依据 rules.md）

- 决定顺序：按“空余卡槽”多者先；空余相同→按上一回合顺序靠前先；“首个飞机营销”在计算时+2 空余卡槽。
- 工作时间：强制与可选员工行为区分；忙碌的营销员不在公司结构内。
- 距离：默认沿公路，以跨越“地图板块边界”的次数计；从餐厅入口起算；飞艇依卡面说明。
- 餐厅：2×2 占位；初始设置限制仅在初始阶段生效；“免下车”本回合四角视为入口。
- 采购员：从餐厅出发，不需返回；禁止 U 型转弯；同一饮品标志同一回合同一采购员仅一次，但多个采购员可顺序拾取。
- 晚餐分配：候选餐厅需连通且“库存能满足全部需求”；选择最小“单价+距离”；再平局比女服务员数量；仍平局按回合顺序靠前。
- 收入：单价×数量 + 奖励；花园翻倍“单价部分”，奖励不翻倍；若各种修正（定价经理、折扣经理、里程碑与模块等）叠加后计算结果小于 0，则最终收入按 0 计算，不会出现负收入，也不会向银行支付费用。
- 女服务员：晚餐结束统一收取（默认3；里程碑可至5）。
- CFO：本回合现金（含女服务员）×1.5 向上取整；对负收入同样生效。
- 银行破产：
  - 第一次：翻储备卡→补充资金，并按出现最多数字设定 CEO 之后卡槽数（或由“储备价格”模块替换为固定补充与锁定基础单价）。
  - 第二次：在晚餐阶段结束后立刻游戏结束（本回合不再有发薪日）。

---

## 行动系统与规则引擎

### 设计理念：命令模式 + 事件溯源

- 核心目标：游戏可复盘、可回退、可验证、存档小且语义清晰。
- 核心原则：
  1. **命令即真相**：存档只记录命令序列，不记录状态变更（diff）
  2. **确定性执行**：相同命令 + 相同初始状态 = 相同结果状态
  3. **校验点验证**：定期保存状态哈希与关键数值，用于验证复盘正确性
  4. **不可变状态**：动作执行器通过创建新状态返回结果，不修改输入状态
  5. **纯函数保证**：所有动作执行器、修饰器、验证器都是纯函数

### 命令结构（Command）

```gdscript
class Command:
    var index: int              # 全局序号（从 0 开始递增）
    var action_id: String       # 动作类型 ID
    var actor: int              # 执行者：玩家 ID（0-5）或 -1（系统）
    var params: Dictionary      # 动作参数（位置、对象、数量等）
    var phase: String           # 所在阶段："Restructuring", "Working", "Dinnertime" 等
    var timestamp: int          # 游戏内时间戳（round * 1000 + phase_index）
    var metadata: Dictionary    # 可选：调试信息、UI 提示等
```

示例命令：

```gdscript
Command.new({
    "index": 42,
    "action_id": "Recruit",
    "actor": 0,
    "params": {"employee_id": "recruiter"},
    "phase": "Working",
    "timestamp": 2003  # 第 2 回合，第 3 阶段
})
```

### 动作执行器（ActionExecutor）

所有动作执行器遵循统一接口，是纯函数：

```gdscript
class ActionExecutor:
    var action_id: String
    var mandatory: bool = false  # 是否为强制行动
    var allowed_phases: Array[String] = []  # 允许的阶段

    # 核心方法：纯函数执行
    func execute(params: Dictionary, state: GameState) -> Result:
        # 1. 前置校验
        var validation = validate(params, state)
        if not validation.ok:
            return validation

        # 2. 计算新状态（不修改 state）
        var new_state = compute_new_state(params, state)

        # 3. 生成事件日志
        var events = generate_events(params, state, new_state)

        return {
            "ok": true,
            "new_state": new_state,
            "events": events,
            "description": "简短的人类可读描述"
        }

    # 校验（纯函数）
    func validate(params: Dictionary, state: GameState) -> Result:
        # 示例：校验玩家是否有足够资源
        pass

    # 计算新状态（核心逻辑，纯函数）
    func compute_new_state(params: Dictionary, state: GameState) -> GameState:
        # 使用 StateUpdater 辅助类更新状态
        pass

    # 生成事件
    func generate_events(params, old_state, new_state) -> Array:
        return [{"type": "action_executed", "action": action_id}]
```

### 强制行动（Mandatory Actions）

部分员工的行动是强制的，必须在对应阶段执行：

| 员工 | 动作 | 阶段 | 强制原因 |
|------|------|------|---------|
| 定价经理 | SetPrice | Working | 必须设定单价 |
| 折扣经理 | SetDiscount | Working | 必须设定折扣 |
| 奢侈品经理 | SetLuxuryPrice | Working | 必须设定奢侈品价 |
| CFO | (自动) | Dinnertime | 自动应用收入倍增 |
| 招聘经理 | (自动) | Payday | 自动提供折扣 |
| 人力资源总监 | (自动) | Payday | 自动提供折扣 |
| 女服务员 | (自动) | Dinnertime | 自动收取小费 |

- 标记方式：在 `EmployeeDef` 中设置 `mandatory: true`
- UI 提示：未完成的强制行动会高亮显示
- 自动执行：部分强制行动由系统自动触发（如 CFO、女服务员）

### 示例动作实现

#### 示例 1：招聘（Recruit）

```gdscript
class RecruitAction extends ActionExecutor:
    func _init():
        action_id = "Recruit"
        mandatory = false
        allowed_phases = ["Working"]

    func validate(params, state):
        var employee_id = params.employee_id
        var player_id = params.actor

        # 检查是否为入门级员工
        if not Registry.is_entry_level(employee_id):
            return {ok: false, error: "只能招聘入门级员工"}

        # 检查供应池是否有牌
        if state.employee_pool[employee_id] <= 0:
            # 允许"缺货预支"，但需要在培训阶段立即培训
            if not can_train_immediately(state, employee_id):
                return {ok: false, error: "供应池缺货且无法立即培训"}

        return {ok: true}

    func compute_new_state(params, state):
        var employee_id = params.employee_id
        var player_id = params.actor

        # 使用 StateUpdater 辅助函数
        var new_state = state

        # 从供应池移除
        new_state = StateUpdater.increment(new_state,
            ["employee_pool", employee_id], -1)

        # 添加到玩家的待命区
        new_state = StateUpdater.append_to_array(new_state,
            ["players", player_id, "reserve_employees"],
            {"id": employee_id, "status": "reserve"})

        return new_state

    func generate_events(params, old_state, new_state):
        return [{
            "type": "employee_recruited",
            "player": params.actor,
            "employee": params.employee_id
        }]
```

#### 示例 2：出售给房屋（SellToHouse）

```gdscript
class SellToHouseAction extends ActionExecutor:
    func _init():
        action_id = "SellToHouse"
        mandatory = false
        allowed_phases = ["Dinnertime"]

    func compute_new_state(params, state):
        var house_id = params.house_id
        var restaurant_owner = params.winner_player
        var products = params.products  # [{type: "burger", count: 2}, ...]
        var price = params.calculated_price  # 已由定价管道计算

        var new_state = state

        # 1. 扣减库存
        for product in products:
            new_state = StateUpdater.increment(new_state,
                ["players", restaurant_owner, "inventory", product.type],
                -product.count)

        # 2. 转移现金（自动处理银行对冲）
        new_state = StateUpdater.transfer_cash(new_state,
            from: "bank",
            to: "player:%d" % restaurant_owner,
            amount: price)

        # 3. 清空房屋需求
        new_state = StateUpdater.set_value(new_state,
            ["map", "houses", house_id, "demands"],
            [])

        return new_state
```

### 状态更新辅助器（StateUpdater）

为避免手写状态更新逻辑的重复和错误，提供类型安全的辅助函数：

```gdscript
class StateUpdater:
    # ===== 现金操作 =====

    # 转移现金（自动处理银行对冲）
    static func transfer_cash(state: GameState, from: String, to: String, amount: int) -> GameState:
        """
        在两个现金账户间转移金额，自动保证守恒。

        参数：
            from/to: 账户标识符
                - "bank": 银行
                - "player:N": 玩家 N (0-5)
                - 可扩展："milestone_pool", "cfm_bank" 等

        示例：
            transfer_cash(state, "bank", "player:0", 50)  # 银行 -50, 玩家0 +50
            transfer_cash(state, "player:0", "player:1", 20)  # 玩家间转账
        """
        var new_state = state.duplicate(false)

        var from_account = _resolve_cash_account(new_state, from)
        var to_account = _resolve_cash_account(new_state, to)

        from_account.cash -= amount
        to_account.cash += amount

        return new_state

    # 设置现金（不对冲，仅用于调试/初始化）
    static func set_cash(state: GameState, account: String, value: int) -> GameState:
        var new_state = state.duplicate(false)
        var acc = _resolve_cash_account(new_state, account)
        acc.cash = value
        return new_state

    # ===== 嵌套属性操作 =====

    # 设置嵌套值（类型安全）
    static func set_value(state: GameState, path: Array, value) -> GameState:
        """
        设置嵌套属性。

        示例：
            set_value(state, ["players", 0, "drive_thru_active"], true)
            set_value(state, ["map", "houses", "7", "demands"], [])
        """
        var new_state = state.duplicate(false)
        _set_nested(new_state, path, value)
        return new_state

    # 增量更新
    static func increment(state: GameState, path: Array, delta: int) -> GameState:
        """
        对数值字段进行增量更新。

        示例：
            increment(state, ["employee_pool", "recruiter"], -1)
            increment(state, ["players", 0, "inventory", "burger"], 5)
        """
        var current_value = _get_nested(state, path)
        return set_value(state, path, current_value + delta)

    # ===== 数组操作 =====

    # 添加元素
    static func append_to_array(state: GameState, path: Array, item) -> GameState:
        """
        向数组末尾添加元素。

        示例：
            append_to_array(state, ["players", 0, "reserve_employees"],
                {"id": "recruiter", "status": "reserve"})
        """
        var new_state = state.duplicate(false)
        var array = _get_nested(new_state, path)
        array.append(item)
        return new_state

    # 移除元素（按索引）
    static func remove_from_array(state: GameState, path: Array, index: int) -> GameState:
        var new_state = state.duplicate(false)
        var array = _get_nested(new_state, path)
        array.remove_at(index)
        return new_state

    # 移除元素（按条件）
    static func remove_if(state: GameState, path: Array, predicate: Callable) -> GameState:
        """
        移除满足条件的元素。

        示例：
            remove_if(state, ["players", 0, "employees"],
                func(e): return e.id == "recruiter")
        """
        var new_state = state.duplicate(false)
        var array = _get_nested(new_state, path)
        array = array.filter(func(item): return not predicate.call(item))
        _set_nested(new_state, path, array)
        return new_state

    # ===== 批量操作 =====

    # 批量更新（链式调用）
    static func batch_update(state: GameState, updates: Array[Callable]) -> GameState:
        """
        批量应用多个更新，提高效率。

        示例：
            batch_update(state, [
                func(s): return increment(s, ["bank", "total"], -100),
                func(s): return increment(s, ["players", 0, "cash"], 100),
                func(s): return set_value(s, ["phase"], "Dinnertime")
            ])
        """
        var new_state = state
        for update_fn in updates:
            new_state = update_fn.call(new_state)
        return new_state

    # ===== 内部辅助函数 =====

    static func _get_nested(obj, path: Array):
        var current = obj
        for key in path:
            current = current[key]
        return current

    static func _set_nested(obj, path: Array, value):
        var current = obj
        for i in range(path.size() - 1):
            current = current[path[i]]
        current[path[-1]] = value

    static func _resolve_cash_account(state: GameState, identifier: String):
        if identifier == "bank":
            return state.bank
        elif identifier.begins_with("player:"):
            var player_id = int(identifier.split(":")[1])
            return state.players[player_id]
        else:
            push_error("未知账户标识: " + identifier)
            return null
```

### StateUpdater 的优势

| 方面 | 手写状态更新 | 使用 StateUpdater |
|------|------------|------------------|
| **类型安全** | ❌ 易拼写错误 | ✅ 编译期检查 |
| **银行对冲** | ❌ 手动配对 | ✅ 自动处理 |
| **代码可读性** | ❌ 冗长 | ✅ 语义清晰 |
| **维护成本** | ❌ 重构困难 | ✅ 统一接口 |
| **错误定位** | ❌ 运行时报错 | ✅ 静态检查 |

示例对比：

```gdscript
# 手写（容易出错）
new_state.players[0].cash += 50
new_state.bank.total -= 50  # 容易忘记！
new_state.map.houses["7"].demands = []

# 使用 StateUpdater（安全）
new_state = StateUpdater.transfer_cash(new_state, "bank", "player:0", 50)
new_state = StateUpdater.set_value(new_state, ["map", "houses", "7", "demands"], [])
```

### 命令日志与回放

运行时维护一个命令日志，用于存档和复盘：

```gdscript
class GameEngine:
    var command_log: Array[Command] = []
    var current_state: GameState
    var checkpoint_interval: int = 50  # 每 50 个命令创建校验点

    # 执行命令（运行时 + 复盘通用）
    func execute_command(cmd: Command) -> Result:
        # 1. 查找动作执行器
        var executor = ActionRegistry.get(cmd.action_id)
        if not executor:
            return {ok: false, error: "未知动作: " + cmd.action_id}

        # 2. 执行动作（纯函数）
        var result = executor.execute(cmd.params, current_state)

        # 3. 应用状态变更
        if result.ok:
            current_state = result.new_state

            # 4. 记录命令
            cmd.index = command_log.size()
            command_log.append(cmd)

            # 5. 触发事件
            for event in result.events:
                EventBus.emit(event)

            # 6. 定期创建校验点
            if cmd.index % checkpoint_interval == 0:
                create_checkpoint(cmd.index)

        return result

    # 创建校验点
    func create_checkpoint(after_command_index: int):
        var checkpoint = Checkpoint.new()
        checkpoint.after_command = after_command_index
        checkpoint.state_hash = compute_state_hash(current_state)
        checkpoint.key_values = extract_key_values(current_state)

        # 每 10 回合保存完整快照（可配置）
        if current_state.round % 10 == 0:
            checkpoint.full_snapshot = current_state.duplicate(true)

        checkpoints.append(checkpoint)

    # 提取关键数值（用于快速验证）
    func extract_key_values(state: GameState) -> Dictionary:
        return {
            "round": state.round,
            "phase": state.phase,
            "bank_total": state.bank.total,
            "player_cash": state.players.map(func(p): return p.cash),
            "house_count": state.map.houses.size(),
            "total_employees": sum_all_employees(state)
        }

    # 计算状态哈希
    func compute_state_hash(state: GameState) -> String:
        var json = JSON.stringify(state, "", false)
        return json.md5_text()
```

### 校验器注册表（Validator Registry）

- 结构：每个动作类型维护一个验证器链 `validators: Array[Validator]`。
- 验证器接口：`func validate(action, state, context) -> Result`
  - `Result` 包含：`ok: bool`、`error_message: String`、`warnings: Array[String]`
- 模块扩展方式：
  - `ValidatorRegistry.add_validator(action_type, validator, priority)`: 添加新验证器
  - `ValidatorRegistry.replace_validator(action_type, old_name, new_validator)`: 替换既有验证器
  - `ValidatorRegistry.remove_validator(action_type, validator_name)`: 移除验证器
- 执行：按 `priority` 升序执行，任一失败则整个验证失败。
- 内置验证器：
  - `PhaseValidator`: 检查动作是否在正确阶段执行
  - `ResourceValidator`: 检查资源是否充足
  - `PlacementValidator`: 检查放置是否合法
  - `StructureValidator`: 检查公司结构是否合法

### 价格计算管道（Pricing Pipeline，可插拔）

- 设计目标：将定价逻辑从硬编码改为可插拔的修饰器管道，模块可注册自定义定价规则。
- 核心组件：
  - `PricingPipeline`: 维护有序的 `PriceModifier` 列表，按优先级执行。
  - `PriceModifier`: 接口 `func apply(context: PriceContext) -> PriceContext`
    - `PriceContext` 包含：`base_price`、`quantity`、`has_garden`、`bonuses: Array`、`multipliers: Array`、`player_id`、`house_id`、`products: Array`
- 基础修饰器（按优先级顺序）：
  1. `BasePriceModifier` (priority: 0): 设置基础单价（默认 10，可被定价/折扣/奢侈品经理调整）
  2. `GardenMultiplier` (priority: 100): 花园倍增（仅对单价部分 `base_price * quantity` 翻倍）
  3. `MilestoneBonusModifier` (priority: 200): 里程碑奖励（如"首个营销汉堡"按件 +$5）
  4. `EmployeeBonusModifier` (priority: 300): 职业奖励（如"薯条厨师"按房屋 +$10）
  5. `FloorZeroModifier` (priority: 900): 最终价格下限钳制为 0（不会出现负收入）
  6. `CFOModifier` (priority: 1000): CFO 倍增（×1.5 向上取整，在晚餐阶段末统一应用）
- 模块注册方式：

  ```gdscript
  # 模块可插入自定义修饰器
  PricingPipeline.register_modifier(CustomPriceModifier.new(), priority: 150)

  # 示例："储备价格"模块锁定基础单价
  class ReservePriceModifier extends PriceModifier:
      var locked_price: int = 10
      func apply(context):
          context.base_price = locked_price
          return context
  ```

- 执行流程：

  ```gdscript
  func calculate_price(base_params):
      var context = PriceContext.new(base_params)
      for modifier in modifiers.sort_by_priority():
          context = modifier.apply(context)
      return context.final_price
  ```

---

## 地图与路径系统

### 地图板块与坐标

- 地图由若干 5×5 板块拼接成矩形网格；支持随机朝向（0/90/180/270）。
- 坐标体系（更新）：
  - 渲染坐标：像素/世界单位用于渲染；
  - 世界格坐标（唯一逻辑坐标）：统一使用整图级"世界格"（world cell）坐标 `(wx, wy)`，其范围为 `0..(grid_x*5-1)`、`0..(grid_y*5-1)`。

### 地形系统（可插拔）

- 设计目标：支持模块注册新的地形类型及其效果，如"公园"的邻接价格倍增。
- 核心概念：地形（terrain）是独立于结构（structure）的底层属性，一个格子可以同时有地形和结构。

#### 地形注册表（TerrainRegistry）

- 核心接口：

  ```gdscript
  class TerrainType:
      var id: String
      var name: String
      var visual_asset: String = ""  # 渲染资源路径
      var placement_cost: int = 0    # 放置成本（若允许玩家放置）
      var can_build_on: bool = true  # 是否允许在上面建造结构
      var tags: Array[String] = []   # 标签（如 "scenic", "commercial"）

  class TerrainEffectModifier extends PriceModifier:
      # 地形效果作为定价修饰器，符合纯函数原则
      var terrain_id: String
      var effect_type: String  # "adjacency_price_multiply", "adjacency_bonus" 等
      var params: Dictionary

      func apply(context: PriceContext) -> PriceContext:
          var affected_positions = get_affected_positions(context.house_pos)
          if has_adjacent_terrain(affected_positions, terrain_id):
              match effect_type:
                  "adjacency_price_multiply":
                      context.price_multiplier *= params.get("multiplier", 2.0)
                  "adjacency_bonus":
                      context.bonuses.append(params.get("bonus", 10))
          return context

      func has_adjacent_terrain(positions: Array, terrain_id: String) -> bool:
          for pos in positions:
              if map.get_terrain(pos) == terrain_id:
                  return true
          return false

      func get_affected_positions(house_pos: Vector2i) -> Array[Vector2i]:
          # 四向邻接（可配置为八向）
          return [
              house_pos + Vector2i(1, 0),
              house_pos + Vector2i(-1, 0),
              house_pos + Vector2i(0, 1),
              house_pos + Vector2i(0, -1)
          ]
  ```

#### 模块注册地形

```gdscript
# "说客"模块注册公园地形
class ModuleLobbyists:
    func on_enable():
        # 1. 注册地形类型
        TerrainRegistry.register_terrain(TerrainType.new({
            "id": "park",
            "name": "公园",
            "visual_asset": "res://assets/terrain/park.png",
            "can_build_on": false,  # 公园上不能建房
            "tags": ["scenic"]
        }))

        # 2. 注册地形效果（作为定价修饰器）
        PricingPipeline.register_modifier(
            TerrainEffectModifier.new({
                "terrain_id": "park",
                "effect_type": "adjacency_price_multiply",
                "params": {"multiplier": 2.0}  # 邻接公园的房屋价格×2
            }),
            priority: 105  # 在花园倍增(100)之后
        )

        # 3. 注册放置公园的动作
        ActionRegistry.register_action("PlacePark", PlaceParkAction.new())

# 放置公园的动作实现
class PlaceParkAction extends Action:
    func execute(params, state):
        var pos = params.position
        # 校验：格子为空且不在道路上
        if not map.is_cell_empty(pos):
            return {ok: false, error: "格子已占用"}

        # 写入地形数据
        var diff = Diffs.dset(
            "/game/map/cells/%d/%d/terrain_type" % [pos.y, pos.x],
            "park"
        )
        return {ok: true, diff: [diff]}
```

#### 地形数据存储

- 地图格子结构：

  ```gdscript
  # map.cells[y][x] 的完整结构
  {
      "terrain_type": "park",  # 地形层（默认 null 或 "ground"）
      "structure": {           # 结构层（房屋、餐厅等）
          "piece_id": "house",
          "owner": 0,
          ...
      },
      "road_segments": [...],  # 道路层
      ...
  }
  ```

- 分层优势：
  - 地形和结构解耦，可独立修改
  - 一个格子可以有"公园地形 + 空结构"（纯公园）
  - 或"草地地形 + 房屋结构"（普通房屋）

#### 地形效果应用流程（端到端）

1. **放置阶段**（工作时间）：
   - 说客在岗 → 玩家选择位置 → 执行 `PlacePark` 动作
   - Diff 写入：`/game/map/cells/3/5/terrain_type = "park"`

2. **定价阶段**（晚餐时间）：
   - 房屋 #7 需要分配餐厅
   - `PricingPipeline.calculate_price()` 遍历所有修饰器
   - `TerrainEffectModifier` (priority: 105) 执行：
     - 查询房屋周围四个格子的 `terrain_type`
     - 发现 (3, 5) 是 "park"
     - 修改 `context.price_multiplier *= 2.0`
   - 返回倍增后的价格上下文

3. **视觉反馈**（UI）：
   - 公园格子渲染绿色公园图标
   - 悬停时显示："邻接房屋价格×2"

#### 邻接检测配置

```gdscript
# 地形效果可配置邻接范围
class TerrainEffectModifier:
    enum AdjacencyType {
        ORTHOGONAL_4,  # 四向（上下左右）
        DIAGONAL_4,    # 对角线四向
        ALL_8,         # 八向
        RANGE_2        # 范围2格内
    }

    var adjacency_type: AdjacencyType = ORTHOGONAL_4

    func get_affected_positions(house_pos: Vector2i) -> Array[Vector2i]:
        match adjacency_type:
            ORTHOGONAL_4:
                return get_orthogonal_neighbors(house_pos)
            ALL_8:
                return get_all_8_neighbors(house_pos)
            RANGE_2:
                return get_positions_in_range(house_pos, 2)
```

#### 地形与棋件的关系

| 概念 | 存储位置 | 用途 | 示例 |
|------|---------|------|------|
| **地形** | `cells[y][x].terrain_type` | 底层环境属性 | 公园、沙漠、水域 |
| **结构** | `cells[y][x].structure` | 玩家建造的棋件 | 房屋、餐厅、营销板 |
| **道路** | `cells[y][x].road_segments` | 连通性 | 公路、桥 |

- 公园在 rules.md 中是说客放置的，所以是**地形**（terrain），不是结构
- 房屋是**结构**，通过 PieceDef 定义
- 两者可共存（未来可能支持"公园里的房屋"，但当前公园设置 `can_build_on: false`）

### 距离与路径（按格道路段模型）

- 道路段（road_segments）：每个格包含“若干个相互独立的道路段”，每段由若干方向（N/E/S/W）构成；
  - 直线：如竖直段 `[N,S]`，水平段 `[E,W]`；
  - 交叉口（已确认）：普通十字路口用单段 `[N,E,S,W]` 表达，表示四向互通；
  - 桥/不相交十字（已确认）：同一格写成两段 `[[N,S],[E,W]]`，表示竖直与水平在此格不连通；
  - 单行（可选，预留）：段可附加 one_way 定义，限制边的通行方向；
- 连通性：图构建遍历所有格的所有段，段内方向连接为邻接，且同格不同段互不相通；
- “街区”划分：凡段覆盖的边界均视为道路边，用于分割街区（桥因有两个方向段，会在两方向上分区）；
- 距离定义：从餐厅入口到房屋服务边（相邻道路）在“有效道路”上求最短路；距离的“跨板块计数”在构图期通过世界格坐标与板块边界索引推导，运行期不再查询 tile 数据。
- 飞机与边缘放置：按行/列覆盖，不走公路；位置用 `edge/index` 表示，合法范围由地图世界格尺寸推导；后续可在 `RoadGraph` 中接入为虚拟节点/边以参与范围/放置校验；
- 采购员路径：
  - 起点为己方任一餐厅入口；
  - 禁止立即 180° 掉头（U 型）；
  - 每个饮品标志对单一采购员每回合仅生效一次；
  - 可跨板块，记录跨越次数仅用于距离（与销售计算分离）。

### 放置规则

- 餐厅：2×2 占位、入口标识；初始放置限制仅在设置阶段；移动/放置需保证在空格上且与公路邻接（入口）。
- 免下车能力（Drive-Thru）：
  - 触发条件：玩家在工作阶段使用了本地经理或区域经理。
  - 效果：该玩家的所有餐厅在**本回合**自动获得"免下车"能力，餐厅的四个角落都视为入口。
  - 状态管理：在玩家状态中增加 `drive_thru_active: bool` 标志，在清理阶段重置为 `false`。
  - 距离计算：启用"免下车"时，计算到餐厅的距离以最近的角落为准。
- 营销物：
  - 广告牌/邮箱/收音机需放在空格且邻接公路；
  - 收音机可放在任意道路旁，与自家连通性无关；
  - 飞机放置于地图边缘（地图外侧），通过 `edge/index` 指定行或列；不占用世界格，仅登记实例；若未提供 `edge/index`，则按地图长边与 `pos` 推导行/列。
  - 营销板编号管理：按玩家人数在"设置"阶段移除指定编号，编号与资源严格一致（2p：#12/#15/#16；3p：#15/#16；4p：#16；5p：无）。
- 花园与带花园房屋：
  - 直接放置：`house_with_garden` 作为 2×3（或旋转 3×2）结构，`placement_rules.must_be_on_empty=true` 且 `must_touch_road=true`；
  - 附加合并：通过动作 `AddGarden` 在"纯房屋（piece_id=house）"相邻两格放置花园，且必须与该 2×2 房屋对齐形成 2×3/3×2；校验器 `GardenPlacementValidator` 保证：
     1) 所有花园要占用的格子为空；
     2) 邻接对象必须是 `house` 而非 `house_with_garden`；
     3) 能与该房屋形成完整矩形（对齐于某一侧）。
  - 合并写入：执行器 `AddGarden` 将相应区域写为 `house_with_garden`，替换原来房屋/花园格的 `structure.piece_id`。
- 房屋编号分配（House Numbering）：
  - 印刷房屋：地图板块中预置的房屋（`TileDef.printed_structures`）的编号由 `house_number` 字段定义。
  - 运行时放置：通过 `PlaceHouseGarden` 动作放置的新房屋，编号自动分配规则：
    - 维护全局计数器 `next_house_number`，初始值为"印刷房屋的最大编号 + 1"。
    - 每次放置新房屋时，分配 `next_house_number` 并递增。
    - 房屋编号用于晚餐阶段的处理顺序（按编号升序）。
  - 字符串编号：公寓楼等特殊房屋可使用字符串编号（如"π"、"9 3/4"），排序时按数值转换（`float(house_number)`），无法转换的排在最后并按字典序。

---

## 公司与员工系统

### 员工卡

- 字段：职业名、是否付薪（$）、可培训路线（树）、范围/距离（公路/飞艇）、卡槽数（经理）、唯一限制（1x）。
- 忙碌营销员：从公司结构移出，不占卡槽，仍需在发薪日付薪。

### 公司结构（金字塔）

- CEO 顶点；直接下属数量不得超卡槽；
- 经理只能直接向 CEO 汇报；经理的下属禁止为经理；
- 重组时自动校验，超限则除 CEO 外全部转为"待命"。
- 结构验证（可插拔）：
  - 设计目标：公司结构规则应可被模块扩展或替换，以支持新的组织模式。
  - 验证器接口：

    ```gdscript
    class StructureRule:
        var name: String
        var priority: int
        func check(structure, player_state) -> Result:
            # 返回 { ok: bool, error_message: String }
            pass
    ```

  - 内置规则：
    - `CEOSlotsRule`: 检查 CEO 直接下属不超过卡槽数
    - `ManagerHierarchyRule`: 检查经理只向 CEO 汇报，且下属不能是经理
    - `BusyMarketerRule`: 检查忙碌的营销员不占用卡槽
    - `UniqueEmployeeRule`: 检查 1x 唯一职位限制
  - 模块扩展方式：

    ```gdscript
    # 添加新规则
    CompanyStructureValidator.add_rule(CustomRule.new(), priority: 150)

    # 替换既有规则（如允许双层经理的模块）
    CompanyStructureValidator.replace_rule("ManagerHierarchyRule",
        AllowDoubleManagersRule.new())

    # 移除规则
    CompanyStructureValidator.remove_rule("UniqueEmployeeRule")
    ```

### 招聘/培训/薪资

- 招聘：CEO 每回合 1 次免费招聘入门级；可“缺货预支”但需紧接培训为上级职位。
- 培训：仅要求最终职位有牌可用，中间职位可缺货。
- 发薪：先可解雇任意数量员工（在岗/待命，卡牌回供应区）。随后为所有“带薪”员工每人支付 $5，忙碌营销员照付；所有折扣必须使用（招聘经理/HR 未用的招聘次数每次 $5）。最低支付为 $0。若已解雇所有其他带薪员工仍无力支付忙碌的营销员，可解雇该忙碌的营销员（营销活动保留在版图上）。

---

## 库存与营销系统

### 库存

- 食物（汉堡、披萨）与饮品（软饮、柠檬水、啤酒）无限供应；玩家库存共享于所有餐厅。
- 大配件=5 小配件（UI 层面聚合显示）。
- 清理（更新）：
  - 无“冰箱容量”则清空；
  - 有容量则将每种产品各自限幅到容量（当前简化，后续可改为“总容量”按策略分配）。
  - 在 `Cleanup.Apply` 中以 `Diffs.dset` 下发至 `/game/player_inventories/<pid>/<product>`。
- 饮品来源约束：饮品标志无限产量；同回合可被多名采购员依次拾取；单一采购员对同一来源每回合仅记一次拾取。

### 营销

- 发起：每位在岗营销员 1 次，选择编号（id）、时长与目标产品；类型恒由编号映射（`type = Registry.marketing_defs[id].type`），UI 不再提供类型选择；
- 持续：在营销活动阶段按编号升序结算；从板块移除 1 个持续标记（飞机不写入世界格，仅递减实例持续）；0 时收回板与忙碌标记；
- 需求上限：普通房屋最多 3，有花园最多 5（公寓楼/乡村等模块可覆盖）。
- 范围计算（可插拔）：
  - 设计目标：营销范围算法应完全数据驱动，模块可注册自定义范围计算器。
  - 内置范围类型：
    - `adjacent_orthogonal_houses`: 广告牌，影响横向/纵向相邻的房屋
    - `same_block`: 邮箱，影响同一街区（不跨道路连通域）的所有房屋
    - `tiles_3x3`: 收音机，影响所在板块及周围 8 个板块的所有房屋
    - `line_row_or_col`: 飞机，影响飞行路径下（一行或一列）的所有房屋
  - 自定义范围计算器：

    ```gdscript
    # 模块可注册自定义范围计算器
    class CustomRangeCalculator extends MarketingRangeCalculator:
        func calculate(marketing_instance, map_state) -> Array[Vector2i]:
            # 返回受影响的房屋世界格坐标列表
            return affected_house_positions

    # 在模块启用时注册
    MarketingRegistry.register_range_calculator("custom_range", CustomRangeCalculator.new())
    ```

  - MarketingDef 中指定范围类型：

    ```json
    {
      "effect": {
        "kind": "custom_range",  // 内置类型或注册的自定义类型
        "params": { "radius": 3 }  // 可选参数，传递给计算器
      }
    }
    ```

---

## 晚餐时间与经济系统

### 决策流程

1) 按房屋编号升序；
2) 过滤候选餐厅：需道路连通且有足够库存满足“全部需求”；
3) 选择：最小化（单价 + 距离）；
4) 平局：女服务员数量多者胜；仍平局由回合顺序靠前者胜；
5) 结算：扣减库存、收入入账；
6) 女服务员：阶段结束后统一入账（3 或 5）；
7) CFO：对本回合总现金应用 ×1.5 向上取整（最终收入不为负）；
8) 破产与银行：不因负价产生对银行的支付；银行破产仍按基础规则处理。

### 价格与奖励

- 花园：仅倍增单价部分；
- 里程碑：如“营销汉堡/披萨/饮品”按件 +5 奖励；
- 模块：如“薯条厨师”按房屋 +10 固定奖励；
- 售价下限：最终收入不低于 0（不会出现负收入或向银行支付）；
- 基础单价：默认 10；可被定价/折扣/奢侈品经理与“储备价格”等模块调整。

---

## 里程碑系统

- 触发即生效，通常强制；同回合多名可获得；
- 清理阶段：本回合被至少一名玩家获得的"类型"从供应区移除（其他玩家不再可得）；
- 示例（见 rules.md 第5节）：首个广告牌、首个培训、首个女服务员、首个拥有 $100（CEO 获 CFO 能力）等。
- 过期机制（Expiration）：
  - 部分里程碑有时间限制，如果在指定回合结束前未被获得，将自动从供应区移除。
  - MilestoneDef 中增加 `expires_at: int` 字段（默认 `null` 表示永不过期）：

    ```json
    {
      "id": "first_train_someone",
      "name": "首个培训员工",
      "expires_at": 2,  // 第二回合结束后移除
      ...
    }
    ```

  - 在清理阶段的 `before_exit` 钩子中检查并移除过期里程碑：

    ```gdscript
    PhaseManager.register_hook("Cleanup", "before_exit",
        func(state, ctx):
            for milestone in state.available_milestones:
                if milestone.expires_at and ctx.round_number >= milestone.expires_at:
                    remove_milestone_from_supply(milestone)
        , priority: 150)
    ```

  - 典型应用（"艰难抉择"模块）：
    - "首个营销汉堡/披萨/饮品"、"首个培训员工" → 第二回合后移除
    - "首个一回合雇佣三人" → 第三回合后移除

---

## 扩展模块（插件化）

### 模块系统 V2（严格模式，最终方案）

- 权威设计文档：`docs/architecture/60-modules-v2.md`
- ADR：`docs/decisions/0002-modules-v2-strict-mode.md`
- 核心约束：
  - 禁用模块 = 该模块员工/里程碑/规则在运行期**完全不存在**（严格模式）
  - 阶段结算（Dinnertime/Payday/Marketing/Cleanup…）必须由模块注册；缺失主结算器 → **初始化失败**
  - 供应池/可选集合由启用模块内容推导（不再在 `GameConfig` 写死类似 `one_x_employee_ids` 的列表）
- 落盘目录结构：`res://modules/<module_id>/`（每个模块独立目录 + `README.md` 描述文件 + 可选 `content/` 与 `rules/`）

> 本章节下方的“V1 插件机制”描述用于解释当前已实现代码路径；后续实现将按 V2 方案迁移并逐步淘汰 V1。

### 模块系统 V1（当前实现，待迁移）

#### 插件机制

- 每个模块包含：`ModuleDef` 资源（ID、依赖、启用/停用钩子、优先级）、脚本实现（注册校验器/钩子/数据）。
- 可注入点：
  - 数据：新增员工/里程碑/地图板块；
  - 规则：追加或替换校验器（如放置/路径/结算）；
  - 事件：监听阶段事件（如“营销结算轮次扩展”、“番茄酱距离 -1”）。

#### 模块声明与加载流程

- 配置源：`data/config/game_config.json`（未来：可加入模块启用清单字段）。
- 加载顺序：
  1) 读取模块资源与元数据（`id`、`dependencies`、`priority`）。
  2) 进行依赖拓扑排序与冲突检测。
  3) 依序调用模块脚本的 `on_enable(ctx)`，注入数据/规则/事件订阅。
- 运行期边界：对局开始后禁用启停切换；模块仅通过规则引擎与事件总线修改状态。

#### 冲突与决定性

- 同一钩子链按“依赖拓扑 + priority”顺序执行；
- 标量配置默认“显式覆盖”；集合配置默认“合并”；
- 发现互斥声明（两个模块都替换同一基础集合且未申明互相兼容）时阻止开局；
- 所有修饰器与订阅器必须是纯函数（只依赖上下文与输入），以保证复盘一致。

#### 存档与复盘

- 存档记录：模块 ID 与版本、启用顺序、随机种子、事件流；
- 复盘要求：模块集合与版本必须完全一致，否则拒绝加载；
- 模块内随机性统一使用 `Random.gd` 的受控 RNG。

#### 典型模块落地映射

- 番茄酱（Ketchup）：
  - 订阅 `house_sold` 事件，判断"他人卖出你营销产生的需求"→ 授予里程碑。
  - 在 `PricingPipeline` 中注册距离修饰器，应用 `-1` 距离修正：

    ```gdscript
    class KetchupDistanceModifier extends PriceModifier:
        func apply(context):
            if player_has_ketchup_milestone(context.player_id):
                context.distance -= 1
            return context
    PricingPipeline.register_modifier(KetchupDistanceModifier.new(), priority: 90)
    ```

- 大众营销员（Mass Marketeers）：
  - 在 `PhaseManager` 注册 `Marketing` 阶段的 `before_enter` 钩子。
  - 计算当回合在岗的大众营销员数量 N，设置 `ctx.marketing_rounds = 1 + N`。
  - 营销结算内层循环执行 N 轮；持续标记在所有轮次结束后统一 -1。

- 夜班经理（Night Shift Managers）：
  - 在 `PhaseManager` 注册 `Working` 阶段的 `after_enter` 钩子。
  - 复制"无薪员工"的行动队列（CEO 排除）：

    ```gdscript
    PhaseManager.register_hook("Working", "after_enter",
        func(state, ctx):
            if has_night_shift_manager(state.current_player):
                for employee in get_no_salary_employees(state.current_player):
                    if employee.id != "ceo":
                        ctx.action_queue.append(duplicate_action(employee))
        , priority: 100)
    ```

- 储备价格（Reserve Prices）：
  - 替换首次破产处理器，固定补充"玩家数×200"。
  - 在 `PricingPipeline` 注册基础单价锁定器：

    ```gdscript
    class ReservePriceModifier extends PriceModifier:
        var locked_price: int  # 5/10/20 根据储备卡决定
        func apply(context):
            context.base_price = locked_price
            return context
    PricingPipeline.register_modifier(ReservePriceModifier.new(), priority: 5)
    ```

- 新区域（New Districts）：
  - 注册公寓楼棋件到 `Registry.piece_defs`。
  - 注册需求规则修饰器：

    ```gdscript
    # 公寓楼需求翻倍
    MarketingRegistry.add_demand_modifier(
        func(house, demand):
            if house.piece_id == "apartment":
                return demand * 2
            return demand
    )
    # 公寓楼无需求上限
    MarketingRegistry.override_demand_cap("apartment", null)
    ```

- 乡村营销员（Rural Marketeers）：
  - 注册乡村 Piece 与"高速公路出口"边缘端口。
  - 扩展晚餐顺序，使乡村在最后结算且无上限：

    ```gdscript
    PhaseManager.register_hook("Dinnertime", "before_enter",
        func(state, ctx):
            ctx.house_order.append("rural_area")  # 排在最后
        , priority: 200)
    ```

- 艰难抉择（Hard Choices）：
  - 替换基础里程碑集合，为指定里程碑设置 `expires_at`。
  - 在 `Cleanup` 阶段的 `before_exit` 钩子中移除到期里程碑（见"阶段钩子系统"示例）。

- 电影明星（Movie Stars）：
  - 注册"决定顺序"阶段的优先级比较器：

    ```gdscript
    OrderOfBusinessManager.add_tiebreaker(
        func(player_a, player_b):
            if has_movie_star(player_a) and not has_movie_star(player_b):
                return -1  # player_a 优先
            return 0
        , priority: 10)
    ```

  - 注册"女服务员平局"决策修饰器：

    ```gdscript
    DinnertimeManager.add_tiebreaker("waitress_count",
        func(player_a, player_b):
            if has_movie_star(player_a):
                return -1  # 自动胜出
            return 0
        , priority: 5)
    ```

- 说客（Lobbyists）：
  - 新建公路：通过 `MapService.add_road_overlay()` 增量添加 `road_segments` 段，初始 `state=construction`（不连通、不分区）；清理后 `promote_to_built()`（并入有效连通且作为街区分隔）。
  - 路障：对既有道路边打标记；晚餐寻路时，每穿越 1 个"有路障"的边，距离+1；清理阶段移除标记。
  - 公园：通过 `TerrainRegistry.register_terrain()` 注册公园地形类型，通过 `PricingPipeline.register_modifier()` 注册价格倍增修饰器（见"地形系统"完整示例）。

### UI 与配置联动

- 设置向导读取模块元数据（名称、描述、依赖与冲突），灰化非法组合；
- 模块的 UI 描述仅用于展示；实际生效仍通过上述注册与订阅机制。

---

## 数据模型与资源格式

### 通用棋件占位与旋转（PieceDef）

为适配餐厅 2×2、可能存在的“自带花园房屋（例如 2×3）”、以及不同尺寸/形状的营销板件，引入统一的棋件定义：

```json
{
  "id": "house_with_garden_2x3",
  "name": "带花园房屋(2x3)",
  "category": "structure",                 
  "footprint": {
    "mask": [                               
      [1,1,1],
      [1,1,1]
    ],
    "anchor": [0,0],                        
    "rotation_allowed": [0,90,180,270],
    "mirror_allowed": false
  },
  "entrances": {                             
    "type": "adjacent_road",
    "points": []
  },
  "placement_rules": {
    "must_be_on_empty": true,                
    "must_touch_road": true,                 
    "forbidden_layers": ["road_center"],
    "allowed_on": ["ground"]
  },
  "served_via": "adjacent_road"            
}
```

- footprint.mask：二维 0/1 网格，定义占位形状；任意多格与不规则形状均可。
- anchor：掩码左上角相对锚点，放置时以锚点对齐地图单元。
- rotation_allowed / mirror_allowed：允许的旋转/镜像，满足不同组件朝向需求。
- entrances：
  - type = "adjacent_road"（房屋/公寓等）：通过与道路相邻的任意边即可被服务，不需要显式门点。
  - type = "points"（餐厅/咖啡店等）：显式列出可用入口点，供距离与放置校验。
- placement_rules：通用放置约束；可扩展如“必须邻接某类地形/边缘”等。
- served_via：定义晚餐阶段服务终点的计算方式（房屋默认是道路相邻；餐厅使用 entrances.points）。

示例：餐厅 2×2（四角为潜在入口，驱动“免下车”能力时视为全部入口生效）：

```json
{
  "id": "restaurant_2x2",
  "category": "structure",
  "footprint": { "mask": [[1,1],[1,1]], "anchor": [0,0], "rotation_allowed": [0,90,180,270] },
  "entrances": { "type": "points", "points": [[0,0],[1,0],[0,1],[1,1]] },
  "served_via": "entrance_points"
}
```

### 员工定义（EmployeeDef JSON）

```json
{
  "id": "waitress",
  "name": "女服务员",
  "salary": true,
  "unique": false,
  "manager_slots": 0,
  "range": { "type": null, "value": 0 },
  "train_to": ["movie_star"],
  "tags": ["tips_provider"],
  "mandatory": true  // 女服务员的行动是强制的
}
```

示例：定价经理（强制行动）

```json
{
  "id": "pricing_manager",
  "name": "定价经理",
  "salary": true,
  "unique": true,
  "manager_slots": 0,
  "train_to": [],
  "tags": ["pricing_control"],
  "mandatory": true  // 定价经理必须设置价格
}
```

### 里程碑定义（MilestoneDef JSON）

```json
{
  "id": "first_billboard",
  "name": "首个放置广告牌",
  "trigger": { "event": "PlaceMarketing", "filter": {"type":"billboard"} },
  "effects": [
    { "type": "marketing_no_salary" },
    { "type": "marketing_permanent" }
  ],
  "exclusive_type": "first_billboard",
  "expires_at": null  // 永不过期
}
```

示例：有时间限制的里程碑（"艰难抉择"模块）

```json
{
  "id": "first_train_someone",
  "name": "首个培训员工",
  "trigger": { "event": "Train" },
  "effects": [
    { "type": "salary_discount", "amount": 15 }
  ],
  "exclusive_type": "first_train",
  "expires_at": 2  // 第二回合结束后过期
}
```

### 地图板块定义（TileDef JSON）

为避免“预置花园”语义不清，将原 `prebuilt_gardens` 改为 `printed_structures`，直接声明印刷在板块上的固定棋件（含占位与旋转）。道路采用“按格道路段（road_segments）”以简洁支持桥/交叉口/单行。

```json
{
  "id": "tile_A1",
  "size": [5,5],
  "rotation_allowed": [0,90,180,270],           
  "layers": {
    "ground": [[0,0,0,0,0], ...],               
    "blocked": [ [0,0,0,0,0], ... ]             
  },
  "road_segments": [                             
    [ [], [{"dirs":["E","W"]}], [], [{"dirs":["N","S"]}], [] ],
    [ [], [{"dirs":["E","W"]}], [{"dirs":["N","S"]},{"dirs":["E","W"]}], [{"dirs":["N","S"]}], [] ],
    [ [], [{"dirs":["E","W"]}], [], [{"dirs":["N","S"]}], [] ],
    [ [], [], [], [], [] ],
    [ [], [], [], [], [] ]
  ],
  "road_graph_overrides": { "one_way": [] },
  "printed_structures": [                        
    {
      "piece_id": "house_with_garden",     
      "anchor": [2,1],                           
      "rotation": 90,
      "house_id": "2",
      "house_number": 2,                         
    },
    {
      "piece_id": "apartment",                   
      "anchor": [0,4],
      "rotation": 0，
      "house_id": "π",
      "house_number": 3.14,
    }
  ],
  "drink_sources": [{"pos":[0,4],"type":"beer"}]
}
```

- printed_structures：表达“自带花园的房屋”等复合占位的印刷物；随板块旋转一起旋转。
- house_spots 被移除，改由 printed_structures 或运行时放置的 Piece 来表示房屋。
- road_segments：以段表达道路；桥用同格多段互不相通来建模；可附带单行。

### 地图定义（MapDef JSON）

用于描述整张地图的拼接。

```json
{
  "id": "map_3x4_random",
  "grid_size": [3,4],
  "tiles": [
    {"tile_id":"tile_A1", "board_pos":[0,0], "rotation":90},
    {"tile_id":"tile_B2", "board_pos":[1,0], "rotation":0}
  ]
}
```

#### 运行期不依赖 Tile 的约定（更新）

- 仅在地图构建与烘焙阶段读取 `TileDef/MapDef`，将道路段、印刷结构、饮品来源等全部下沉写入 `map.cells[y][x]` 与必要的全局索引。
- 烘焙完成后，运行期一切规则逻辑（放置、校验、路径、距离、营销范围、销售）只查询世界格坐标与 `map.cells`/索引，不再访问 tile 或 `board_pos/cell`。
- UI 可显示板块边框/编号；印刷建筑与饮品源的顶绘也改为从 `map.cells` 读取。道路与边框的可视化可继续使用 `tiles[*].roads` 与板块外观，但仅限渲染用途。

#### 坐标规范与迁移结论

- 统一坐标：运行期仅使用世界格坐标 `pos: Vector2i(wx, wy)`；`board_pos/cell` 已移除，不再兼容。
- 反算仅用于渲染或调试：`board_pos = Vector2i(floor(wx/5), floor(wy/5))`，`cell = Vector2i(wx%5, wy%5)`。
- 数据结构：所有行动与状态仅保留 `pos` 或 `cells: Array[Vector2i]` 字段。

#### 验证器与放置 API 收敛（更新）

- Validators：统一入口 `run_checks_common(map_ctx, pos, piece_id, foot_offsets, context)`（世界格签名）。所有注册的检查器函数也采用世界格签名 `(map_ctx, pos, piece_id, foot_offsets, context) -> { ok }`。
- StructurePlacement：移除旧的 bpos/cell 接口，仅保留世界格函数：
  - `check_world_cells_empty(map_ctx, world_anchor, anchor_base, foot_offsets)`
  - `get_world_cells_for_foot_world(world_anchor, anchor_base, foot_offsets)`
  - `write_structure_world(map_ctx, world_anchor, anchor_base, piece_id, foot_offsets, dynamic)`

### 模块系统（V2，已实现）

本项目已落地模块系统 V2（严格模式），用于将**内容**与**规则**按“启用的模块集合”装配到每局游戏中，避免硬编码与跨模块耦合。

详见：

- `docs/architecture/60-modules-v2.md`
- `docs/decisions/0002-modules-v2-strict-mode.md`

约定（简版）：

- 模块包目录：`res://modules/<module_id>/module.json` + `README.md`
- 内容：`modules/<module_id>/content/*`（products/employees/milestones/marketing/tiles/maps/pieces）
- 规则入口：`module.json.entry_script`（例如 `modules/base_rules/rules/entry.gd`，注册 settlements/effects/milestone effects）
- 严格模式：禁用模块 = 运行期完全不存在；缺必需结算器/handler 直接初始化失败（Fail Fast）

### 营销板件定义（MarketingDef JSON）

营销类组件需要同时定义“物理占位”与“效果范围/规则”。

```json
{
  "id": "billboard_1x1",
  "category": "marketing",
  "piece": {
    "footprint": { "mask": [[1]], "anchor": [0,0], "rotation_allowed": [0,90,180,270] },
    "placement_rules": { "must_touch_road": true, "must_be_on_empty": true }
  },
  "effect": {
    "kind": "adjacent_orthogonal_houses",     
    "amount_per_house": 1,
    "cap_rules": { "normal": 3, "with_garden": 5 },
    "duration_type": "tokens",                
    "order_key": "board_number"               
  },
  "board_number": 12                           
}
```

飞机营销：

```json
{
	  "id": "airplane_edge",
	  "category": "marketing",
	  "piece": {
	    "footprint": { "mask": [[1]], "anchor": [0,0], "rotation_allowed": [0] },
	    "placement_rules": { "must_be_on_map_edge": true }
	  },
	  "effect": {
	    "kind": "line_row_or_col",               
	    "amount_per_house": 1,
    "select": { "axis": "row_or_col" }
  },
  "board_number": 15
}
```

收音机与邮箱示意：

```json
{
  "id": "radio_1x1",
  "piece": { "footprint": { "mask": [[1]] }, "placement_rules": { "must_touch_road": true } },
  "effect": { "kind": "tiles_3x3", "amount_per_house": 1 }   
}
```

```json
{
  "id": "mailbox_1x1",
  "piece": { "footprint": { "mask": [[1]] }, "placement_rules": { "must_touch_road": true } },
  "effect": { "kind": "same_block", "amount_per_house": 1 }  
}
```

说明：

- same_block：与其所在道路连通，不跨越道路的连通域中的所有房屋。
- tiles_3x3：所在板块及其 8 邻接板块。
- line_row_or_col：沿所选行/列覆盖整条线。

```json
{
  "id": "fcm_ketchup",
  "name": "番茄酱机制",
  "dependencies": [],
  "enable_hooks": ["on_enable"],
  "events": ["on_house_sold"],
  "priority": 100
}
```

---

### 营销板件清单与编号表（模板）

用途：集中维护所有营销板件的“种类、棋件尺寸（footprint）与编号”，供范围结算与“按玩家人数移除编号”使用。

- 数据来源：`modules/*/content/marketing/*.json`
- 读取入口：`Registry.register_marketing_defs(...)` 并在开局由 `Game.gd` 写入 `game.removed_board_numbers`

字段约定（每条板件记录）：

- id：编号（字符串，例如 "12"，用于排序与移除规则；排序时按数值转换）
- type：种类（`billboard` | `mailbox` | `radio` | `airplane`）
- size：二维数组 `[w,h]`，例如 `[1,1]`、`[3,2]`
- （可选）mask/anchor：若提供 `mask: number[][]` 与 `anchor:[ax,ay]`，引擎在预览与落地时将优先按掩码形状放置；未提供则回退为矩形 `size`。

按玩家人数移除（模板）：

- 2 人：移除 [12, 15, 16]
- 3 人：移除 [15, 16]
- 4 人：移除 [16]
- 5 人：不移除

示例（节选）：

```text
编号(id)  type       size
--------  ---------  -----
"1"       radio      [1,1]
"4"       airplane   [1,2]
"7"       mailbox    [2,2]
"11"      billboard  [2,3]
"12"      billboard  [2,2]
"15"      billboard  [1,1]
```

说明：尺寸对应放置棋件的 footprint（后续由 `Registry` 基于 type+size 解析到具体棋件）；飞机为边缘放置棋件，放置校验要求在地图边缘（例如用 `edge/index` 坐标）。

---

## UI 与交互流程

### 设计原则（参考业界最佳实践）

本游戏的 UI/UX 设计参考了以下成功游戏的设计理念：

- **Slay the Spire**：卡牌游戏 UI 黄金标准（智能状态切换、清晰反馈）
- **Into the Breach**：极简策略 UI（精确预测、可撤销操作）
- **Civilization VI**：回合策略游戏（强制决策锁定、上下文帮助）
- **Wingspan (数字版)**：桌游数字化典范（动画流畅、规则清晰）
- **Root (数字版)**：现代桌游数字化（实时对战解算、规则提示）

核心设计原则：

1. **零认知负担**：UI 自动适应当前阶段，玩家无需记忆操作流程
2. **即时反馈**：所有操作提供视觉/数值预测，避免"黑盒"决策
3. **安全操作**：关键决策有确认流程，阶段内支持撤销
4. **渐进学习**：新手引导与上下文帮助无缝融合
5. **性能优先**：大地图使用智能渲染，保证 60fps

---

### 主要界面

#### 1. 开局向导（`SetupWizard.tscn`）

**功能**：玩家人数、模块启用、地图生成、储备卡设置

**改进**：

- **预设方案推荐**：

  ```gdscript
  var presets = [
      {
          "name": "快速游戏（30 分钟）",
          "desc": "3 人 | 小地图 | 禁用扩展模块",
          "config": {"players": 3, "map": "2x3", "modules": []}
      },
      {
          "name": "标准游戏（60 分钟）",
          "desc": "4 人 | 标准地图 | 推荐模块",
          "config": {"players": 4, "map": "3x4", "modules": ["ketchup", "coca_cola"]}
      },
      {
          "name": "史诗游戏（90+ 分钟）",
          "desc": "5 人 | 大地图 | 全部模块",
          "config": {"players": 5, "map": "4x5", "modules": "all"}
      }
  ]
  ```

- **模块说明悬停卡片**：鼠标悬停在"番茄酱机制"上时显示完整规则摘要
- **地图预览**：选择地图时显示 3D 预览图和建议玩家数

**参考**：Civilization VI 的游戏设置界面、Wingspan 的扩展选择

---

#### 2. 智能 HUD（`HUD.tscn`）

**功能**：显示当前阶段/子阶段、强制动作提醒、回合顺序轨

**核心改进：UI 状态机自动切换**

```gdscript
class UIStateMachine:
    enum Mode { FREE, PLACEMENT, DECISION, SPECTATOR, BLOCKED }
    var current_mode: Mode = Mode.FREE

    func on_phase_changed(phase: String):
        match phase:
            "Working":
                if has_mandatory_action():
                    enter_decision_mode("员工管理", ["招募", "训练"])
                else:
                    enter_free_mode()

            "Marketing":
                if player.available_marketing > 0:
                    enter_placement_mode("营销板件", preview_marketing)
                else:
                    show_phase_summary("本阶段无可用营销")

            "Dinnertime":
                enter_spectator_mode()  # 自动切换到观战视角
                start_interactive_resolution()

    func enter_decision_mode(category: String, options: Array):
        # 自动展开相关面板，其他面板折叠
        panel_manager.focus_panel(category)
        # 高亮可用选项
        highlight_available_actions(options)
        # 显示上下文帮助
        show_context_help(category)
```

**强制动作视觉锁定**（参考 Civilization VI）

```gdscript
class MandatoryActionBlocker:
    func check_can_end_phase() -> bool:
        var mandatory = get_mandatory_actions()
        if mandatory.size() > 0:
            show_modal_blocker({
                "title": "⚠️ 必须完成以下动作之一",
                "actions": mandatory,
                "buttons": [
                    {"text": "前往完成", "action": "navigate"},
                    {"text": "查看规则", "action": "help"}
                ],
                "cannot_close": true,  # 玩家无法关闭此对话框
                "dim_background": true  # 半透明遮罩
            })
            return false
        return true
```

**UI 展示**：

```
┌─────────────────────────────────────┐
│  ⚠️  你必须完成以下动作之一         │
│                                     │
│  □ 招募新员工                       │
│  □ 训练现有员工                     │
│                                     │
│  未完成将无法进入下一阶段           │
│                                     │
│  [查看规则]       [前往招募] ← 高亮 │
└─────────────────────────────────────┘
       ↑ 其他 UI 被半透明遮罩遮挡
```

**参考**：

- Civilization VI：必须选择科技/政策时锁定 UI
- Root：必须行动时高亮可操作单位

---

#### 3. 公司视图（`CompanyView.tscn`）

**功能**：拖拽排布员工卡、卡槽校验、忙碌标记

**改进**：

- **拖拽预览**：拖动员工卡时实时显示有效/无效卡槽（绿色边框/红色 X）
- **自动排列建议**：点击"自动优化"按钮，AI 推荐最优结构并高亮变化
- **能力图标化**：员工卡上显示图标而非文字（厨师=🍳，服务员=👔，管理=📋）

**参考**：Slay the Spire 的卡牌拖拽、Wingspan 的鸟卡放置预览

---

#### 4. 智能地图（`Board.tscn`）

**功能**：网格/道路/板块边界渲染、放置预览与冲突提示、范围高亮

**核心改进：收益预测系统**（参考 Into the Breach）

```gdscript
class ActionPreview:
    func preview_placement(piece_id: String, pos: Vector2i) -> PreviewData:
        var context = PriceContext.new(...)
        var range_calc = Registry.get_range_calculator(piece_id)
        var affected_houses = range_calc.get_affected_houses(pos, context)

        return {
            "valid": check_placement_valid(pos, piece_id),
            "visual": {
                "highlight_cells": get_footprint_cells(pos, piece_id),  # 绿色
                "range_cells": get_range_cells(pos, piece_id),         # 淡蓝色
                "affected_houses": affected_houses,                    # 黄色边框
                "conflicts": get_conflicts(pos, piece_id)              # 红色 X
            },
            "prediction": {
                "immediate": {
                    "cost": -get_placement_cost(piece_id),
                    "houses_covered": affected_houses.size()
                },
                "this_round": {
                    "estimated_sales": predict_sales(affected_houses),
                    "estimated_revenue": predict_revenue(affected_houses)
                },
                "duration": get_duration_text(piece_id)
            }
        }
```

**悬浮预测卡片**：

```
地图上悬浮显示：
┌──────────────────────────┐
│ 📢 广告牌 #12            │
├──────────────────────────┤
│ 💰 花费: -$15            │
│ 🏠 覆盖: 3 栋房屋        │
│                          │
│ 📊 预计本回合晚餐时间:   │
│   • +2 汉堡销售          │
│   • +$20 收入            │
│   • 击败玩家 B 概率 65%  │
│                          │
│ ⏰ 回合结束后失效        │
│                          │
│ [确认放置]    [取消]     │
└──────────────────────────┘
```

**智能渲染优化**（参考 Factorio）

```gdscript
class SmartBoardRenderer:
    var visible_rect: Rect2i
    var dirty_cells: Set[Vector2i] = Set.new()
    var render_layers = ["terrain", "roads", "structures", "highlights"]

    func _process(delta):
        # 1. 计算可见区域（视口 + 1 格边距）
        var new_visible = calculate_visible_rect(viewport_transform)
        if new_visible != visible_rect:
            visible_rect = new_visible
            queue_full_redraw()

        # 2. 增量渲染脏区域
        if dirty_cells.size() > 0:
            redraw_cells(dirty_cells)
            dirty_cells.clear()

    func on_state_changed(changed_cells: Array[Vector2i]):
        # 只标记变化的格子及其邻居
        for cell in changed_cells:
            dirty_cells.add(cell)
            dirty_cells.add_all(get_neighbors(cell))
```

**参考**：

- Into the Breach：精确预测每个行动的后果（攻击箭头、伤害数值）
- Factorio：大地图分块渲染，视野外降低细节

---

#### 5. 库存与定价（`InventoryPanel.tscn`、`PricingPanel.tscn`）

**功能**：库存数量、单价设置、里程碑效果图标

**改进**：

- **价格建议系统**：

  ```gdscript
  func suggest_optimal_price(player_id: int) -> int:
      var competitors = get_competitor_prices()
      var inventory = get_inventory(player_id)

      if inventory.burgers > 10:
          return min(competitors) - 1  # 库存多，降价促销
      elif inventory.burgers < 3:
          return max(competitors) + 1  # 库存少，提价惜售
      else:
          return avg(competitors)      # 库存适中，跟随市场
  ```

- **价格历史图表**：显示近 3 轮的价格变化曲线
- **对手价格对比**：并排显示所有玩家的当前定价

**参考**：Offworld Trading Company 的市场价格图表

---

#### 6. 营销面板（`MarketingPanel.tscn`）

**功能**：选择营销类型、时长与目标，预览影响范围

**改进**：

- **智能推荐**：根据当前地图布局推荐最优营销位置

  ```gdscript
  func recommend_marketing_placement(piece_id: String) -> Array[Recommendation]:
      var recommendations = []
      for pos in all_valid_positions:
          var score = calculate_placement_score(pos, piece_id)
          recommendations.append({"pos": pos, "score": score})

      recommendations.sort_by_score_desc()
      return recommendations.slice(0, 3)  # 返回前 3 个
  ```

- **对比视图**：选择营销板件后，地图上同时显示所有推荐位置的得分

**参考**：Civilization VI 的城市规划推荐

---

#### 7. 交互式晚餐时间（`DinnertimeViewer.tscn`）

**功能**：逐屋解算、路径与距离、平局说明、价格拆分

**核心改进：从"事后回放"改为"实时观战"**（参考 Root + Tabletop Simulator）

```gdscript
class InteractiveDinnertime:
    enum Mode { ANIMATED, QUICK, REPORT }
    var current_mode: Mode = Mode.ANIMATED

    func run_dinnertime():
        match current_mode:
            Mode.ANIMATED:
                await run_animated_mode()
            Mode.QUICK:
                run_quick_mode()
            Mode.REPORT:
                show_final_report()

    func run_animated_mode():
        for house in demand_houses:
            # 1. 聚焦房屋（相机平滑移动）
            await camera.smooth_move_to(house.pos, duration=0.5)

            # 2. 显示竞争信息
            var competitors = get_competitors_for_house(house)
            show_competition_panel(house, competitors)

            # 3. 玩家预测小游戏（可选）
            if settings.enable_prediction:
                var guess = await ask_player_guess(house, competitors)
                # 稍后对比揭晓

            # 4. 动画展示结果
            var winner = resolve_winner(house, competitors)
            await animate_delivery(winner, house, speed=settings.animation_speed)

            # 5. 结果弹窗
            await show_result_popup(winner, house, {
                "revenue": "+$15",
                "was_correct": (guess == winner) if settings.enable_prediction else null
            })

            # 6. 快进按钮
            if Input.is_action_just_pressed("ui_accept"):
                switch_to_quick_mode()
                break

        show_round_summary()

    func show_competition_panel(house: House, competitors: Array):
        # 在房屋上方显示悬浮面板
        var panel_data = {
            "address": "房屋 #" + str(house.number),
            "demand": house.demand_count,
            "competitors": []
        }

        for comp in competitors:
            panel_data.competitors.append({
                "player": comp.player_name,
                "distance": comp.distance,
                "price": comp.price,
                "modifiers": comp.active_modifiers  # 里程碑、促销等
            })

        show_floating_panel(house.pos, panel_data)
```

**UI 展示**：

```
房屋上方悬浮面板：
┌─────────────────────────────┐
│ 🏠 房屋 #7                  │
│ 需求: 🍔🍔🍔 (3 个)         │
├─────────────────────────────┤
│ 竞争者:                     │
│ 🔴 Alice   距离 3  $10      │
│           +里程碑折扣 -$2   │
│ 🔵 Bob     距离 2  $12      │
│ 🟢 Carol   距离 4  $9       │
├─────────────────────────────┤
│ 你认为谁会赢? (可选)        │
│ [ Alice ]  [ Bob ]  [Carol] │
└─────────────────────────────┘

动画播放：
1. 高亮胜者餐厅（脉冲效果）
2. 汉堡图标沿路径飞向房屋
3. 金币从房屋飞回餐厅
4. 显示 +$15 弹窗
```

**模式切换**：

- **动画模式**（默认）：完整动画 + 可选预测小游戏
- **快速模式**：跳过动画，仅显示文字日志
- **战报模式**：直接显示最终统计表格

**快捷键**：

- `Space`：跳过当前房屋动画
- `Shift+Space`：切换到快速模式
- `Tab`：切换到战报模式

**参考**：

- Root (数字版)：战斗动画可点击跳过，速度可调节
- Tabletop Simulator：骰子动画可快进/关闭
- Slay the Spire：敌人行动有动画但可快进

---

#### 8. 日志与回放（`LogView.tscn`）

**功能**：事件时间线、逐步播放、跳转定位

**改进**：

- **决策历史标注**：

  ```gdscript
  class DecisionHistory:
      func log_action(cmd: Command, context: Dictionary):
          history.append({
              "round": current_round,
              "phase": current_phase,
              "action": cmd.action_id,
              "params": cmd.params,
              "player_note": "",  # 玩家可添加备注
              "outcome": null     # 稍后填充结果
          })

      func add_player_note(cmd_index: int, note: String):
          history[cmd_index].player_note = note
  ```

- **时间轴视图**：

  ```
  ┌───────────────────────────────────────┐
  │ 📜 决策历史                           │
  ├───────────────────────────────────────┤
  │ 回合 1 - 工作阶段                     │
  │   👤 招募厨师                         │
  │   💭 "准备扩大产能" (我的备注)        │
  │   ✅ 成功，花费 $9                    │
  │                                       │
  │ 回合 1 - 营销阶段                     │
  │   📢 放置广告牌 #12 于 (5,3)          │
  │   💭 "覆盖新建社区"                   │
  │   📊 结果: 本回合销售 +2              │
  │                                       │
  │ 回合 2 - 工作阶段                     │
  │   🎓 训练厨师 → 高级厨师              │
  │   ⏱️ 刚刚完成                         │
  └───────────────────────────────────────┘
  ```

**参考**：Slay the Spire 的战斗回放、Civilization VI 的科技树历史

---

#### 9. 上下文帮助系统（`ContextHelp.tscn`）

**新增功能**：根据当前阶段自动显示相关帮助

```gdscript
class ContextHelpSystem:
    var help_database = {
        "Working": {
            "title": "🏢 工作阶段",
            "summary": "招募或训练员工来提升公司能力",
            "what_to_do": [
                "✓ 招募新员工（必须）或训练现有员工",
                "✓ 可选：使用管理培训生调整公司结构"
            ],
            "tips": [
                "💡 厨师优先级高于服务员（产能 > 配送）",
                "💡 首次招募同类员工折扣：$9 → $3",
                "💡 训练后员工本回合不可用（忙碌状态）"
            ],
            "shortcuts": {
                "R": "打开招募面板",
                "T": "打开训练面板",
                "C": "查看公司结构"
            },
            "related_rules": ["员工能力", "公司结构限制", "忙碌状态"]
        },
        "Marketing": {
            "title": "📢 营销阶段",
            "summary": "放置营销板件来吸引特定区域的顾客",
            "what_to_do": [
                "✓ 选择营销板件类型（广告牌/飞机/收音机/邮箱）",
                "✓ 选择放置位置（必须靠路或在边缘）",
                "✓ 选择持续时间（消耗标记数量）"
            ],
            "tips": [
                "💡 广告牌覆盖邻接房屋，飞机覆盖整行/列",
                "💡 营销范围内房屋优先购买你的汉堡",
                "💡 按编号顺序结算（小编号优先）"
            ],
            "shortcuts": {
                "M": "打开营销面板",
                "P": "预览当前选择",
                "1-9": "快速选择编号"
            }
        }
    }

    func show_help_for_phase(phase: String):
        var data = help_database[phase]
        sidebar.update_content(data)
```

**UI 展示**（右侧边栏）：

```
┌─────────────────────────────┐
│ 🏢 工作阶段                 │
├─────────────────────────────┤
│ 招募或训练员工来提升能力    │
│                             │
│ 📋 你需要做什么?            │
│ • 招募/训练员工 (必须)      │
│ • 调整公司结构 (可选)       │
│                             │
│ 💡 新手提示:                │
│ • 厨师比服务员重要          │
│ • 首次招募打折 ($9→$3)      │
│ • 训练后本回合不可用        │
│                             │
│ ⌨️ 快捷键:                  │
│ R - 招募                    │
│ T - 训练                    │
│ C - 公司结构                │
│                             │
│ 📖 相关规则:                │
│ • 员工能力详解              │
│ • 公司结构限制              │
│ • 忙碌状态说明              │
└─────────────────────────────┘
```

**参考**：

- Civilization VI：每个界面右侧有"Civilopedia"链接
- Wingspan：鸟卡悬停显示完整能力说明
- Into the Breach：武器悬停显示详细数值

---

### 交互系统

#### 1. 撤销/重做系统（参考 Into the Breach）

**核心设计**：阶段内可撤销，阶段确认后锁定

```gdscript
class UndoSystem:
    var undo_stack: Array[CommandSnapshot] = []
    var redo_stack: Array[CommandSnapshot] = []
    var phase_lock: bool = false

    func can_undo() -> bool:
        return undo_stack.size() > 0 and not phase_lock

    func undo():
        if not can_undo():
            show_toast("⚠️ 无法撤销：阶段已确认")
            return

        var snapshot = undo_stack.pop_back()
        current_state = snapshot.state_before.duplicate(true)
        redo_stack.push_back(snapshot)

        show_toast("↶ 已撤销: " + get_action_name(snapshot.cmd.action_id))
        refresh_ui()

    func redo():
        if redo_stack.size() == 0:
            return

        var snapshot = redo_stack.pop_back()
        var result = execute_command(snapshot.cmd)
        undo_stack.push_back(snapshot)

        show_toast("↷ 已重做: " + get_action_name(snapshot.cmd.action_id))

    func on_phase_end():
        # 阶段结束时清空撤销栈，锁定历史
        undo_stack.clear()
        redo_stack.clear()
        phase_lock = true

    func on_phase_start():
        phase_lock = false
```

**规则**：

- ✅ **阶段内撤销**：可撤销本阶段所有操作（无限次）
- ❌ **跨阶段撤销**：不允许（符合桌游"确认"规则）
- ✅ **快捷键**：`Ctrl+Z` 撤销，`Ctrl+Shift+Z` 重做
- ✅ **UI 提示**：撤销按钮在阶段确认后置灰并显示"已锁定"

**参考**：

- Into the Breach：回合内可无限撤销，"结束回合"是确认点
- Wingspan：打出卡牌前可撤销，打出后锁定

---

#### 2. 确认流程系统（参考 XCOM）

**设计原则**：高风险操作需要二次确认，低风险操作无阻碍

```gdscript
class ConfirmationSystem:
    const HIGH_RISK = ["EndPhase", "SellMilestone", "DestroyStructure", "Bankruptcy"]
    const MEDIUM_RISK = ["PlaceMarketing", "TrainEmployee"]  # 仅在花费 >$20 时确认

    func should_confirm(cmd: Command) -> bool:
        if cmd.action_id in HIGH_RISK:
            return true

        if cmd.action_id in MEDIUM_RISK:
            var cost = calculate_cost(cmd)
            return cost > 20

        return false

    func execute_with_confirmation(cmd: Command):
        if not should_confirm(cmd):
            return execute_command(cmd)

        var confirm_data = {
            "EndPhase": {
                "title": "⚠️ 确认结束阶段",
                "message": "结束后无法撤销，确定要继续吗？",
                "preview": get_phase_summary(),
                "options": ["确认结束", "返回"]
            },
            "SellMilestone": {
                "title": "⚠️ 确认出售里程碑",
                "message": "出售后将永久失去此能力！",
                "preview": {
                    "milestone": cmd.params.milestone_id,
                    "ability": get_milestone_ability(cmd.params.milestone_id),
                    "income": "+$5"
                },
                "options": ["确认出售", "取消"]
            }
        }

        var choice = await show_confirmation_dialog(confirm_data[cmd.action_id])
        if choice == 0:  # 第一个选项（确认）
            return execute_command(cmd)
        else:
            return {ok: false, cancelled: true}
```

**需要确认的操作**：

| 操作 | 风险等级 | 确认原因 |
|------|---------|---------|
| 结束阶段 | 高 | 无法撤销 |
| 出售里程碑 | 高 | 永久失去能力 |
| 拆除建筑 | 高 | 高成本损失 |
| 破产操作 | 高 | 游戏结束风险 |
| 昂贵操作 (>$20) | 中 | 资金消耗大 |

**不需要确认的操作**：

- ✅ 普通放置（可撤销）
- ✅ 拖拽员工（可撤销）
- ✅ 价格调整（可撤销）

**参考**：

- XCOM 2："结束回合"需要二次确认
- Civilization VI：宣战、使用核武器需要确认

---

#### 3. 新手引导系统（参考 Into the Breach）

**设计原则**：渐进式教学，不打断游戏流程

```gdscript
class TutorialSystem:
    var current_step: int = 0
    var completed_steps: Set[String] = Set.new()

    var tutorial_steps = [
        {
            "id": "welcome",
            "type": "message",
            "trigger": "game_start",
            "content": {
                "title": "欢迎来到汉堡连锁大亨！",
                "text": "你将经营一家汉堡连锁店，与对手竞争成为最成功的企业家。",
                "image": "tutorial/welcome.png"
            }
        },
        {
            "id": "first_recruit",
            "type": "guided_action",
            "trigger": "phase_Working_first_time",
            "content": {
                "title": "招募你的第一位员工",
                "text": "点击'招募'按钮雇佣一名厨师。厨师负责生产汉堡。",
                "highlight": "recruit_button",
                "arrow": "point_to_recruit_button",
                "lock_other_ui": true
            },
            "validation": func(cmd): return cmd.action_id == "Recruit" and cmd.params.role == "cook"
        },
        {
            "id": "explain_company_structure",
            "type": "message",
            "trigger": "after_first_recruit",
            "content": {
                "title": "公司结构规则",
                "text": "员工必须按照特定顺序排列：厨师 → 服务员 → 管理。",
                "diagram": "tutorial/structure.png",
                "highlight_panel": "company_view"
            }
        },
        {
            "id": "first_marketing",
            "type": "guided_action",
            "trigger": "phase_Marketing_first_time",
            "content": {
                "title": "放置营销板件",
                "text": "选择一个广告牌并放置在靠近房屋的位置。",
                "highlight": "marketing_panel",
                "show_preview": true
            },
            "validation": func(cmd): return cmd.action_id == "PlaceMarketing"
        },
        {
            "id": "watch_dinnertime",
            "type": "spectate",
            "trigger": "phase_Dinnertime_first_time",
            "content": {
                "title": "观看晚餐时间",
                "text": "现在顾客会向最近的餐厅购买汉堡。观看动画了解竞争结果。",
                "allow_skip": true
            }
        }
    ]

    func run_tutorial():
        tutorial_mode = true

        for step in tutorial_steps:
            await wait_for_trigger(step.trigger)

            match step.type:
                "message":
                    await show_tutorial_message(step.content)

                "guided_action":
                    lock_ui_except(step.content.highlight)
                    show_tutorial_overlay(step.content)
                    await wait_for_valid_action(step.validation)
                    unlock_ui()

                "spectate":
                    show_tutorial_overlay(step.content)
                    # 让玩家观看，但提供跳过按钮

            completed_steps.add(step.id)
            save_tutorial_progress()

        show_tutorial_complete_message()
        tutorial_mode = false
```

**UI 展示**：

```
引导步骤界面：
┌──────────────────────────────┐
│ 💡 教程: 招募第一位员工      │
├──────────────────────────────┤
│ 点击'招募'按钮雇佣一名厨师。 │
│ 厨师负责生产汉堡。           │
│                              │
│       ↓ 点击这里             │
│   [  招募  ] ← 高亮闪烁      │
│                              │
│ [跳过教程]                   │
└──────────────────────────────┘
     ↑ 箭头指向招募按钮
     ↑ 其他 UI 置灰不可点击
```

**教程特性**：

- ✅ **渐进解锁**：只在需要时教学，不一次性灌输
- ✅ **可跳过**：每个步骤都可跳过，不强制观看
- ✅ **进度保存**：关闭游戏后重新打开会继续教程
- ✅ **可重放**：设置中可随时重新观看教程

**参考**：

- Into the Breach：教程关卡只能点击指定按钮，其他 UI 置灰
- Wingspan：第一局游戏时逐步解锁规则提示
- Slay the Spire：教程文本以卡片形式展示，不打断游戏

---

### 辅助功能

#### 1. 无障碍设计

- **色盲友好配色**：
  - 玩家标识使用"颜色 + 图案"双重编码（红色 + 圆形，蓝色 + 方形）
  - 高对比度模式（白底黑字）
  - 自定义颜色方案
- **可自定义快捷键**：所有操作都可重新绑定
- **字体缩放**：支持 80%-150% 字体大小调节
- **屏幕阅读器支持**（长期目标）

#### 2. 预设模式

```gdscript
var game_modes = {
    "beginner": {
        "name": "入门模式",
        "changes": {
            "disable_reserve_cards": true,
            "initial_bank_per_player": 75,
            "disable_milestones": true,
            "skip_payday": true,
            "first_bankruptcy_ends_game": true
        }
    },
    "standard": {
        "name": "标准模式",
        "changes": {}  # 默认规则
    },
    "expert": {
        "name": "专家模式",
        "changes": {
            "enable_all_modules": true,
            "initial_bank_per_player": 50,
            "strict_bankruptcy": true  # 破产立即出局
        }
    }
}
```

#### 3. 本地化

- **语言切换**：中文/英文切换按钮，默认中文
- **文案来源**：`config/localization/`
- **动态文本**：所有 UI 文本支持热重载（修改翻译文件后无需重启）

#### 4. 性能设置

```gdscript
var performance_profiles = {
    "ultra": {
        "animation_quality": "high",
        "particle_effects": true,
        "shadow_quality": "high",
        "target_fps": 60
    },
    "low": {
        "animation_quality": "minimal",
        "particle_effects": false,
        "shadow_quality": "off",
        "target_fps": 30
    }
}
```

---

### 实现现状

#### 已完成

- ✅ `scenes/Board.gd` 的绘制委托至 `BoardRenderer.gd`
- ✅ 输入处理委托至 `BoardInteractor.gd`
- ✅ 所有状态修改通过 `GameCommands.gd` 统一调用 `Rules.perform_action`
- ✅ 调试专用动作：`PlaceRoadDebug`、`AddDemandDebug`、`PlaceHouseVisualDebug`

#### 待实现（优先级排序）

1. **P0 - 核心交互**：
   - UIStateMachine（智能状态切换）
   - MandatoryActionBlocker（强制动作锁定）
   - UndoSystem（撤销/重做）
   - ConfirmationSystem（确认流程）

2. **P1 - 新手体验**：
   - ContextHelpSystem（上下文帮助）
   - TutorialSystem（交互式教程）
   - ActionPreview（收益预测）

3. **P2 - 高级功能**：
   - InteractiveDinnertime（交互式晚餐）
   - DecisionHistory（决策历史）
   - SmartBoardRenderer（智能渲染）

4. **P3 - 锦上添花**：
   - PredictionMinigame（预测小游戏）
   - OptimalPlacementRecommender（智能推荐）
   - PerformanceProfiles（性能配置）

---

### 实现复杂度估计

| 系统 | 代码量 | 难度 | 依赖 |
|------|--------|------|------|
| UIStateMachine | ~200 行 | ⭐⭐ | Phase 系统 |
| MandatoryActionBlocker | ~150 行 | ⭐⭐ | Rules 引擎 |
| UndoSystem | ~250 行 | ⭐⭐⭐ | Command 系统 |
| ConfirmationSystem | ~180 行 | ⭐⭐ | UI 框架 |
| ContextHelp | ~300 行 | ⭐⭐ | 帮助文本数据库 |
| TutorialSystem | ~500 行 | ⭐⭐⭐⭐ | 全部系统 |
| ActionPreview | ~400 行 | ⭐⭐⭐⭐ | Rules + Pricing |
| InteractiveDinnertime | ~600 行 | ⭐⭐⭐⭐⭐ | 动画系统 |
| DecisionHistory | ~200 行 | ⭐⭐ | Command 日志 |
| SmartRenderer | ~350 行 | ⭐⭐⭐ | 渲染管线 |

**总计**：约 3130 行核心 UI 代码

---

## 存档与复盘

### 设计目标

- **存档小**：只记录命令序列，不记录状态 diff
- **语义清晰**：每个命令都有业务含义，可读性强
- **可验证**：通过校验点检测复盘偏差
- **可调试**：可定位到具体命令，支持断点和时光倒流
- **版本兼容**：严格检查模块版本，避免不确定性

### 存档格式

#### ReplayArchive 结构

```gdscript
class ReplayArchive:
    var version: int = 1               # 存档格式版本
    var game_id: String                # 游戏唯一 ID (UUID)
    var created_at: int                # 创建时间戳（Unix）
    var game_metadata: Dictionary      # 游戏元数据
    var seed: int                      # 随机种子
    var modules: Array[ModuleInfo]     # 启用的模块
    var initial_state: GameState       # 初始状态快照
    var command_log: Array[Command]    # 命令序列
    var checkpoints: Array[Checkpoint] # 校验点
```

#### GameMetadata 示例

```gdscript
{
    "player_names": ["Alice", "Bob", "Charlie"],
    "player_count": 3,
    "map_size": "3x4",
    "difficulty": "standard",
    "duration_seconds": 3600,
    "final_round": 8,
    "winner": 0
}
```

#### ModuleInfo 结构

```gdscript
class ModuleInfo:
    var id: String          # 模块 ID
    var version: String     # 版本号（语义化版本）
    var hash: String        # 模块代码的哈希值
    var enabled_at: int     # 启用时间戳
```

#### Checkpoint 结构

```gdscript
class Checkpoint:
    var after_command: int          # 在第 N 个命令之后
    var state_hash: String          # 整体状态哈希（用于快速验证）
    var key_values: Dictionary      # 关键数值（详细验证）
    var full_snapshot: GameState    # 可选：完整快照（每 N 回合）
```

#### 存档示例（JSON）

```json
{
    "version": 1,
    "game_id": "a3f2b1c4-5d6e-7f8g-9h0i-1j2k3l4m5n6o",
    "created_at": 1704067200,
    "game_metadata": {
        "player_names": ["Alice", "Bob"],
        "player_count": 2,
        "duration_seconds": 1800,
        "winner": 0
    },
    "seed": 123456,
    "modules": [
        {
            "id": "fcm_ketchup",
            "version": "1.0.0",
            "hash": "a3f29bc1..."
        }
    ],
    "initial_state": {
        "round": 0,
        "phase": "Setup",
        "bank": {"total": 100},
        "players": [...]
    },
    "command_log": [
        {
            "index": 0,
            "action_id": "PlaceInitialRestaurant",
            "actor": 0,
            "params": {"pos": [3, 5], "rotation": 0},
            "phase": "Setup",
            "timestamp": 0
        },
        {
            "index": 1,
            "action_id": "Recruit",
            "actor": 0,
            "params": {"employee_id": "recruiter"},
            "phase": "Working",
            "timestamp": 1003
        }
    ],
    "checkpoints": [
        {
            "after_command": 50,
            "state_hash": "a3f29bc1...",
            "key_values": {
                "round": 2,
                "bank_total": 250,
                "player_cash": [120, 85]
            }
        },
        {
            "after_command": 100,
            "state_hash": "b7e14f3a...",
            "key_values": {...},
            "full_snapshot": {/* 完整状态 */}
        }
    ]
}
```

### 复盘流程

```gdscript
class ReplayEngine:
    # 复盘验证
    func replay(archive: ReplayArchive) -> ReplayResult:
        # 1. 验证存档格式版本
        if archive.version != CURRENT_VERSION:
            return {ok: false, error: "存档版本不兼容"}

        # 2. 验证模块版本与哈希
        var module_check = verify_modules(archive.modules)
        if not module_check.ok:
            return {ok: false, error: "模块版本不匹配: " + module_check.error}

        # 3. 从初始状态开始
        current_state = archive.initial_state.duplicate(true)
        Random.seed = archive.seed

        # 4. 逐个执行命令
        for i in archive.command_log.size():
            var cmd = archive.command_log[i]
            var result = execute_command(cmd)

            if not result.ok:
                return {
                    ok: false,
                    error: "命令 %d 执行失败" % i,
                    failed_command: cmd,
                    error_detail: result.error
                }

            # 5. 在校验点验证
            var checkpoint = find_checkpoint_after(i)
            if checkpoint:
                var verify_result = verify_checkpoint(checkpoint, current_state)
                if not verify_result.ok:
                    return {
                        ok: false,
                        error: "校验点 %d 验证失败" % i,
                        expected: checkpoint.key_values,
                        actual: extract_key_values(current_state),
                        deviation: verify_result.deviation
                    }

        return {ok: true, final_state: current_state}

    # 模块验证
    func verify_modules(modules: Array[ModuleInfo]) -> Result:
        for module_info in modules:
            var installed_module = ModuleRegistry.get(module_info.id)

            if not installed_module:
                return {ok: false, error: "模块未安装: " + module_info.id}

            if installed_module.version != module_info.version:
                return {ok: false, error: "模块版本不匹配: %s (需要 %s, 当前 %s)" % [
                    module_info.id, module_info.version, installed_module.version
                ]}

            if installed_module.hash != module_info.hash:
                return {ok: false, error: "模块代码已变更: " + module_info.id}

        return {ok: true}

    # 校验点验证
    func verify_checkpoint(checkpoint: Checkpoint, state: GameState) -> Result:
        # 1. 验证整体哈希
        var actual_hash = compute_state_hash(state)
        if actual_hash != checkpoint.state_hash:
            # 哈希不匹配，进行详细验证
            var actual_values = extract_key_values(state)
            var deviation = find_deviation(checkpoint.key_values, actual_values)

            return {
                ok: false,
                error: "状态哈希不匹配",
                deviation: deviation
            }

        # 2. 验证关键数值（双重保险）
        var actual_values = extract_key_values(state)
        for key in checkpoint.key_values:
            if checkpoint.key_values[key] != actual_values[key]:
                return {
                    ok: false,
                    error: "关键值不匹配: " + key,
                    expected: checkpoint.key_values[key],
                    actual: actual_values[key]
                }

        return {ok: true}

    # 查找偏差
    func find_deviation(expected: Dictionary, actual: Dictionary) -> Dictionary:
        var deviations = {}
        for key in expected:
            if expected[key] != actual.get(key):
                deviations[key] = {
                    "expected": expected[key],
                    "actual": actual.get(key)
                }
        return deviations
```

### 时光倒流（Time Travel）

```gdscript
class GameEngine:
    # 回退到指定命令
    func rewind_to_command(target_index: int) -> Result:
        if target_index < 0 or target_index >= command_log.size():
            return {ok: false, error: "无效的命令索引"}

        # 1. 找到最近的完整快照
        var checkpoint = find_closest_full_snapshot(target_index)

        if checkpoint:
            # 从快照开始
            current_state = checkpoint.full_snapshot.duplicate(true)
            var start_index = checkpoint.after_command
        else:
            # 从初始状态开始
            current_state = initial_state.duplicate(true)
            var start_index = 0

        # 2. 重新执行到目标位置
        for i in range(start_index, target_index + 1):
            var result = execute_command(command_log[i])
            if not result.ok:
                return {ok: false, error: "回放失败"}

        # 3. 截断命令日志
        command_log.resize(target_index + 1)

        return {ok: true, current_state: current_state}

    # 查找最近的完整快照
    func find_closest_full_snapshot(target_index: int) -> Checkpoint:
        var closest = null
        for checkpoint in checkpoints:
            if checkpoint.after_command <= target_index and checkpoint.full_snapshot:
                if not closest or checkpoint.after_command > closest.after_command:
                    closest = checkpoint
        return closest
```

### 存档压缩优化

```gdscript
class ArchiveCompressor:
    # 压缩存档
    static func compress(archive: ReplayArchive) -> PackedByteArray:
        var json = JSON.stringify(archive)
        var compressed = json.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
        return compressed

    # 解压存档
    static func decompress(data: PackedByteArray) -> ReplayArchive:
        var decompressed = data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
        var json = decompressed.get_string_from_utf8()
        var dict = JSON.parse_string(json)
        return ReplayArchive.from_dict(dict)

    # 增量存档（只保存新增命令）
    static func create_incremental_save(base_archive: ReplayArchive, new_commands: Array[Command]) -> Dictionary:
        return {
            "type": "incremental",
            "base_game_id": base_archive.game_id,
            "from_command": base_archive.command_log.size(),
            "new_commands": new_commands,
            "new_checkpoints": [] # 如果有新校验点
        }
```

### 复盘调试工具

```gdscript
class ReplayDebugger:
    # 逐步执行（单步调试）
    func step_forward() -> Result:
        if current_command_index >= command_log.size():
            return {ok: false, error: "已到末尾"}

        var cmd = command_log[current_command_index]
        var result = execute_command(cmd)
        current_command_index += 1

        return result

    # 比较两次复盘
    func compare_replays(archive1: ReplayArchive, archive2: ReplayArchive) -> ComparisonResult:
        # 逐命令执行并比较状态
        for i in min(archive1.command_log.size(), archive2.command_log.size()):
            var cmd1 = archive1.command_log[i]
            var cmd2 = archive2.command_log[i]

            if cmd1 != cmd2:
                return {
                    ok: false,
                    diverge_at: i,
                    diff: compare_commands(cmd1, cmd2)
                }

        return {ok: true}

    # 导出为人类可读格式
    func export_readable(archive: ReplayArchive) -> String:
        var output = "游戏复盘记录\n"
        output += "玩家: %s\n" % archive.game_metadata.player_names
        output += "种子: %d\n\n" % archive.seed

        for i in archive.command_log.size():
            var cmd = archive.command_log[i]
            output += "[%d] 回合%d/%s: 玩家%d %s %s\n" % [
                i,
                cmd.timestamp / 1000,
                cmd.phase,
                cmd.actor,
                cmd.action_id,
                JSON.stringify(cmd.params)
            ]

        return output
```

### 存档策略建议

| 场景 | 校验点间隔 | 完整快照间隔 | 估计大小 |
|------|-----------|-------------|---------|
| **开发调试** | 每 10 命令 | 每 1 回合 | 较大，但方便调试 |
| **普通游戏** | 每 50 命令 | 每 10 回合 | 中等，平衡性能与安全 |
| **长时游戏** | 每 100 命令 | 每 20 回合 | 较小，减少存档大小 |
| **竞技模式** | 每 20 命令 | 每 5 回合 | 较大，严格验证 |

---

## 调试控制台（Debug Console）

### 设计目标

- 开发期快速调试：修改状态、跳过阶段、触发事件
- 测试用例构建：快速设置特定游戏场景
- 作弊模式：玩家娱乐用途（可选启用）
- 复盘分析：执行特定命令观察结果
- 完全集成：控制台命令与游戏命令共享执行器

### 架构优势

当前命令模式架构**天然支持**控制台，无需额外设计：

```gdscript
// 游戏命令
execute_command(Command.new({
    "action_id": "Recruit",
    "actor": 0,
    "params": {"employee_id": "recruiter"}
}))

// 控制台命令（本质相同！）
execute_command(Command.new({
    "action_id": "CheatAddCash",
    "actor": -1,  // 系统标记
    "params": {"player": 0, "amount": 1000}
}))
```

**关键点**：控制台命令与游戏命令走相同的 `execute_command()` 通道，享受相同特性（可撤销、可记录、可复盘）。

### 核心组件

#### 1. ConsoleCommandRegistry（命令注册表）

```gdscript
class ConsoleCommandRegistry:
    var commands: Dictionary = {}  # name -> ConsoleCommand

    func register(cmd: ConsoleCommand):
        commands[cmd.name] = cmd
        for alias in cmd.aliases:
            commands[alias] = cmd

    func find_matching(prefix: String) -> Array:
        # 自动补全：返回匹配前缀的命令
        return commands.keys().filter(func(k): return k.begins_with(prefix))
```

#### 2. ConsoleCommand（命令定义）

```gdscript
class ConsoleCommand:
    var name: String
    var aliases: Array[String]
    var description: String
    var usage: String
    var category: String  # "cheat", "debug", "util"
    var requires_debug: bool
    var params: Array[ParamDef]
    var executor: Callable

class ParamDef:
    var name: String
    var type: ParamType  # INT, FLOAT, STRING, BOOL, ENUM
    var description: String
    var default_value = null
    var choices: Array = []  # For ENUM type
```

#### 3. ConsoleParser（解析器）

```gdscript
class ConsoleParser:
    static func parse(input: String) -> ParseResult:
        # "give_cash 0 1000" -> {command: "give_cash", args: [0, 1000]}
        var parts = input.split(" ", false)
        var cmd = ConsoleCommandRegistry.get_command(parts[0])
        var args = parse_arguments(cmd, parts.slice(1))
        return {ok: true, command: cmd, args: args}
```

### 内置命令示例

#### 作弊命令

```gdscript
# 增加现金
> give_cash 0 1000
✓ 玩家 0 获得 $1000

# 增加库存
> give_item 0 burger 10
✓ 玩家 0 获得 10 个汉堡

# 招聘员工（无视限制）
> spawn_employee 0 cfo
✓ 玩家 0 获得员工: CFO

# 授予里程碑
> grant_milestone 0 first_billboard
✓ 玩家 0 获得里程碑: 首个广告牌
```

#### 调试命令

```gdscript
# 跳转阶段
> goto_phase Dinnertime
✓ 跳转到晚餐阶段

# 跳转回合
> goto_round 5
✓ 跳转到第 5 回合

# 触发银行破产
> trigger_bank_break
✓ 银行破产已触发

# 验证状态一致性
> verify
✓ 现金守恒检查通过
✓ 员工卡数量正确
✓ 状态验证通过

# 显示状态
> dump_state
银行: $250
玩家0: $120, 员工3, 餐厅2
玩家1: $85, 员工2, 餐厅1
```

#### 工具命令

```gdscript
# 帮助
> help
[CHEAT]
  give_cash - 给玩家增加现金
  give_item - 给玩家增加库存
  spawn_employee - 招聘员工（无视限制）

[DEBUG]
  goto_phase - 跳转到指定阶段
  verify - 验证游戏状态一致性
  dump_state - 显示当前状态

[UTIL]
  help - 显示帮助信息
  clear - 清空控制台输出
  history - 显示命令历史

# 详细帮助
> help give_cash
give_cash
描述: 给玩家增加现金
用法: give_cash <player> <amount>
别名: cash, money

参数:
  player: 玩家ID (0-5)
  amount: 金额

# 历史记录
> history
1: give_cash 0 1000
2: spawn_employee 0 cfo
3: goto_phase Dinnertime
```

### UI 实现

```gdscript
class Console extends Control:
    @onready var input_line: LineEdit
    @onready var output_text: RichTextLabel
    @onready var suggestion_panel: ItemList

    var history: Array[String] = []
    var history_index: int = -1

    func _input(event):
        # ~ 键切换显示
        if event.keycode == KEY_QUOTELEFT and event.pressed:
            toggle_console()

        # 上下键导航历史
        if visible and event.keycode == KEY_UP:
            navigate_history(-1)
        elif visible and event.keycode == KEY_DOWN:
            navigate_history(1)

        # Tab 键自动补全
        if visible and event.keycode == KEY_TAB:
            auto_complete()

    func execute_input():
        var input = input_line.text
        history.append(input)

        var result = ConsoleParser.parse(input)
        if result.ok:
            var exec_result = result.command.executor.call(result.args)
            if exec_result.ok:
                print_success(exec_result.message)
            else:
                print_error(exec_result.error)
        else:
            print_error(result.error)
```

### 权限控制

```gdscript
class DebugFlags:
    static var debug_mode: bool = false

    static func is_debug_mode() -> bool:
        # 发布版本强制禁用
        if OS.has_feature("release"):
            return false
        return debug_mode

    # 开发者快捷键: Ctrl+Shift+D
    func _input(event):
        if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
            DebugFlags.enable_debug()
            print("调试模式已启用")
```

### 集成到命令系统

作弊命令通过 `CheatActionExecutor` 实现，继承 `ActionExecutor`：

```gdscript
class CheatAddCashExecutor extends ActionExecutor:
    func _init():
        action_id = "CheatAddCash"
        mandatory = false
        allowed_phases = []  # 不受阶段限制

    func validate(params, state):
        return {ok: true}  # 作弊命令跳过验证

    func compute_new_state(params, state):
        return StateUpdater.transfer_cash(state,
            from: "bank",  # 或 "cheat_pool"（凭空生成）
            to: "player:%d" % params.player,
            amount: params.amount
        )
```

### 实现成本

| 组件 | 代码量 | 难度 |
|------|--------|------|
| ConsoleCommandRegistry | ~50 行 | ⭐ |
| ConsoleParser | ~100 行 | ⭐⭐ |
| Console UI | ~150 行 | ⭐⭐ |
| CheatCommands | ~200 行 | ⭐ |
| DebugCommands | ~150 行 | ⭐⭐ |
| UtilityCommands | ~100 行 | ⭐ |
| **总计** | **~750 行** | **⭐⭐ (简单)** |

### 优势总结

| 方面 | 说明 |
|------|------|
| **统一执行** | 控制台命令与游戏命令走同一通道 |
| **可撤销** | 所有作弊操作都可回退 |
| **可记录** | 作弊记录在命令日志中，可复盘 |
| **类型安全** | 参数类型自动校验 |
| **易扩展** | 新增命令只需注册 ConsoleCommand |
| **权限控制** | 发布版自动禁用 |

---

## 可插拔性设计总结

本架构采用**注册表模式**和**钩子系统**实现组件的最大化可插拔性，确保扩展模块无需修改核心代码即可：

### 核心可插拔组件

| 组件 | 可插拔机制 | 扩展方式 | 应用场景 |
|------|----------|---------|---------|
| **定价系统** | PricingPipeline + PriceModifier | 注册修饰器 | 储备价格、番茄酱、公园倍增 |
| **验证器** | ValidatorRegistry | 添加/替换/移除验证器 | 自定义放置规则、结构规则 |
| **阶段流程** | PhaseManager + Hooks | 注册钩子回调 | 夜班经理、大众营销员、艰难抉择 |
| **营销范围** | MarketingRegistry + RangeCalculator | 注册范围计算器 | 自定义营销类型 |
| **公司结构** | CompanyStructureValidator + StructureRule | 添加/替换结构规则 | 双层经理、特殊组织模式 |
| **地形系统** | TerrainRegistry + TerrainEffectModifier | 注册地形类型 + 定价修饰器 | 公园价格倍增、特殊地形效果 |
| **员工/里程碑** | Registry + Resource 定义 | 数据驱动注册 | 所有扩展卡牌 |

### 可插拔设计原则

1. **最小核心原则**
   - 核心系统只实现基础规则（七阶段流程、基础定价、标准验证）
   - 所有变体和扩展通过模块实现
   - 示例：基础单价 10 在核心，储备价格锁定在模块

2. **注册表模式**
   - 所有可变部分（定价、验证、范围计算）使用注册表管理
   - 支持优先级排序，确保执行顺序确定性
   - 支持添加、替换、移除操作

3. **钩子优先**
   - 阶段流程暴露 4 个钩子点（before_enter, after_enter, before_exit, after_exit）
   - 事件系统支持订阅和发布（house_sold, milestone_awarded 等）
   - 所有副作用通过钩子和事件处理

4. **纯函数保证**
   - 所有修饰器、验证器、钩子回调都是纯函数
   - 只依赖输入参数和上下文，不修改全局状态
   - 确保复盘和回放的一致性

5. **数据驱动**
   - 员工、里程碑、地图板块、营销板件全部用 Resource 定义
   - 规则参数外置（距离、卡槽、单价、范围、奖励）
   - 模块元数据包含依赖、冲突、版本信息

### 扩展模块开发流程

```gdscript
# 1. 定义模块资源
class_name MyModule extends ModuleDef

func _init():
    id = "my_module"
    name = "我的模块"
    dependencies = []  # 依赖的其他模块
    conflicts = []     # 互斥的模块
    priority = 100

# 2. 实现启用钩子
func on_enable(ctx):
    # 注册新数据
    Registry.register_employee(MyEmployeeDef.new())

    # 注册验证器
    ValidatorRegistry.add_validator("PlaceHouse",
        MyPlacementValidator.new(), priority: 150)

    # 注册定价修饰器
    PricingPipeline.register_modifier(MyPriceModifier.new(), priority: 120)

    # 注册阶段钩子
    PhaseManager.register_hook("Dinnertime", "before_exit",
        func(state, ctx): apply_my_effect(state), priority: 100)

    # 订阅事件
    EventBus.subscribe("house_sold", on_house_sold)

# 3. 实现自定义逻辑
class MyPriceModifier extends PriceModifier:
    func apply(context):
        context.base_price += my_bonus
        return context

func on_house_sold(event):
    if should_trigger_milestone(event):
        award_milestone(event.player_id, "my_milestone")
```

### 模块兼容性保证

- **依赖检查**：启动时验证依赖模块已加载
- **冲突检测**：互斥模块不能同时启用
- **版本控制**：存档记录模块版本，不匹配时拒绝加载
- **确定性保证**：优先级排序 + 纯函数 + 受控随机 = 可重放

### 未来扩展方向

基于当前可插拔架构，未来可轻松支持：

1. **自定义员工职业路线**：通过注册新 EmployeeDef 和培训规则
2. **全新阶段**：在现有七阶段间插入新阶段（如"午休时间"）
3. **动态地图元素**：天气、时段、季节效果
4. **社区模块市场**：玩家自制模块，通过元数据验证兼容性
5. **AI 对手**：作为特殊模块注入决策系统

---
