# Game scene：Working/Train 面板控制器
# 负责：TrainPanel 的生命周期、同步与命令分发。
class_name GamePanelWorkingTrainController
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const TrainActionClass = preload("res://gameplay/actions/train_action.gd")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")

var _scene = null
var _execute_command: Callable = Callable()
var _hide_all: Callable = Callable()
var _center_popup: Callable = Callable()

var train_panel = null

func _init(scene, execute_command: Callable, hide_all: Callable, center_popup: Callable) -> void:
	_scene = scene
	_execute_command = execute_command
	_hide_all = hide_all
	_center_popup = center_popup

func hide() -> void:
	if is_instance_valid(train_panel):
		train_panel.visible = false

func sync(state: GameState, force_full_refresh: bool = false) -> void:
	if state == null:
		return
	if not is_instance_valid(train_panel) or not train_panel.visible:
		return
	if state.phase != DefsClass.PHASE_WORKING or state.sub_phase != DefsClass.SUB_PHASE_TRAIN:
		train_panel.visible = false
		return

	if force_full_refresh:
		_refresh_for_state(state)

func show() -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if _hide_all.is_valid():
		_hide_all.call()

	if train_panel == null:
		train_panel = TrainPanelScene.instantiate()
		train_panel.visible = false
		train_panel.set_meta("popup_layout", "dock_right")
		train_panel.set_meta("popup_title", "培训")
		train_panel.train_requested.connect(_on_train_requested)
		_scene.add_child(train_panel)

	var state = _scene.game_engine.get_state()
	_refresh_for_state(state)

	if _center_popup.is_valid():
		_center_popup.call(train_panel)
	train_panel.visible = true

func _refresh_for_state(state: GameState) -> void:
	if state == null:
		return
	if not is_instance_valid(train_panel):
		return

	var current_player: Dictionary = state.get_current_player()
	var actor_id: int = int(state.get_current_player_id())

	if train_panel.has_method("set_employee_pool"):
		train_panel.set_employee_pool(state.employee_pool)

	if train_panel.has_method("set_trainable_employees"):
		var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, actor_id))
		var sources := {}
		var requires_same_color := {}
		var section_text := "待命区员工（点击选择）"
		var badges := {}

		if pending_total > 0:
			sources = _read_immediate_train_pending_sources(state, actor_id)
			section_text = "缺货预支待培训（必须先清账）"
			for emp_id in sources.keys():
				badges[str(emp_id)] = "预支"
		else:
			var reserve_counts := _build_employee_type_counts(Array(current_player.get("reserve_employees", [])))
			sources = reserve_counts.duplicate(true)
			var can_train_from_active := bool(current_player.get("train_from_active_same_color", false))
			if can_train_from_active:
				section_text = "待命/在岗员工（点击选择；在岗同色培训：目标需同色）"
				var active_counts := _build_employee_type_counts(Array(current_player.get("employees", [])))
				for emp_id in active_counts.keys():
					sources[str(emp_id)] = int(sources.get(emp_id, 0)) + int(active_counts.get(emp_id, 0))
				for emp_id in sources.keys():
					var active_count: int = int(active_counts.get(emp_id, 0))
					var reserve_count: int = int(reserve_counts.get(emp_id, 0))
					if active_count > 0 and reserve_count <= 0:
						requires_same_color[str(emp_id)] = true

		sources = _filter_sources_with_valid_targets(state, actor_id, sources)
		var filtered_requires_same_color := {}
		for emp_id in requires_same_color.keys():
			if sources.has(emp_id):
				filtered_requires_same_color[str(emp_id)] = bool(requires_same_color.get(emp_id, false))
		requires_same_color = filtered_requires_same_color
		var filtered_badges := {}
		for emp_id in badges.keys():
			if sources.has(emp_id):
				filtered_badges[str(emp_id)] = str(badges.get(emp_id, ""))
		badges = filtered_badges

		if train_panel.has_method("set_source_requires_same_color"):
			train_panel.set_source_requires_same_color(requires_same_color)
		if train_panel.has_method("set_source_badges"):
			train_panel.set_source_badges(badges)
		if train_panel.has_method("set_trainable_sources"):
			train_panel.set_trainable_sources(sources, section_text)
		else:
			var reserve: Array[String] = []
			for emp_id in sources.keys():
				reserve.append(str(emp_id))
			reserve.sort()
			train_panel.set_trainable_employees(reserve)

	if train_panel.has_method("set_train_count"):
		var counts := _compute_train_counts(state, actor_id)
		train_panel.set_train_count(int(counts.remaining), int(counts.total))
	if train_panel.has_method("set_max_steps_one_employee"):
		var max_steps := int(EmployeeRulesClass.get_max_train_steps_for_single_employee_for_working(state, actor_id))
		train_panel.set_max_steps_one_employee(max_steps)

