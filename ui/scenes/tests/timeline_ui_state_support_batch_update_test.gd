class_name TimelineUiStateSupportBatchUpdateTest
extends RefCounted

const GameTimelineUiStateSupportClass = preload("res://ui/scenes/game/timeline/ui_state_support.gd")

class _BatchPanel:
	extends RefCounted

	var batch_count: int = 0
	var head_count: int = 0
	var cursor_count: int = 0
	var last_update_visible_items: bool = true
	var last_head: int = -999
	var last_cursor: int = -999

	func set_timeline_head_cursor(head_index: int, cursor_index: int, update_visible_items: bool = true) -> void:
		batch_count += 1
		last_head = int(head_index)
		last_cursor = int(cursor_index)
		last_update_visible_items = bool(update_visible_items)

	func set_timeline_head(head_index: int) -> void:
		head_count += 1
		last_head = int(head_index)

	func set_timeline_cursor(cursor_index: int) -> void:
		cursor_count += 1
		last_cursor = int(cursor_index)

class _LegacyPanel:
	extends RefCounted

	var head_count: int = 0
	var cursor_count: int = 0
	var last_head: int = -999
	var last_cursor: int = -999

	func set_timeline_head(head_index: int) -> void:
		head_count += 1
		last_head = int(head_index)

	func set_timeline_cursor(cursor_index: int) -> void:
		cursor_count += 1
		last_cursor = int(cursor_index)

static func run() -> Result:
	var batch_panel := _BatchPanel.new()
	GameTimelineUiStateSupportClass.sync_ui(
		batch_panel,
		null,
		12,
		11,
		null,
		false,
		false,
		false,
		Callable(),
		Callable(),
		Callable()
	)
	if batch_panel.batch_count != 1:
		return Result.failure("支持批量接口时应只调用 1 次 set_timeline_head_cursor，实际=%d" % batch_panel.batch_count)
	if batch_panel.head_count != 0 or batch_panel.cursor_count != 0:
		return Result.failure(
			"支持批量接口时不应回退到旧接口，实际 head=%d cursor=%d"
				% [batch_panel.head_count, batch_panel.cursor_count]
		)
	if batch_panel.last_head != 12 or batch_panel.last_cursor != 11:
		return Result.failure(
			"批量接口参数错误，实际 head=%d cursor=%d"
				% [batch_panel.last_head, batch_panel.last_cursor]
		)
	if not batch_panel.last_update_visible_items:
		return Result.failure("默认 sync_ui 应按可见态刷新 timeline items")

	var legacy_panel := _LegacyPanel.new()
	GameTimelineUiStateSupportClass.sync_ui(
		legacy_panel,
		null,
		7,
		7,
		null,
		false,
		false,
		false,
		Callable(),
		Callable(),
		Callable()
	)
	if legacy_panel.head_count != 1 or legacy_panel.cursor_count != 1:
		return Result.failure(
			"不支持批量接口时应回退到旧接口，实际 head=%d cursor=%d"
				% [legacy_panel.head_count, legacy_panel.cursor_count]
		)
	if legacy_panel.last_head != 7 or legacy_panel.last_cursor != 7:
		return Result.failure(
			"旧接口参数错误，实际 head=%d cursor=%d"
				% [legacy_panel.last_head, legacy_panel.last_cursor]
		)

	return Result.success({})
