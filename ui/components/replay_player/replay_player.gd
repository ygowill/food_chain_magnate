# 回放播放器组件
# 提供游戏回放的播放、暂停、步进等功能
class_name ReplayPlayer
extends PanelContainer

signal state_changed(command_index: int, state: GameState)
signal playback_finished()
signal error_occurred(message: String)
signal close_requested()

# 播放状态
enum PlayState { STOPPED, PLAYING, PAUSED }

# UI 节点
var _file_selector: OptionButton
var _load_file_btn: Button
var _refresh_files_btn: Button
var _browse_file_btn: Button
var _play_btn: Button
var _pause_btn: Button
var _stop_btn: Button
var _step_back_btn: Button
var _step_forward_btn: Button
var _slider: HSlider
var _progress_label: Label
var _speed_selector: OptionButton
var _command_info_label: Label
var _command_list: ItemList
var _status_label: Label
var _close_btn: Button
var _file_dialog: FileDialog

# 回放数据
var _game_engine: GameEngine = null
var _loaded_file_path: String = ""
var _available_file_paths: Array[String] = []
var _command_history: Array[Command] = []
var _checkpoints: Array[Dictionary] = []
var _current_index: int = -1
var _total_commands: int = 0

# 播放控制
var _play_state: PlayState = PlayState.STOPPED
var _playback_speed: float = 1.0
var _playback_timer: float = 0.0
var _base_interval: float = 1.0  # 每条命令间隔（秒）

var _suppress_command_list_signal: bool = false

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	set_process(false)

func _process(delta: float) -> void:
	if _play_state != PlayState.PLAYING:
		return

	_playback_timer += delta * _playback_speed
	if _playback_timer < _base_interval:
		return

	_playback_timer = 0.0
	_step_forward()

	if _current_index >= _total_commands - 1:
		_stop_playback()
		playback_finished.emit()

func _setup_ui() -> void:
	custom_minimum_size = Vector2(760, 520)

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

	_close_btn = Button.new()
	_close_btn.text = "关闭"
	_close_btn.tooltip_text = "关闭回放播放器"
	_close_btn.custom_minimum_size = Vector2(64, 28)
	title_row.add_child(_close_btn)

	# 文件选择行
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	vbox.add_child(file_row)

	var file_label := Label.new()
	file_label.text = "文件:"
	file_label.add_theme_font_size_override("font_size", 12)
	file_row.add_child(file_label)

	_file_selector = OptionButton.new()
	_file_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_row.add_child(_file_selector)

	_refresh_files_btn = Button.new()
	_refresh_files_btn.text = "刷新"
	_refresh_files_btn.tooltip_text = "刷新存档列表"
	_refresh_files_btn.custom_minimum_size = Vector2(64, 28)
	file_row.add_child(_refresh_files_btn)

	_load_file_btn = Button.new()
	_load_file_btn.text = "加载"
	_load_file_btn.tooltip_text = "从选择的文件加载回放"
	_load_file_btn.custom_minimum_size = Vector2(64, 28)
	file_row.add_child(_load_file_btn)

	_browse_file_btn = Button.new()
	_browse_file_btn.text = "浏览..."
	_browse_file_btn.tooltip_text = "从文件系统选择存档文件"
	_browse_file_btn.custom_minimum_size = Vector2(80, 28)
	file_row.add_child(_browse_file_btn)

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

	# 当前命令信息
	_command_info_label = Label.new()
	_command_info_label.text = ""
	_command_info_label.add_theme_font_size_override("font_size", 12)
	_command_info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_command_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_command_info_label)

	# 命令时间线（列表）
	_command_list = ItemList.new()
	_command_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_command_list.allow_reselect = true
	_command_list.select_mode = ItemList.SELECT_SINGLE
	vbox.add_child(_command_list)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray([
		"*.json;存档文件;application/json"
	])
	add_child(_file_dialog)

	_refresh_available_files()
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
	_load_file_btn.pressed.connect(_on_load_file_pressed)
	_refresh_files_btn.pressed.connect(_on_refresh_files_pressed)
	_browse_file_btn.pressed.connect(_on_browse_file_pressed)

	_play_btn.pressed.connect(_on_play_pressed)
	_pause_btn.pressed.connect(_on_pause_pressed)
	_stop_btn.pressed.connect(_on_stop_pressed)
	_step_back_btn.pressed.connect(_on_step_back_pressed)
	_step_forward_btn.pressed.connect(_on_step_forward_pressed)
	_slider.value_changed.connect(_on_slider_value_changed)
	_speed_selector.item_selected.connect(_on_speed_selected)

	_close_btn.pressed.connect(_on_close_pressed)
	_command_list.item_selected.connect(_on_command_item_selected)
	_command_list.item_activated.connect(_on_command_item_activated)
	_file_dialog.file_selected.connect(_on_file_dialog_selected)

