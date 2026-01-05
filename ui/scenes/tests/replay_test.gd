# 回放确定性测试场景（可运行 / Headless）
extends Control

const ReplayDeterminismTestClass = preload("res://core/tests/replay_determinism_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("回放确定性测试：生成 20+ 条命令，执行→存档回放→完整重放，比较 state_hash。\n")
	if _should_autorun():
		_exit_code = _run_test()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = _run_test()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_test() -> int:
	output.append_text("\n--- 开始测试 ---\n")
	print("[ReplayTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result := ReplayDeterminismTestClass.run(2, 12345, 20)
	if result.ok:
		var info: Dictionary = result.value
		output.append_text("PASS\n")
		output.append_text("- 玩家数: %d\n" % info.player_count)
		output.append_text("- 种子: %d\n" % info.seed)
		output.append_text("- 命令数: %d\n" % info.command_count)
		output.append_text("- 最终 Hash: %s...\n" % str(info.final_hash).substr(0, 12))
		print("[ReplayTest] PASS seed=%d commands=%d hash=%s" % [info.seed, info.command_count, str(info.final_hash).substr(0, 12)])
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[ReplayTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
