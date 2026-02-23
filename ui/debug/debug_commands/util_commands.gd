# 工具类调试命令（UI/开发工具）
extends RefCounted

const CommandPrivacyClass = preload("res://core/utils/command_privacy.gd")

static func register_all(registry: DebugCommandRegistry) -> void:
	registry.register("help", _cmd_help.bind(registry), "显示帮助信息", "help [command]", ["command"])
	registry.register("clear", _cmd_clear.bind(registry), "清空输出", "clear")
	registry.register("history", _cmd_history.bind(registry), "显示命令历史", "history [count]", ["count"])
	registry.register("validate", _cmd_validate.bind(registry), "验证游戏状态不变量", "validate")
	registry.register("snapshot", _cmd_snapshot.bind(registry), "创建状态快照", "snapshot")
	registry.register("restore", _cmd_restore.bind(registry), "恢复到上一个快照", "restore")
	registry.register("save", _cmd_save.bind(registry), "保存游戏", "save [filename]", ["filename"])
	registry.register("load", _cmd_load.bind(registry), "加载游戏", "load [filename]", ["filename"])
	registry.register("exec", _cmd_exec.bind(registry), "执行任意动作", "exec <actor> <action_id> [params_json]", ["actor", "action_id", "params"])
	registry.register("actions", _cmd_actions.bind(registry), "显示可用动作", "actions")
	registry.register("undo", _cmd_undo.bind(registry), "撤销命令", "undo [steps]", ["steps"])
	registry.register("redo", _cmd_redo.bind(registry), "重做命令", "redo [steps]", ["steps"])

static func _mark_debug_force(cmd: Command) -> void:
	if not DebugFlags.is_debug_mode():
		return
	if not DebugFlags.force_execute_commands:
		return
	if not (cmd.metadata is Dictionary):
		cmd.metadata = {}
	cmd.metadata["debug_force"] = true

static func _parse_player_id_arg(arg, state: GameState) -> Result:
	if state == null:
		return Result.failure("游戏状态为空")
	var player_count := state.players.size()
	if player_count <= 0:
		return Result.failure("玩家数量无效: %d" % player_count)

	var token := str(arg).strip_edges()
	if token.is_empty():
		return Result.failure("actor 不能为空")

	var lower := token.to_lower()
	if lower == "system" or lower == "-1":
		return Result.success(-1)

	if lower.begins_with("id:"):
		var id_str := token.substr(3).strip_edges()
		if not id_str.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid := int(id_str)
		if pid < 0 or pid >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid, player_count - 1])
		return Result.success(pid)

	if lower.begins_with("pid:"):
		var id_str2 := token.substr(4).strip_edges()
		if not id_str2.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid2 := int(id_str2)
		if pid2 < 0 or pid2 >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid2, player_count - 1])
		return Result.success(pid2)

	# 默认按玩家顺位 1..N 解析（不允许“当前玩家”隐式行为）
	if not token.is_valid_int():
		return Result.failure("actor 必须为 system/-1 或 1..%d（或使用 id:<player_id>）" % player_count)
	var pnum := int(token)
	if pnum < 1 or pnum > player_count:
		return Result.failure("无效的玩家顺位: %d（有效范围 1..%d）" % [pnum, player_count])
	return Result.success(pnum - 1)

static func _cmd_help(args: Array, registry: DebugCommandRegistry) -> Result:
	var cmd_name := ""
	if not args.is_empty():
		cmd_name = str(args[0])
	return Result.success(registry.get_help(cmd_name))

static func _cmd_clear(args: Array, registry: DebugCommandRegistry) -> Result:
	# 返回特殊标记，由面板处理
	return Result.success("__CLEAR__")