func _update_ui_state() -> void:
	var is_loaded := _game_engine != null
	var is_playing := _play_state == PlayState.PLAYING

	if _file_selector != null:
		_file_selector.disabled = is_playing or _available_file_paths.is_empty()
	if _load_file_btn != null:
		_load_file_btn.disabled = is_playing or _available_file_paths.is_empty()
	if _refresh_files_btn != null:
		_refresh_files_btn.disabled = is_playing
	if _browse_file_btn != null:
		_browse_file_btn.disabled = is_playing

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

	if _status_label != null:
		_status_label.tooltip_text = _loaded_file_path if is_loaded and not _loaded_file_path.is_empty() else ""

	_update_command_info()
	_sync_command_list_selection()

# === 公共方法 ===

func load_from_engine(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("游戏引擎为空")

	_game_engine = engine
	_command_history = engine.get_command_history()
	_checkpoints = engine.get_checkpoints()
	_total_commands = _command_history.size()
	_current_index = -1  # 从初始状态开始

	if _slider != null:
		_slider.max_value = maxi(-1, _total_commands - 1)
		_slider.value = _current_index

	var rewind_result := _game_engine.rewind_to_command(_current_index)
	if not rewind_result.ok:
		_set_error(rewind_result.error)
		return rewind_result

	_rebuild_command_list()
	_update_ui_state()
	state_changed.emit(_current_index, _game_engine.get_state())

	return Result.success(null)

func load_from_file(file_path: String) -> Result:
	if file_path.is_empty():
		return Result.failure("文件路径为空")

	var engine := GameEngine.new()
	var load_result := engine.load_from_file(file_path)
	if not load_result.ok:
		_set_error(load_result.error)
		error_occurred.emit(load_result.error)
		return load_result

	_loaded_file_path = file_path
	var result := load_from_engine(engine)
	if result.ok:
		_refresh_available_files()
	return result

func get_game_engine() -> GameEngine:
	return _game_engine

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
	if _slider != null:
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

func _on_refresh_files_pressed() -> void:
	_refresh_available_files()

func _on_load_file_pressed() -> void:
	var path := _get_selected_file_path()
	if path.is_empty():
		return
	if not FileAccess.file_exists(path):
		_set_error("文件不存在: %s" % path)
		error_occurred.emit("文件不存在: %s" % path)
		return
	_stop_playback()
	load_from_file(path)

func _on_browse_file_pressed() -> void:
	if _file_dialog == null:
		return
	_file_dialog.current_path = ""
	_file_dialog.popup_centered_clamped(Vector2i(900, 650))

func _on_file_dialog_selected(path: String) -> void:
	if path.is_empty():
		return
	_stop_playback()
	load_from_file(path)

func _on_command_item_selected(item_index: int) -> void:
	if _suppress_command_list_signal:
		return
	if _game_engine == null:
		return
	if _play_state == PlayState.PLAYING:
		return
	var cmd_index := _command_index_from_item_index(item_index)
	seek_to(cmd_index)

func _on_command_item_activated(item_index: int) -> void:
	_on_command_item_selected(item_index)

func _on_close_pressed() -> void:
	_stop_playback()
	hide()
	close_requested.emit()

# === 文件列表 ===

func _refresh_available_files() -> void:
	_available_file_paths.clear()
	if _file_selector == null:
		return

	var selected_before := _file_selector.selected
	_file_selector.clear()

	# 外部文件（从文件系统加载过）
	if not _loaded_file_path.is_empty() and not _loaded_file_path.begins_with("user://"):
		if FileAccess.file_exists(_loaded_file_path):
			_add_available_file("外部/%s" % _loaded_file_path.get_file(), _loaded_file_path)

	# 快速存档
	var quick_path := "user://savegame.json"
	var quick_label := "快速存档 (savegame.json)" if FileAccess.file_exists(quick_path) else "快速存档 (不存在)"
	_add_available_file(quick_label, quick_path)

	# 多存档槽：user://saves/*.json
	var saves_dir := DirAccess.open("user://saves")
	if saves_dir != null:
		var files: Array[String] = []
		saves_dir.list_dir_begin()
		var f := saves_dir.get_next()
		while not f.is_empty():
			if not saves_dir.current_is_dir() and str(f).to_lower().ends_with(".json"):
				files.append(str(f))
			f = saves_dir.get_next()
		saves_dir.list_dir_end()
		files.sort()
		for i in range(files.size()):
			var file_name: String = files[i]
			var path := "user://saves/%s" % file_name
			_add_available_file("槽位/%s" % file_name, path)

	# 其它 user:// 根目录 *.json（排除 savegame.json）
	var root_dir := DirAccess.open("user://")
	if root_dir != null:
		var files: Array[String] = []
		root_dir.list_dir_begin()
		var f := root_dir.get_next()
		while not f.is_empty():
			var name := str(f)
			if not root_dir.current_is_dir() and name.to_lower().ends_with(".json") and name != "savegame.json":
				files.append(name)
			f = root_dir.get_next()
		root_dir.list_dir_end()
		files.sort()
		for i in range(files.size()):
			var file_name: String = files[i]
			_add_available_file("其它/%s" % file_name, "user://%s" % file_name)

	var selected_index := 0
	if not _loaded_file_path.is_empty():
		for i in range(_available_file_paths.size()):
			if _available_file_paths[i] == _loaded_file_path:
				selected_index = i
				break
	elif selected_before >= 0 and selected_before < _available_file_paths.size():
		selected_index = selected_before

	_file_selector.select(selected_index)
	_update_ui_state()

func _add_available_file(label: String, path: String) -> void:
	_available_file_paths.append(path)
	_file_selector.add_item(label)

func _get_selected_file_path() -> String:
	if _file_selector == null:
		return ""
	var idx := _file_selector.selected
	if idx < 0 or idx >= _available_file_paths.size():
		return ""
	return _available_file_paths[idx]

# === 时间线/信息 ===

func _rebuild_command_list() -> void:
	if _command_list == null:
		return
	_command_list.clear()

	# item 0: 初始状态（command_index = -1）
	_command_list.add_item("初始状态")
	for i in range(_command_history.size()):
		var cmd := _command_history[i]
		var actor_str := "系统" if cmd.actor == -1 else "玩家%d" % cmd.actor
		var display_index := cmd.index if cmd.index >= 0 else i
		_command_list.add_item("#%d [%s] %s" % [display_index, actor_str, cmd.action_id])

	_sync_command_list_selection()

func _sync_command_list_selection() -> void:
	if _command_list == null:
		return
	if _game_engine == null:
		return

	var item_index := _item_index_from_command_index(_current_index)
	var count := _command_list.get_item_count()
	if item_index < 0 or item_index >= count:
		return
	if _command_list.is_selected(item_index):
		return

	_suppress_command_list_signal = true
	_command_list.select(item_index)
	_command_list.ensure_current_is_visible()
	_suppress_command_list_signal = false

func _item_index_from_command_index(command_index: int) -> int:
	# item 0 是初始状态（-1）
	return command_index + 1

func _command_index_from_item_index(item_index: int) -> int:
	return item_index - 1

func _update_command_info() -> void:
	if _command_info_label == null:
		return
	if _game_engine == null:
		_command_info_label.text = ""
		return

	var state := _game_engine.get_state()
	var phase_str := ""
	if state != null:
		phase_str = "%s%s" % [state.phase, (" / %s" % state.sub_phase) if not state.sub_phase.is_empty() else ""]

	if _current_index < 0:
		_command_info_label.text = "当前位置: 初始状态  |  阶段: %s" % phase_str
		return

	var cmd := get_current_command()
	if cmd == null:
		_command_info_label.text = "当前位置: #%d  |  阶段: %s" % [_current_index, phase_str]
		return

	var actor_str := "系统" if cmd.actor == -1 else "玩家%d" % cmd.actor
	_command_info_label.text = "当前位置: #%d [%s] %s  |  阶段: %s" % [_current_index, actor_str, cmd.action_id, phase_str]

func _set_error(message: String) -> void:
	_play_state = PlayState.STOPPED
	_update_ui_state()
	if _status_label != null:
		_status_label.text = "加载失败"
		_status_label.tooltip_text = message

