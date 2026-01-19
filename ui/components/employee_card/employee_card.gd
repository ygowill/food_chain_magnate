# 员工卡牌组件
# 显示单张员工卡的信息
class_name EmployeeCard
extends PanelContainer

const EmployeeRoleColorsClass = preload("res://ui/visual/employee_role_colors.gd")

signal card_clicked(employee_id: String)
signal card_drag_started(employee_id: String)
signal card_drag_ended(employee_id: String, drop_position: Vector2)

enum CardVariant {
	COMPACT,
	FULL,
}

@export var employee_id: String = ""
@export var show_salary_indicator: bool = true
@export var draggable: bool = true
@export var variant: CardVariant = CardVariant.COMPACT

var display_scale: float = 1.0

var _employee_def: Dictionary = {}
var _selected: bool = false
var _busy: bool = false
var _dragging: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO

# UI 子节点
var _role_color_rect: ColorRect
var _name_label: Label
var _salary_indicator: Label
var _description_label: Label
var _level_label: Label
var _range_label: Label
var _salary_label: Label

var _portrait_texture: TextureRect
var _portrait_placeholder_rect: ColorRect

var _entry_icon_rect: TextureRect
var _range_icon_rect: TextureRect
var _salary_icon_rect: TextureRect

const COMPACT_SIZE := Vector2(130, 90)
const FULL_SIZE := Vector2(180, 252)

static var _icon_texture_cache: Dictionary = {} # path -> Texture2D|nil

static func _load_icon_texture_cached(path: String) -> Texture2D:
	var p := str(path).strip_edges()
	if p.is_empty():
		return null
	if _icon_texture_cache.has(p):
		return _icon_texture_cache[p]

	var tex: Texture2D = null
	if ResourceLoader.exists(p):
		var res = load(p)
		if res is Texture2D:
			tex = res

	_icon_texture_cache[p] = tex
	return tex

func _get_entry_icon_texture() -> Texture2D:
	return _load_icon_texture_cached("res://assets/images/Arrow in Black Circle.svg")

func _get_one_x_icon_texture() -> Texture2D:
	return _load_icon_texture_cached("res://assets/images/1x in Black Circle.svg")

func _get_salary_icon_texture() -> Texture2D:
	return _load_icon_texture_cached("res://assets/images/Bank Notes for Salary in Black Circle.svg")

func _get_range_icon_info(range_type: String, range_value: int, employee_role: String) -> Dictionary:
	var t := str(range_type).strip_edges().to_lower()
	if t.is_empty() or t == "none" or t == "null":
		return {"texture": null, "icon_has_value": false}

	if t == "road":
		var tex := _load_icon_texture_cached("res://assets/images/Road - %d.svg" % range_value)
		# Road icons already contain the distance number in the artwork.
		return {"texture": tex, "icon_has_value": tex != null}

	if t == "air":
		if range_value < 0:
			var inf := _load_icon_texture_cached("res://assets/images/Zeppelin with Infinity Symbol.svg")
			if inf != null:
				return {"texture": inf, "icon_has_value": true}
			return {"texture": _load_icon_texture_cached("res://assets/images/Zeppelin.svg"), "icon_has_value": false}

		var numbered := _load_icon_texture_cached("res://assets/images/Zeppelin with %d.svg" % range_value)
		if numbered != null:
			return {"texture": numbered, "icon_has_value": true}
		return {"texture": _load_icon_texture_cached("res://assets/images/Zeppelin.svg"), "icon_has_value": false}

	return {"texture": null, "icon_has_value": false}

func set_display_scale(scale: float) -> void:
	var s := clampf(float(scale), 0.5, 2.0)
	if is_equal_approx(s, display_scale):
		return
	display_scale = s
	if is_inside_tree():
		_build_ui()

func _scaled(base: float, min_value: int = 1) -> int:
	return maxi(min_value, int(round(base * clampf(display_scale, 0.5, 2.0))))

