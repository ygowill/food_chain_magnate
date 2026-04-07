# LeftPanel regression test
# Busy marketers must not be mixed into "hand"; they should be rendered in a dedicated section.
extends RefCounted

const EmployeeIconsControllerClass = preload("res://ui/components/left_panel/left_panel_employee_icons_controller.gd")

static func run() -> Result:
	var panel := _MockLeftPanel.new()
	var state := GameState.new()
	state.players = [{
		"employees": [],
		"reserve_employees": ["kitchen_trainee"],
		"busy_marketers": ["marketing_trainee"],
	}]
	panel._game_state = state

	var controller := EmployeeIconsControllerClass.new()
	controller.setup(panel)
	controller.refresh()

	if panel.hand_tags_flow.get_child_count() != 1:
		_cleanup_mock_panel(panel)
		return Result.failure("手牌区应仅包含 reserve_employees，实际数量: %d" % panel.hand_tags_flow.get_child_count())
	if panel.busy_tags_flow.get_child_count() != 1:
		_cleanup_mock_panel(panel)
		return Result.failure("忙碌营销员区应包含 busy_marketers，实际数量: %d" % panel.busy_tags_flow.get_child_count())

	if panel.hand_section_header.text.find("(1)") < 0:
		_cleanup_mock_panel(panel)
		return Result.failure("手牌标题数量不正确: %s" % panel.hand_section_header.text)
	if panel.busy_section_header.text.find("(1)") < 0:
		_cleanup_mock_panel(panel)
		return Result.failure("忙碌营销员标题数量不正确: %s" % panel.busy_section_header.text)

	_cleanup_mock_panel(panel)
	return Result.success({})

static func _cleanup_mock_panel(panel) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if panel.has_method("dispose"):
		panel.call("dispose")


class _MockLeftPanel:
	extends RefCounted

	var _game_state: GameState = null

	var company_section: VBoxContainer = VBoxContainer.new()
	var hand_section: VBoxContainer = VBoxContainer.new()
	var busy_section: VBoxContainer = VBoxContainer.new()

	var company_section_header: Label = Label.new()
	var hand_section_header: Label = Label.new()
	var busy_section_header: Label = Label.new()

	var company_tags_flow: VBoxContainer = VBoxContainer.new()
	var hand_tags_flow: VBoxContainer = VBoxContainer.new()
	var busy_tags_flow: VBoxContainer = VBoxContainer.new()

	func _resolve_view_player_id() -> int:
		return 0

	func _get_player_salary_cost(_player: Dictionary) -> int:
		return 0

	func dispose() -> void:
		for n in [
			company_tags_flow,
			hand_tags_flow,
			busy_tags_flow,
			company_section_header,
			hand_section_header,
			busy_section_header,
			company_section,
			hand_section,
			busy_section,
		]:
			if n != null and is_instance_valid(n):
				n.free()
		company_tags_flow = null
		hand_tags_flow = null
		busy_tags_flow = null
		company_section_header = null
		hand_section_header = null
		busy_section_header = null
		company_section = null
		hand_section = null
		busy_section = null
		_game_state = null
