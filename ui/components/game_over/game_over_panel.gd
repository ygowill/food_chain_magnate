# 游戏结束面板组件
# 显示玩家排名和统计数据
class_name GameOverPanel
extends Control

signal return_to_menu_requested()
signal play_again_requested()

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var rankings_container: VBoxContainer = $MarginContainer/VBoxContainer/RankingsContainer
@onready var stats_container: VBoxContainer = $MarginContainer/VBoxContainer/StatsContainer
@onready var return_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ReturnButton
@onready var play_again_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/PlayAgainButton

var _final_state: GameState = null
var _player_rankings: Array[Dictionary] = []

func _ready() -> void:
	if return_btn != null:
		return_btn.pressed.connect(_on_return_pressed)
	if play_again_btn != null:
		play_again_btn.pressed.connect(_on_play_again_pressed)

	# 初始隐藏
	visible = false

func set_final_state(state: GameState) -> void:
	_final_state = state
	_calculate_rankings()
	_rebuild_display()

func show_with_animation() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0)

	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.5)

func _calculate_rankings() -> void:
	_player_rankings.clear()

	if _final_state == null:
		return

	# 收集所有玩家数据
	for i in range(_final_state.players.size()):
		var player: Dictionary = _final_state.players[i]
		_player_rankings.append({
			"id": i,
			"cash": int(player.get("cash", 0)),
			"employees": Array(player.get("employees", [])).size(),
			"restaurants": Array(player.get("restaurants", [])).size(),
			"milestones": Array(player.get("milestones", [])).size(),
		})

	# 按现金排序（降序）
	_player_rankings.sort_custom(func(a, b): return a.cash > b.cash)

func _rebuild_display() -> void:
	_rebuild_rankings()
	_rebuild_stats()

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
	rank_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	header.add_child(rank_header)

	var player_header := Label.new()
	player_header.text = "玩家"
	player_header.custom_minimum_size = Vector2(100, 0)
	player_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_header.add_theme_font_size_override("font_size", 14)
	player_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	header.add_child(player_header)

	var cash_header := Label.new()
	cash_header.text = "现金"
	cash_header.custom_minimum_size = Vector2(100, 0)
	cash_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_header.add_theme_font_size_override("font_size", 14)
	cash_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
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
		rank_item.is_winner = (rank_idx == 0)
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
	stats_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
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
	var bankruptcy_count: int = int(_final_state.bank.get("bankruptcy_count", 0))
	var bankruptcy_stat := _create_stat_row("银行破产次数", str(bankruptcy_count))
	stats_container.add_child(bankruptcy_stat)

func _create_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	row.add_child(value)

	return row

func _on_return_pressed() -> void:
	return_to_menu_requested.emit()

func _on_play_again_pressed() -> void:
	play_again_requested.emit()


# === 内部类：排名项 ===
class RankingItem extends PanelContainer:
	var rank: int = 0
	var player_id: int = 0
	var cash: int = 0
	var is_winner: bool = false

	var _rank_label: Label
	var _player_label: Label
	var _cash_label: Label
	var _crown_label: Label

	const RANK_COLORS: Array[Color] = [
		Color("#ffd700"),  # 金色 - 第1名
		Color("#c0c0c0"),  # 银色 - 第2名
		Color("#cd7f32"),  # 铜色 - 第3名
		Color("#808080"),  # 灰色 - 其他
	]

	const PLAYER_COLORS: Array[Color] = [
		Color("#e74c3c"),  # 红色
		Color("#3498db"),  # 蓝色
		Color("#2ecc71"),  # 绿色
		Color("#f1c40f"),  # 黄色
		Color("#9b59b6"),  # 紫色
	]

	func _ready() -> void:
		_build_ui()

	func _build_ui() -> void:
		custom_minimum_size = Vector2(350, 50)

		var style := StyleBoxFlat.new()
		if is_winner:
			style.bg_color = Color(0.25, 0.22, 0.15, 0.9)
			style.border_color = Color(1, 0.84, 0, 0.5)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.15, 0.17, 0.2, 0.8)
		style.set_corner_radius_all(6)
		add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 20)
		add_child(hbox)

		# 排名
		_rank_label = Label.new()
		_rank_label.custom_minimum_size = Vector2(60, 0)
		_rank_label.add_theme_font_size_override("font_size", 20)
		var rank_color_idx := mini(rank - 1, RANK_COLORS.size() - 1)
		_rank_label.add_theme_color_override("font_color", RANK_COLORS[rank_color_idx])
		_rank_label.text = "#%d" % rank
		hbox.add_child(_rank_label)

		# 玩家颜色标记
		var player_color := ColorRect.new()
		player_color.custom_minimum_size = Vector2(8, 30)
		var color_idx := player_id % PLAYER_COLORS.size()
		player_color.color = PLAYER_COLORS[color_idx]
		hbox.add_child(player_color)

		# 玩家名称
		_player_label = Label.new()
		_player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_player_label.add_theme_font_size_override("font_size", 16)
		_player_label.text = "玩家 %d" % (player_id + 1)
		hbox.add_child(_player_label)

		# 冠军标记
		if is_winner:
			_crown_label = Label.new()
			_crown_label.text = "Winner"
			_crown_label.add_theme_font_size_override("font_size", 14)
			_crown_label.add_theme_color_override("font_color", Color(1, 0.84, 0, 1))
			hbox.add_child(_crown_label)

		# 现金
		_cash_label = Label.new()
		_cash_label.custom_minimum_size = Vector2(100, 0)
		_cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cash_label.add_theme_font_size_override("font_size", 18)
		_cash_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6, 1))
		_cash_label.text = "$%d" % cash
		hbox.add_child(_cash_label)
