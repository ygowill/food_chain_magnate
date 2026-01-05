# 公司结构测试场景脚本（M3）
extends Control

const CompanyStructureTestClass = preload("res://core/tests/company_structure_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("公司结构测试：验证 CEO 卡槽容量限制、唯一员工约束。\n")
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
	print("[CompanyStructureTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result = CompanyStructureTestClass.run(2, 12345)
	if result.ok:
		var data: Dictionary = result.value if result.value is Dictionary else {}
		output.append_text("PASS\n")
		output.append_text("  唯一员工约束测试: %s\n" % ("通过" if data.get("unique_constraint_tested", false) else "未测试"))
		output.append_text("  CEO 卡槽测试: %s\n" % ("通过" if data.get("ceo_slots_tested", false) else "未测试"))
		output.append_text("  正常招聘测试: %s\n" % ("通过" if data.get("normal_recruit_tested", false) else "未测试"))
		print("[CompanyStructureTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[CompanyStructureTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
