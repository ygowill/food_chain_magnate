class_name CreateRoomResumeLogHistoryBuilderTest
extends RefCounted

const ResumeLogHistoryBuilderClass = preload("res://ui/dialogs/create_room_resume_log_history_builder.gd")

const SAVE_RES_PATH := "res://testdata/saves/manual_cases/logs/event_log_review.json"

class _SilentEventSink:
	extends RefCounted

	func emit_event(_event_type: String, _data: Dictionary) -> void:
		pass

	func clear_history_and_reset_sequence() -> void:
		pass

	func clear_history() -> void:
		pass

	func record_event(_event_type: String, _data: Dictionary) -> void:
		pass

static func run() -> Result:
	var abs_path := ProjectSettings.globalize_path(SAVE_RES_PATH)
	var engine := GameEngine.new()
	if engine.has_method("set_event_sink"):
		engine.set_event_sink(_SilentEventSink.new())
	var load_r: Result = engine.load_from_file(abs_path)
	if not load_r.ok:
		return Result.failure("load failed: %s" % load_r.error)
	if engine.get_state() == null:
		return Result.failure("load succeeded but state is null")
	if engine.command_history.size() < 2:
		return Result.failure("expected at least 2 commands in %s" % SAVE_RES_PATH)

	var max_index := int(engine.command_history.size()) - 1
	var selected_index := maxi(0, int(floor(float(engine.command_history.size()) / 2.0)) - 1)
	if selected_index >= max_index:
		return Result.failure("selected_index should be earlier than max_index: selected=%d max=%d" % [selected_index, max_index])

	var rewind_r: Result = engine.rewind_to_command(selected_index)
	if not rewind_r.ok:
		return Result.failure("rewind failed: %s" % rewind_r.error)

	var build_r: Result = ResumeLogHistoryBuilderClass.new().build(engine, selected_index)
	if not build_r.ok:
		return Result.failure("build failed: %s" % build_r.error)
	var data_val = build_r.value
	if not (data_val is Dictionary):
		return Result.failure("build.value type error (expected Dictionary)")
	var data: Dictionary = data_val

	var items_val = data.get("items", null)
	if not (items_val is Array):
		return Result.failure("items type error (expected Array)")
	var items: Array = items_val
	if items.is_empty():
		return Result.failure("items should not be empty")

	var prev_command_index := -999999
	var has_log_item := false
	for item_val in items:
		if not (item_val is Dictionary):
			return Result.failure("item type error (expected Dictionary): %s" % str(item_val))
		var item: Dictionary = item_val
		var command_index := int(item.get("command_index", -999999))
		if command_index < prev_command_index:
			return Result.failure("command_index should be monotonic non-decreasing: prev=%d cur=%d" % [prev_command_index, command_index])
		prev_command_index = command_index
		var display_text := str(item.get("display_text", "")).strip_edges()
		if display_text.is_empty():
			return Result.failure("item.display_text should not be empty: %s" % str(item))
		if bool(item.get("is_log", false)):
			has_log_item = true
	if not has_log_item:
		return Result.failure("expected at least one log item in resume history")

	var original_item_index := int(data.get("original_item_index", -1))
	if original_item_index < 0 or original_item_index >= items.size():
		return Result.failure("original_item_index out of range: %d (items=%d)" % [original_item_index, items.size()])
	var original_item: Dictionary = items[original_item_index]
	if int(original_item.get("command_index", -999999)) != selected_index:
		return Result.failure("original item command_index mismatch: %d vs %d" % [int(original_item.get("command_index", -999999)), selected_index])
	if not _item_has_tag(original_item, "原存档点"):
		return Result.failure("original item missing 原存档点 tag: %s" % str(original_item))

	var full_history_item_index := int(data.get("full_history_item_index", -1))
	if full_history_item_index < 0 or full_history_item_index >= items.size():
		return Result.failure("full_history_item_index out of range: %d (items=%d)" % [full_history_item_index, items.size()])
	var full_history_item: Dictionary = items[full_history_item_index]
	if int(full_history_item.get("command_index", -999999)) != max_index:
		return Result.failure("full history item command_index mismatch: %d vs %d" % [int(full_history_item.get("command_index", -999999)), max_index])
	if not _item_has_tag(full_history_item, "完整历史末尾"):
		return Result.failure("full history item missing 完整历史末尾 tag: %s" % str(full_history_item))

	if int(data.get("selected_item_index", -1)) != original_item_index:
		return Result.failure("selected_item_index should point to original_item_index")

	return Result.success({
		"items": items.size(),
		"selected_index": selected_index,
		"max_index": max_index,
	})

static func _item_has_tag(item: Dictionary, expected_tag: String) -> bool:
	var tags_val = item.get("tags", null)
	if not (tags_val is Array):
		return false
	for tag_val in tags_val:
		if str(tag_val).strip_edges() == expected_tag:
			return true
	return false
