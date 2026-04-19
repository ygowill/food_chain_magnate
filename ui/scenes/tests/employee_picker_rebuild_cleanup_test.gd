class_name EmployeePickerRebuildCleanupTest
extends RefCounted

const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 EmployeePicker UI 测试）")
	var st: SceneTree = tree
	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 EmployeePicker）")

	var picker := EmployeePickerClass.new()
	host.add_child(picker)
	await st.process_frame

	picker.set_items([
		{"id": "new_business_developer", "key": "staff:101", "enabled": true},
		{"id": "new_business_developer", "key": "staff:102", "enabled": true},
	], "staff:101")
	if picker.get_child_count() != 2:
		picker.queue_free()
		await st.process_frame
		return Result.failure("EmployeePicker 初次渲染应有 2 个子项，实际: %d" % picker.get_child_count())

	picker.set_items([
		{"id": "new_business_developer", "key": "staff:102", "enabled": true},
	], "staff:102")
	if picker.get_child_count() != 1:
		picker.queue_free()
		await st.process_frame
		return Result.failure("EmployeePicker 重建后不应残留旧子项，期望 1 个，实际: %d" % picker.get_child_count())

	picker.queue_free()
	await st.process_frame
	return Result.success()
