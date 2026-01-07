# Recruit quota sync test（Headless / Autorun）
# 目标：当玩家 A 在 Working/Recruit 用尽招聘额度后 skip，UI 中的 RecruitPanel 必须切换到玩家 B 的额度（不能沿用 A 的 0）。
extends Control

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _game_instance: Node = null

func _ready() -> void:
	if is_instance_valid(output):
		output.clear()
		output.append_text("Recruit quota sync test：A 用尽 → 回到 A → A skip → 面板应显示 B 的额度。\n")
		output.append_text("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")

	if _should_autorun():
		_exit_code = await _run_test()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = await _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_test() -> int:
	if is_instance_valid(output):
		output.append_text("\n--- 开始测试 ---\n")
	print("[RecruitQuotaTurnSyncTest] START args=%s" % str(OS.get_cmdline_user_args()))

	if GameScene == null:
		return await _fail("预加载 game.tscn 失败（PackedScene 为空）")

	var game = GameScene.instantiate()
	if game == null:
		return await _fail("实例化 game.tscn 失败（instantiate 为空）")

	add_child(game)
	_game_instance = game

	# 等待若干帧，确保 game 初始化完成（包括 Globals.current_game_engine 写入）
	await get_tree().process_frame
	await get_tree().process_frame

	if game.game_engine == null:
		return await _fail("game.game_engine 为空（初始化失败或节点结构变更）")

	# 推进到 Working/Recruit（使用 core 工具直接推进引擎状态）
	var adv = TestPhaseUtilsClass.advance_until_phase(game.game_engine, "Working", 80)
	if not adv.ok:
		return await _fail("推进到 Working 失败: %s" % adv.error)
	if game.game_engine.get_state().sub_phase != "Recruit":
		return await _fail("Working 初始子阶段应为 Recruit，实际: %s" % game.game_engine.get_state().sub_phase)

	# 打开招聘面板（保持在屏幕上，模拟玩家持续查看/操作）
	if game.has_method("_show_recruit_panel"):
		game._show_recruit_panel()
	else:
		return await _fail("game 缺少 _show_recruit_panel（脚本接口变更）")

	await get_tree().process_frame

	if not is_instance_valid(game.recruit_panel):
		return await _fail("game.recruit_panel 无效（面板未创建或节点结构变更）")
	if not bool(game.recruit_panel.visible):
		return await _fail("RecruitPanel 未显示（预期为可见）")

	# 让玩家 A 用尽本子阶段招聘额度（每次 recruit 会自动 end_turn，所以通过让 B end_turn 回到 A 循环）
	var state = game.game_engine.get_state()
	var player_a: int = state.get_current_player_id()
	var counts_a = game._compute_recruit_counts(state, player_a)
	var total_a: int = int(counts_a.total)
	if total_a <= 0:
		return await _fail("玩家 A 招聘额度应 > 0，实际: %d" % total_a)

	for _i in range(total_a):
		var r = game._execute_command(Command.create("recruit", player_a, {"employee_type": "waitress"}))
		if not r.ok:
			return await _fail("玩家 A recruit 失败: %s" % r.error)

		# auto end_turn 后应轮到 B；再让 B end_turn 回到 A（保持在 Recruit 子阶段）
		var mid_state = game.game_engine.get_state()
		var player_b: int = mid_state.get_current_player_id()
		if player_b == player_a:
			return await _fail("recruit 后应切到另一位玩家（auto end_turn 预期生效）")

		var et = game._execute_command(Command.create("end_turn", player_b))
		if not et.ok:
			return await _fail("玩家 B end_turn 失败: %s" % et.error)

		var after_et = game.game_engine.get_state()
		if after_et.get_current_player_id() != player_a:
			return await _fail("end_turn 后应回到玩家 A")

	# 此时轮到 A，且 A 的 remaining 应为 0
	state = game.game_engine.get_state()
	var counts_a_after = game._compute_recruit_counts(state, player_a)
	if int(counts_a_after.remaining) != 0:
		return await _fail("玩家 A remaining 应为 0，实际: %d (total=%d used=%d)" % [
			int(counts_a_after.remaining),
			int(counts_a_after.total),
			int(counts_a_after.total) - int(counts_a_after.remaining),
		])

	# A skip（结束招聘）；应切换到 B，且面板同步显示 B 的剩余次数（不能沿用 A 的 0）
	var sk = game._execute_command(Command.create("skip", player_a))
	if not sk.ok:
		return await _fail("玩家 A skip 失败: %s" % sk.error)

	await get_tree().process_frame

	state = game.game_engine.get_state()
	var player_b_final = state.get_current_player_id()
	if player_b_final == player_a:
		return await _fail("skip 后应轮到另一位玩家")

	var expected_b = game._compute_recruit_counts(state, player_b_final)
	var panel_remaining := int(game.recruit_panel.get("_recruit_remaining"))
	var panel_total := int(game.recruit_panel.get("_recruit_total"))

	if panel_remaining != int(expected_b.remaining) or panel_total != int(expected_b.total):
		return await _fail("RecruitPanel 未同步到玩家 B：panel=%d/%d expected=%d/%d" % [
			panel_remaining,
			panel_total,
			int(expected_b.remaining),
			int(expected_b.total),
		])

	if panel_remaining <= 0:
		return await _fail("玩家 B remaining 应 > 0（否则无法招聘），实际: %d/%d" % [panel_remaining, panel_total])

	await _cleanup()

	if is_instance_valid(output):
		output.append_text("PASS\n")
	print("[RecruitQuotaTurnSyncTest] PASS")
	return 0

func _cleanup() -> void:
	if is_instance_valid(_game_instance):
		_game_instance.queue_free()
		_game_instance = null
	await get_tree().process_frame
	Globals.reset_game_config()

func _fail(msg: String) -> int:
	if is_instance_valid(output):
		output.append_text("FAIL: %s\n" % msg)
	push_error("[RecruitQuotaTurnSyncTest] FAIL: %s" % msg)
	print("[RecruitQuotaTurnSyncTest] FAIL: %s" % msg)
	await _cleanup()
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
