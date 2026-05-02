class_name ActionPanelExternalBlockReasonTest
extends RefCounted

const ActionPanelScene: PackedScene = preload("res://ui/components/action_panel/action_panel.tscn")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

class _BlockReasonProvider:
	extends RefCounted

	func get_reason(action_id: String, _state: GameState, _player_id: int) -> String:
		if str(action_id).strip_edges() == ActionIdsClass.SKIP_SUB_PHASE:
			return "教学局当前请先完成当前步骤。"
		return ""

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 ActionPanel）")

	if ActionPanelScene == null:
		return Result.failure("预加载 action_panel.tscn 失败（PackedScene 为空）")

	var panel = ActionPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("实例化 ActionPanel 失败")
	host.add_child(panel)
	(panel as Control).visible = true
	await st.process_frame

	if not (panel is ActionPanel):
		await _cleanup_panel(panel, st)
		return Result.failure("实例不是 ActionPanel")
	var action_panel: ActionPanel = panel

	var provider := _BlockReasonProvider.new()
	action_panel.set_external_action_block_reason_provider(Callable(provider, "get_reason"))
	action_panel.set_available_actions(["recruit", ActionIdsClass.SKIP_SUB_PHASE])
	await st.process_frame

	if action_panel.get_action_enabled(ActionIdsClass.SKIP_SUB_PHASE):
		await _cleanup_panel(panel, st)
		return Result.failure("外部 block reason 应将 skip_sub_phase 置为 disabled")

	var reason := action_panel.get_action_disabled_reason(ActionIdsClass.SKIP_SUB_PHASE)
	if reason.find("教学局") == -1:
		await _cleanup_panel(panel, st)
		return Result.failure("应保留外部 block reason 文案，实际: %s" % reason)

	if not action_panel.get_action_enabled("recruit"):
		await _cleanup_panel(panel, st)
		return Result.failure("外部 block reason 不应误伤其他动作")

	var game_over_state := GameState.new()
	game_over_state.phase = DefsClass.PHASE_GAME_OVER
	action_panel.set_game_state(game_over_state)
	var flow_cfg: Dictionary = action_panel.get_flow_controls_config()
	var confirm_cfg: Dictionary = Dictionary(flow_cfg.get("confirm_end", {}))
	var rewind_cfg: Dictionary = Dictionary(flow_cfg.get("rewind", {}))
	if bool(confirm_cfg.get("visible", true)):
		await _cleanup_panel(panel, st)
		return Result.failure("GameOver 后确认结束按钮不应继续显示")
	if bool(rewind_cfg.get("visible", true)):
		await _cleanup_panel(panel, st)
		return Result.failure("GameOver 后回退按钮不应继续显示")

	await _cleanup_panel(panel, st)
	return Result.success()

static func _cleanup_panel(panel: Node, st: SceneTree) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	await st.process_frame
