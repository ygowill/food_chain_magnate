# 实体标签页
# 提供实体浏览和检查功能
extends MarginContainer

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

var _registry: DebugCommandRegistry = null

@onready var entity_tree: Tree = $HSplitContainer/EntityTree
@onready var details_label: Label = $HSplitContainer/EntityDetails/DetailsLabel
@onready var details_text: RichTextLabel = $HSplitContainer/EntityDetails/DetailsText

var _tree_root: TreeItem = null
var _last_state: GameState = null

func init(registry: DebugCommandRegistry) -> void:
	_registry = registry

func _ready() -> void:
	if is_instance_valid(entity_tree):
		entity_tree.item_selected.connect(_on_item_selected)
		_build_tree()

func _build_tree() -> void:
	if not is_instance_valid(entity_tree):
		return

	entity_tree.clear()
	_tree_root = entity_tree.create_item()

func refresh() -> void:
	if _registry == null:
		return

	var engine := _registry.get_game_engine()
	if engine == null:
		return

	var state := engine.get_state()
	if state == null:
		return
	_last_state = state

	_build_tree()
	_populate_tree(state)

func _populate_tree(state: GameState) -> void:
	if not is_instance_valid(entity_tree) or _tree_root == null:
		return

	# 玩家分类
	var players_item := entity_tree.create_item(_tree_root)
	players_item.set_text(0, "玩家 (%d)" % state.players.size())
	players_item.set_metadata(0, {"type": "category", "category": "players"})

	for i in range(state.players.size()):
		var player: Dictionary = state.players[i]
		var cash := int(player.get("cash", 0))
		var player_item := entity_tree.create_item(players_item)
		player_item.set_text(0, "玩家 %d ($%d)" % [i, cash])
		player_item.set_metadata(0, {"type": "player", "id": i, "data": player})

		_add_employee_group(player_item, i, player, "employees", "在岗员工")
		_add_employee_group(player_item, i, player, "reserve_employees", "待命员工")
		_add_employee_group(player_item, i, player, "busy_marketers", "忙碌营销员")

	# 建筑分类
	var map_data = state.map
	if map_data is Dictionary:
		var buildings = map_data.get("buildings", [])
		if buildings is Array:
			var buildings_item := entity_tree.create_item(_tree_root)
			buildings_item.set_text(0, "建筑 (%d)" % buildings.size())
			buildings_item.set_metadata(0, {"type": "category", "category": "buildings"})

			for i in range(buildings.size()):
				var b = buildings[i]
				if b is Dictionary:
					var pos = b.get("position", {})
					var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
					var type_str := str(b.get("type", "?"))
					var building_item := entity_tree.create_item(buildings_item)
					building_item.set_text(0, "%s @ %s" % [type_str, pos_str])
					building_item.set_metadata(0, {"type": "building", "index": i, "data": b})

	# 营销实例分类
	var instances = state.marketing_instances
	if instances is Array and not instances.is_empty():
		var marketing_item := entity_tree.create_item(_tree_root)
		marketing_item.set_text(0, "营销 (%d)" % instances.size())
		marketing_item.set_metadata(0, {"type": "category", "category": "marketing"})

		for i in range(instances.size()):
			var inst = instances[i]
			if inst is Dictionary:
				var type_str := str(inst.get("type", "?"))
				var pos = inst.get("position", {})
				var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
				var inst_item := entity_tree.create_item(marketing_item)
				inst_item.set_text(0, "%s @ %s" % [type_str, pos_str])
				inst_item.set_metadata(0, {"type": "marketing", "index": i, "data": inst})

func _on_item_selected() -> void:
	var selected := entity_tree.get_selected()
	if selected == null:
		return

	var metadata = selected.get_metadata(0)
	if metadata == null or not (metadata is Dictionary):
		return

	_show_details(metadata)

func _show_details(metadata: Dictionary) -> void:
	if not is_instance_valid(details_label) or not is_instance_valid(details_text):
		return

	var entity_type: String = metadata.get("type", "")
	var data = metadata.get("data", {})

	match entity_type:
		"player":
			details_label.text = "玩家 %d" % metadata.get("id", -1)
			var pid := int(metadata.get("id", -1))
			var viewer_pid := _resolve_viewer_player_id(_last_state)
			var sanitized := _sanitize_player_dict_for_viewer(data, pid, viewer_pid, _last_state)
			details_text.text = _format_dict(sanitized)
		"employee":
			details_label.text = "员工 (玩家 %d)" % metadata.get("player_id", -1)
			details_text.text = _format_dict(data)
		"employee_id":
			var pid := int(metadata.get("player_id", -1))
			var eid: String = str(metadata.get("employee_id", ""))
			var list_key: String = str(metadata.get("list", ""))
			details_label.text = "员工 %s (玩家 %d)" % [eid, pid]
			var detail := {
				"player_id": pid,
				"employee_id": eid,
				"list": list_key,
			}
			if EmployeeRegistryClass.is_loaded() and EmployeeRegistryClass.has(eid):
				var def_val = EmployeeRegistryClass.get_def(eid)
				if def_val != null and def_val.has_method("to_dict"):
					detail["def"] = def_val.to_dict()
			details_text.text = _format_dict(detail)
		"building":
			details_label.text = "建筑 #%d" % metadata.get("index", -1)
			details_text.text = _format_dict(data)
		"marketing":
			details_label.text = "营销 #%d" % metadata.get("index", -1)
			details_text.text = _format_dict(data)
		"category":
			var cat: String = str(metadata.get("category", "分类"))
			var pid2 := int(metadata.get("player_id", -1))
			details_label.text = ("%s (玩家 %d)" % [cat, pid2]) if pid2 >= 0 else cat
			details_text.text = "选择一个具体实体查看详情"
		_:
			details_label.text = "未知类型"
			details_text.text = str(metadata)

