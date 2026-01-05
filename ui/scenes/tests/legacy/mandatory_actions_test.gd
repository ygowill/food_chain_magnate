# 强制动作测试场景脚本（M3）
extends Control

const MandatoryActionsTestClass = preload("res://core/tests/mandatory_actions_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("强制动作测试：验证定价经理等员工的强制动作逻辑、阻塞机制。\n")
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
	print("[MandatoryActionsTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result = MandatoryActionsTestClass.run(2, 12345)
	if result.ok:
		var data: Dictionary = result.value if result.value is Dictionary else {}
		output.append_text("PASS\n")
		output.append_text("  pricing_manager mandatory: %s\n" % data.get("pricing_mandatory", false))
		output.append_text("  discount_manager mandatory: %s\n" % data.get("discount_mandatory", false))
		output.append_text("  luxury_manager mandatory: %s\n" % data.get("luxury_mandatory", false))
		output.append_text("  价格修正: %d\n" % data.get("price_modifier_applied", 0))
		print("[MandatoryActionsTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[MandatoryActionsTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
