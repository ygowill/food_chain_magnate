# 公司结构重组遮罩面板
# - 复用 HandArea + CompanyStructure 组件（由外部临时 reparent 进来）
class_name RestructuringModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

signal player_selected(player_id: int)

@onready var hand_host: Control = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/HandHost
@onready var company_host: Control = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split/CompanyHost
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Hint
@onready var player_buttons_host: HBoxContainer = $Panel/MarginContainer/VBoxContainer/PlayerRow/PlayerButtons
@onready var split: HSplitContainer = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/Split

const RESTRUCTURING_HAND_TARGET_WIDTH := 440.0 # fits 3 compact cards/row (issue_tracker #45)
const _MAX_SPLIT_ADJUST_ATTEMPTS := 6

var _hand_area: Node = null
var _company_structure: Node = null
var _hand_area_prev_display_mode: String = "default"
var _player_button_group: ButtonGroup = null
var _player_buttons: Array[Button] = []
var _split_adjust_attempts: int = 0
var _split_adjusted: bool = false

func _ready() -> void:
	allow_cancel = false
	super._ready()
	set_title_text("公司结构重组")
	set_confirm_text("确认重组")
	set_cancel_text("关闭")
	set_confirm_enabled(true)

func open(_covered_rect: Rect2) -> void:
	# Restructuring needs a full-screen modal (covers left info panel as well).
	var size_guess := Vector2.ZERO
	if is_inside_tree():
		size_guess = get_viewport_rect().size
	if size_guess.x <= 1.0 or size_guess.y <= 1.0:
		# Fallback for headless/tests before layout: use a reasonable size.
		size_guess = Vector2(1280, 720)
	var rect := Rect2(Vector2.ZERO, size_guess)
	super.open(rect)
	_queue_apply_split_target_width()

func _center_panel() -> void:
	# Restructuring modal is not a centered popup; panel fills the whole covered area.
	if not is_instance_valid(panel):
		return
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

func close() -> void:
	_restore_hand_area_display_mode()
	super.close()

func set_status_text(text: String) -> void:
	if not is_instance_valid(status_label):
		return
	status_label.text = text

func set_player_switcher(player_count: int, view_player_id: int, submitted: Dictionary) -> void:
	if not is_instance_valid(player_buttons_host):
		return
	if player_count <= 0:
		player_buttons_host.visible = false
		return
	player_buttons_host.visible = true

	var is_online := false
	var local_pid := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_pid = int(NetContext.local_player_id)

	var need_rebuild := (_player_buttons.size() != player_count)
	if need_rebuild:
		for c in player_buttons_host.get_children():
			if is_instance_valid(c):
				c.queue_free()
		_player_buttons.clear()
		_player_button_group = ButtonGroup.new()

		for pid in range(player_count):
			var btn := Button.new()
			btn.toggle_mode = true
			btn.button_group = _player_button_group
			btn.custom_minimum_size = Vector2(140, 32)
			btn.pressed.connect(_on_player_button_pressed.bind(pid))
			player_buttons_host.add_child(btn)
			_player_buttons.append(btn)

	for pid2 in range(player_count):
		var btn2_val = _player_buttons[pid2]
		if not is_instance_valid(btn2_val):
			continue
		var btn2: Button = btn2_val

		var name := Globals.get_player_name(pid2) if Globals != null else ("玩家%d" % (pid2 + 1))

		var submitted_flag = submitted.get(pid2, null)
		if submitted_flag == null and submitted.has(str(pid2)):
			submitted_flag = submitted.get(str(pid2), null)
		var is_submitted := bool(submitted_flag)

		btn2.text = "%s%s" % [name, "（已提交）" if is_submitted else ""]
		btn2.set_pressed_no_signal(pid2 == view_player_id)
		# 隐私规则：
		# - Online：禁止查看其他玩家的重组结构（仅显示提交状态）
		# - Hotseat：已提交玩家不可再查看
		var selectable := true
		if is_online:
			selectable = (local_pid >= 0 and pid2 == local_pid)
		else:
			selectable = not is_submitted
		btn2.disabled = not selectable

func _on_player_button_pressed(player_id: int) -> void:
	player_selected.emit(player_id)

func set_content_visible(visible: bool) -> void:
	if is_instance_valid(split):
		split.visible = bool(visible)

func _queue_apply_split_target_width() -> void:
	_split_adjust_attempts = 0
	_split_adjusted = false
	call_deferred("_apply_split_target_width")

func _apply_split_target_width() -> void:
	if _split_adjusted:
		return
	if not is_instance_valid(split) or not is_instance_valid(hand_host):
		return

	_split_adjust_attempts += 1
	if _split_adjust_attempts > _MAX_SPLIT_ADJUST_ATTEMPTS:
		_split_adjusted = true
		return

	# Wait until layout has produced a non-zero size.
	if split.size.x <= 1.0 or hand_host.size.x <= 1.0:
		call_deferred("_apply_split_target_width")
		return

	# split_offset semantics can be non-obvious; adjust using measured left width so it works across viewports.
	var delta := RESTRUCTURING_HAND_TARGET_WIDTH - float(hand_host.size.x)
	if absf(delta) >= 1.0:
		split.split_offset = int(round(float(split.split_offset) + delta))
		split.clamp_split_offset()
		call_deferred("_apply_split_target_width")
		return

	_split_adjusted = true

func attach_hand_area(panel: Node) -> void:
	_hand_area = panel
	_apply_hand_area_display_mode()
	_attach_panel_to_host(panel, hand_host)

func attach_company_structure(panel: Node) -> void:
	_company_structure = panel
	_attach_panel_to_host(panel, company_host)

func detach_to_parent(target_parent: Node) -> void:
	if _hand_area != null and is_instance_valid(_hand_area):
		_restore_hand_area_display_mode()
		_detach_panel_to_parent(_hand_area, target_parent)
	if _company_structure != null and is_instance_valid(_company_structure):
		_detach_panel_to_parent(_company_structure, target_parent)

func _apply_hand_area_display_mode() -> void:
	if not is_instance_valid(_hand_area):
		return
	if _hand_area.has_method("get_display_mode"):
		_hand_area_prev_display_mode = str(_hand_area.call("get_display_mode")).strip_edges()
		if _hand_area_prev_display_mode.is_empty():
			_hand_area_prev_display_mode = "default"
	if _hand_area.has_method("set_display_mode"):
		_hand_area.call("set_display_mode", "restructuring")

func _restore_hand_area_display_mode() -> void:
	if not is_instance_valid(_hand_area):
		return
	if not _hand_area.has_method("set_display_mode"):
		return
	var m := str(_hand_area_prev_display_mode).strip_edges()
	if m.is_empty():
		m = "default"
	_hand_area.call("set_display_mode", m)

func _attach_panel_to_host(panel: Node, host: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if host == null or not is_instance_valid(host):
		return
	if not (panel is Control):
		return

	var c: Control = panel
	if c.get_parent() != host:
		var old_parent := c.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(c)
		host.add_child(c)

	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

func _detach_panel_to_parent(panel: Node, target_parent: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if target_parent == null or not is_instance_valid(target_parent):
		return

	var old_parent := panel.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(panel)
	target_parent.add_child(panel)

	if panel is Control:
		var c: Control = panel
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.offset_left = 0
		c.offset_top = 0
		c.offset_right = 0
		c.offset_bottom = 0

func _on_confirm_pressed() -> void:
	completed.emit({"action": "submit_restructuring"})
