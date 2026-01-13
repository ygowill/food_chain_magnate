# 里程碑面板组件
# 显示里程碑池与玩家已获得（里程碑为自动授予，不支持手动领取）
class_name MilestonePanel
extends Control

signal cancelled()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var milestones_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/MilestonesContainer
@onready var button_row: Control = $MarginContainer/VBoxContainer/ButtonRow
@onready var close_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CloseButton

const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

@export var show_close_button: bool = true

var _milestone_pool: Array[String] = []
var _player_milestones: Array[String] = []
var _milestone_items: Dictionary = {}  # milestone_id -> MilestoneItem
var _embedded_in_right_panel: bool = false

func _ready() -> void:
	if close_btn != null:
		close_btn.pressed.connect(_on_close_pressed)
	_update_close_visibility()
	_rebuild_milestones()

func set_embedded_in_right_panel(embedded: bool) -> void:
	_embedded_in_right_panel = embedded
	_update_close_visibility()

func set_milestone_pool(pool: Array) -> void:
	_milestone_pool.clear()
	for v in pool:
		_milestone_pool.append(str(v))
	_maybe_rebuild_milestones()

func set_player_milestones(milestones: Array) -> void:
	_player_milestones.clear()
	for v in milestones:
		_player_milestones.append(str(v))
	_maybe_rebuild_milestones()

func refresh() -> void:
	_update_states()

func _update_close_visibility() -> void:
	if not is_instance_valid(button_row):
		return
	button_row.visible = show_close_button and not _embedded_in_right_panel

func _rebuild_milestones() -> void:
	if milestones_container == null:
		return
	for c in milestones_container.get_children():
		if is_instance_valid(c):
			c.queue_free()
	_milestone_items.clear()

	var ids := _get_desired_milestone_ids()
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无已获得的里程碑"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.9))
		milestones_container.add_child(empty)
		return

	for ms_id in ids:
		if ms_id.is_empty():
			continue

		var def = MilestoneRegistryClass.get_def(ms_id) if MilestoneRegistryClass.is_loaded() else null
		var item := MilestoneItem.new()
		item.milestone_id = ms_id
		item.milestone_def = def
		milestones_container.add_child(item)
		_milestone_items[ms_id] = item

	_update_states()

func _maybe_rebuild_milestones() -> void:
	if milestones_container == null:
		return

	var desired_ids := _get_desired_milestone_ids()
	var current_ids: Array[String] = []
	for k in _milestone_items.keys():
		current_ids.append(str(k))
	current_ids.sort()

	if desired_ids != current_ids:
		_rebuild_milestones()
	else:
		_update_states()

func _get_desired_milestone_ids() -> Array[String]:
	var set := {}
	for v in _player_milestones:
		var mid := str(v)
		if mid.is_empty():
			continue
		set[mid] = true

	var ids: Array[String] = []
	for k in set.keys():
		ids.append(str(k))

	ids.sort()
	return ids

func _update_states() -> void:
	var pool_counts := {}
	for v in _milestone_pool:
		var mid := str(v)
		if mid.is_empty():
			continue
		pool_counts[mid] = int(pool_counts.get(mid, 0)) + 1

	for ms_id in _milestone_items.keys():
		var item: MilestoneItem = _milestone_items[ms_id]
		if is_instance_valid(item):
			var is_claimed := _player_milestones.has(ms_id)
			var pool_count := int(pool_counts.get(ms_id, 0))
			item.set_state(is_claimed, pool_count)

func _on_close_pressed() -> void:
	cancelled.emit()


# === 内部类：里程碑项 ===
class MilestoneItem extends PanelContainer:
	var milestone_id: String = ""

	var milestone_def = null  # MilestoneDef | null

	var _is_claimed: bool = false
	var _pool_count: int = 0

	var _name_label: Label
	var _desc_label: Label
	var _status_label: Label

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(0, 70)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		add_child(hbox)

		# 左侧：信息
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_box.add_theme_constant_override("separation", 4)
		hbox.add_child(info_box)

		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 15)
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(_name_label)

		_desc_label = Label.new()
		_desc_label.add_theme_font_size_override("font_size", 12)
		_desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_box.add_child(_desc_label)

		# 右侧：状态/按钮
		var right_box := VBoxContainer.new()
		right_box.custom_minimum_size = Vector2(80, 0)
		right_box.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(right_box)

		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", 12)
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right_box.add_child(_status_label)

		update_display()
		_update_style()

	func update_display() -> void:
		if _name_label != null:
			var name := milestone_id
			if milestone_def != null and milestone_def is MilestoneDef:
				name = str((milestone_def as MilestoneDef).name)
			_name_label.text = name

		if _desc_label != null:
			if milestone_def != null and milestone_def is MilestoneDef:
				var def: MilestoneDef = milestone_def
				var parts: Array[String] = []
				parts.append("触发: %s" % def.trigger_event)
				if not def.trigger_filter.is_empty():
					parts.append("条件: %s" % str(def.trigger_filter))
				if def.effects.size() > 0:
					parts.append("效果: %s" % str(def.effects))
				_desc_label.text = " | ".join(parts)
			else:
				_desc_label.text = milestone_id

	func set_state(claimed: bool, pool_count: int) -> void:
		_is_claimed = claimed
		_pool_count = pool_count

		if _status_label != null:
			if claimed:
				_status_label.text = "已领取"
				_status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 1))
				_status_label.visible = true
			elif pool_count > 0:
				_status_label.text = "供应 ×%d" % pool_count
				_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
				_status_label.visible = true
			else:
				_status_label.text = ""
				_status_label.visible = false

		_update_style()

	func _update_style() -> void:
		var style := StyleBoxFlat.new()
		if _is_claimed:
			style.bg_color = Color(0.15, 0.2, 0.15, 0.8)
			style.border_color = Color(0.4, 0.6, 0.4, 0.5)
			style.set_border_width_all(1)
		elif _pool_count > 0:
			style.bg_color = Color(0.2, 0.2, 0.15, 0.9)
			style.border_color = Color(0.4, 0.4, 0.45, 0.6)
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(0.12, 0.12, 0.14, 0.7)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)

		# 供应池以外变暗
		if not _is_claimed and _pool_count <= 0:
			modulate = Color(0.6, 0.6, 0.6, 0.8)
		else:
			modulate = Color(1, 1, 1, 1)
