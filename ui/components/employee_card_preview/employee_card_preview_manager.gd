# 员工卡片预览管理器（统一悬停/点击预览）
# - 用于在任意 UI 文本/列表中，通过 employee_id 显示一张 COMPACT EmployeeCard（类似升级路线卡片）。
# - 采用延迟显示/延迟隐藏以避免“扫过闪烁”。
class_name EmployeeCardPreviewManager
extends CanvasLayer

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const MilestonePanelClass = preload("res://ui/components/milestone_panel/milestone_panel.gd")
const MilestonePreviewCardClass = preload("res://ui/components/milestone_panel/milestone_preview_card.gd")

@onready var panel: PanelContainer = $PreviewPanel
@onready var card_host: Control = $PreviewPanel/MarginContainer/CardHost
@onready var margin: MarginContainer = $PreviewPanel/MarginContainer

enum PreviewKind {
	EMPLOYEE,
	MILESTONE,
}

var _show_delay: float = 0.10
var _hide_delay: float = 0.02

var _show_timer: Timer = null
var _hide_timer: Timer = null

var _current_id: String = ""
var _current_kind: int = PreviewKind.EMPLOYEE
var _pending_position: Vector2 = Vector2.ZERO
var _is_visible: bool = false

var _card: EmployeeCard = null
var _milestone_formatter: MilestonePanel = null

func _ready() -> void:
	add_to_group("employee_card_preview_manager")

	_show_timer = Timer.new()
	_show_timer.one_shot = true
	_show_timer.timeout.connect(_on_show_timer_timeout)
	add_child(_show_timer)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(_on_hide_timer_timeout)
	add_child(_hide_timer)

	if panel != null:
		panel.visible = false
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_preview_panel_style()

func _apply_preview_panel_style() -> void:
	if panel == null or not is_instance_valid(panel):
		return

	# 预览面板只承载 EmployeeCard，本身不绘制“外层对话框”的底色/边框/阴影，
	# 避免出现一圈黑边把卡片包住（影响观感）。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(0)
	sb.shadow_size = 0
	panel.add_theme_stylebox_override("panel", sb)

func request_preview(employee_id: String, position: Vector2) -> void:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		hide_preview()
		return
	_request(PreviewKind.EMPLOYEE, eid, position)

func show_immediate(employee_id: String, position: Vector2) -> void:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		hide_preview()
		return
	_show_immediate(PreviewKind.EMPLOYEE, eid, position)

func request_milestone_preview(milestone_id: String, position: Vector2) -> void:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		hide_preview()
		return
	_request(PreviewKind.MILESTONE, mid, position)

func show_milestone_immediate(milestone_id: String, position: Vector2) -> void:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		hide_preview()
		return
	_show_immediate(PreviewKind.MILESTONE, mid, position)

func _request(kind: int, id: String, position: Vector2) -> void:
	_hide_timer.stop()

	_pending_position = position
	_update_position(_pending_position)

	if _is_visible and id == _current_id and int(kind) == int(_current_kind):
		return

	_current_kind = int(kind)
	_current_id = id
	_show_timer.stop()
	_show_timer.start(_show_delay)

func _show_immediate(kind: int, id: String, position: Vector2) -> void:
	_current_kind = int(kind)
	_current_id = id
	_pending_position = position
	_show_timer.stop()
	_hide_timer.stop()
	_show_preview(_current_kind, _current_id, position)

func hide_preview() -> void:
	_current_id = ""
	_show_timer.stop()

	if not _is_visible:
		return
	_hide_timer.stop()
	_hide_timer.start(_hide_delay)

func set_show_delay(seconds: float) -> void:
	_show_delay = maxf(0.0, float(seconds))

func set_hide_delay(seconds: float) -> void:
	_hide_delay = maxf(0.0, float(seconds))

func _on_show_timer_timeout() -> void:
	if _current_id.is_empty():
		return
	_show_preview(_current_kind, _current_id, _pending_position)

