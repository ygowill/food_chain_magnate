class_name EmployeeCardDescriptionWrapTest
extends RefCounted

const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")

static func run() -> Result:
	var compact := EmployeeCardClass.new()
	compact.variant = EmployeeCard.CardVariant.COMPACT
	compact._build_ui()
	if compact._description_label == null:
		compact.free()
		return Result.failure("Compact 卡片未创建描述标签")
	if compact._description_label.autowrap_mode != TextServer.AUTOWRAP_ARBITRARY:
		var got := compact._description_label.autowrap_mode
		compact.free()
		return Result.failure("Compact 描述换行模式错误: got=%s expect=%s" % [str(got), str(TextServer.AUTOWRAP_ARBITRARY)])
	if not compact._description_label.clip_text:
		compact.free()
		return Result.failure("Compact 描述应启用 clip_text，避免导出端横向溢出")
	if compact._description_label.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
		compact.free()
		return Result.failure("Compact 描述应水平填充卡片宽度")
	if not compact.clip_contents:
		compact.free()
		return Result.failure("EmployeeCard 应启用 clip_contents，避免导出端文本绘制越界")
	compact.free()

	var full := EmployeeCardClass.new()
	full.variant = EmployeeCard.CardVariant.FULL
	full._build_ui()
	if full._description_label == null:
		full.free()
		return Result.failure("Full 卡片未创建描述标签")
	if full._description_label.autowrap_mode != TextServer.AUTOWRAP_WORD_SMART:
		var got_full := full._description_label.autowrap_mode
		full.free()
		return Result.failure("Full 描述换行模式错误: got=%s expect=%s" % [str(got_full), str(TextServer.AUTOWRAP_WORD_SMART)])
	full.free()

	return Result.success()
