# 初始公司结构测试场景脚本（M3）
extends Control

const InitialCompanyTestClass = preload("res://core/tests/initial_company_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("初始公司结构测试：验证玩家初始 CEO、薪资逻辑、招聘额度。\n")
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
	print("[InitialCompanyTest] START args=%s" % str(OS.get_cmdline_user_args()))

	var result = InitialCompanyTestClass.run(2, 12345)
	if result.ok:
		var data: Dictionary = result.value if result.value is Dictionary else {}
		output.append_text("PASS\n")
		output.append_text("  员工定义数量: %d\n" % data.get("employee_count", 0))
		output.append_text("  CEO 需要薪水: %s\n" % data.get("ceo_salary", true))
		print("[InitialCompanyTest] PASS")
		return 0

	output.append_text("FAIL: %s\n" % result.error)
	push_error("[InitialCompanyTest] FAIL: %s" % result.error)
	return 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
