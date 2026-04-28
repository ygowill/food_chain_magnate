# 里程碑全屏视图（TopBar）
# - 响应式多列布局，居中展示全部里程碑卡片
# - 展示已获得/可获得状态，并在卡片底部显示获得者玩家餐厅 logo
# - ESC 关闭；关闭不改变左/右侧面板显示状态（仅隐藏自身）
class_name MilestoneFullScreenView
extends Control

signal close_requested()
signal build_finished()

@onready var grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/CenterContainer/Grid
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var loading_center: Control = $MarginContainer/VBoxContainer/LoadingCenter
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var hint_label: Label = $MarginContainer/VBoxContainer/HeaderRow/HintLabel

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestonePanelClass = preload("res://ui/components/milestone_panel/milestone_panel.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const MAX_COLUMNS := 4
const CARD_MIN_WIDTH := 300

# 里程碑分类色板（与 left_panel_milestones_controller 保持一致）
const PALETTE_PURPLE := Color(0.69, 0.57, 0.77, 1.0)
const PALETTE_GRAY := Color(0.76, 0.75, 0.74, 1.0)
const PALETTE_MARKETING_BLUE := Color(0.59, 0.77, 0.82, 1.0)
const PALETTE_PRODUCE_GREEN := Color(0.60, 0.71, 0.35, 1.0)
const PALETTE_PROCURE_GREEN := Color(0.70, 0.81, 0.58, 1.0)
const PALETTE_PRICE_ORANGE := Color(0.92, 0.66, 0.56, 1.0)
const PALETTE_COFFEE_MINT := Color(0.60, 0.80, 0.72, 1.0)
const PALETTE_KETCHUP_DARK := Color(0.15, 0.11, 0.10, 1.0)

const MILESTONE_COLOR_BY_ID: Dictionary = {
	"first_hire_3": PALETTE_PURPLE,
	"first_throw_away": PALETTE_PURPLE,
	"first_waitress": PALETTE_PURPLE,
	"first_have_20": PALETTE_PURPLE,
	"first_have_100": PALETTE_PURPLE,
	"first_train": PALETTE_GRAY,
	"first_pay_20_salaries": PALETTE_GRAY,
	"first_billboard": PALETTE_MARKETING_BLUE,
	"first_burger_marketed": PALETTE_MARKETING_BLUE,
	"first_pizza_marketed": PALETTE_MARKETING_BLUE,
	"first_drink_marketed": PALETTE_MARKETING_BLUE,
	"first_airplane": PALETTE_MARKETING_BLUE,
	"first_radio": PALETTE_MARKETING_BLUE,
	"first_burger_produced": PALETTE_PRODUCE_GREEN,
	"first_pizza_produced": PALETTE_PRODUCE_GREEN,
	"first_errand_boy": PALETTE_PROCURE_GREEN,
	"first_cart_operator": PALETTE_PROCURE_GREEN,
	"first_lower_prices": PALETTE_PRICE_ORANGE,
	"first_rural_marketeer_used": PALETTE_MARKETING_BLUE,
	"first_lobbyist_used": PALETTE_PURPLE,
	"first_coffee_sold": PALETTE_COFFEE_MINT,
	"ketchup_sold_your_demand": PALETTE_KETCHUP_DARK,
	"first_marketeer_used": PALETTE_MARKETING_BLUE,
	"first_marketing_trainee_used": PALETTE_MARKETING_BLUE,
	"first_campaign_manager_used": PALETTE_MARKETING_BLUE,
	"first_brand_manager_used": PALETTE_MARKETING_BLUE,
	"first_brand_director_used": PALETTE_MARKETING_BLUE,
	"first_new_restaurant": PALETTE_MARKETING_BLUE,
	"first_burger_sold": PALETTE_PRODUCE_GREEN,
	"first_pizza_sold": PALETTE_PRODUCE_GREEN,
	"first_beer_sold": PALETTE_PROCURE_GREEN,
	"first_coke_sold": PALETTE_PROCURE_GREEN,
	"first_lemonade_sold": PALETTE_PROCURE_GREEN,
	"first_recruiting_girl_used": PALETTE_PURPLE,
	"first_waitress_used": PALETTE_PURPLE,
	"first_trainer_used": PALETTE_GRAY,
	"first_house_built": PALETTE_GRAY,
	"first_discount_manager_used": PALETTE_PRICE_ORANGE,
	"first_cart_operator_used": PALETTE_PROCURE_GREEN,
}

const MILESTONE_CATEGORY_COLORS: Dictionary = {
	"employee": PALETTE_PURPLE,
	"marketing": PALETTE_MARKETING_BLUE,
	"finance": PALETTE_PURPLE,
	"ops": PALETTE_PRODUCE_GREEN,
	"expansion": PALETTE_MARKETING_BLUE,
	"general": PALETTE_GRAY,
}

const MILESTONE_EFFECT_CATEGORY: Dictionary = {
	"gain_card": "employee",
	"gain_cards": "employee",
	"ban_card": "employee",
	"multi_trainer_on_one": "employee",
	"train_from_active_same_color": "employee",
	"employee_no_salary": "employee",
	"peek_reserve_cards": "finance",
	"base_price_delta": "finance",
	"sell_bonus": "finance",
	"salary_total_delta": "finance",
	"turnorder_empty_slots": "finance",
	"ceo_get_cfo": "finance",
	"salary_pay_with_tokens": "finance",
	"salary_allow_unpaid": "finance",
	"salary_cost_override": "finance",
	"bank_burn_on_discount_ge_3": "finance",
	"marketing_no_salary": "marketing",
	"marketing_permanent": "marketing",
	"extra_marketing": "marketing",
	"procure_plus_one": "ops",
	"drinks_per_source_delta": "ops",
	"distance_plus_one": "ops",
	"gain_fridge": "ops",
}

var _skin = null
var _skin_key: String = ""
var _rules: Dictionary = {}
var _viewer_player_id: int = -1

var _cards: Dictionary = {} # milestone_id -> MilestoneCard
var _formatter: MilestonePanel = null
var _built_milestone_ids_key: String = ""
var _last_sync_key: String = ""
var _last_skin_ref = null
var _build_in_progress: bool = false
var _pending_state = null
var _opened: bool = false

func _ready() -> void:
	set_process_unhandled_input(true)
	if is_instance_valid(close_button):
		close_button.pressed.connect(_on_close_pressed)
		UiStylesClass.apply_button_secondary(close_button)
	if is_instance_valid(title_label):
		title_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	if is_instance_valid(hint_label):
		hint_label.add_theme_color_override("font_color", UiStylesClass.COLOR_TEXT_MUTED)
	_set_loading_visible(false)
	if not _opened:
		visible = false
	_apply_responsive_grid_columns()

func _exit_tree() -> void:
	# _formatter 不入树（仅用于复用文案格式化逻辑）；需要显式释放，避免 headless 测试退出时报 “resources still in use”。
	if _formatter != null and is_instance_valid(_formatter):
		_formatter.free()
	_formatter = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_responsive_grid_columns()
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_apply_responsive_grid_columns()

func set_skin(skin) -> void:
	# 允许外部（例如 MapCanvas）注入已构建的 MapSkin，避免重复 build 导致卡顿。
	_skin = skin

func prime_with_state(state: GameState, skin_override = null, viewer_player_id: int = -1) -> void:
	# 进入对局后后台预热；不会阻塞首帧交互。
	begin_background_build(state, skin_override, viewer_player_id)

func begin_background_build(state: GameState, skin_override = null, viewer_player_id: int = -1) -> void:
	if state == null:
		return
	_pending_state = state
	_viewer_player_id = _resolve_viewer_player_id(state, viewer_player_id)

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
	var pool_counts := _build_pool_counts(state)
	var logo_textures := _build_player_logo_textures(state)
	var round_number := int(state.round_number)

	call_deferred("_run_background_rebuild", milestone_ids, claimed_by, pool_counts, logo_textures, round_number, ids_key, sync_key)

func sync_from_state(state: GameState, skin_override = null, force_rebuild: bool = false, viewer_player_id: int = -1) -> void:
	if state == null:
		return
	_viewer_player_id = _resolve_viewer_player_id(state, viewer_player_id)

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

func open_with_state(state: GameState, skin_override = null, viewer_player_id: int = -1) -> void:
	_opened = true
	visible = true
	begin_background_build(state, skin_override, viewer_player_id)

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
	if not loading:
		_apply_responsive_grid_columns()

func _ensure_formatter() -> void:
	if _formatter != null and is_instance_valid(_formatter):
		return
	# 复用 MilestonePanel 的效果文案格式化逻辑；该实例不入树，仅作为 formatter 使用。
	_formatter = MilestonePanelClass.new()

func _resolve_viewer_player_id(state: GameState, requested_viewer_player_id: int = -1) -> int:
	if state == null:
		return -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var pid := int(NetContext.local_player_id)
		if pid >= 0 and pid < state.players.size():
			return pid
		return -1
	var requested := int(requested_viewer_player_id)
	if requested >= 0 and requested < state.players.size():
		return requested
	var current := int(state.get_current_player_id())
	if current >= 0 and current < state.players.size():
		return current
	return -1

func _ensure_skin_for_state(state: GameState) -> void:
	var modules: Array[String] = []
	if state.modules is Array:
		modules = Array(state.modules, TYPE_STRING, "", null)
	var base_dir := ModulesBaseDirClass.get_base_dir()
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

func _run_background_rebuild(milestone_ids: Array[String], claimed_by: Dictionary, pool_counts: Dictionary, logo_textures: Dictionary, round_number: int, ids_key: String, sync_key: String) -> void:
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
		empty.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 0.95))
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

		var pool_count := int(pool_counts.get(ms_id, 0))

		var accent_color := _get_milestone_accent_color(ms_id, def)

		var card := MilestoneCard.new()
		card.milestone_id = ms_id
		card.milestone_def = def
		card.effect_text = effect_text
		card.accent_color = accent_color
		card.player_logo_textures = logo_textures
		card.set_state(owners, pool_count, round_number, _viewer_player_id)
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
	var round_key := str(int(state.round_number))

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

	return "%s|%s|%s|viewer=%d|%s" % [round_key, modules_key, pool_key, _viewer_player_id, "|".join(players_parts)]

