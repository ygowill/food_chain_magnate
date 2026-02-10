class_name PhaseActionUiRegistry
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const _PENDING_PHASE_ACTIONS_KEY := "pending_phase_actions"
const _CLEANUP_COMPAT_KEY := "cleanup"
const _CLEANUP_COMPAT_KIND_KEY := "pending_choice_kind"
const _CLEANUP_COMPAT_DEFAULT_KIND := "fridge_keep"

static func sync_cleanup_pending_modals(controller, state: GameState, current_player_id: int, covered: Rect2, interactive: bool) -> void:
	if controller == null:
		return
	if not interactive:
		_hide_cleanup_modals(controller)
		return

	var kind := _resolve_cleanup_pending_choice_kind(state, current_player_id)
	if kind.is_empty():
		_hide_cleanup_modals(controller)
		return

	if controller.has_method("show_phase_action_ui_modal"):
		controller.call("show_phase_action_ui_modal", DefsClass.PHASE_CLEANUP, kind, state, current_player_id, covered)
	else:
		GameLog.warn("PhaseActionUiRegistry", "controller 缺少 show_phase_action_ui_modal（无法显示 Cleanup pending modal）")

static func _hide_cleanup_modals(controller) -> void:
	if controller == null:
		return
	if controller.has_method("hide_phase_action_ui_modals_for_phase"):
		controller.call("hide_phase_action_ui_modals_for_phase", DefsClass.PHASE_CLEANUP)

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
		if not kind.is_empty():
			return kind
		return _CLEANUP_COMPAT_DEFAULT_KIND

	return ""