static func _cmd_history(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var count := 10
	if not args.is_empty():
		count = int(args[0])

	var history := engine.get_recent_commands(count)
	var state := engine.get_state()
	var viewer_player_id := -1
	if NetContext != null:
		viewer_player_id = int(NetContext.get_command_privacy_viewer_player_id())
	var lines: Array[String] = ["=== 命令历史 (最近 %d 条) ===" % count]

	for cmd in history:
		var actor_str := "系统" if cmd.actor == -1 else "玩家%d" % cmd.actor
		var sanitized: Dictionary = CommandPrivacyClass.sanitize_params(str(cmd.action_id), int(cmd.actor), cmd.params, viewer_player_id, state)
		lines.append("#%d [%s] %s %s" % [cmd.index, actor_str, cmd.action_id, str(sanitized)])

	return Result.success("\n".join(lines))

static func _cmd_validate(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	# 验证校验点
	var checkpoint_result := engine.verify_checkpoints()
	if not checkpoint_result.ok:
		return Result.failure("校验点验证失败: %s" % checkpoint_result.error)

	return Result.success("所有不变量验证通过")

static func _cmd_snapshot(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	# 创建存档作为快照
	var archive_result := engine.create_archive()
	if not archive_result.ok:
		return Result.failure("创建快照失败: %s" % archive_result.error)

	# 存储到临时位置
	var path := "user://debug_snapshot.json"
	var save_result := engine.save_to_file(path)
	if not save_result.ok:
		return Result.failure("保存快照失败: %s" % save_result.error)

	return Result.success("快照已保存到: %s" % path)

static func _cmd_restore(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var path := "user://debug_snapshot.json"
	if not FileAccess.file_exists(path):
		return Result.failure("快照文件不存在: %s" % path)

	var load_result := engine.load_from_file(path)
	if not load_result.ok:
		return Result.failure("恢复快照失败: %s" % load_result.error)

	return Result.success("已恢复到快照")

static func _cmd_save(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var filename := "debug_save"
	if not args.is_empty():
		filename = str(args[0])

	var path := "user://%s.json" % filename
	var result := engine.save_to_file(path)
	if not result.ok:
		return Result.failure("保存失败: %s" % result.error)

	return Result.success("已保存到: %s" % path)

static func _cmd_load(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var filename := "debug_save"
	if not args.is_empty():
		filename = str(args[0])

	var path := "user://%s.json" % filename
	if not FileAccess.file_exists(path):
		return Result.failure("文件不存在: %s" % path)

	var result := engine.load_from_file(path)
	if not result.ok:
		return Result.failure("加载失败: %s" % result.error)

	return Result.success("已加载: %s" % path)

static func _cmd_exec(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: exec <actor> <action_id> [params_json]")

	var state := engine.get_state()
	var actor_read := _parse_player_id_arg(args[0], state)
	if not actor_read.ok:
		return actor_read
	var actor_id := int(actor_read.value)

	var action_id := str(args[1])
	var params := {}

	if args.size() > 2:
		var json_str := str(args[2])
		var json := JSON.new()
		var parse_result := json.parse(json_str)
		if parse_result != OK:
			return Result.failure("JSON 解析失败: %s" % json.get_error_message())
		params = json.data

	var cmd := Command.create(action_id, actor_id, params)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)

	if not result.ok:
		return Result.failure("执行失败: %s" % result.error)

	return Result.success("已执行: %s" % action_id)

static func _cmd_actions(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var actions := engine.get_available_actions()
	var lines: Array[String] = ["=== 可用动作 ==="]
	for action in actions:
		lines.append("  - %s" % action)

	return Result.success("\n".join(lines))

static func _cmd_undo(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var steps: int = 1
	if not args.is_empty():
		steps = int(args[0])

	var history := engine.get_command_history()
	var current_index: int = engine.current_command_index
	var target_index: int = max(-1, current_index - steps)

	var result := engine.rewind_to_command(target_index)
	if not result.ok:
		return Result.failure("撤销失败: %s" % result.error)

	return Result.success("已撤销 %d 步 (当前: #%d)" % [steps, target_index])

static func _cmd_redo(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var steps: int = 1
	if not args.is_empty():
		steps = int(args[0])

	var history := engine.get_command_history()
	var current_index: int = engine.current_command_index
	var target_index: int = min(history.size() - 1, current_index + steps)

	if target_index <= current_index:
		return Result.failure("没有可重做的命令")

	var result := engine.rewind_to_command(target_index)
	if not result.ok:
		return Result.failure("重做失败: %s" % result.error)

	return Result.success("已重做 %d 步 (当前: #%d)" % [steps, target_index])