func _on_hide_timer_timeout() -> void:
	if panel != null:
		panel.visible = false
	_is_visible = false

func _show_preview(kind: int, id: String, position: Vector2) -> void:
	if panel == null or not is_instance_valid(panel):
		return

	_rebuild_card(kind, id)
	_update_position(position)
	panel.visible = true
	_is_visible = true

func _rebuild_card(kind: int, id: String) -> void:
	if card_host == null or not is_instance_valid(card_host):
		return

	# 清理旧卡片
	for ch in card_host.get_children():
		if is_instance_valid(ch):
			ch.queue_free()
	_card = null

	var key := str(id).strip_edges()
	if key.is_empty():
		return

	if int(kind) == PreviewKind.MILESTONE:
		_rebuild_milestone_card(key)
	else:
		_rebuild_employee_card(key)

	_sync_panel_size_to_card()

func _rebuild_employee_card(employee_id: String) -> void:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		return

	var def_dict: Dictionary = {}
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(eid)
		if def_val is EmployeeDefClass:
			var def: EmployeeDef = def_val
			def_dict = def.to_dict()

	# 兜底：尽量显示 id，避免空白
	if def_dict.is_empty():
		def_dict = {"id": eid, "name": eid, "description": "", "role": "special"}

	var card := EmployeeCardClass.new()
	card.variant = EmployeeCardClass.CardVariant.COMPACT
	card.draggable = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.setup(def_dict)
	card_host.add_child(card)
	_card = card

func _rebuild_milestone_card(milestone_id: String) -> void:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return

	var def = null
	var name := mid
	if MilestoneRegistryClass.is_loaded():
		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val != null and def_val is MilestoneDefClass:
			def = def_val
			name = str((def as MilestoneDef).name).strip_edges()

	var effect_text := mid
	if def != null and def is MilestoneDefClass:
		if _milestone_formatter == null or not is_instance_valid(_milestone_formatter):
			_milestone_formatter = MilestonePanelClass.new()
			if _milestone_formatter.has_method("set_rules"):
				_milestone_formatter.call("set_rules", {})
		if _milestone_formatter != null and is_instance_valid(_milestone_formatter) and _milestone_formatter.has_method("_format_milestone_effect_text"):
			effect_text = str(_milestone_formatter.call("_format_milestone_effect_text", def))

	var card = MilestonePreviewCardClass.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card.has_method("setup"):
		card.call("setup", mid, def, effect_text)
	else:
		if card.has_method("set"):
			card.set("milestone_id", mid)
	card_host.add_child(card)

func _sync_panel_size_to_card() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if card_host == null or not is_instance_valid(card_host):
		return
	if margin == null or not is_instance_valid(margin):
		return

	var pad_x := float(margin.get_theme_constant("margin_left") + margin.get_theme_constant("margin_right"))
	var pad_y := float(margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom"))

	var content_size := Vector2.ZERO
	if card_host.get_child_count() > 0:
		var ch0 = card_host.get_child(0)
		if ch0 is Control:
			content_size = (ch0 as Control).custom_minimum_size
	if content_size == Vector2.ZERO:
		content_size = card_host.custom_minimum_size

	var min_size := content_size + Vector2(pad_x, pad_y)
	panel.custom_minimum_size = min_size
	panel.size = min_size

func _update_position(position: Vector2) -> void:
	if panel == null or not is_instance_valid(panel):
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := panel.size

	# 默认显示在鼠标右下方
	var target_pos := position + Vector2(15, 15)

	# 边界检测
	if target_pos.x + panel_size.x > viewport_size.x:
		target_pos.x = position.x - panel_size.x - 10
	if target_pos.y + panel_size.y > viewport_size.y:
		target_pos.y = position.y - panel_size.y - 10

	# 确保不超出左上边界
	target_pos.x = maxf(5, target_pos.x)
	target_pos.y = maxf(5, target_pos.y)

	panel.position = target_pos