func _resolve_viewer_player_id(state: GameState) -> int:
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		return int(NetContext.get_command_privacy_viewer_player_id())
	if state != null:
		var cur := int(state.get_current_player_id())
		if cur >= 0:
			return cur
	return -1

func _viewer_can_peek_all_reserve_cards(viewer_player_id: int, state: GameState) -> bool:
	if state == null:
		return false
	if viewer_player_id < 0 or viewer_player_id >= state.players.size():
		return false
	var p_val = state.players[viewer_player_id]
	if not (p_val is Dictionary):
		return false
	var p: Dictionary = p_val
	var v = p.get("can_peek_all_reserve_cards", false)
	return (v is bool) and bool(v)

func _sanitize_player_dict_for_viewer(player: Dictionary, player_id: int, viewer_player_id: int, state: GameState) -> Dictionary:
	if player == null:
		return {}

	var out: Dictionary = player.duplicate(true)

	# 无法确定查看者：不做脱敏（通常为开发调试模式）
	if viewer_player_id < 0:
		return out

	# 本人可见
	if viewer_player_id == player_id:
		return out

	# 特殊能力：允许查看全部储备卡（里程碑 first_have_20）
	if _viewer_can_peek_all_reserve_cards(viewer_player_id, state):
		return out

	# 其它玩家：在储备卡揭示前隐藏 reserve_cards/selected；揭示后仅公开已选择的那一张卡
	var cards_val = out.get("reserve_cards", null)
	if cards_val is Array:
		var cards: Array = cards_val
		var revealed := bool(out.get("reserve_card_revealed", false))

		var idx := -1
		var idx_val = out.get("reserve_card_selected", -1)
		if idx_val is int:
			idx = int(idx_val)
		elif idx_val is float:
			var f: float = float(idx_val)
			if f == floor(f):
				idx = int(f)

		var masked: Array = []
		if revealed and idx >= 0 and idx < cards.size():
			for i in range(cards.size()):
				masked.append(cards[i] if i == idx else "<hidden>")
		else:
			for _i in range(cards.size()):
				masked.append("<hidden>")
			if out.has("reserve_card_selected"):
				out["reserve_card_selected"] = "<hidden>"

		out["reserve_cards"] = masked

	return out

func _add_employee_group(parent_item: TreeItem, player_id: int, player: Dictionary, key: String, label: String) -> void:
	if not is_instance_valid(entity_tree):
		return

	var list_val = player.get(key, null)
	if not (list_val is Array):
		return
	var list: Array = list_val

	var group_item := entity_tree.create_item(parent_item)
	group_item.set_text(0, "%s (%d)" % [label, list.size()])
	group_item.set_metadata(0, {"type": "category", "category": key, "player_id": player_id})

	for emp_val in list:
		var emp_id := _extract_employee_id(emp_val)
		if emp_id.is_empty():
			continue
		var emp_item := entity_tree.create_item(group_item)
		emp_item.set_text(0, _format_employee_title(emp_id))
		emp_item.set_metadata(0, {"type": "employee_id", "player_id": player_id, "employee_id": emp_id, "list": key})

func _extract_employee_id(emp_val: Variant) -> String:
	if emp_val is String:
		return str(emp_val)
	if emp_val is Dictionary:
		var emp: Dictionary = emp_val
		var id_val = emp.get("employee_id", null)
		if id_val is String:
			return str(id_val)
	return ""

func _format_employee_title(employee_id: String) -> String:
	if employee_id.is_empty():
		return ""
	if EmployeeRegistryClass.is_loaded() and EmployeeRegistryClass.has(employee_id):
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and def_val.has_method("to_dict"):
			var d: Dictionary = def_val.to_dict()
			var name: String = str(d.get("name", employee_id))
			if not name.is_empty() and name != employee_id:
				return "%s (%s)" % [name, employee_id]
	return employee_id

func _format_dict(data: Dictionary, indent: int = 0) -> String:
	var lines: Array[String] = []
	var prefix := "  ".repeat(indent)

	for key in data.keys():
		var value = data[key]
		if value is Dictionary:
			lines.append("%s%s:" % [prefix, str(key)])
			lines.append(_format_dict(value, indent + 1))
		elif value is Array:
			lines.append("%s%s: [%d 项]" % [prefix, str(key), value.size()])
			for i in range(mini(value.size(), 5)):
				var item = value[i]
				if item is Dictionary:
					lines.append("%s  [%d]:" % [prefix, i])
					lines.append(_format_dict(item, indent + 2))
				else:
					lines.append("%s  [%d]: %s" % [prefix, i, str(item)])
			if value.size() > 5:
				lines.append("%s  ... 还有 %d 项" % [prefix, value.size() - 5])
		else:
			lines.append("%s%s: %s" % [prefix, str(key), str(value)])

	return "\n".join(lines)
