class_name TutorialRuntimeScopeTest
extends RefCounted

static func run() -> Result:
	if Globals == null:
		return Result.failure("Globals 不可用")

	var snapshot := _capture_globals()
	Globals.clear_tutorial_runtime_flags()

	if Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("没有规则教学运行标记时，不应在普通模式开启教学运行时")

	Globals.tutorial_match_enabled = true
	if not Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("规则教学局标记应开启教学运行时")

	Globals.clear_tutorial_runtime_flags()
	if Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("清理教学运行标记后，不应继续开启教学运行时")

	Globals.request_rules_tutorial()
	if not Globals.tutorial_pending_setup_tour:
		_restore_globals(snapshot)
		return Result.failure("规则教学入口应设置 setup 导览待启动标记")
	if not Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("规则教学入口应开启教学运行时")

	Globals.clear_tutorial_runtime_flags()
	Globals.tutorial_pending_game_ui_tour = true
	if not Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("规则教学 game UI 导览待启动标记应开启教学运行时")

	Globals.clear_tutorial_runtime_flags()
	Globals.tutorial_pending_flow_tutorial = true
	if not Globals.is_tutorial_runtime_enabled():
		_restore_globals(snapshot)
		return Result.failure("规则教学流程提示待启动标记应开启教学运行时")

	_restore_globals(snapshot)
	return Result.success()

static func _capture_globals() -> Dictionary:
	return {
		"tutorial_progress_version": int(Globals.tutorial_progress_version),
		"tutorial_setup_tour_seen": bool(Globals.tutorial_setup_tour_seen),
		"tutorial_game_ui_tour_seen": bool(Globals.tutorial_game_ui_tour_seen),
		"tutorial_flow_hints_seen": Globals.tutorial_flow_hints_seen.duplicate(true),
		"tutorial_pending_setup_tour": bool(Globals.tutorial_pending_setup_tour),
		"tutorial_pending_game_ui_tour": bool(Globals.tutorial_pending_game_ui_tour),
		"tutorial_pending_flow_tutorial": bool(Globals.tutorial_pending_flow_tutorial),
		"tutorial_match_enabled": bool(Globals.tutorial_match_enabled),
	}

static func _restore_globals(snapshot: Dictionary) -> void:
	Globals.tutorial_progress_version = int(snapshot.get("tutorial_progress_version", Globals.TUTORIAL_PROGRESS_VERSION))
	Globals.tutorial_setup_tour_seen = bool(snapshot.get("tutorial_setup_tour_seen", false))
	Globals.tutorial_game_ui_tour_seen = bool(snapshot.get("tutorial_game_ui_tour_seen", false))
	var flow_seen_val = snapshot.get("tutorial_flow_hints_seen", [])
	if flow_seen_val is Array:
		Globals.tutorial_flow_hints_seen = Array(flow_seen_val, TYPE_STRING, "", null)
	else:
		Globals.tutorial_flow_hints_seen = []
	Globals.tutorial_pending_setup_tour = bool(snapshot.get("tutorial_pending_setup_tour", false))
	Globals.tutorial_pending_game_ui_tour = bool(snapshot.get("tutorial_pending_game_ui_tour", false))
	Globals.tutorial_pending_flow_tutorial = bool(snapshot.get("tutorial_pending_flow_tutorial", false))
	Globals.tutorial_match_enabled = bool(snapshot.get("tutorial_match_enabled", false))
