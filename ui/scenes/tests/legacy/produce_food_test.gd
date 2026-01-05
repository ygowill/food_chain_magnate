# 生产食物测试场景脚本（M3）
extends Control

const ProduceFoodTestClass = preload("res://core/tests/produce_food_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("生产食物测试：验证厨师/主厨在 GetFood 子阶段生产食物到库存。\n")
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
	print("[ProduceFoodTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result = ProduceFoodTestClass.run(2, 12345)
	if result.ok:
		var data: Dictionary = result.value if result.value is Dictionary else {}
		output.append_text("PASS\n")
		output.append_text("  最终汉堡库存: %d\n" % data.get("final_burger_inventory", 0))
		output.append_text("  最终披萨库存: %d\n" % data.get("final_pizza_inventory", 0))
		output.append_text("  测试的汉堡厨师: %d\n" % data.get("burger_cooks_tested", 0))
		output.append_text("  测试的汉堡主厨: %d\n" % data.get("burger_chef_tested", 0))
		output.append_text("  测试的披萨厨师: %d\n" % data.get("pizza_cook_tested", 0))
		print("[ProduceFoodTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[ProduceFoodTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
