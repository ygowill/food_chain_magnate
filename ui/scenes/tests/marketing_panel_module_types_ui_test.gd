# MarketingPanel module marketing type regression test
# Ensures module-defined marketing types (e.g., gourmet_guide) appear in the MarketingPanel selector.
class_name MarketingPanelModuleTypesUiTest
extends RefCounted

const MarketingPanelClass = preload("res://ui/components/marketing_panel/marketing_panel.gd")

static func run() -> Result:
	var panel := MarketingPanelClass.new()
	var container := HFlowContainer.new()
	panel.add_child(container)
	panel.type_container = container

	panel.set_available_marketers([
		{"id": "gourmet_food_critic", "type": "gourmet_guide", "max_duration": 3},
	])
	panel.set_available_boards({"gourmet_guide": [17, 18]})

	if not panel._type_buttons.has("gourmet_guide"):
		_safe_free(panel)
		return Result.failure("MarketingPanel should include module marketing type gourmet_guide")

	var btn = panel._type_buttons.get("gourmet_guide", null)
	if btn == null or not is_instance_valid(btn):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide button invalid: %s" % str(btn))

	if str(btn.type_id) != "gourmet_guide":
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide type_id mismatch: %s" % str(btn.type_id))

	if not bool(btn.is_available):
		_safe_free(panel)
		return Result.failure("MarketingPanel gourmet_guide should be available when marketer+boards exist")

	_safe_free(panel)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()
