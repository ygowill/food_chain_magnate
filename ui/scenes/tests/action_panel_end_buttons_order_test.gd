# ActionPanel ordering regression test
# Covers issue_tracker #65: "skip_sub_phase" and "skip" must be the last two buttons,
# with "skip_sub_phase" directly above "skip".
class_name ActionPanelEndButtonsOrderTest
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")
const ActionsControllerClass = preload("res://ui/components/action_panel/action_panel_actions_controller.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run() -> Result:
	var r1 := _case_both_present()
	if not r1.ok:
		return r1
	var r2 := _case_skip_only()
	if not r2.ok:
		return r2
	var r3 := _case_skip_visible_when_only_disabled_real_action()
	if not r3.ok:
		return r3
	return Result.success({})

static func _case_both_present() -> Result:
	var panel := ActionPanelClass.new()

	panel.set_available_actions(["recruit", ActionIdsClass.SKIP, "train", ActionIdsClass.SKIP_SUB_PHASE])

	var ids := _read_action_ids(panel)
	if ids.size() < 2 or ids[ids.size() - 2] != ActionIdsClass.SKIP_SUB_PHASE or ids[ids.size() - 1] != ActionIdsClass.SKIP:
		_safe_free(panel)
		return Result.failure("ActionPanel order mismatch (both): %s" % str(ids))

	_safe_free(panel)
	return Result.success({})

static func _case_skip_only() -> Result:
	var panel := ActionPanelClass.new()

	panel.set_available_actions([ActionIdsClass.SKIP, "recruit"])

	var ids := _read_action_ids(panel)
	if ids.is_empty() or ids[ids.size() - 1] != ActionIdsClass.SKIP:
		_safe_free(panel)
		return Result.failure("ActionPanel order mismatch (skip only): %s" % str(ids))

	_safe_free(panel)
	return Result.success({})

static func _case_skip_visible_when_only_disabled_real_action() -> Result:
	var panel := _FlowMockPanel.new()
	panel._visible_action_ids = ["initiate_marketing", ActionIdsClass.SKIP]
	panel._visible_initiatable_action_ids = []
	panel._action_enabled["initiate_marketing"] = false
	panel._action_enabled[ActionIdsClass.SKIP] = true

	var controller := ActionsControllerClass.new()
	controller.setup(panel)
	controller._compute_guided_flow_visibility()

	if not panel._flow_confirm_end_visible:
		return Result.failure("ActionPanel flow should show skip when only disabled real action remains")

	return Result.success({})

static func _read_action_ids(panel: Object) -> Array[String]:
	if panel == null or not is_instance_valid(panel):
		return []
	if panel.has_method("get_visible_action_ids"):
		return Array(panel.call("get_visible_action_ids"), TYPE_STRING, "", null)
	return []

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

class _FlowMockPanel:
	extends RefCounted

	var _guided_action_id: String = ""
	var _visible_initiatable_action_ids: Array[String] = []
	var _visible_action_ids: Array[String] = []
	var _flow_confirm_end_visible: bool = false
	var _flow_skip_step_visible: bool = false
	var _action_enabled: Dictionary = {}

	func _sync_guided_action_placeholder() -> void:
		pass

	func get_action_enabled(action_id: String) -> bool:
		return bool(_action_enabled.get(str(action_id), false))
