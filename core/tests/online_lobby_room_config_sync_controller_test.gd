class_name OnlineLobbyRoomConfigSyncControllerTest
extends RefCounted

const ControllerClass = preload("res://ui/scenes/online/online_lobby_room_config_sync_controller.gd")

class FakeEditor extends RefCounted:
	var set_from_room_config_calls: int = 0
	var set_editable_calls: int = 0
	var last_cfg: Dictionary = {}
	var last_editable: bool = false

	func set_from_room_config(cfg: Dictionary) -> void:
		set_from_room_config_calls += 1
		last_cfg = cfg.duplicate(true)

	func set_editable(editable: bool) -> void:
		set_editable_calls += 1
		last_editable = bool(editable)

static func run() -> Result:
	var controller = ControllerClass.new()
	controller.setup(RefCounted.new(), null, null)
	var editor := FakeEditor.new()
	var room_state: Dictionary = {
		"status": "Lobby",
		"room_mode": "normal",
		"config": {
			"desired_player_count": 2,
			"seed_mode": "random",
			"seed": 123,
			"allow_spectators": true,
		},
	}

	controller.sync_editor_from_room_state(room_state, true, editor)
	if editor.set_from_room_config_calls != 1:
		return Result.failure("首次同步应写入一次配置，实际=%d" % editor.set_from_room_config_calls)
	if editor.set_editable_calls != 1 or not editor.last_editable:
		return Result.failure("首次同步应设置 editable=true")

	controller.sync_editor_from_room_state(room_state, true, editor)
	if editor.set_from_room_config_calls != 1:
		return Result.failure("相同房间状态重复同步时不应重复写配置")
	if editor.set_editable_calls != 1:
		return Result.failure("相同房间状态重复同步时不应重复设置 editable")

	var changed_room_state: Dictionary = room_state.duplicate(true)
	var changed_cfg: Dictionary = Dictionary(changed_room_state.get("config", {}))
	changed_cfg["seed"] = 456
	changed_room_state["config"] = changed_cfg
	controller.sync_editor_from_room_state(changed_room_state, true, editor)
	if editor.set_from_room_config_calls != 2:
		return Result.failure("配置变化后应重新写入编辑器")

	controller.sync_editor_from_room_state(changed_room_state, false, editor)
	if editor.set_editable_calls != 3:
		return Result.failure("host 状态变化后应重新设置 editable")
	if editor.last_editable:
		return Result.failure("非房主时 editable 应为 false")

	return Result.success()
