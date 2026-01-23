# 里程碑全屏视图（TopBar）
# - 每行 3 列，居中展示全部里程碑卡片
# - 展示已获得/未获得状态，并在卡片右下角显示获得者玩家餐厅 logo
# - ESC 关闭；关闭不改变左/右侧面板显示状态（仅隐藏自身）
class_name MilestoneFullScreenView
extends Control

signal close_requested()
signal build_finished()

@onready var grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/CenterContainer/Grid
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var loading_center: Control = $MarginContainer/VBoxContainer/LoadingCenter
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
var _built_milestone_ids_key: String = ""
var _last_sync_key: String = ""
var _last_skin_ref = null
var _build_in_progress: bool = false
var _pending_state = null

func _ready() -> void:
	set_process_unhandled_input(true)
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
	_set_loading_visible(false)
	visible = false

func _exit_tree() -> void:
	# _formatter 不入树（仅用于复用文案格式化逻辑）；需要显式释放，避免 headless 测试退出时报 “resources still in use”。
	if _formatter != null and is_instance_valid(_formatter):
		_formatter.free()
	_formatter = null

func set_skin(skin) -> void:
	# 允许外部（例如 MapCanvas）注入已构建的 MapSkin，避免重复 build 导致卡顿。
	_skin = skin

func prime_with_state(state: GameState, skin_override = null) -> void:
	# 进入对局后后台预热；不会阻塞首帧交互。
	begin_background_build(state, skin_override)

func begin_background_build(state: GameState, skin_override = null) -> void:
	if state == null:
		return
	_pending_state = state

	if skin_override != null:
		set_skin(skin_override)
	else:
		_ensure_skin_for_state(state)

	# 仅用于格式化少量文案（例如 CFO 加成百分比），不需要 deep duplicate。
	_rules = state.rules if (state.rules is Dictionary) else {}
	_ensure_formatter()
	if _formatter != null:
		_formatter._rules = _rules

	var sync_key := _compute_sync_key(state)
	var milestone_ids := _get_all_milestone_ids(state)
	var ids_key := ",".join(milestone_ids)

	# 若卡片集合未变化，则仅做轻量更新（不进入后台构建）。
	if not _cards.is_empty() and ids_key == _built_milestone_ids_key:
		if sync_key != _last_sync_key:
			_last_sync_key = sync_key
			_update_from_state(state)
		_set_loading_visible(false)
		build_finished.emit()
		return

	if _build_in_progress:
		return

	_build_in_progress = true
	_set_loading_visible(true)

	var claimed_by := _build_claimed_by(state)
	var logo_textures := _build_player_logo_textures(state)

	call_deferred("_run_background_rebuild", milestone_ids, claimed_by, logo_textures, ids_key, sync_key)

func sync_from_state(state: GameState, skin_override = null, force_rebuild: bool = false) -> void:
	if state == null:
		return

	# 仅用于格式化少量文案（例如 CFO 加成百分比），不需要 deep duplicate；避免首次打开里程碑面板卡顿。
	_rules = state.rules if (state.rules is Dictionary) else {}

	if skin_override != null:
		set_skin(skin_override)
	else:
		_ensure_skin_for_state(state)

	var skin_changed: bool = (_last_skin_ref != _skin)
	_last_skin_ref = _skin

	_ensure_formatter()
	# 复用 MilestonePanel 的文案格式化逻辑，但跳过其 set_rules()（内部 deep duplicate 可能很重）。
	# 这里直接注入引用即可；该 formatter 实例不入树，且不会修改 rules。
	if _formatter != null:
		_formatter._rules = _rules

	var sync_key := _compute_sync_key(state)
	if not force_rebuild and not skin_changed and sync_key == _last_sync_key:
		return
	_last_sync_key = sync_key

	var milestone_ids := _get_all_milestone_ids(state)
	var ids_key := ",".join(milestone_ids)
	if force_rebuild or ids_key != _built_milestone_ids_key:
		_built_milestone_ids_key = ids_key
		_rebuild_from_state(state)
		return

	_update_from_state(state)

func open_with_state(state: GameState, skin_override = null) -> void:
	visible = true
	begin_background_build(state, skin_override)

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

func _set_loading_visible(loading: bool) -> void:
	if is_instance_valid(loading_center):
		loading_center.visible = loading
	if is_instance_valid(scroll_container):
		scroll_container.visible = not loading

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

