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

	var registry := ActionRegistryClass.new()
	var ex := ActionExecutorClass.new()
	ex.action_id = "custom_action"
	ex.display_name = "自定义动作"
	ex.description = "这是一条描述"
	registry.register_executor(ex)

	panel.set_action_registry(registry)
	var name := ""
	var desc := ""
	if panel.has_method("get_action_display_name"):
		name = str(panel.call("get_action_display_name", "custom_action"))
	if panel.has_method("get_action_description"):
		desc = str(panel.call("get_action_description", "custom_action"))

	if name != "自定义动作":
		_safe_free(panel)
		return Result.failure("display_name mismatch: %s" % name)
	if desc != "这是一条描述":
		_safe_free(panel)
		return Result.failure("description mismatch: %s" % desc)

	_safe_free(panel)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