func _rebuild_from_state(state: GameState) -> void:
	if grid == null:
		return
	_viewer_player_id = _resolve_viewer_player_id(state)
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
		empty.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 0.95))
		grid.add_child(empty)
		return

	var claimed_by := _build_claimed_by(state)
	var pool_counts := _build_pool_counts(state)
	var logo_textures := _build_player_logo_textures(state)
	var round_number := int(state.round_number)

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

		var pool_count := int(pool_counts.get(ms_id, 0))

		var accent_color := _get_milestone_accent_color(ms_id, def)

		var card := MilestoneCard.new()
		card.milestone_id = ms_id
		card.milestone_def = def
		card.effect_text = effect_text
		card.accent_color = accent_color
		card.player_logo_textures = logo_textures
		card.set_state(owners, pool_count, round_number, _viewer_player_id)
		grid.add_child(card)
		_cards[ms_id] = card

func _update_from_state(state: GameState) -> void:
	if _cards.is_empty():
		return
	_viewer_player_id = _resolve_viewer_player_id(state)
	var claimed_by := _build_claimed_by(state)
	var pool_counts := _build_pool_counts(state)
	var logo_textures := _build_player_logo_textures(state)
	var round_number := int(state.round_number)

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
		var pool_count := int(pool_counts.get(ms_id, 0))
		card.update_from_state(owners, pool_count, round_number, logo_textures, _viewer_player_id)

