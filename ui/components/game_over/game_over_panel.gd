# 游戏结束面板组件
# 显示玩家排名和统计数据
class_name GameOverPanel
extends Control

const GameOverWinnerRulesClass = preload("res://core/rules/game_over_winner_rules.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")

signal return_to_menu_requested()
signal play_again_requested()
signal save_replay_requested()

@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var rankings_container: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/RankingsContainer
@onready var stats_container: VBoxContainer = $CenterContainer/Panel/MarginContainer/VBoxContainer/StatsContainer
@onready var return_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/ReturnButton
@onready var play_again_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/PlayAgainButton
@onready var save_replay_btn: Button = $CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/SaveReplayButton

var _final_state: GameState = null
var _player_rankings: Array[Dictionary] = []
var _winner_player_id: int = -1
var _pending_final_state_refresh: bool = false
var _skin = null
var _skin_modules_key: String = ""
var _player_restaurant_logo_ids: Dictionary = {} # player_id -> logo_id
var _fallback_logo_ids: Array[int] = []
var _state_seed: int = 0
var _return_button_text: String = "返回主菜单"

func _ready() -> void:
	if return_btn != null:
		return_btn.text = _return_button_text
		return_btn.pressed.connect(_on_return_pressed)
	if play_again_btn != null:
		play_again_btn.pressed.connect(_on_play_again_pressed)
	if save_replay_btn != null:
		save_replay_btn.pressed.connect(_on_save_replay_pressed)

	# 应用 Diner Poster 风格
	UiStylesClass.apply_dialog_surface($CenterContainer/Panel)
	UiStylesClass.apply_button_primary(play_again_btn)
	UiStylesClass.apply_button_secondary(save_replay_btn)
	UiStylesClass.apply_button_secondary(return_btn)

	if _pending_final_state_refresh:
		_pending_final_state_refresh = false
		_ensure_skin()
		_rebuild_player_logo_ids()
		_calculate_rankings()
		_rebuild_display()

func set_final_state(state: GameState) -> void:
	_final_state = state
	if not is_node_ready():
		_pending_final_state_refresh = true
		return
	_ensure_skin()
	_rebuild_player_logo_ids()
	_calculate_rankings()
	_rebuild_display()

func set_return_button_text(text: String) -> void:
	var next_text := str(text).strip_edges()
	if next_text.is_empty():
		next_text = "返回主菜单"
	_return_button_text = next_text
	if return_btn != null:
		return_btn.text = _return_button_text

func show_with_animation() -> void:
	visible = true
	# 先确保可见，避免 tween 未运行时出现“透明但吃输入”的软锁。
	modulate = Color(1, 1, 1, 1)

	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5).from(Color(1, 1, 1, 0))

func _calculate_rankings() -> void:
	_player_rankings.clear()
	_winner_player_id = -1

	if _final_state == null:
		return

	# 收集所有玩家数据
	var stats_by_id: Dictionary = {}
	for i in range(_final_state.players.size()):
		var player: Dictionary = _final_state.players[i]
		stats_by_id[i] = {
			"id": i,
			"cash": int(player.get("cash", 0)),
			"forfeited": bool(player.get("forfeited", false)),
			"employees": Array(player.get("employees", [])).size(),
			"restaurants": Array(player.get("restaurants", [])).size(),
			"milestones": Array(player.get("milestones", [])).size(),
		}

	var rankings_r: Result = GameOverWinnerRulesClass.build_cash_rankings(_final_state)
	if rankings_r.ok and rankings_r.value is Array:
		for e_val in Array(rankings_r.value):
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = Dictionary(e_val)
			var pid := int(e.get("id", -1))
			if stats_by_id.has(pid):
				_player_rankings.append(Dictionary(stats_by_id[pid]))
	else:
		# 兜底：保持旧行为（按现金降序）
		for k in stats_by_id.keys():
			_player_rankings.append(Dictionary(stats_by_id[k]))
		_player_rankings.sort_custom(func(a, b): return int(a.cash) > int(b.cash))

	var winner_r: Result = GameOverWinnerRulesClass.pick_winner_player_id(_final_state)
	if winner_r.ok:
		_winner_player_id = int(winner_r.value)

func _rebuild_display() -> void:
	_update_title()
	_rebuild_rankings()
	_rebuild_stats()

func _update_title() -> void:
	if title_label == null:
		return
	title_label.text = "游戏结束"
	if _final_state == null or not (_final_state.round_state is Dictionary):
		return
	var game_over_val = _final_state.round_state.get("game_over", null)
	if not (game_over_val is Dictionary):
		return
	var game_over: Dictionary = Dictionary(game_over_val)
	if str(game_over.get("reason", "")) != "last_player_standing":
		return
	if int(game_over.get("forfeited_player_id", -1)) >= 0:
		title_label.text = "玩家弃权，游戏结束"

