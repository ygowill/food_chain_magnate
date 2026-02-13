# 里程碑预览卡片（用于日志悬停/点击预览）
# - 轻量展示：名称 + 效果描述（复用 MilestonePanel 的文案格式化结果）。
class_name MilestonePreviewCard
extends PanelContainer

var milestone_id: String = ""
var milestone_def = null # MilestoneDef | null
var effect_text: String = ""

var _name_label: Label = null
var _desc_label: Label = null

func _ready() -> void:
	_build_ui()
	_update_display()

func setup(ms_id: String, def_val, effect: String) -> void:
	milestone_id = str(ms_id).strip_edges()
	milestone_def = def_val
	effect_text = str(effect).strip_edges()
	if is_inside_tree():
		_update_display()

func _build_ui() -> void:
	for ch in get_children():
		if is_instance_valid(ch):
			ch.queue_free()

	custom_minimum_size = Vector2(240, 120)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.86, 0.95)
	style.border_color = Color(0.73, 0.23, 0.18, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(14) if Globals != null else 14)
	vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(11) if Globals != null else 11)
	_desc_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	_desc_label.max_lines_visible = 5
	_desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_desc_label)

func _update_display() -> void:
	if _name_label != null:
		var name := milestone_id
		if milestone_def != null and milestone_def is MilestoneDef:
			name = str((milestone_def as MilestoneDef).name).strip_edges()
		if name.is_empty():
			name = milestone_id
		name = _strip_id_suffix(name)
		_name_label.text = name
		_name_label.tooltip_text = name

	if _desc_label != null:
		var text := effect_text
		if text.is_empty():
			text = milestone_id
		_desc_label.text = text

func _strip_id_suffix(raw_name: String) -> String:
	var s := str(raw_name).strip_edges()
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return s

	var suffixes: Array[String] = [
		" (" + mid + ")",
		"(" + mid + ")",
		" （" + mid + "）",
		"（" + mid + "）",
	]
	for suffix in suffixes:
		if s.ends_with(suffix):
			return s.substr(0, s.length() - suffix.length()).strip_edges()
	return s