func _get_all_milestone_ids(state: GameState) -> Array[String]:
	var set := {}

	# 展示“本局模块可用的全部里程碑”，并兼容存档中出现但 registry 缺失的 id。
	if MilestoneRegistryClass.is_loaded():
		for mid0 in MilestoneRegistryClass.get_all_ids():
			var mid3 := str(mid0).strip_edges()
			if mid3.is_empty():
				continue
			set[mid3] = true

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

func _build_pool_counts(state: GameState) -> Dictionary:
	var pool_counts := {}
	if state == null:
		return pool_counts
	for v in Array(state.milestone_pool):
		var mid := str(v).strip_edges()
		if mid.is_empty():
			continue
		pool_counts[mid] = int(pool_counts.get(mid, 0)) + 1
	return pool_counts

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
	if not _skin.has_method("get_restaurant_logo_piece_ids") or not _skin.has_method("get_restaurant_logo_texture_by_id"):
		return out
	var logo_ids_val = _skin.get_restaurant_logo_piece_ids()
	if not (logo_ids_val is Array) or (logo_ids_val as Array).is_empty():
		return out
	var logo_count := (logo_ids_val as Array).size()

	for pid in range(state.players.size()):
		var logo_id := -1
		var p_val = state.players[pid]
		if p_val is Dictionary:
			var v = Dictionary(p_val).get("restaurant_logo_id", null)
			if v is int or v is float:
				logo_id = int(v)
		if logo_id < 0 or logo_id >= logo_count:
			logo_id = int(pid % logo_count)
		out[pid] = _skin.get_restaurant_logo_texture_by_id(logo_id)

	return out

