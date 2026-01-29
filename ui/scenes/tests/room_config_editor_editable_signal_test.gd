# RoomConfigEditor：切换 editable 不应触发 changed（回归：避免联机大厅房主无法开始游戏）
extends RefCounted

const RoomConfigEditorClass = preload("res://ui/components/room_config_editor/room_config_editor.gd")

static func run() -> Result:
	var editor = RoomConfigEditorClass.new()
	if editor == null or not is_instance_valid(editor):
		return Result.failure("实例化 RoomConfigEditor 失败")

	var changed_count := 0
	editor.changed.connect(func() -> void:
		changed_count += 1
	)

	# 该组件在未加载模块列表（set_from_room_config 之前）时也会被 set_editable()；
	# 这不应被视为“配置变更”，否则会导致房主进入 error/dirty 状态而无法开始游戏。
	if editor.has_method("_ready"):
		editor.call("_ready")

	editor.set_editable(true)
	editor.set_editable(false)

	var ok := Result.success()
	if changed_count != 0:
		ok = Result.failure("set_editable 不应触发 changed：count=%d" % changed_count)
	if is_instance_valid(editor):
		editor.free()
	return ok

