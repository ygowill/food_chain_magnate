# CompanyStructure regression test (no real rendering required)
# Covers issue_tracker #39: set_player_data may be called before _ready(), so CEO direct slots
# must still be built once the node becomes ready.
class_name CompanyStructureDeferredRebuildTest
extends RefCounted

const CompanyStructureScene = preload("res://ui/components/company_structure/company_structure.tscn")

static func run() -> Result:
	var company = CompanyStructureScene.instantiate()
	if company == null or not is_instance_valid(company):
		return Result.failure("无法实例化 CompanyStructure")

	# Call set_player_data BEFORE _ready(). This simulates reparenting/init order in the real UI.
	if company.has_method("set_player_data"):
		company.call("set_player_data", {
			"employees": [],
			"company_structure": {"ceo_slots": 2},
		})
	else:
		_safe_free(company)
		return Result.failure("CompanyStructure 缺少 set_player_data()")

	# Now become ready.
	if company.has_method("_ready"):
		company.call("_ready")

	var manager_container := company.get_node_or_null("MarginContainer/VBoxContainer/ManagerRow/ManagerScroll/ManagerContainer")
	if manager_container == null:
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerContainer 节点缺失")

	if int(manager_container.get_child_count()) != 2:
		var n := int(manager_container.get_child_count())
		_safe_free(company)
		return Result.failure("CompanyStructure.ManagerContainer child_count=%d (expected 2 CEO slots)" % n)

	_safe_free(company)
	return Result.success({})

static func _safe_free(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).free()