func _apply_responsive_grid_columns() -> void:
	if grid == null or not is_instance_valid(grid):
		return
	if scroll_container == null or not is_instance_valid(scroll_container):
		return

	var available := float(scroll_container.size.x)
	if available <= 0.0:
		return

	# 预留滚动条与边距的安全空间，避免窄屏下出现横向溢出。
	var vbar := scroll_container.get_v_scroll_bar()
	if is_instance_valid(vbar) and vbar.visible:
		available -= float(vbar.size.x)
	available -= 8.0
	if available <= 0.0:
		return

	var sep := int(grid.get_theme_constant("h_separation"))
	var denom := float(CARD_MIN_WIDTH + sep)
	if denom <= 0.0:
		return
	var fit := int(floor((available + float(sep)) / denom))
	var columns := clampi(fit, 1, MAX_COLUMNS)
	if grid.columns != columns:
		grid.columns = columns

func _get_milestone_category(milestone_id: String, def) -> String:
	if def != null and def is MilestoneDef:
		var effects: Array = def.effects if (def.effects is Array) else []
		for eff in effects:
			if eff is Dictionary:
				var eff_type: String = str(eff.get("type", ""))
				if MILESTONE_EFFECT_CATEGORY.has(eff_type):
					return str(MILESTONE_EFFECT_CATEGORY[eff_type])
	return "general"

func _get_milestone_accent_color(milestone_id: String, def) -> Color:
	if MILESTONE_COLOR_BY_ID.has(milestone_id):
		return Color(MILESTONE_COLOR_BY_ID[milestone_id])
	var cat := _get_milestone_category(milestone_id, def)
	if MILESTONE_CATEGORY_COLORS.has(cat):
		return Color(MILESTONE_CATEGORY_COLORS[cat])
	return PALETTE_GRAY


