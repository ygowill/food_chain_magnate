# 历史标签页
# 显示命令执行历史和游戏日志
extends MarginContainer

var _registry: DebugCommandRegistry = null

@onready var system_check: CheckBox = $VBoxContainer/FilterBar/SystemCheck
@onready var player_check: CheckBox = $VBoxContainer/FilterBar/PlayerCheck
@onready var refresh_button: Button = $VBoxContainer/FilterBar/RefreshButton
@onready var export_button: Button = $VBoxContainer/FilterBar/ExportButton
@onready var history_list: RichTextLabel = $VBoxContainer/HistoryList

func init(registry: DebugCommandRegistry) -> void:
	_registry = registry

func _ready() -> void:
	if is_instance_valid(refresh_button):
		refresh_button.pressed.connect(_on_refresh_pressed)
	if is_instance_valid(export_button):
		export_button.pressed.connect(_on_export_pressed)
	if is_instance_valid(system_check):
		system_check.toggled.connect(_on_filter_changed)
	if is_instance_valid(player_check):
		player_check.toggled.connect(_on_filter_changed)

func refresh() -> void:
	if _registry == null:
		return

	var engine := _registry.get_game_engine()
	if engine == null:
		return

	_update_history_list(engine)

func _update_history_list(engine: GameEngine) -> void:
	if not is_instance_valid(history_list):
		return

	history_list.clear()

	var show_system := system_check.button_pressed if is_instance_valid(system_check) else true
	var show_player := player_check.button_pressed if is_instance_valid(player_check) else true

	var history := engine.get_command_history()

	history_list.push_color(Color(0.7, 0.7, 0.7))
	history_list.append_text("═══ 命令历史 (%d 条) ═══\n" % history.size())
	history_list.pop()

	# 从最新到最旧显示
	for i in range(history.size() - 1, -1, -1):
		var cmd: Command = history[i]
		var is_system := cmd.actor == -1

		# 过滤
		if is_system and not show_system:
			continue
		if not is_system and not show_player:
			continue

		# 格式化
		var actor_str := "[系统]" if is_system else "[玩家%d]" % cmd.actor
		var color := Color(0.7, 0.7, 0.7) if is_system else Color(0.5, 0.8, 1.0)

		history_list.push_color(Color(0.6, 0.6, 0.6))
		history_list.append_text("#%d " % cmd.index)
		history_list.pop()

		history_list.push_color(color)
		history_list.append_text("%s " % actor_str)
		history_list.pop()

		history_list.push_color(Color(0.9, 0.9, 0.9))
		history_list.append_text("%s" % cmd.action_id)
		history_list.pop()

		if not cmd.params.is_empty():
			history_list.push_color(Color(0.6, 0.6, 0.6))
			history_list.append_text(" %s" % _format_params(cmd.params))
			history_list.pop()

		history_list.append_text("\n")

func _format_params(params: Dictionary) -> String:
	if params.is_empty():
		return ""

	var parts: Array[String] = []
	for key in params.keys():
		var value = params[key]
		if value is Dictionary or value is Array:
			parts.append("%s=..." % str(key))
		else:
			parts.append("%s=%s" % [str(key), str(value)])

	return "{%s}" % ", ".join(parts)

func _on_refresh_pressed() -> void:
	refresh()

func _on_export_pressed() -> void:
	if _registry == null:
		return

	var engine := _registry.get_game_engine()
	if engine == null:
		return

	var history := engine.get_command_history()
	var lines: Array[String] = ["# 命令历史导出", "# 时间: %s" % Time.get_datetime_string_from_system(), ""]

	for cmd in history:
		var actor_str := "系统" if cmd.actor == -1 else "玩家%d" % cmd.actor
		lines.append("#%d [%s] %s %s" % [cmd.index, actor_str, cmd.action_id, str(cmd.params)])

	var path := "user://command_history_export.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string("\n".join(lines))
		file.close()
		GameLog.info("DebugPanel", "命令历史已导出到: %s" % path)

func _on_filter_changed(_toggled: bool) -> void:
	refresh()
