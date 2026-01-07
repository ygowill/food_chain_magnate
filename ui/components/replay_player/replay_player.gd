# 回放播放器组件
# 提供游戏回放的播放、暂停、步进等功能
class_name ReplayPlayer
extends PanelContainer

signal state_changed(command_index: int, state: GameState)
signal playback_finished()
signal error_occurred(message: String)

# 播放状态
enum PlayState { STOPPED, PLAYING, PAUSED }

# UI 节点
var _play_btn: Button
var _pause_btn: Button
var _stop_btn: Button
var _step_back_btn: Button
var _step_forward_btn: Button
var _slider: HSlider
var _progress_label: Label
var _speed_selector: OptionButton
var _status_label: Label

# 回放数据
var _game_engine: GameEngine = null
var _command_history: Array[Command] = []
var _checkpoints: Array[Dictionary] = []
var _current_index: int = -1
var _total_commands: int = 0

# 播放控制
var _play_state: PlayState = PlayState.STOPPED
var _playback_speed: float = 1.0
var _playback_timer: float = 0.0
var _base_interval: float = 1.0  # 每条命令间隔（秒）

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	set_process(false)

func _process(delta: float) -> void:
	if _play_state != PlayState.PLAYING:
		return

	_playback_timer += delta * _playback_speed
	if _playback_timer >= _base_interval:
		_playback_timer = 0.0
		_step_forward()

		if _current_index >= _total_commands - 1:
			_stop_playback()
			playback_finished.emit()

func _setup_ui() -> void:
	custom_minimum_size = Vector2(400, 120)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 标题行
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)

	var title_label := Label.new()
	title_label.text = "回放播放器"
	title_label.add_theme_font_size_override("font_size", 16)
	title_row.add_child(title_label)

	title_row.add_child(_create_spacer())

	_status_label = Label.new()
	_status_label.text = "未加载"
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	title_row.add_child(_status_label)

	# 进度条行
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	vbox.add_child(slider_row)

	_progress_label = Label.new()
	_progress_label.text = "0 / 0"
	_progress_label.custom_minimum_size = Vector2(80, 0)
	_progress_label.add_theme_font_size_override("font_size", 12)
	slider_row.add_child(_progress_label)

	_slider = HSlider.new()
	_slider.min_value = -1
	_slider.max_value = 0
	_slider.value = -1
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_child(_slider)

	# 控制按钮行
	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 4)
	control_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(control_row)

	_step_back_btn = _create_button("|<", "后退一步")
	control_row.add_child(_step_back_btn)

	_stop_btn = _create_button("[]", "停止")
	control_row.add_child(_stop_btn)

	_play_btn = _create_button(">", "播放")
	control_row.add_child(_play_btn)

	_pause_btn = _create_button("||", "暂停")
	_pause_btn.visible = false
	control_row.add_child(_pause_btn)

	_step_forward_btn = _create_button(">|", "前进一步")
	control_row.add_child(_step_forward_btn)

	control_row.add_child(_create_spacer())

	# 速度选择
	var speed_label := Label.new()
	speed_label.text = "速度:"
	speed_label.add_theme_font_size_override("font_size", 12)
	control_row.add_child(speed_label)

	_speed_selector = OptionButton.new()
	_speed_selector.add_item("0.5x", 0)
	_speed_selector.add_item("1x", 1)
	_speed_selector.add_item("2x", 2)
	_speed_selector.add_item("4x", 3)
	_speed_selector.add_item("8x", 4)
	_speed_selector.select(1)  # 默认1x
	_speed_selector.custom_minimum_size = Vector2(70, 0)
	control_row.add_child(_speed_selector)

	_update_ui_state()

func _create_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(36, 32)
	return btn

func _create_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _connect_signals() -> void:
	_play_btn.pressed.connect(_on_play_pressed)
	_pause_btn.pressed.connect(_on_pause_pressed)
	_stop_btn.pressed.connect(_on_stop_pressed)
	_step_back_btn.pressed.connect(_on_step_back_pressed)
	_step_forward_btn.pressed.connect(_on_step_forward_pressed)
	_slider.value_changed.connect(_on_slider_value_changed)
	_speed_selector.item_selected.connect(_on_speed_selected)