# === 内部类：里程碑卡片 ===
class MilestoneCard extends PanelContainer:
	enum CardStatus {
		OBTAINABLE,
		UNOBTAINABLE,
		CLAIMED,
	}

	var milestone_id: String = ""
	var milestone_def = null # MilestoneDef | null
	var effect_text: String = ""
	var accent_color: Color = Color(0.76, 0.75, 0.74, 1.0)
	var player_logo_textures: Dictionary = {} # player_id -> Texture2D

	var _owners: Array[int] = []
	var _pool_count: int = 0
	var _round_number: int = 0
	var _viewer_player_id: int = -1

	var _panel_style: StyleBoxFlat = null
	var _header_panel: Panel = null
	var _header_style: StyleBoxFlat = null
	var _name_label: Label
	var _desc_label: Label
	var _status_label: Label
	var _expires_label: Label
	var _icons_row: HBoxContainer

	func _ready() -> void:
		_build_ui()
		_update_display()

	func set_state(owners: Array[int], pool_count: int, round_number: int, viewer_player_id: int = -1) -> void:
		var normalized: Array[int] = []
		for v in Array(owners):
			if v is int:
				normalized.append(int(v))
		normalized.sort()

		_owners = normalized
		_pool_count = maxi(0, int(pool_count))
		_round_number = maxi(0, int(round_number))
		_viewer_player_id = int(viewer_player_id)
		_update_display()

	func update_from_state(owners: Array[int], pool_count: int, round_number: int, logo_textures: Dictionary, viewer_player_id: int = -1) -> void:
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

		var pool_changed := (_pool_count != maxi(0, int(pool_count)))
		var round_changed := (_round_number != maxi(0, int(round_number)))
		var viewer_changed := (_viewer_player_id != int(viewer_player_id))

		if not owners_changed and not textures_changed and not pool_changed and not round_changed and not viewer_changed:
			return
		_owners = normalized
		_pool_count = maxi(0, int(pool_count))
		_round_number = maxi(0, int(round_number))
		_viewer_player_id = int(viewer_player_id)
		_update_display()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(300, 210)

		# IMPORTANT: never mutate a theme-shared StyleBox (would affect unrelated UI).
		_ensure_panel_style()

		var outer_vbox := VBoxContainer.new()
		outer_vbox.add_theme_constant_override("separation", 0)
		outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(outer_vbox)

		# --- 头部色彩条 ---
		_header_panel = Panel.new()
		_header_panel.custom_minimum_size = Vector2(0, 38)
		_header_style = StyleBoxFlat.new()
		_header_style.bg_color = accent_color
		_header_style.corner_radius_top_left = 4
		_header_style.corner_radius_top_right = 4
		_header_style.corner_radius_bottom_left = 0
		_header_style.corner_radius_bottom_right = 0
		_header_panel.add_theme_stylebox_override("panel", _header_style)
		outer_vbox.add_child(_header_panel)

		var header_margin := MarginContainer.new()
		header_margin.add_theme_constant_override("margin_left", 12)
		header_margin.add_theme_constant_override("margin_right", 12)
		header_margin.add_theme_constant_override("margin_top", 0)
		header_margin.add_theme_constant_override("margin_bottom", 0)
		header_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_header_panel.add_child(header_margin)

		_name_label = Label.new()
		_name_label.name = "NameLabel"
		_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_name_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(16) if Globals != null else 16)
		_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# 头部文字颜色在 _update_header_text_color 中根据亮度设置
		header_margin.add_child(_name_label)

		# --- 正文区域 ---
		var body_margin := MarginContainer.new()
		body_margin.add_theme_constant_override("margin_left", 14)
		body_margin.add_theme_constant_override("margin_top", 12)
		body_margin.add_theme_constant_override("margin_right", 14)
		body_margin.add_theme_constant_override("margin_bottom", 12)
		body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer_vbox.add_child(body_margin)

		var body_vbox := VBoxContainer.new()
		body_vbox.add_theme_constant_override("separation", 8)
		body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_margin.add_child(body_vbox)

		_desc_label = Label.new()
		_desc_label.name = "DescLabel"
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(14) if Globals != null else 14)
		_desc_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1.0))
		_desc_label.max_lines_visible = 5
		_desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_vbox.add_child(_desc_label)

		var footer_vbox := VBoxContainer.new()
		footer_vbox.name = "FooterVBox"
		footer_vbox.add_theme_constant_override("separation", 3)
		body_vbox.add_child(footer_vbox)

		var status_row := HBoxContainer.new()
		status_row.name = "StatusRow"
		status_row.add_theme_constant_override("separation", 8)
		footer_vbox.add_child(status_row)

		_status_label = Label.new()
		_status_label.name = "StatusLabel"
		_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_status_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(16) if Globals != null else 16)
		_status_label.add_theme_constant_override("outline_size", 1)
		_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_row.add_child(_status_label)

		_icons_row = HBoxContainer.new()
		_icons_row.name = "OwnerLogoRow"
		_icons_row.alignment = BoxContainer.ALIGNMENT_END
		_icons_row.add_theme_constant_override("separation", 7)
		_icons_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status_row.add_child(_icons_row)

		_expires_label = Label.new()
		_expires_label.name = "ExpiresLabel"
		_expires_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_expires_label.add_theme_font_size_override("font_size", Globals.get_scaled_font_size(12) if Globals != null else 12)
		_expires_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1.0))
		footer_vbox.add_child(_expires_label)

	func _update_header_text_color() -> void:
		if _name_label == null:
			return
		var lum := accent_color.r * 0.299 + accent_color.g * 0.587 + accent_color.b * 0.114
		if lum > 0.65:
			_name_label.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1.0))
		else:
			_name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

	func _update_display() -> void:
		if _name_label != null:
			var display_name := milestone_id
			if milestone_def != null and milestone_def is MilestoneDef:
				display_name = str((milestone_def as MilestoneDef).name)
			display_name = _strip_id_suffix(display_name)
			_name_label.text = display_name
			_name_label.tooltip_text = display_name

		if _desc_label != null:
			_desc_label.text = effect_text if not effect_text.is_empty() else milestone_id

		var expires_text := ""
		var expired := false
		if milestone_def != null and milestone_def is MilestoneDef:
			var def: MilestoneDef = milestone_def
			# 若里程碑已被领取且 supply 已耗尽，则不再展示"剩余回合"（避免与"已获得/不可获得"混淆）。
			# 仍保留：未领取或 supply 仍有剩余时，展示过期倒计时。
			if def.expires_at != null and (_owners.is_empty() or _pool_count > 0):
				var exp_round := int(def.expires_at)
				# 过期语义：在第 exp_round 回合的 Cleanup 被移除，因此倒计时应"包含本回合"。
				# 示例：exp_round=2
				# - 回合1：剩余 2 回合（含本回合）
				# - 回合2：剩余 1 回合（含本回合）
				# - 回合3+：已过期
				var round_now := maxi(1, int(_round_number))
				var turns_left := exp_round - round_now + 1
				if turns_left <= 0:
					expires_text = "已过期"
					expired = true
				else:
					expires_text = "剩余 %d 回合（含本回合）" % turns_left

				# 若 supply 已在 Cleanup 被移除（pool=0 且无人领取），则视为已过期（即使仍处于 exp_round）。
				if not expired and _pool_count <= 0 and _owners.is_empty() and round_now >= exp_round:
					expires_text = "已过期"
					expired = true

		var status := CardStatus.UNOBTAINABLE
		if _viewer_player_id >= 0:
			if _owners.has(_viewer_player_id):
				status = CardStatus.CLAIMED
			elif _pool_count > 0 and not expired:
				status = CardStatus.OBTAINABLE
			else:
				status = CardStatus.UNOBTAINABLE
		else:
			# 非联机视角：保持原逻辑（全局状态）。
			if _pool_count > 0 and not expired:
				status = CardStatus.OBTAINABLE
			elif not _owners.is_empty():
				status = CardStatus.CLAIMED
			else:
				status = CardStatus.UNOBTAINABLE

		var status_text := ""
		match status:
			CardStatus.OBTAINABLE:
				status_text = "可获得"
			CardStatus.CLAIMED:
				status_text = "已获得"
			_:
				if _viewer_player_id >= 0 and not _owners.is_empty() and not _owners.has(_viewer_player_id):
					status_text = "他人已获得"
				else:
					status_text = "不可获得"

		if _status_label != null:
			_status_label.text = status_text
			var color := Color(0.5, 0.45, 0.35, 1.0)
			if status == CardStatus.OBTAINABLE:
				color = Color(0.83, 0.63, 0.23, 1.0)
			elif status == CardStatus.CLAIMED:
				color = Color(0.28, 0.55, 0.22, 1.0)
			_status_label.add_theme_color_override("font_color", color)
			_status_label.add_theme_color_override("font_outline_color", color)

		if _expires_label != null:
			_expires_label.text = expires_text
			_expires_label.visible = not expires_text.is_empty()

		if _icons_row != null:
			for child in _icons_row.get_children():
				if is_instance_valid(child):
					child.queue_free()

			for pid in _owners:
				var tex_val = player_logo_textures.get(pid, null)
				var tex: Texture2D = tex_val if tex_val is Texture2D else null

				var icon := TextureRect.new()
				icon.custom_minimum_size = Vector2(32, 32)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.texture = tex
				icon.tooltip_text = Globals.get_player_name(pid) if Globals != null else ("玩家%d" % (pid + 1))
				_icons_row.add_child(icon)
			_icons_row.visible = not _owners.is_empty()

		_update_style(status)

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
				s = s.substr(0, s.length() - suffix.length()).strip_edges()
				break
		return s

	func _ensure_panel_style() -> void:
		if _panel_style == null:
			_panel_style = StyleBoxFlat.new()
			_panel_style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", _panel_style)

	func _desaturate(c: Color, factor: float) -> Color:
		var gray := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		return Color(
			lerpf(gray, c.r, factor),
			lerpf(gray, c.g, factor),
			lerpf(gray, c.b, factor),
			c.a
		)

	func _update_style(status: int) -> void:
		_ensure_panel_style()
		var style: StyleBoxFlat = _panel_style
		var ac := accent_color

		match status:
			CardStatus.OBTAINABLE:
				# 可获得：奶油色背景，accent色边框
				style.bg_color = Color(0.96, 0.93, 0.82, 1.0)  # #f4edd1
				style.border_color = Color(ac.r, ac.g, ac.b, 0.72)
				style.set_border_width_all(1)
				if _header_style != null:
					_header_style.bg_color = ac
				self.modulate = Color(1, 1, 1, 1)
			CardStatus.CLAIMED:
				# 已获得：奶油色混入8% accent
				var bg := Color(0.96, 0.93, 0.82, 1.0)
				style.bg_color = bg.lerp(ac, 0.08)
				style.border_color = Color(ac.r, ac.g, ac.b, 0.85)
				style.set_border_width_all(2)
				if _header_style != null:
					_header_style.bg_color = ac
				self.modulate = Color(1, 1, 1, 1)
			_:
				# 不可获得：灰暗奶油色，去饱和accent
				style.bg_color = Color(0.92, 0.89, 0.80, 1.0)
				var desat := _desaturate(ac, 0.35)
				style.border_color = Color(desat.r, desat.g, desat.b, 0.36)
				style.set_border_width_all(1)
				if _header_style != null:
					_header_style.bg_color = desat
				self.modulate = Color(1, 1, 1, 0.7)

		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)
		_update_header_text_color()
