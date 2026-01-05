# 决定顺序 smoke test（Headless / Autorun）
extends Control

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("决定顺序测试：验证空余卡槽排序与选择 turn_order 落地。\n")
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
	print("[OrderOfBusinessTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result := OrderOfBusinessTest.run(3, 12345)
	if result.ok:
		output.append_text("PASS\n")
		print("[OrderOfBusinessTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[OrderOfBusinessTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