func _ready() -> void:
	_build_ui()
	gui_input.connect(_on_gui_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _build_ui() -> void:
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()

	_role_color_rect = null
	_name_label = null
	_salary_indicator = null
	_description_label = null
	_level_label = null
	_range_label = null
	_salary_label = null
	_portrait_texture = null
	_portrait_placeholder_rect = null
	_entry_icon_rect = null
	_range_icon_rect = null
	_salary_icon_rect = null

	var s := clampf(display_scale, 0.5, 2.0)
	var base_size := FULL_SIZE if variant == CardVariant.FULL else COMPACT_SIZE
	custom_minimum_size = Vector2(round(base_size.x * s), round(base_size.y * s))

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	# Ensure the content area expands to fill the card, so bottom icons stay at the bottom.
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	_build_header_bar(root)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad := _scaled(12.0 if variant == CardVariant.FULL else 6.0, 1)
	var top_pad := _scaled(8.0 if variant == CardVariant.FULL else 4.0, 1)
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_top", top_pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	root.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _scaled(6.0 if variant == CardVariant.FULL else 2.0, 1))
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	if variant == CardVariant.FULL:
		_build_full_layout(vbox)
	else:
		_build_compact_layout(vbox)

	_update_style()
	# setup() 可能在节点入树前被调用（例如升级路线树的节点构建），此时 _ready 尚未执行，
	# _update_display() 会因 _name_label 为空而提前 return。这里在 UI 组件创建完后补一次刷新。
	if not _employee_def.is_empty():
		_update_display()
	queue_redraw()

func _build_header_bar(parent: VBoxContainer) -> void:
	# 顶部：类别色整行底色 + 名称（填满宽度并紧贴卡片上边缘）
	_role_color_rect = ColorRect.new()
	_role_color_rect.custom_minimum_size = Vector2(0, _scaled(24.0 if variant == CardVariant.FULL else 20.0, 1))
	_role_color_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_role_color_rect)

	# Use a container to guarantee horizontal/vertical centering regardless of Control anchor behavior.
	var header_center := CenterContainer.new()
	header_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	header_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_color_rect.add_child(header_center)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _scaled(16.0 if variant == CardVariant.FULL else 14.0, 1))
	_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_center.add_child(_name_label)

func _build_compact_layout(vbox: VBoxContainer) -> void:
	# 底部：简短描述
	_description_label = Label.new()
	_description_label.add_theme_font_size_override("font_size", _scaled(11.0, 1))
	_description_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_description_label)

	# 底部图标行：Entry/路程/工资
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", _scaled(6.0, 0))
	vbox.add_child(bottom)

	_entry_icon_rect = TextureRect.new()
	_entry_icon_rect.custom_minimum_size = Vector2(_scaled(16.0, 1), _scaled(16.0, 1))
	_entry_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_entry_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_entry_icon_rect.size_flags_horizontal = 0
	_entry_icon_rect.size_flags_vertical = 0
	_entry_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_entry_icon_rect)

	var range_box := HBoxContainer.new()
	range_box.add_theme_constant_override("separation", _scaled(4.0, 0))
	range_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(range_box)

	_range_icon_rect = TextureRect.new()
	_range_icon_rect.custom_minimum_size = Vector2(_scaled(16.0, 1), _scaled(16.0, 1))
	_range_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_range_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_range_icon_rect.size_flags_horizontal = 0
	_range_icon_rect.size_flags_vertical = 0
	_range_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	range_box.add_child(_range_icon_rect)

	_range_label = Label.new()
	_range_label.add_theme_font_size_override("font_size", _scaled(11.0, 1))
	_range_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_box.add_child(_range_label)

	var salary_box := HBoxContainer.new()
	salary_box.add_theme_constant_override("separation", _scaled(4.0, 0))
	salary_box.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(salary_box)

	_salary_icon_rect = TextureRect.new()
	_salary_icon_rect.custom_minimum_size = Vector2(_scaled(16.0, 1), _scaled(16.0, 1))
	_salary_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_salary_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_salary_icon_rect.size_flags_horizontal = 0
	_salary_icon_rect.size_flags_vertical = 0
	_salary_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	salary_box.add_child(_salary_icon_rect)

	_salary_label = Label.new()
	_salary_label.add_theme_font_size_override("font_size", _scaled(11.0, 1))
	_salary_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	salary_box.add_child(_salary_label)

