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

	var compact_title := EmployeeCardClass.new()
	compact_title.variant = EmployeeCard.CardVariant.COMPACT
	compact_title.multiline_name = true
	compact_title.display_scale = 0.5
	compact_title._build_ui()
	if compact_title._name_label == null:
		compact_title.free()
		return Result.failure("Compact 标题标签未创建")
	if compact_title._name_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var name_wrap := compact_title._name_label.autowrap_mode
		compact_title.free()
		return Result.failure("Compact 标题换行模式错误: got=%s expect=%s" % [str(name_wrap), str(TextServer.AUTOWRAP_OFF)])
	if compact_title._name_label.max_lines_visible != 1:
		var max_lines := compact_title._name_label.max_lines_visible
		compact_title.free()
		return Result.failure("Compact 标题最大行数错误: got=%d expect=1" % max_lines)
	if not compact_title._name_label.clip_text:
		compact_title.free()
		return Result.failure("Compact 标题应启用 clip_text")
	var title_font_size := compact_title._name_label.get_theme_font_size("font_size")
	if title_font_size < 9:
		compact_title.free()
		return Result.failure("Compact 标题字号下限错误: got=%d expect>=9" % title_font_size)
	if compact_title._role_color_rect == null:
		compact_title.free()
		return Result.failure("Compact 标题栏未创建")
	if compact_title._role_color_rect.custom_minimum_size.y < 16.0:
		var header_h := compact_title._role_color_rect.custom_minimum_size.y
		compact_title.free()
		return Result.failure("Compact 标题栏高度下限错误: got=%s expect>=16" % str(header_h))
	compact_title.free()

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
