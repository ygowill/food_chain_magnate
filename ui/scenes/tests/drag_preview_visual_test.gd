# 重组阶段拖拽预览卡不变形（UI 属性测试）
# 覆盖 issue_tracker #24：鼠标跟随的预览卡应维持缩略卡片的尺寸/样式。
class_name DragPreviewVisualTest
extends RefCounted

const HandAreaClass = preload("res://ui/components/hand_area/hand_area.gd")
const CompanyStructureClass = preload("res://ui/components/company_structure/company_structure.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")

static func run() -> Result:
	var hand_area := HandAreaClass.new()

	var source := EmployeeCardClass.new()
	source.variant = EmployeeCard.CardVariant.COMPACT
	source.display_scale = 1.0
	source.setup({"id": "cfo", "name": "CFO", "role": "special"})
	# 用非默认尺寸模拟“缩略卡片”布局（用于捕获 _ready 重置尺寸的回归）。
	source.custom_minimum_size = Vector2(100, 70)
	source.size = Vector2(100, 70)

	hand_area._start_drag_visuals("cfo", source)

	var preview = hand_area._drag_preview
	var r := _assert_preview_matches_source("HandArea", preview, source)
	hand_area._end_drag_visuals()
	source.free()
	hand_area.free()
	if not r.ok:
		return r

	var company := CompanyStructureClass.new()

	var source2 := EmployeeCardClass.new()
	source2.variant = EmployeeCard.CardVariant.COMPACT
	source2.display_scale = 1.0
	source2.setup({"id": "cfo", "name": "CFO", "role": "special"})
	source2.custom_minimum_size = Vector2(100, 70)
	source2.size = Vector2(100, 70)

	company._start_drag_visuals("cfo", source2)
	var preview2 = company._drag_preview
	var r2 := _assert_preview_matches_source("CompanyStructure", preview2, source2)
	company._end_drag_visuals()
	source2.free()
	company.free()

	return r2

static func _assert_preview_matches_source(label: String, preview, source: EmployeeCard) -> Result:
	if preview == null or not is_instance_valid(preview):
		return Result.failure("%s: drag_preview 未创建" % label)
	if preview.scale != Vector2.ONE:
		return Result.failure("%s: drag_preview.scale=%s (期望 %s)" % [label, str(preview.scale), str(Vector2.ONE)])
	if preview.variant != source.variant:
		return Result.failure("%s: drag_preview.variant=%s (期望 %s)" % [label, str(preview.variant), str(source.variant)])
	if not is_equal_approx(float(preview.display_scale), float(source.display_scale)):
		return Result.failure("%s: drag_preview.display_scale=%s (期望 %s)" % [label, str(preview.display_scale), str(source.display_scale)])
	if preview.custom_minimum_size != source.custom_minimum_size:
		return Result.failure("%s: drag_preview.custom_minimum_size=%s (期望 %s)" % [label, str(preview.custom_minimum_size), str(source.custom_minimum_size)])
	if preview.size != source.size:
		return Result.failure("%s: drag_preview.size=%s (期望 %s)" % [label, str(preview.size), str(source.size)])
	return Result.success({})