func _rebuild_rankings() -> void:
	if rankings_container == null:
		return

	# 清除旧内容
	for child in rankings_container.get_children():
		child.queue_free()

	# 添加排名标题
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	rankings_container.add_child(header)

	var rank_header := Label.new()
	rank_header.text = "排名"
	rank_header.custom_minimum_size = Vector2(60, 0)
	rank_header.add_theme_font_size_override("font_size", 14)
	rank_header.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	header.add_child(rank_header)

	var player_header := Label.new()
	player_header.text = "玩家"
	player_header.custom_minimum_size = Vector2(100, 0)
	player_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_header.add_theme_font_size_override("font_size", 14)
	player_header.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	header.add_child(player_header)

	var cash_header := Label.new()
	cash_header.text = "现金"
	cash_header.custom_minimum_size = Vector2(100, 0)
	cash_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_header.add_theme_font_size_override("font_size", 14)
	cash_header.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	header.add_child(cash_header)

	# 添加分隔线
	var sep := HSeparator.new()
	rankings_container.add_child(sep)

	# 添加排名项
	for rank_idx in range(_player_rankings.size()):
		var player_data: Dictionary = _player_rankings[rank_idx]
		var rank_item := RankingItem.new()
		rank_item.rank = rank_idx + 1
		rank_item.player_id = int(player_data.id)
		rank_item.cash = int(player_data.cash)
		rank_item.is_forfeited = bool(player_data.get("forfeited", false))
		rank_item.is_winner = (_winner_player_id >= 0 and int(player_data.id) == _winner_player_id)
		rank_item.logo_texture = _get_player_restaurant_logo_texture(rank_item.player_id)
		rankings_container.add_child(rank_item)

func _rebuild_stats() -> void:
	if stats_container == null or _final_state == null:
		return

	# 清除旧内容
	for child in stats_container.get_children():
		child.queue_free()

	# 游戏统计
	var stats_title := Label.new()
	stats_title.text = "游戏统计"
	stats_title.add_theme_font_size_override("font_size", 16)
	stats_title.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
	stats_container.add_child(stats_title)

	var sep := HSeparator.new()
	stats_container.add_child(sep)

	# 回合数
	var round_stat := _create_stat_row("总回合数", str(_final_state.round_number))
	stats_container.add_child(round_stat)

	# 银行余额
	var bank_total: int = int(_final_state.bank.get("total", 0))
	var bank_stat := _create_stat_row("银行余额", "$%d" % bank_total)
	stats_container.add_child(bank_stat)

	# 银行破产次数
	var bankruptcy_count: int = int(_final_state.bank.get("broke_count", 0))
	var bankruptcy_stat := _create_stat_row("银行破产次数", str(bankruptcy_count))
	stats_container.add_child(bankruptcy_stat)

func _create_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color(0.17, 0.13, 0.09, 1))
	row.add_child(value)

	return row

func _on_return_pressed() -> void:
	return_to_menu_requested.emit()

func _on_play_again_pressed() -> void:
	play_again_requested.emit()

func _on_save_replay_pressed() -> void:
	save_replay_requested.emit()

func _ensure_skin() -> void:
	if _final_state == null:
		_skin = null
		_skin_modules_key = ""
		return

	var mods: Array[String] = Array(_final_state.modules, TYPE_STRING, "", null)
	var key: String = str(mods)
	if _skin != null and key == _skin_modules_key:
		return
	_skin_modules_key = key
	_skin = UiSkinCacheClass.get_skin_for_modules(Globals.modules_v2_base_dir, mods, 40)

func _read_logo_id(value, logo_count: int) -> int:
	if logo_count <= 0:
		return -1
	var logo_id := -1
	if value is int:
		logo_id = int(value)
	elif value is float:
		var f: float = float(value)
		if f == floor(f):
			logo_id = int(f)
	if logo_id < 0 or logo_id >= logo_count:
		return -1
	return logo_id

func _build_fallback_logo_ids(logo_count: int) -> Array[int]:
	if logo_count <= 0:
		return []
	var ids: Array[int] = []
	for i in range(logo_count):
		ids.append(i)

	var rng := RandomNumberGenerator.new()
	var logo_seed := int(_state_seed) ^ int(0x4C4F474F) # 'LOGO'
	rng.seed = int(logo_seed)
	rng.state = int(logo_seed)
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp

	return ids

func _fallback_logo_id_for_player(player_id: int, fallback_logo_ids: Array[int]) -> int:
	if fallback_logo_ids.is_empty():
		return -1
	var pid := maxi(0, int(player_id))
	return int(fallback_logo_ids[pid % fallback_logo_ids.size()])

