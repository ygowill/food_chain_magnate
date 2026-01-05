# 采购饮料测试场景脚本（M3）
extends Control

const ProcureDrinksTestClass = preload("res://core/tests/procure_drinks_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("采购饮料测试：验证卡车司机/飞艇驾驶员在 GetDrinks 子阶段采购饮料到库存。\n")
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
	print("[ProcureDrinksTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result = ProcureDrinksTestClass.run(2, 12345)
	if result.ok:
		var data: Dictionary = result.value if result.value is Dictionary else {}
		output.append_text("PASS\n")
		output.append_text("  饮料源数量: %d\n" % data.get("drink_sources_count", 0))
		output.append_text("  饮料类型: %s\n" % data.get("drink_type", ""))
		output.append_text("  最终饮料库存: %d\n" % data.get("final_drink_inventory", 0))
		output.append_text("  飞艇驾驶员测试: %s\n" % ("通过" if data.get("zeppelin_tested", false) else "未测试"))
		output.append_text("  卡车司机测试: %s\n" % ("通过" if data.get("truck_tested", false) else "未测试"))
		print("[ProcureDrinksTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[ProcureDrinksTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
