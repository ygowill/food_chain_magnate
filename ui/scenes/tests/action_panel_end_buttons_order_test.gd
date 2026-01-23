# ActionPanel ordering regression test
# Covers issue_tracker #65: "skip_sub_phase" and "skip" must be the last two buttons,
# with "skip_sub_phase" directly above "skip".
class_name ActionPanelEndButtonsOrderTest
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")

static func run() -> Result:
	var r1 := _case_both_present()
	if not r1.ok:
		return r1
	var r2 := _case_skip_only()
	if not r2.ok:
		return r2
	return Result.success({})

static func _case_both_present() -> Result:
	var panel := ActionPanelClass.new()
	var container := VBoxContainer.new()
	panel.add_child(container)
	panel.items_container = container

	panel.set_available_actions(["recruit", "skip", "train", "skip_sub_phase"])

	var ids := _read_action_ids(container)
	if ids.size() < 2 or ids[ids.size() - 2] != "skip_sub_phase" or ids[ids.size() - 1] != "skip":
		_safe_free(panel)
		return Result.failure("ActionPanel order mismatch (both): %s" % str(ids))

	_safe_free(panel)
	return Result.success({})

static func _case_skip_only() -> Result:
	var panel := ActionPanelClass.new()
	var container := VBoxContainer.new()
	panel.add_child(container)
	panel.items_container = container

	panel.set_available_actions(["skip", "recruit"])

	var ids := _read_action_ids(container)
	if ids.is_empty() or ids[ids.size() - 1] != "skip":
		_safe_free(panel)
		return Result.failure("ActionPanel order mismatch (skip only): %s" % str(ids))

	_safe_free(panel)
	return Result.success({})

static func _read_action_ids(container: VBoxContainer) -> Array[String]:
	var ids: Array[String] = []
	if container == null:
		return ids
	for child in container.get_children():
		if not is_instance_valid(child):
			continue
		# ActionButton is an inner class; the script variable is still accessible.
		ids.append(str(child.action_id))
	return ids

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
