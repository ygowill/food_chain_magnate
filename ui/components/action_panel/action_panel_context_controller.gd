# ActionPanel：上下文面板与 overlay 同步控制器（从 action_panel.gd 拆出以降低文件体积）
extends RefCounted

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PiecePlacementOverlayScript = preload("res://ui/components/piece_placement/piece_placement_overlay.gd")
const PiecePickerButtonClass = preload("res://ui/components/action_panel/piece_picker_button.gd")

var _action_registry = null
var _map_skin = null # MapSkin (optional)
var _panel: Object = null

var _context_panel: Control = null
var _context_title_label: Label = null
var _context_hint_label: Label = null
var _restaurant_row: Control = null
var _restaurant_option: OptionButton = null
var _employee_row: Control = null
var _employee_option: HFlowContainer = null
var _piece_row: Control = null
var _piece_flow: HFlowContainer = null
var _rotation_row: Control = null
var _rotate_left_button: Button = null
var _rotation_value_label: Label = null
var _rotate_right_button: Button = null
var _house_number_row: Control = null
var _house_number_option: OptionButton = null
var _direction_row: Control = null
var _direction_option: OptionButton = null
var _custom_context_container: Control = null
var _cancel_context_button: Button = null
var _skip_context_button: Button = null
var _confirm_context_button: Button = null

var _context_overlay: Node = null
var _context_syncing: bool = false
var _custom_context_node: Control = null
var _custom_context_scene_path: String = ""

func setup(panel) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_panel = panel
	_context_panel = panel.context_panel
	_context_title_label = panel.context_title_label
	_context_hint_label = panel.context_hint_label
	_restaurant_row = panel.restaurant_row
	_restaurant_option = panel.restaurant_option
	_employee_row = panel.employee_row
	_employee_option = panel.employee_option
	_piece_row = panel.piece_row
	_piece_flow = panel.piece_flow
	_rotation_row = panel.rotation_row
	_rotate_left_button = panel.rotate_left_button
	_rotation_value_label = panel.rotation_value_label
	_rotate_right_button = panel.rotate_right_button
	_house_number_row = panel.house_number_row
	_house_number_option = panel.house_number_option
	_direction_row = panel.direction_row
	_direction_option = panel.direction_option
	_custom_context_container = panel.custom_context_container
	_cancel_context_button = panel.cancel_context_button
	_skip_context_button = panel.skip_context_button
	_confirm_context_button = panel.confirm_context_button

	if not is_instance_valid(_context_panel):
		return
	_context_panel.visible = false

	UiSignalHelpersClass.safe_connect(_cancel_context_button, "pressed", _on_cancel_context_pressed)
	UiSignalHelpersClass.safe_connect(_skip_context_button, "pressed", _on_skip_context_pressed)
	UiSignalHelpersClass.safe_connect(_confirm_context_button, "pressed", _on_confirm_context_pressed)
	UiSignalHelpersClass.safe_connect(_restaurant_option, "item_selected", _on_restaurant_option_selected)
	UiSignalHelpersClass.safe_connect(_employee_option, "employee_selected", _on_employee_option_selected)
	UiSignalHelpersClass.safe_connect(_rotate_left_button, "pressed", _on_rotate_left_pressed)
	UiSignalHelpersClass.safe_connect(_rotate_right_button, "pressed", _on_rotate_right_pressed)
	UiSignalHelpersClass.safe_connect(_house_number_option, "item_selected", _on_house_number_option_selected)
	UiSignalHelpersClass.safe_connect(_direction_option, "item_selected", _on_direction_option_selected)
	_clear_custom_context()

func set_action_registry(registry) -> void:
	_action_registry = registry
	_refresh_context_from_overlay()

func set_map_skin(skin) -> void:
	if _map_skin == skin:
		return
	_map_skin = skin
	_refresh_context_from_overlay()

func bind_context_overlay(overlay: Node) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	if _context_overlay == overlay:
		_refresh_context_from_overlay()
		return

	_detach_overlay_signals()
	_clear_custom_context()
	_context_overlay = overlay
	_attach_overlay_signals()
	_refresh_context_from_overlay()

func clear_context_overlay() -> void:
	_detach_overlay_signals()
	_clear_custom_context()
	_context_overlay = null
	_hide_context_panel()

