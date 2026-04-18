# Game scene：Working/Train 面板控制器
# 负责：TrainPanel 的生命周期、同步与命令分发。
class_name GamePanelWorkingTrainController
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const TrainActionClass = preload("res://gameplay/actions/train_action.gd")
const TrainPanelScene = preload("res://ui/components/train_panel/train_panel.tscn")
const StaffStateClass = preload("res://core/state/staff_state.gd")

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
		var source_items: Array[Dictionary] = []
		var section_text := "待命区员工（点击选择）"

		if pending_total > 0:
			source_items = _build_immediate_train_pending_source_items(state, actor_id)
			section_text = "缺货预支待培训（必须先清账）"
		else:
			source_items = _build_trainable_source_items_from_staff(state, actor_id)
			var can_train_from_active := bool(current_player.get("train_from_active_same_color", false))
			if can_train_from_active:
				section_text = "待命/在岗员工（点击选择；在岗同色培训：目标需同色）"
		source_items = _filter_source_items_with_valid_targets(state, actor_id, source_items)
		if train_panel.has_method("set_trainable_source_items"):
			train_panel.set_trainable_source_items(source_items, section_text)
		elif train_panel.has_method("set_trainable_sources"):
			train_panel.set_trainable_sources({}, section_text)
		else:
			var reserve: Array[String] = []
			for item_val in source_items:
				if not (item_val is Dictionary):
					continue
				var item: Dictionary = item_val
				var emp_id := str(item.get("employee_type", ""))
				if not emp_id.is_empty():
					reserve.append(emp_id)
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

func _build_trainable_source_items_from_staff(state: GameState, actor_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var sync_read := StaffStateClass.ensure_state_staff_support(state)
	if not sync_read.ok:
		return out
	var player: Dictionary = state.get_player(actor_id)
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))
	var reserve_ids: Array = Array(player.get("reserve_staff_ids", []))
	var active_ids: Array = Array(player.get("employees_staff_ids", []))
	var registry: Dictionary = Dictionary(player.get("staff_registry", {}))

	for staff_id_val in reserve_ids:
		var item := _build_train_source_item_from_registry_entry(registry, int(staff_id_val), "reserve_employees", false, "")
		if not item.is_empty():
			out.append(item)
	if can_train_from_active:
		for staff_id_val2 in active_ids:
			var staff_id := int(staff_id_val2)
			var emp_type := _read_employee_type_from_registry(registry, staff_id)
			if emp_type.is_empty():
				continue
			var reserve_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, actor_id, emp_type, ["reserve_employees"])
			var reserve_has_same_type := reserve_ids_read.ok and not Array(reserve_ids_read.value).is_empty()
			var tag_text := "在岗" if not reserve_has_same_type else ""
			var item2 := _build_train_source_item_from_registry_entry(registry, staff_id, "employees", true, tag_text)
			if not item2.is_empty():
				out.append(item2)

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	return out

func _build_train_source_item_from_registry_entry(
	registry: Dictionary,
	staff_id: int,
	zone_key: String,
	requires_same_color: bool,
	tag_text: String
) -> Dictionary:
	if staff_id <= 0:
		return {}
	if not registry.has(staff_id):
		return {}
	var record_val = registry.get(staff_id, null)
	if not (record_val is Dictionary):
		return {}
	var record: Dictionary = record_val
	var emp_type := str(record.get("employee_type", "")).strip_edges()
	if emp_type.is_empty():
		return {}
	return {
		"staff_id": staff_id,
		"employee_type": emp_type,
		"zone_key": zone_key,
		"requires_same_color": requires_same_color,
		"tag_text": tag_text,
		"badge_count": 1,
		"enabled": true,
	}

func _read_employee_type_from_registry(registry: Dictionary, staff_id: int) -> String:
	if staff_id <= 0 or not registry.has(staff_id):
		return ""
	var record_val = registry.get(staff_id, null)
	if not (record_val is Dictionary):
		return ""
	return str(Dictionary(record_val).get("employee_type", "")).strip_edges()

func _build_immediate_train_pending_source_items(state: GameState, player_id: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var sources := _read_immediate_train_pending_sources(state, player_id)
	for key in sources.keys():
		if not (key is String):
			continue
		var emp_id := str(key).strip_edges()
		if emp_id.is_empty():
			continue
		var count := int(sources.get(key, 0))
		for i in range(count):
			items.append({
				"staff_id": -(i + 1 + items.size()),
				"employee_type": emp_id,
				"zone_key": "pending",
				"requires_same_color": false,
				"tag_text": "预支",
				"badge_count": 1,
				"enabled": true,
			})
	return items

func _filter_source_items_with_valid_targets(state: GameState, actor_id: int, source_items: Array[Dictionary]) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for item_val in source_items:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if _source_item_has_valid_train_target(state, actor_id, item):
			filtered.append(item)
	return filtered

func _source_item_has_valid_train_target(state: GameState, actor_id: int, item: Dictionary) -> bool:
	var from_employee := str(item.get("employee_type", "")).strip_edges()
	var source_staff_id := int(item.get("staff_id", -1))
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
		var params := {
			"from_employee": from_employee,
			"to_employee": target,
		}
		if source_staff_id > 0:
			params["staff_id"] = source_staff_id
		var validate_result := action.validate(state, Command.create("train", actor_id, params))
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

func _on_train_requested(from_employee: String, to_employee: String, staff_id: int) -> void:
	if _scene == null or _scene.game_engine == null:
		return
	if not _execute_command.is_valid():
		return
	var was_visible: bool = is_instance_valid(train_panel) and bool(train_panel.visible)
	var current_player_id = _scene.game_engine.get_state().get_current_player_id()
	var result: Result = _execute_command.call(Command.create("train", current_player_id, {
		"from_employee": from_employee,
		"to_employee": to_employee,
		"staff_id": staff_id
	}))

	if result.ok:
		var state: GameState = _scene.game_engine.get_state()
		if state != null and state.phase == DefsClass.PHASE_WORKING and state.sub_phase == DefsClass.SUB_PHASE_TRAIN:
			# 执行命令后 UI 会立刻同步；再调用 show() 会触发 hide_all()，
			# 可能误关闭“培训后立即可选动作”的模块覆盖层。
			_refresh_for_state(state)
			if was_visible and is_instance_valid(train_panel) and train_panel.visible and train_panel.has_method("refresh"):
				train_panel.refresh()
