# ActionPanel metadata rendering regression test:
# - ActionPanel should use ActionExecutor.display_name/description when available
#   (avoids module-specific action ids showing raw strings like "place_lobbyists_road").
class_name ActionPanelExecutorMetadataTest
extends RefCounted

const ActionPanelClass = preload("res://ui/components/action_panel/action_panel.gd")
const ActionRegistryClass = preload("res://core/actions/action_registry.gd")
const ActionExecutorClass = preload("res://core/actions/action_executor.gd")

static func run() -> Result:
	var panel := ActionPanelClass.new()
	var container := VBoxContainer.new()
	panel.add_child(container)
	panel.items_container = container

	var registry := ActionRegistryClass.new()
	var ex := ActionExecutorClass.new()
	ex.action_id = "custom_action"
	ex.display_name = "自定义动作"
	ex.description = "这是一条描述"
	registry.register_executor(ex)

	panel.set_action_registry(registry)
	panel.set_available_actions(["custom_action"])

	if container.get_child_count() != 1:
		_safe_free(panel)
		return Result.failure("expected 1 action button, got %d" % int(container.get_child_count()))

	var btn = container.get_child(0)
	if btn == null or not is_instance_valid(btn):
		_safe_free(panel)
		return Result.failure("action button is invalid")

	if str(btn.display_name) != "自定义动作":
		_safe_free(panel)
		return Result.failure("display_name mismatch: %s" % str(btn.display_name))
	if str(btn.description) != "这是一条描述":
		_safe_free(panel)
		return Result.failure("description mismatch: %s" % str(btn.description))

	_safe_free(panel)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