func _attach_overlay_signals() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return
	UiSignalHelpersClass.safe_connect(_context_overlay, "ui_state_changed", _on_overlay_ui_state_changed)

func _detach_overlay_signals() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return
	var sig := StringName("ui_state_changed")
	if not _context_overlay.has_signal(sig):
		return
	if _context_overlay.is_connected(sig, _on_overlay_ui_state_changed):
		_context_overlay.disconnect(sig, _on_overlay_ui_state_changed)

func _on_overlay_ui_state_changed() -> void:
	_refresh_context_from_overlay()

func _hide_context_panel() -> void:
	if is_instance_valid(_context_panel):
		_context_panel.visible = false
	if is_instance_valid(_skip_context_button):
		_skip_context_button.visible = false
		_skip_context_button.tooltip_text = ""

func _show_context_panel() -> void:
	if is_instance_valid(_context_panel):
		_context_panel.visible = true

func _get_executor_display_name(action_id: String) -> String:
	if _action_registry == null or not _action_registry.has_method("get_executor"):
		return ""
	var ex = _action_registry.get_executor(action_id)
	if ex == null:
		return ""
	return str(ex.display_name).strip_edges()

func _refresh_context_from_overlay() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		_hide_context_panel()
		return
	if _context_overlay is Control and not (_context_overlay as Control).visible:
		clear_context_overlay()
		return

	if _context_overlay.has_method("get_action_panel_context_spec"):
		_refresh_custom_context(_context_overlay)
		return
	if _is_restaurant_placement_overlay(_context_overlay):
		_refresh_restaurant_placement_context(_context_overlay)
		return
	if _is_house_placement_overlay(_context_overlay):
		_refresh_house_placement_context(_context_overlay)
		return
	if PiecePlacementOverlayScript != null and _context_overlay is PiecePlacementOverlayScript:
		_refresh_piece_placement_context(_context_overlay)
		return

	clear_context_overlay()

func _is_restaurant_placement_overlay(overlay: Object) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	return overlay.has_method("get_available_restaurants") and overlay.has_method("get_selected_restaurant")

func _is_house_placement_overlay(overlay: Object) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	return overlay.has_method("get_available_house_numbers") and overlay.has_method("get_selected_house_number")

func _set_custom_context_visible(show: bool) -> void:
	if is_instance_valid(_custom_context_container):
		_custom_context_container.visible = show

func _sync_skip_sub_phase_button() -> void:
	if not is_instance_valid(_skip_context_button):
		return

	var cfg: Dictionary = {}
	if _panel != null and is_instance_valid(_panel) and _panel.has_method("get_flow_controls_config"):
		var v = _panel.call("get_flow_controls_config")
		if v is Dictionary:
			var ss_val = (v as Dictionary).get("skip_step", null)
			if ss_val is Dictionary:
				cfg = Dictionary(ss_val)

	var visible := bool(cfg.get("visible", false))
	_skip_context_button.visible = visible
	if not visible:
		_skip_context_button.tooltip_text = ""
		return

	_skip_context_button.text = str(cfg.get("text", "跳过"))
	var enabled := bool(cfg.get("enabled", true))
	_skip_context_button.disabled = not enabled

	var reason := str(cfg.get("disabled_reason", "")).strip_edges()
	if _skip_context_button.disabled and not reason.is_empty():
		_skip_context_button.tooltip_text = "不可用：%s" % reason
	else:
		_skip_context_button.tooltip_text = ""

