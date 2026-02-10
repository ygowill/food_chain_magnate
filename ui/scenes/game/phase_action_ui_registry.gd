class_name PhaseActionUiRegistry
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const _PENDING_PHASE_ACTIONS_KEY := "pending_phase_actions"
const _CLEANUP_COMPAT_KEY := "cleanup"
const _CLEANUP_COMPAT_KIND_KEY := "pending_choice_kind"

static func sync_cleanup_pending_modals(controller, state: GameState, current_player_id: int, covered: Rect2, interactive: bool) -> void:
	if controller == null:
		return
	if not interactive:
		_hide_cleanup_modals(controller)
		return

	var kind := _resolve_cleanup_pending_choice_kind(state, current_player_id)
	match kind:
		"kimchi":
			_call_show(controller, "show_kimchi_storage_modal", state, current_player_id, covered)
			_call_hide(controller, "hide_fridge_keep_modal")
		"fridge_keep":
			_call_show(controller, "show_fridge_keep_modal", state, current_player_id, covered)
			_call_hide(controller, "hide_kimchi_storage_modal")
		"":
			_hide_cleanup_modals(controller)
		_:
			GameLog.warn("PhaseActionUiRegistry", "未知 Cleanup pending kind: %s" % kind)
			_hide_cleanup_modals(controller)

static func _hide_cleanup_modals(controller) -> void:
	_call_hide(controller, "hide_fridge_keep_modal")
	_call_hide(controller, "hide_kimchi_storage_modal")

static func _resolve_cleanup_pending_choice_kind(state: GameState, current_player_id: int) -> String:
	if state == null:
		return ""
	if str(state.phase) != DefsClass.PHASE_CLEANUP:
		return ""
	if not (state.round_state is Dictionary):
		return ""

	var rs: Dictionary = state.round_state
	var ppa_val = rs.get(_PENDING_PHASE_ACTIONS_KEY, null)
	if not (ppa_val is Dictionary):
		return ""
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_CLEANUP, null)
	if not (list_val is Array):
		return ""
	var list: Array = list_val
	if list.is_empty():
		return ""

	var first = list[0]
	if first is Dictionary:
		var task: Dictionary = first
		var pid: int = int(task.get("player_id", -1))
		if pid != current_player_id:
			return ""
		return str(task.get("kind", "")).strip_edges()

	if first is int or first is float:
		# 兼容旧存档：Cleanup pending 列表为 [player_id(int)]
		if int(first) != current_player_id:
			return ""
		var kind := ""
		var cleanup_val = rs.get(_CLEANUP_COMPAT_KEY, null)
		if cleanup_val is Dictionary:
			var cleanup: Dictionary = cleanup_val
			kind = str(cleanup.get(_CLEANUP_COMPAT_KIND_KEY, "")).strip_edges()
		# 旧格式下：只有 kimchi 是显式分支；其余默认 fridge_keep
		if kind == "kimchi":
			return kind
		return "fridge_keep"

	return ""

static func _call_show(controller, method_name: String, state: GameState, current_player_id: int, covered: Rect2) -> void:
	if controller == null:
		return
	if method_name.is_empty():
		return
	if controller.has_method(method_name):
		controller.call(method_name, state, current_player_id, covered)

static func _call_hide(controller, method_name: String) -> void:
	if controller == null:
		return
	if method_name.is_empty():
		return
	if controller.has_method(method_name):
		controller.call(method_name)