func _build_full_layout(vbox: VBoxContainer) -> void:
	var portrait_box := PanelContainer.new()
	portrait_box.custom_minimum_size = Vector2(_scaled(120.0, 1), _scaled(120.0, 1))
	portrait_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(portrait_box)

	var portrait_root := Control.new()
	portrait_root.custom_minimum_size = Vector2(_scaled(120.0, 1), _scaled(120.0, 1))
	portrait_box.add_child(portrait_root)

	_portrait_placeholder_rect = ColorRect.new()
	_portrait_placeholder_rect.anchors_preset = Control.PRESET_FULL_RECT
	_portrait_placeholder_rect.color = Color(0.2, 0.2, 0.22, 1)
	portrait_root.add_child(_portrait_placeholder_rect)

	_portrait_texture = TextureRect.new()
	_portrait_texture.anchors_preset = Control.PRESET_FULL_RECT
	_portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_root.add_child(_portrait_texture)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", _scaled(12.0, 1))
	_level_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_level_label)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	_description_label = Label.new()
	_description_label.add_theme_font_size_override("font_size", _scaled(12.0, 1))
	_description_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_description_label)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", _scaled(8.0, 0))
	vbox.add_child(bottom)

	_entry_icon_rect = TextureRect.new()
	_entry_icon_rect.custom_minimum_size = Vector2(_scaled(18.0, 1), _scaled(18.0, 1))
	_entry_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_entry_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_entry_icon_rect.size_flags_horizontal = 0
	_entry_icon_rect.size_flags_vertical = 0
	_entry_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_entry_icon_rect)

	var range_box := HBoxContainer.new()
	range_box.add_theme_constant_override("separation", _scaled(6.0, 0))
	range_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(range_box)

	_range_icon_rect = TextureRect.new()
	_range_icon_rect.custom_minimum_size = Vector2(_scaled(18.0, 1), _scaled(18.0, 1))
	_range_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_range_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_range_icon_rect.size_flags_horizontal = 0
	_range_icon_rect.size_flags_vertical = 0
	_range_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	range_box.add_child(_range_icon_rect)

	_range_label = Label.new()
	_range_label.add_theme_font_size_override("font_size", _scaled(12.0, 1))
	_range_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_box.add_child(_range_label)

	var salary_box := HBoxContainer.new()
	salary_box.add_theme_constant_override("separation", _scaled(6.0, 0))
	salary_box.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(salary_box)

	_salary_icon_rect = TextureRect.new()
	_salary_icon_rect.custom_minimum_size = Vector2(_scaled(18.0, 1), _scaled(18.0, 1))
	_salary_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_salary_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_salary_icon_rect.size_flags_horizontal = 0
	_salary_icon_rect.size_flags_vertical = 0
	_salary_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	salary_box.add_child(_salary_icon_rect)

	_salary_label = Label.new()
	_salary_label.add_theme_font_size_override("font_size", _scaled(12.0, 1))
	_salary_label.add_theme_color_override("font_color", Color(0.18, 0.18, 0.2, 1))
	_salary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	salary_box.add_child(_salary_label)

func setup(employee_def: Dictionary) -> void:
	_employee_def = employee_def
	employee_id = str(employee_def.get("id", ""))
	_update_display()

func set_selected(selected: bool) -> void:
	_selected = selected
	_update_style()

func set_busy(busy: bool) -> void:
	_busy = busy
	_update_style()