func _refresh_restaurant_placement_context(overlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode: String = str(overlay.get_mode()).strip_edges()
	_context_title_label.text = "放置餐厅" if mode != "move_restaurant" else "移动餐厅"
	_context_hint_label.text = overlay.get_hint_text()

	_restaurant_row.visible = (mode == "move_restaurant")
	_employee_row.visible = false
	_piece_row.visible = false
	_direction_row.visible = false
	_rotation_row.visible = true
	_house_number_row.visible = false
	_set_custom_context_visible(false)

	_sync_rotation_controls(overlay.get_selected_rotation())
	_rebuild_employee_picker_for_overlay(overlay)
	_employee_row.visible = _overlay_has_employee_items(overlay)

	if mode == "move_restaurant":
		_rebuild_restaurant_option(
			overlay.get_available_restaurants(),
			overlay.get_selected_restaurant()
		)

	_confirm_context_button.text = "确认移动" if mode == "move_restaurant" else "确认放置"
	_confirm_context_button.disabled = not overlay.can_confirm()
	_cancel_context_button.visible = false
	_cancel_context_button.text = "取消"
	_sync_skip_sub_phase_button()

	_context_syncing = false

func _refresh_house_placement_context(overlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode: String = str(overlay.get_mode()).strip_edges()
	_context_title_label.text = "添加花园" if mode == "add_garden" else "放置房屋"
	_context_hint_label.text = overlay.get_hint_text()

	_restaurant_row.visible = false
	_employee_row.visible = false
	_piece_row.visible = false
	_rotation_row.visible = (mode == "place_house")
	_house_number_row.visible = (mode == "place_house")
	_direction_row.visible = (mode == "add_garden")
	_set_custom_context_visible(false)

	_rebuild_employee_picker_for_overlay(overlay)
	_employee_row.visible = _overlay_has_employee_items(overlay)

	if mode == "place_house":
		_sync_rotation_controls(overlay.get_selected_rotation())
		_rebuild_house_number_option(
			overlay.get_available_house_numbers(),
			overlay.get_selected_house_number()
		)
	if mode == "add_garden":
		_rebuild_direction_option(overlay.get_selected_direction())

	_confirm_context_button.text = "确认添加花园" if mode == "add_garden" else "确认放置"
	_confirm_context_button.disabled = not overlay.can_confirm()
	_cancel_context_button.visible = false
	_cancel_context_button.text = "取消"
	_sync_skip_sub_phase_button()

	_context_syncing = false

func _refresh_piece_placement_context(overlay) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	_context_syncing = true
	_show_context_panel()

	var mode := str(overlay.get_mode()).strip_edges()
	var title := _get_executor_display_name(mode)
	if title.is_empty():
		_context_title_label.text = "放置板块"
	else:
		_context_title_label.text = title
	_context_hint_label.text = overlay.get_hint_text()

	_restaurant_row.visible = false
	_employee_row.visible = false
	_piece_row.visible = true
	_rotation_row.visible = true
	_house_number_row.visible = false
	_direction_row.visible = false
	_set_custom_context_visible(false)

	_rebuild_piece_flow(overlay.get_available_pieces(), overlay.get_selected_piece(), overlay.get_selected_rotation())
	_sync_rotation_controls(overlay.get_selected_rotation())

	_confirm_context_button.text = "确认放置"
	_confirm_context_button.disabled = not overlay.can_confirm()
	_cancel_context_button.visible = false
	_cancel_context_button.text = "取消"
	_sync_skip_sub_phase_button()

	_context_syncing = false

func _clear_custom_context() -> void:
	_custom_context_scene_path = ""
	_custom_context_node = null
	if not is_instance_valid(_custom_context_container):
		return
	for child in _custom_context_container.get_children():
		child.queue_free()

func _refresh_custom_context(overlay: Node) -> void:
	if overlay == null or not is_instance_valid(overlay):
		clear_context_overlay()
		return

	var spec_val = overlay.call("get_action_panel_context_spec") if overlay.has_method("get_action_panel_context_spec") else null
	if not (spec_val is Dictionary):
		clear_context_overlay()
		return
	var spec: Dictionary = spec_val

	_context_syncing = true
	_show_context_panel()

	var title := str(spec.get("title", "")).strip_edges()
	_context_title_label.text = title if not title.is_empty() else "当前操作"

	var hint := ""
	if spec.has("hint"):
		hint = str(spec.get("hint", ""))
	elif overlay.has_method("get_hint_text"):
		hint = str(overlay.call("get_hint_text"))
	_context_hint_label.text = hint

	_restaurant_row.visible = false
	_employee_row.visible = false
	_piece_row.visible = false
	_rotation_row.visible = false
	_house_number_row.visible = false
	_direction_row.visible = false
	_set_custom_context_visible(true)

	var scene_path := str(spec.get("custom_scene", "")).strip_edges()
	_ensure_custom_context_node(scene_path, overlay)
	_sync_custom_context_node(overlay)

	if is_instance_valid(_cancel_context_button):
		_cancel_context_button.visible = false
		_cancel_context_button.text = str(spec.get("cancel_text", "取消"))
	if is_instance_valid(_confirm_context_button):
		_confirm_context_button.text = str(spec.get("confirm_text", "确认"))
		var disabled := false
		if overlay.has_method("can_confirm"):
			disabled = not bool(overlay.call("can_confirm"))
		elif spec.has("confirm_disabled"):
			disabled = bool(spec.get("confirm_disabled", false))
		_confirm_context_button.disabled = disabled
	_sync_skip_sub_phase_button()

	_context_syncing = false

func _should_clear_context_on_cancel() -> bool:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return true
	if not _context_overlay.has_method("get_action_panel_context_spec"):
		return true
	var spec_val = _context_overlay.call("get_action_panel_context_spec")
	if not (spec_val is Dictionary):
		return true
	var spec: Dictionary = spec_val
	return bool(spec.get("clear_on_cancel", true))

func _ensure_custom_context_node(scene_path: String, overlay: Node) -> void:
	if not is_instance_valid(_custom_context_container):
		return
	var path := str(scene_path).strip_edges()
	if path.is_empty():
		_clear_custom_context()
		return
	if path != _custom_context_scene_path or _custom_context_container.get_child_count() == 0:
		_clear_custom_context()
		_custom_context_scene_path = path
		var res = load(path)
		if res is PackedScene:
			var inst = (res as PackedScene).instantiate()
			if inst != null:
				_custom_context_container.add_child(inst)
				_custom_context_node = inst if inst is Control else null
		elif res is Script:
			var inst2 = (res as Script).new()
			if inst2 != null:
				_custom_context_container.add_child(inst2)
				_custom_context_node = inst2 if inst2 is Control else null

func _sync_custom_context_node(overlay: Node) -> void:
	if not is_instance_valid(_custom_context_node):
		return
	if _custom_context_node.has_method("bind_overlay"):
		_custom_context_node.call("bind_overlay", overlay)
	elif _custom_context_node.has_method("set_overlay"):
		_custom_context_node.call("set_overlay", overlay)
	if _custom_context_node.has_method("sync_from_overlay"):
		_custom_context_node.call("sync_from_overlay")

func _sync_rotation_controls(selected_rotation: int) -> void:
	if is_instance_valid(_rotation_value_label):
		_rotation_value_label.text = "%d度" % int(selected_rotation)

	var can_rotate := _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("set_selected_rotation")
	var globally_disabled := false
	if _panel != null and is_instance_valid(_panel) and _panel.has_method("is_globally_disabled"):
		globally_disabled = bool(_panel.call("is_globally_disabled"))
	if is_instance_valid(_rotate_left_button):
		_rotate_left_button.disabled = globally_disabled or not can_rotate
	if is_instance_valid(_rotate_right_button):
		_rotate_right_button.disabled = globally_disabled or not can_rotate

func _rebuild_house_number_option(available_numbers: Array[int], selected_house_number: int) -> void:
	if not is_instance_valid(_house_number_option):
		return
	_house_number_option.clear()
	_house_number_option.add_item("请选择...")
	_house_number_option.set_item_metadata(0, -1)
	var nums: Array[int] = []
	for n_val in available_numbers:
		nums.append(int(n_val))
	nums.sort()
	for n in nums:
		_house_number_option.add_item(str(n))
		var idx := _house_number_option.get_item_count() - 1
		_house_number_option.set_item_metadata(idx, int(n))
	_select_option_by_metadata_int(_house_number_option, int(selected_house_number))

func _rebuild_direction_option(selected_direction: String) -> void:
	if not is_instance_valid(_direction_option):
		return
	_direction_option.clear()
	for d in ["N", "E", "S", "W"]:
		_direction_option.add_item(d)
		var idx := _direction_option.get_item_count() - 1
		_direction_option.set_item_metadata(idx, d)
	_select_option_by_metadata_string(_direction_option, selected_direction)

func _rebuild_restaurant_option(restaurant_ids: Array[String], selected_restaurant_id: String) -> void:
	if not is_instance_valid(_restaurant_option):
		return
	_restaurant_option.clear()
	var ids := restaurant_ids.duplicate()
	ids.sort()
	for rid in ids:
		var s := str(rid).strip_edges()
		if s.is_empty():
			continue
		var label := s
		if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("get_restaurant_display_label"):
			var v = _context_overlay.call("get_restaurant_display_label", s)
			var t := str(v).strip_edges()
			if not t.is_empty():
				label = t
		_restaurant_option.add_item(label)
		var idx := _restaurant_option.get_item_count() - 1
		_restaurant_option.set_item_metadata(idx, s)
	_select_option_by_metadata_string(_restaurant_option, selected_restaurant_id)

func _rebuild_piece_flow(piece_ids: Array[String], selected_piece_id: String, rotation: int) -> void:
	if not is_instance_valid(_piece_flow):
		return

	# Clear old buttons
	for child in _piece_flow.get_children():
		if is_instance_valid(child):
			child.queue_free()

	var ids := piece_ids.duplicate()
	var selected := str(selected_piece_id).strip_edges()
	var rot := int(rotation)

	var group := ButtonGroup.new()
	group.allow_unpress = false

	for pid in ids:
		var s := str(pid).strip_edges()
		if s.is_empty():
			continue

		var btn = PiecePickerButtonClass.new()
		btn.piece_id = s
		btn.call("set_piece_rotation", rot)
		btn.button_group = group
		btn.button_pressed = (not selected.is_empty()) and s == selected
		if _map_skin != null and is_instance_valid(_map_skin) and _map_skin.has_method("get_piece_texture") and btn.has_method("set_preview_texture"):
			btn.call("set_preview_texture", _map_skin.call("get_piece_texture", s))

		var label := s
		if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("get_piece_display_label"):
			var v = _context_overlay.call("get_piece_display_label", s)
			var t := str(v).strip_edges()
			if not t.is_empty():
				label = t
		btn.tooltip_text = label

		btn.pressed.connect(_on_piece_button_pressed.bind(s))
		_piece_flow.add_child(btn)

func _on_piece_button_pressed(piece_id: String) -> void:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return
	_call_context_overlay_method("set_selected_piece", [pid])

func _rebuild_employee_option(employee_ids: Array[String], selected_employee_id: String) -> void:
	if not is_instance_valid(_employee_option):
		return
	var ids: Array[String] = []
	var seen := {}
	for v in employee_ids:
		var s := str(v).strip_edges()
		if s.is_empty():
			continue
		if not seen.has(s):
			ids.append(s)
		seen[s] = int(seen.get(s, 0)) + 1
	ids.sort()

	var items: Array[Dictionary] = []
	for emp_id in ids:
		items.append({
			"id": emp_id,
			"employee_def": _get_employee_def_for_card(emp_id),
			"badge_text": "",
			"enabled": true,
		})

	var selected := str(selected_employee_id).strip_edges()
	if selected.is_empty() and not ids.is_empty():
		selected = str(ids[0])
	_employee_option.set_items(items, selected)

func _overlay_has_employee_items(overlay) -> bool:
	if overlay == null or not is_instance_valid(overlay):
		return false
	if overlay.has_method("get_available_employee_items"):
		var items_val = overlay.call("get_available_employee_items")
		return items_val is Array and not Array(items_val).is_empty()
	if overlay.has_method("get_available_employees"):
		var ids_val = overlay.call("get_available_employees")
		return ids_val is Array and not Array(ids_val).is_empty()
	return false

func _rebuild_employee_picker_for_overlay(overlay) -> void:
	if not is_instance_valid(_employee_option):
		return
	if overlay != null and is_instance_valid(overlay) and overlay.has_method("get_available_employee_items"):
		var items_val = overlay.call("get_available_employee_items")
		var items: Array[Dictionary] = []
		if items_val is Array:
			for item_val in Array(items_val):
				if item_val is Dictionary:
					items.append(Dictionary(item_val))
		var selected_key := ""
		if overlay.has_method("get_selected_employee_key"):
			selected_key = str(overlay.call("get_selected_employee_key")).strip_edges()
		_employee_option.set_items(items, selected_key)
		return
	if overlay != null and is_instance_valid(overlay) and overlay.has_method("get_available_employees") and overlay.has_method("get_selected_employee"):
		_rebuild_employee_option(overlay.get_available_employees(), overlay.get_selected_employee())
		return
	_employee_option.clear()

func _select_option_by_metadata_int(option: OptionButton, desired: int) -> void:
	if option == null or not is_instance_valid(option):
		return
	for i in range(option.get_item_count()):
		if int(option.get_item_metadata(i)) == desired:
			option.select(i)
			return
	if option.get_item_count() > 0:
		option.select(0)

func _select_option_by_metadata_string(option: OptionButton, desired: String) -> void:
	if option == null or not is_instance_valid(option):
		return
	var d := str(desired).strip_edges()
	if not d.is_empty():
		for i in range(option.get_item_count()):
			if str(option.get_item_metadata(i)) == d:
				option.select(i)
				return
	if option.get_item_count() > 0:
		option.select(0)

func _call_context_overlay_method(method: StringName, args: Array = []) -> bool:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return false
	if not _context_overlay.has_method(method):
		return false
	_context_overlay.callv(method, args)
	return true

func _emit_guided_action_dismissed() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if not _panel.has_signal("guided_action_dismissed"):
		return

	var aid := ""
	if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("get_mode"):
		aid = str(_context_overlay.call("get_mode")).strip_edges()
	if aid.is_empty() and _panel.has_method("get_guided_action_id"):
		aid = str(_panel.call("get_guided_action_id")).strip_edges()
	if aid.is_empty():
		return

	_panel.emit_signal("guided_action_dismissed", aid)

func _on_cancel_context_pressed() -> void:
	_emit_guided_action_dismissed()
	if not _call_context_overlay_method("request_cancel"):
		clear_context_overlay()
		return
	if _should_clear_context_on_cancel():
		clear_context_overlay()

func _on_skip_context_pressed() -> void:
	if _skip_context_button != null and is_instance_valid(_skip_context_button) and _skip_context_button.disabled:
		return
	if _panel == null or not is_instance_valid(_panel):
		return
	if not _panel.has_signal("action_requested"):
		return
	_panel.emit_signal("action_requested", "skip_sub_phase", {})

func _on_confirm_context_pressed() -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		clear_context_overlay()
		return
	if _confirm_context_button != null and _confirm_context_button.disabled:
		return
	_call_context_overlay_method("request_confirm")
	if _confirm_context_button != null:
		_confirm_context_button.disabled = true

func _on_restaurant_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(_restaurant_option):
		return
	var rid := str(_restaurant_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_restaurant", [rid])

func _on_employee_option_selected(employee_type: String) -> void:
	if _context_syncing:
		return
	var emp_id := str(employee_type).strip_edges()
	if _context_overlay != null and is_instance_valid(_context_overlay) and _context_overlay.has_method("set_selected_employee_key"):
		var key := ""
		if _employee_option != null and is_instance_valid(_employee_option) and _employee_option.has_method("get_selected_key"):
			key = str(_employee_option.call("get_selected_key")).strip_edges()
		if not key.is_empty():
			_call_context_overlay_method("set_selected_employee_key", [key])
			return
	_call_context_overlay_method("set_selected_employee", [emp_id])

func _get_employee_def_for_card(employee_type: String) -> Dictionary:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return {"id": emp_id, "name": emp_id}
	if not EmployeeRegistryClass.is_loaded():
		return {"id": emp_id, "name": emp_id}
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val != null and def_val.has_method("to_dict"):
		return def_val.to_dict()
	return {"id": emp_id, "name": emp_id}

func _on_rotate_left_pressed() -> void:
	if _context_syncing:
		return
	_rotate_selected_rotation(-90)

func _on_rotate_right_pressed() -> void:
	if _context_syncing:
		return
	_rotate_selected_rotation(90)

func _rotate_selected_rotation(delta_degrees: int) -> void:
	if _context_overlay == null or not is_instance_valid(_context_overlay):
		return
	if not _context_overlay.has_method("set_selected_rotation"):
		return
	var rot := 0
	if _context_overlay.has_method("get_selected_rotation"):
		rot = int(_context_overlay.call("get_selected_rotation"))
	_call_context_overlay_method("set_selected_rotation", [rot + int(delta_degrees)])

func _on_house_number_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(_house_number_option):
		return
	var n := int(_house_number_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_house_number", [n])

func _on_direction_option_selected(index: int) -> void:
	if _context_syncing:
		return
	if not is_instance_valid(_direction_option):
		return
	var d := str(_direction_option.get_item_metadata(index))
	_call_context_overlay_method("set_selected_direction", [d])
