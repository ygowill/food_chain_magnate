class_name GameOverlayFirstHave20PopupTest
extends RefCounted

const OverlayControllerClass = preload("res://ui/scenes/game/overlay/controller.gd")

class OverlayPopupHost:
	extends Control

	var game_engine = null
	var shown_focus_ids: Array[int] = []

	func show_reserve_cards_overview(focus_player_id: int = -1) -> void:
		shown_focus_ids.append(focus_player_id)

static func run(seed_val: int = 12345) -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var parent := st.current_scene
	if parent == null or not is_instance_valid(parent):
		return Result.failure("current_scene 为空（无法挂载 overlay host）")

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, null, engine)

	var state := engine.get_state()
	if state == null:
		return _finish(Result.failure("state 为空"), null, null, engine)

	state.players[0]["can_peek_all_reserve_cards"] = true

	var host := OverlayPopupHost.new()
	host.game_engine = engine
	parent.add_child(host)
	await st.process_frame

	var overlay = OverlayControllerClass.new(host, null, null, null)
	if overlay == null:
		return _finish(Result.failure("实例化 GameOverlayController 失败"), overlay, host, engine)

	overlay.call("_maybe_show_milestone_reward_view", 0, "first_have_20")
	await st.process_frame
	if host.shown_focus_ids.size() != 1 or int(host.shown_focus_ids[0]) != 0:
		return _finish(Result.failure("first_have_20 应自动打开储备卡总览，实际: %s" % str(host.shown_focus_ids)), overlay, host, engine)

	overlay.call("_maybe_show_milestone_reward_view", 0, "first_have_100")
	await st.process_frame
	if host.shown_focus_ids.size() != 1:
		return _finish(Result.failure("非 first_have_20 里程碑不应打开储备卡总览，实际: %s" % str(host.shown_focus_ids)), overlay, host, engine)

	return _finish(Result.success({}), overlay, host, engine)

static func _finish(result: Result, overlay, host, engine) -> Result:
	if overlay != null and overlay.has_method("dispose"):
		overlay.dispose()
	if host != null and is_instance_valid(host):
		host.queue_free()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