func _rebuild_player_logo_ids() -> void:
	_player_restaurant_logo_ids.clear()
	_fallback_logo_ids.clear()
	_state_seed = 0
	if _final_state == null:
		return
	_state_seed = int(_final_state.seed)

	var logo_count := 0
	if _skin != null and _skin.has_method("get_restaurant_logo_piece_ids"):
		var ids_val = _skin.get_restaurant_logo_piece_ids()
		if ids_val is Array:
			logo_count = (ids_val as Array).size()

	_fallback_logo_ids = _build_fallback_logo_ids(logo_count)
	for i in range(_final_state.players.size()):
		var p_val = _final_state.players[i]
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		var pid := int(p.get("id", i))
		if pid < 0:
			continue

		var logo_id := _read_logo_id(p.get("restaurant_logo_id", null), logo_count)
		if logo_id >= 0:
			_player_restaurant_logo_ids[pid] = logo_id
		else:
			_player_restaurant_logo_ids[pid] = _fallback_logo_id_for_player(pid, _fallback_logo_ids)

func _get_player_restaurant_logo_texture(player_id: int) -> Texture2D:
	if _skin == null:
		return null
	if not (_skin.has_method("get_restaurant_logo_piece_ids")) or not (_skin.has_method("get_restaurant_logo_texture_by_id")):
		return null
	var logo_count := (_skin.get_restaurant_logo_piece_ids() as Array).size()
	if logo_count <= 0:
		return null
	var logo_id := int(_player_restaurant_logo_ids.get(player_id, -1))
	if logo_id < 0 or logo_id >= logo_count:
		logo_id = _fallback_logo_id_for_player(player_id, _fallback_logo_ids)
	return _skin.get_restaurant_logo_texture_by_id(logo_id)


# === 内部类：排名项 ===
class RankingItem extends PanelContainer:
	var rank: int = 0
	var player_id: int = 0
	var cash: int = 0
	var is_forfeited: bool = false
	var is_winner: bool = false
	var logo_texture: Texture2D = null

	var _rank_label: Label
	var _logo_rect: TextureRect
	var _player_label: Label
	var _status_label: Label
	var _cash_label: Label
	var _crown_label: Label

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(350, 50)

		var style := StyleBoxFlat.new()
		if is_winner:
			style.bg_color = Color(0.95, 0.90, 0.78, 0.95)
			style.border_color = Color(1, 0.84, 0, 0.5)
			style.set_border_width_all(2)
		elif is_forfeited:
			style.bg_color = Color(0.90, 0.86, 0.82, 0.92)
			style.border_color = Color(0.73, 0.23, 0.18, 0.28)
			style.set_border_width_all(1)
		else:
			style.bg_color = Color(0.92, 0.88, 0.78, 0.9)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 20)
		add_child(hbox)

		# 排名
		_rank_label = Label.new()
		_rank_label.custom_minimum_size = Vector2(60, 0)
		_rank_label.add_theme_font_size_override("font_size", 20)
		UiStylesClass.apply_label_dark(_rank_label)
		_rank_label.text = "#%d" % rank
		hbox.add_child(_rank_label)

		# 餐厅 Logo
		_logo_rect = TextureRect.new()
		_logo_rect.custom_minimum_size = Vector2(34, 34)
		_logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_logo_rect.texture = logo_texture
		hbox.add_child(_logo_rect)

		# 玩家名称
		_player_label = Label.new()
		_player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_player_label.add_theme_font_size_override("font_size", 16)
		UiStylesClass.apply_label_dark(_player_label)
		if is_winner:
			_player_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
		var pname := ""
		if Globals != null and Globals.has_method("get_player_name"):
			pname = str(Globals.get_player_name(player_id)).strip_edges()
		if pname.is_empty():
			pname = "玩家 %d" % (player_id + 1)
		_player_label.text = pname
		hbox.add_child(_player_label)

		if is_forfeited:
			_status_label = Label.new()
			_status_label.text = "弃权"
			_status_label.add_theme_font_size_override("font_size", 13)
			_status_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
			hbox.add_child(_status_label)

		# 冠军标记
		if is_winner:
			_crown_label = Label.new()
			_crown_label.text = "Winner"
			_crown_label.add_theme_font_size_override("font_size", 14)
			_crown_label.add_theme_color_override("font_color", Color(0.73, 0.23, 0.18, 1))
			hbox.add_child(_crown_label)

		# 现金
		_cash_label = Label.new()
		_cash_label.custom_minimum_size = Vector2(100, 0)
		_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cash_label.add_theme_font_size_override("font_size", 18)
		if is_forfeited:
			_cash_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.39, 1))
		else:
			_cash_label.add_theme_color_override("font_color", Color(0.28, 0.55, 0.22, 1))
		_cash_label.text = "$%d" % cash
		hbox.add_child(_cash_label)