func _run_background_rebuild(milestone_ids: Array[String], claimed_by: Dictionary, logo_textures: Dictionary, ids_key: String, sync_key: String) -> void:
	# 先让“加载中...”有机会显示出来（避免 open 同帧就做重建导致看不到占位）。
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	if grid == null or not is_instance_valid(grid):
		_build_in_progress = false
		return

	# 清空旧 UI
	for c in grid.get_children():
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()

	if milestone_ids.is_empty():
		var empty := Label.new()
		empty.text = "暂无里程碑"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.95))
		grid.add_child(empty)
		_built_milestone_ids_key = ids_key
		_last_sync_key = sync_key
		_build_in_progress = false
		_set_loading_visible(false)
		build_finished.emit()
		return

	var batch := 0
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

		batch += 1
		if batch >= 6:
			batch = 0
			await get_tree().process_frame
			if not is_instance_valid(self):
				return

	_built_milestone_ids_key = ids_key
	_last_sync_key = sync_key
	_build_in_progress = false
	_set_loading_visible(false)
	build_finished.emit()

	# 若构建期间 state 发生变化（例如有人刚获得里程碑），在不重建的前提下做一次轻量更新。
	if _pending_state != null and is_instance_valid(self) and not _cards.is_empty():
		var pending_key := _compute_sync_key(_pending_state)
		if pending_key != _last_sync_key:
			_last_sync_key = pending_key
			_update_from_state(_pending_state)

func _compute_sync_key(state: GameState) -> String:
	# 仅用于避免重复刷新（打开时不再重复 rebuild）。
	var modules_key := ""
	if state.modules is Array:
		modules_key = ",".join(Array(state.modules, TYPE_STRING, "", null))

	var pool_key := ""
	if state.milestone_pool is Array:
		pool_key = ",".join(Array(state.milestone_pool, TYPE_STRING, "", null))

	var players_parts: Array[String] = []
	for pid in range(state.players.size()):
		var logo_str := ""
		var milestones_key := ""
		var p_val = state.players[pid]
		if p_val is Dictionary:
			var p: Dictionary = p_val
			var logo_val = p.get("restaurant_logo_id", null)
			if logo_val is int or logo_val is float:
				logo_str = str(int(logo_val))
			var ms_list: Array[String] = []
			for m in Array(p.get("milestones", [])):
				var mid := str(m).strip_edges()
				if not mid.is_empty():
					ms_list.append(mid)
			milestones_key = ",".join(ms_list)
		players_parts.append("%s:%s" % [logo_str, milestones_key])

	return "%s|%s|%s" % [modules_key, pool_key, "|".join(players_parts)]

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

func _update_from_state(state: GameState) -> void:
	if _cards.is_empty():
		return
	var claimed_by := _build_claimed_by(state)
	var logo_textures := _build_player_logo_textures(state)

	for k in _cards.keys():
		var ms_id := str(k)
		var card_val = _cards.get(k, null)
		if not (card_val is MilestoneCard):
			continue
		var card: MilestoneCard = card_val

		var owners: Array[int] = []
		if claimed_by.has(ms_id):
			for v in Array(claimed_by[ms_id]):
				if v is int:
					owners.append(int(v))
		owners.sort()
		card.update_from_state(owners, logo_textures)

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
		var normalized: Array[int] = []
		for v in Array(owners):
			if v is int:
				normalized.append(int(v))
		normalized.sort()

		if _owners.size() == normalized.size():
			var same := true
			for i in range(normalized.size()):
				if _owners[i] != normalized[i]:
					same = false
					break
			if same:
				return

		_owners = normalized
		_update_display()

	func update_from_state(owners: Array[int], logo_textures: Dictionary) -> void:
		# 仅在必要时刷新（避免每次 open/sync 都重建 icons 节点）。
		var textures_changed := (player_logo_textures != logo_textures)
		if textures_changed:
			player_logo_textures = logo_textures

		var normalized: Array[int] = []
		for v in Array(owners):
			if v is int:
				normalized.append(int(v))
		normalized.sort()

		var owners_changed := true
		if _owners.size() == normalized.size():
			owners_changed = false
			for i in range(normalized.size()):
				if _owners[i] != normalized[i]:
					owners_changed = true
					break

		if not owners_changed and not textures_changed:
			return
		_owners = normalized
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