func _compute_train_counts(state: GameState, player_id: int) -> Dictionary:
	if state == null:
		return {"remaining": 0, "total": 0}
	var total: int = EmployeeRulesClass.get_train_limit_for_working(state, player_id)
	var used: int = EmployeeRulesClass.get_action_count(state, player_id, "train")
	return {"remaining": maxi(0, total - used), "total": total}

func _build_employee_type_counts(values: Array) -> Dictionary:
	var counts := {}
	for v in values:
		if not (v is String):
			continue
		var emp_id: String = str(v)
		if emp_id.is_empty():
			continue
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1
	return counts

func _filter_sources_with_valid_targets(state: GameState, actor_id: int, sources: Dictionary) -> Dictionary:
	var filtered := {}
	if state == null:
		return filtered

	for key in sources.keys():
		if not (key is String):
			continue
		var emp_id: String = str(key)
		if emp_id.is_empty():
			continue
		var count: int = int(sources.get(key, 0))
		if count <= 0:
			continue
		if _source_has_valid_train_target(state, actor_id, emp_id):
			filtered[emp_id] = count

	return filtered

func _source_has_valid_train_target(state: GameState, actor_id: int, from_employee: String) -> bool:
	if state == null or from_employee.is_empty():
		return false

	var max_steps := int(EmployeeRulesClass.get_max_train_steps_for_single_employee_for_working(state, actor_id))
	if max_steps <= 0:
		return false

	var targets := _collect_reachable_train_targets(from_employee, max_steps)
	if targets.is_empty():
		return false

	var action := TrainActionClass.new()
	for target in targets:
		var validate_result := action.validate(state, Command.create("train", actor_id, {
			"from_employee": from_employee,
			"to_employee": target
		}))
		if validate_result.ok:
			return true

	return false

func _collect_reachable_train_targets(from_employee: String, max_steps: int) -> Array[String]:
	var targets: Array[String] = []
	if from_employee.is_empty() or max_steps <= 0 or not EmployeeRegistryClass.is_loaded():
		return targets

	var visited := {}
	visited[from_employee] = 0
	var queue: Array[String] = [from_employee]
	var qi := 0

	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var dist := int(visited.get(cur, 0))
		if dist >= max_steps:
			continue

		var def_val = EmployeeRegistryClass.get_def(cur)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		for nxt_val in def.train_to:
			var nxt: String = str(nxt_val)
			if nxt.is_empty():
				continue
			if visited.has(nxt):
				continue
			var ndist := dist + 1
			if ndist > max_steps:
				continue

			visited[nxt] = ndist
			queue.append(nxt)
			targets.append(nxt)

	targets.sort()
	return targets

func _read_immediate_train_pending_sources(state: GameState, player_id: int) -> Dictionary:
	var sources := {}
	if state == null or not (state.round_state is Dictionary):
		return sources
	var rs: Dictionary = state.round_state
	var all_val = rs.get("immediate_train_pending", null)
	if not (all_val is Dictionary):
		return sources
	var all: Dictionary = all_val

	var per_val = null
	if all.has(player_id):
		per_val = all.get(player_id, null)
	elif all.has(str(player_id)):
		per_val = all.get(str(player_id), null)
	if not (per_val is Dictionary):
		return sources
	var per: Dictionary = per_val

	for k in per.keys():
		if not (k is String):
			continue
		var emp_id: String = str(k)
		if emp_id.is_empty():
			continue
		var v = per.get(k, 0)
		var count := 0
		if v is int:
			count = int(v)
		elif v is float:
			var f: float = float(v)
			if f == int(f):
				count = int(f)
		if count <= 0:
			continue
		sources[emp_id] = count

	return sources

func _on_train_requested(from_employee: String, to_employee: String) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var was_visible: bool = is_instance_valid(train_panel) and bool(train_panel.visible)
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("train", current_player_id, {
		"from_employee": from_employee,
		"to_employee": to_employee
	}))

	if result.ok:
		var state: GameState = _scene.game_engine.get_state()
		if state != null and state.phase == DefsClass.PHASE_WORKING and state.sub_phase == DefsClass.SUB_PHASE_TRAIN:
			# 执行命令后 UI 会立刻同步；再调用 show() 会触发 hide_all()，
			# 可能误关闭“培训后立即可选动作”的模块覆盖层。
			_refresh_for_state(state)
			if was_visible and is_instance_valid(train_panel) and train_panel.visible and train_panel.has_method("refresh"):
				train_panel.refresh()
