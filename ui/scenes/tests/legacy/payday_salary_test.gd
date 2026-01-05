# 发薪日薪水扣除测试场景（Headless / Autorun）
extends Control

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("发薪日测试：验证进入 Payday 时的薪水扣除与银行对冲。\n")
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
	print("[PaydaySalaryTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result := PaydaySalaryTest.run(2, 12345)
	if result.ok:
		output.append_text("PASS\n")
		print("[PaydaySalaryTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[PaydaySalaryTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