func _update_ui_state() -> void:
	var is_loaded := _total_commands > 0
	var is_playing := _play_state == PlayState.PLAYING

	_play_btn.visible = not is_playing
	_pause_btn.visible = is_playing
	_play_btn.disabled = not is_loaded or _current_index >= _total_commands - 1
	_stop_btn.disabled = not is_loaded or _current_index == -1
	_step_back_btn.disabled = not is_loaded or _current_index < 0
	_step_forward_btn.disabled = not is_loaded or _current_index >= _total_commands - 1
	_slider.editable = is_loaded and not is_playing

	_progress_label.text = "%d / %d" % [_current_index + 1, _total_commands]

	match _play_state:
		PlayState.STOPPED:
			_status_label.text = "已停止" if is_loaded else "未加载"
		PlayState.PLAYING:
			_status_label.text = "播放中..."
		PlayState.PAUSED:
			_status_label.text = "已暂停"

# === 公共方法 ===

func load_from_engine(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("游戏引擎为空")

	_game_engine = engine
	_command_history = engine.get_command_history()
	_checkpoints = engine.get_checkpoints()
	_total_commands = _command_history.size()
	_current_index = _total_commands - 1  # 从最后状态开始

	_slider.max_value = _total_commands - 1
	_slider.value = _current_index

	_update_ui_state()

	return Result.success(null)

func load_from_file(file_path: String) -> Result:
	var engine := GameEngine.new()
	var load_result := engine.load_from_file(file_path)
	if not load_result.ok:
		return load_result

	return load_from_engine(engine)

func seek_to(command_index: int) -> Result:
	if _game_engine == null:
		return Result.failure("未加载游戏")

	var target := clampi(command_index, -1, _total_commands - 1)
	if target == _current_index:
		return Result.success(null)

	var rewind_result := _game_engine.rewind_to_command(target)
	if not rewind_result.ok:
		error_occurred.emit(rewind_result.error)
		return rewind_result

	_current_index = target
	_slider.value = _current_index
	_update_ui_state()

	state_changed.emit(_current_index, _game_engine.get_state())
	return Result.success(null)

func get_current_state() -> GameState:
	if _game_engine == null:
		return null
	return _game_engine.get_state()

func get_current_command() -> Command:
	if _current_index < 0 or _current_index >= _command_history.size():
		return null
	return _command_history[_current_index]

func get_command_count() -> int:
	return _total_commands

func get_current_index() -> int:
	return _current_index

# === 播放控制 ===

func _start_playback() -> void:
	if _current_index >= _total_commands - 1:
		return

	_play_state = PlayState.PLAYING
	_playback_timer = 0.0
	set_process(true)
	_update_ui_state()

func _pause_playback() -> void:
	_play_state = PlayState.PAUSED
	set_process(false)
	_update_ui_state()

func _stop_playback() -> void:
	_play_state = PlayState.STOPPED
	set_process(false)
	_update_ui_state()

func _step_forward() -> void:
	if _current_index >= _total_commands - 1:
		return
	seek_to(_current_index + 1)

func _step_back() -> void:
	if _current_index < 0:
		return
	seek_to(_current_index - 1)

# === 信号处理 ===

func _on_play_pressed() -> void:
	_start_playback()

func _on_pause_pressed() -> void:
	_pause_playback()

func _on_stop_pressed() -> void:
	_stop_playback()
	seek_to(-1)

func _on_step_back_pressed() -> void:
	_step_back()

func _on_step_forward_pressed() -> void:
	_step_forward()

func _on_slider_value_changed(value: float) -> void:
	if _play_state == PlayState.PLAYING:
		return
	seek_to(int(value))

func _on_speed_selected(index: int) -> void:
	match index:
		0: _playback_speed = 0.5
		1: _playback_speed = 1.0
		2: _playback_speed = 2.0
		3: _playback_speed = 4.0
		4: _playback_speed = 8.0
