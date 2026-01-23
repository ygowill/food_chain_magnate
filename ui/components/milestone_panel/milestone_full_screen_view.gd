# 里程碑全屏视图（TopBar）
# - 每行 3 列，居中展示全部里程碑卡片
# - 展示已获得/未获得状态，并在卡片右下角显示获得者玩家餐厅 logo
# - ESC 关闭；关闭不改变左/右侧面板显示状态（仅隐藏自身）
class_name MilestoneFullScreenView
extends Control

signal close_requested()

@onready var grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/CenterContainer/Grid
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MapCanvasDrawerClass = preload("res://ui/scenes/game/map_canvas_drawer.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestonePanelClass = preload("res://ui/components/milestone_panel/milestone_panel.gd")

var _skin = null
var _skin_key: String = ""
var _rules: Dictionary = {}

var _cards: Dictionary = {} # milestone_id -> MilestoneCard
var _formatter: MilestonePanel = null

func _ready() -> void:
	set_process_unhandled_input(true)
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
	visible = false

func open_with_state(state: GameState) -> void:
	if state == null:
		return
	_rules = state.rules.duplicate(true) if (state.rules is Dictionary) else {}
	_ensure_skin_for_state(state)
	_ensure_formatter()
	_formatter.set_rules(_rules)
	_rebuild_from_state(state)
	visible = true

func request_close() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event != null and event.is_action_pressed("ui_cancel"):
		accept_event()
		request_close()

func _on_close_pressed() -> void:
	request_close()

func _ensure_formatter() -> void:
	if _formatter != null and is_instance_valid(_formatter):
		return
	# 复用 MilestonePanel 的效果文案格式化逻辑；该实例不入树，仅作为 formatter 使用。
	_formatter = MilestonePanelClass.new()

func _ensure_skin_for_state(state: GameState) -> void:
	var modules: Array[String] = []
	if state.modules is Array:
		modules = Array(state.modules, TYPE_STRING, "", null)
	var base_dir := Globals.modules_v2_base_dir if Globals != null else "res://modules"
	var key := "%s|%s" % [base_dir, ",".join(modules)]
	if _skin != null and key == _skin_key:
		return

	var build := MapSkinBuilderClass.build_for_modules(base_dir, modules, 40)
	if build.ok:
		_skin = build.value
		_skin_key = key
	else:
		_skin = null
		_skin_key = ""

func _rebuild_from_state(state: GameState) -> void:
	if grid == null:
		return
	for c in grid.get_children():
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

	var milestone_ids := _get_all_milestone_ids(state)
	if milestone_ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无里程碑"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.95))
		grid.add_child(empty)
		return

	var claimed_by := _build_claimed_by(state)
	var logo_textures := _build_player_logo_textures(state)

	for ms_id in milestone_ids:
		var def = MilestoneRegistryClass.get_def(ms_id) if MilestoneRegistryClass.is_loaded() else null

		var effect_text := ms_id
		if def != null and def is MilestoneDef and _formatter != null:
			effect_text = _formatter._format_milestone_effect_text(def)

		var owners: Array[int] = []
		if claimed_by.has(ms_id):
			for v in Array(claimed_by[ms_id]):
				if v is int:
					owners.append(int(v))
		owners.sort()

		var card := MilestoneCard.new()
		card.milestone_id = ms_id
		card.milestone_def = def
		card.effect_text = effect_text
		card.player_logo_textures = logo_textures
		card.set_owners(owners)
		grid.add_child(card)
		_cards[ms_id] = card

func _get_all_milestone_ids(state: GameState) -> Array[String]:
	var set := {}

	for v in Array(state.milestone_pool):
		var mid := str(v).strip_edges()
		if mid.is_empty():
			continue
		set[mid] = true

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		for m in Array(p.get("milestones", [])):
			var mid2 := str(m).strip_edges()
			if mid2.is_empty():
				continue
			set[mid2] = true

	var ids: Array[String] = []
	for k in set.keys():
		ids.append(str(k))
	ids.sort()
	return ids

func _build_claimed_by(state: GameState) -> Dictionary:
	var claimed_by: Dictionary = {} # milestone_id -> Array[int]
	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		for m in Array(p.get("milestones", [])):
			var mid := str(m).strip_edges()
			if mid.is_empty():
				continue
			if not claimed_by.has(mid):
				claimed_by[mid] = []
			var arr: Array = claimed_by[mid]
			if not arr.has(pid):
				arr.append(pid)
			claimed_by[mid] = arr
	return claimed_by

func _build_player_logo_textures(state: GameState) -> Dictionary:
	var out: Dictionary = {} # player_id -> Texture2D
	if _skin == null:
		return out
	var logo_ids: Array = MapCanvasDrawerClass.RESTAURANT_LOGO_PIECE_IDS
	if logo_ids.is_empty():
		return out

	for pid in range(state.players.size()):
		var logo_id := -1
		var p_val = state.players[pid]
		if p_val is Dictionary:
			var v = Dictionary(p_val).get("restaurant_logo_id", null)
			if v is int or v is float:
				logo_id = int(v)
		if logo_id < 0 or logo_id >= logo_ids.size():
			logo_id = int(pid % logo_ids.size())
		var key: String = str(logo_ids[logo_id])
		out[pid] = _skin.get_piece_texture(key)

	return out


# === 内部类：里程碑卡片 ===
class MilestoneCard extends PanelContainer:
	var milestone_id: String = ""
	var milestone_def = null # MilestoneDef | null
	var effect_text: String = ""
	var player_logo_textures: Dictionary = {} # player_id -> Texture2D

	var _owners: Array[int] = []

	var _name_label: Label
	var _desc_label: Label
	var _status_label: Label
	var _icons_row: HBoxContainer

	func _ready() -> void:
		_build_ui()
		_update_display()

	func set_owners(owners: Array[int]) -> void:
		_owners = []
		for v in Array(owners):
			if v is int:
				_owners.append(int(v))
		_owners.sort()
		_update_display()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(280, 170)

		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.set_border_width_all(1)
		add_theme_stylebox_override("panel", style)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		add_child(margin)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(vbox)

		_name_label = Label.new()
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(16) if Globals != null else 16)
		vbox.add_child(_name_label)

		_desc_label = Label.new()
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(12) if Globals != null else 12)
		_desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 0.95))
		_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(_desc_label)

		var bottom := HBoxContainer.new()
		bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.alignment = BoxContainer.ALIGNMENT_END
		bottom.add_theme_constant_override("separation", 8)
		vbox.add_child(bottom)

		_status_label = Label.new()
		_status_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(12) if Globals != null else 12)
		_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(_status_label)

		_icons_row = HBoxContainer.new()
		_icons_row.alignment = BoxContainer.ALIGNMENT_END
		_icons_row.add_theme_constant_override("separation", 6)
		bottom.add_child(_icons_row)

	func _update_display() -> void:
		if _name_label != null:
			var name := milestone_id
			if milestone_def != null and milestone_def is MilestoneDef:
				name = str((milestone_def as MilestoneDef).name)
			_name_label.text = name

		if _desc_label != null:
			_desc_label.text = effect_text if not effect_text.is_empty() else milestone_id

		var claimed := not _owners.is_empty()
		if _status_label != null:
			_status_label.text = "已获得" if claimed else "未获得"
			_status_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55, 1) if claimed else Color(0.7, 0.7, 0.7, 1))

		if _icons_row != null:
			for c in _icons_row.get_children():
				if is_instance_valid(c):
					c.queue_free()

			for pid in _owners:
				var tex_val = player_logo_textures.get(pid, null)
				var tex: Texture2D = tex_val if tex_val is Texture2D else null

				var icon := TextureRect.new()
				icon.custom_minimum_size = Vector2(28, 28)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.texture = tex
				icon.tooltip_text = Globals.get_player_name(pid) if Globals != null else ("玩家%d" % (pid + 1))
				_icons_row.add_child(icon)

		_update_style(claimed)

	func _update_style(claimed: bool) -> void:
		var style_val = get_theme_stylebox("panel") if has_theme_stylebox("panel") else null
		if not (style_val is StyleBoxFlat):
			style_val = StyleBoxFlat.new()
		var style: StyleBoxFlat = style_val

		if claimed:
			style.bg_color = Color(0.14, 0.18, 0.14, 0.96)
			style.border_color = Color(0.35, 0.55, 0.35, 0.65)
		else:
			style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
			style.border_color = Color(0.25, 0.25, 0.3, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(10)
		add_theme_stylebox_override("panel", style)