func _update_display() -> void:
	if _name_label == null:
		return

	var name: String = str(_employee_def.get("name", employee_id))
	_name_label.text = name

	var role: String = str(_employee_def.get("role", "special"))
	var color: Color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))
	if _role_color_rect != null:
		_role_color_rect.color = color

	# 工资
	var salary: bool = bool(_employee_def.get("salary", true))
	if _salary_indicator != null:
		_salary_indicator.text = "$" if (salary and show_salary_indicator) else ""
		_salary_indicator.visible = salary and show_salary_indicator

	var show_salary := salary and show_salary_indicator
	var salary_tex: Texture2D = _get_salary_icon_texture() if show_salary else null
	if _salary_icon_rect != null:
		_salary_icon_rect.texture = salary_tex
		_salary_icon_rect.visible = show_salary and salary_tex != null
	if _salary_label != null:
		# 图标加载失败时回退为文本提示，避免 UI 空白。
		_salary_label.text = "$" if (show_salary and salary_tex == null) else ""
		_salary_label.visible = not _salary_label.text.is_empty()

	# 等级/Entry/1x 图标
	var train_to: Array = Array(_employee_def.get("train_to", []))
	var is_entry: bool = false
	var tags_val = _employee_def.get("tags", null)
	if tags_val is Array and Array(tags_val).has("entry_level"):
		is_entry = true

	var pool_type := ""
	var pool_val = _employee_def.get("pool", null)
	if pool_val is Dictionary:
		var t_val = Dictionary(pool_val).get("type", null)
		if t_val != null:
			pool_type = str(t_val).strip_edges()
	var is_one_x := pool_type == "one_x"

	var entry_tex: Texture2D = null
	if is_one_x:
		entry_tex = _get_one_x_icon_texture()
	elif is_entry:
		entry_tex = _get_entry_icon_texture()

	if _entry_icon_rect != null:
		_entry_icon_rect.texture = entry_tex
		_entry_icon_rect.visible = entry_tex != null

	if _level_label != null:
		if is_entry:
			_level_label.text = "Lv.1 (入门级)"
		elif train_to.is_empty():
			_level_label.text = "Lv.3 (高级)"
		else:
			_level_label.text = "Lv.2 (中级)"

	# 描述：管理岗若无描述，则展示 manager_slots
	if _description_label != null:
		var desc: String = str(_employee_def.get("description", ""))
		if desc.strip_edges().is_empty() and role == "manager":
			var ms_val = _employee_def.get("manager_slots", null)
			if ms_val is int or ms_val is float:
				desc = "管理名额: %d" % int(ms_val)
		var max_len := 120 if variant == CardVariant.FULL else 40
		if desc.length() > max_len:
			desc = desc.substr(0, max_len) + "..."
		_description_label.text = desc

	# 距离/范围（暂用 range.value；未来可用图标替代）
	if _range_label != null:
		var range_val = _employee_def.get("range", null)
		var range_type := ""
		var range_value := 0
		if range_val is Dictionary:
			var type_val = Dictionary(range_val).get("type", "")
			if type_val == null:
				range_type = ""
			else:
				range_type = str(type_val).strip_edges()
			range_value = int(Dictionary(range_val).get("value", 0))

		var rt := range_type.to_lower()
		if rt == "null":
			rt = ""
		var show_range := (rt == "road" or rt == "air")
		# 跑腿伙计采购不走路线/距离限制，避免在卡片上误导显示。
		if employee_id == "errand_boy":
			show_range = false

		var icon_info: Dictionary = _get_range_icon_info(rt, range_value, role) if show_range else {"texture": null, "icon_has_value": false}
		var range_tex: Texture2D = icon_info.get("texture", null)
		var icon_has_value: bool = bool(icon_info.get("icon_has_value", false))

		if _range_icon_rect != null:
			_range_icon_rect.visible = show_range and range_tex != null
			_range_icon_rect.texture = range_tex

		if not show_range:
			_range_label.text = ""
		else:
			if rt == "road":
				# Road SVG already has the number; show fallback text only when icon is missing.
				_range_label.text = "" if range_tex != null else "R%d" % range_value
			elif rt == "air":
				var label := "∞" if range_value < 0 else str(range_value)
				# Zeppelin "with N/∞" artwork already contains the value.
				_range_label.text = "" if icon_has_value else label
			else:
				_range_label.text = "%s%d" % [range_type, range_value]
		_range_label.visible = not _range_label.text.is_empty()

	# 头像占位（资源待补齐：使用空白色块）
	if _portrait_placeholder_rect != null:
		var ph := Color(color.r, color.g, color.b, 0.22)
		ph.a = 1.0
		_portrait_placeholder_rect.color = ph

	if _portrait_texture != null:
		_portrait_texture.visible = _portrait_texture.texture != null
	if _portrait_placeholder_rect != null:
		_portrait_placeholder_rect.visible = (_portrait_texture == null) or (_portrait_texture.texture == null)

	_update_style()
	queue_redraw()

func _update_style() -> void:
	var style := StyleBoxFlat.new()

	var role: String = str(_employee_def.get("role", "special"))
	var base_color: Color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))

	var bg := Color("#f4edd1") # align with restaurant background
	bg.a = 1.0

	if _busy:
		style.bg_color = bg
		style.border_color = Color(0.55, 0.55, 0.6, 0.9)
		style.set_border_width_all(1)
		style.shadow_color = Color(0, 0, 0, 0.25)
		style.shadow_size = 6
		modulate = Color(0.8, 0.8, 0.8, 0.85)
	elif _selected:
		style.bg_color = bg
		style.border_color = Color(0.5, 0.8, 1.0, 0.95)
		style.set_border_width_all(2)
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 8
		modulate = Color(1, 1, 1, 1)
	else:
		style.bg_color = bg
		style.border_color = Color(base_color.r, base_color.g, base_color.b, 0.65)
		style.set_border_width_all(1 if variant == CardVariant.COMPACT else 2)
		style.shadow_color = Color(0, 0, 0, 0.25)
		style.shadow_size = 6 if variant == CardVariant.COMPACT else 10
		modulate = Color(1, 1, 1, 1)

	style.set_corner_radius_all(8 if variant == CardVariant.FULL else 4)
	add_theme_stylebox_override("panel", style)

func _draw() -> void:
	if _employee_def.is_empty():
		return
	var tags_val = _employee_def.get("tags", null)
	if not (tags_val is Array) or not Array(tags_val).has("entry_level"):
		return
	# 若已加载 entry_level 图标，则不再绘制左上角三角标记（避免重复）。
	if _entry_icon_rect != null and _entry_icon_rect.texture != null:
		return

	var role: String = str(_employee_def.get("role", "special"))
	var base_color: Color = Color(EmployeeRoleColorsClass.role_to_color_hex(role))

	var tri := 24.0 if variant == CardVariant.FULL else 18.0
	var points := PackedVector2Array([Vector2(0, 0), Vector2(tri, 0), Vector2(0, tri)])
	draw_colored_polygon(points, base_color)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_start_pos = e.position
				_dragging = false
				card_clicked.emit(employee_id)
			else:
				if _dragging and draggable:
					_dragging = false
					card_drag_ended.emit(employee_id, get_global_mouse_position())

	if event is InputEventMouseMotion and draggable:
		var e2: InputEventMouseMotion = event
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var distance := e2.position.distance_to(_drag_start_pos)
			if distance > 5.0 and not _dragging:
				_dragging = true
				card_drag_started.emit(employee_id)

func _get_tooltip_manager():
	if get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group("help_tooltip_manager"):
		if n != null and is_instance_valid(n) and n.has_method("request_tooltip"):
			return n
	return null

func _build_employee_tooltip_content() -> String:
	var lines: Array[String] = []
	var desc := str(_employee_def.get("description", "")).strip_edges()
	if not desc.is_empty():
		lines.append(desc)

	var role := str(_employee_def.get("role", "")).strip_edges()
	if not role.is_empty():
		lines.append("职责: %s" % role)

	var salary := bool(_employee_def.get("salary", true))
	lines.append("需要薪水: %s" % ("是" if salary else "否"))

	var manager_slots := int(_employee_def.get("manager_slots", 0))
	if manager_slots > 0:
		lines.append("管理槽位: %d" % manager_slots)

	var recruit_cap := int(_employee_def.get("recruit_capacity", 0))
	if recruit_cap > 0:
		lines.append("招聘能力: %d" % recruit_cap)

	var train_cap := int(_employee_def.get("train_capacity", 0))
	if train_cap > 0:
		lines.append("培训能力: %d" % train_cap)

	var produces_amount := int(_employee_def.get("produces_amount", 0))
	var produces_food_type := str(_employee_def.get("produces_food_type", "")).strip_edges()
	if produces_amount > 0 and not produces_food_type.is_empty():
		lines.append("生产: %s x%d" % [produces_food_type, produces_amount])

	return "\n".join(lines)

func _on_mouse_entered() -> void:
	if employee_id.is_empty():
		return
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return

	var key := "employee_%s" % employee_id
	if mgr.has_method("add_help_entry"):
		# 若已存在条目（例如内置 employee_* 文案），则不覆盖
		if not (mgr.HELP_DATABASE is Dictionary and mgr.HELP_DATABASE.has(key)):
			var title := str(_employee_def.get("name", employee_id)).strip_edges()
			if title.is_empty():
				title = employee_id
			mgr.add_help_entry(key, title, _build_employee_tooltip_content())

	var pos: Vector2 = get_global_rect().position + (size / 2.0)
	mgr.request_tooltip(key, pos)

func _on_mouse_exited() -> void:
	var mgr = _get_tooltip_manager()
	if mgr == null:
		return
	if mgr.has_method("hide_tooltip"):
		mgr.hide_tooltip()
