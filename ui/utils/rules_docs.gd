# 规则书查看入口（游戏内阅读）
# - 规则页图位于 res://assets/rules/pages/...
# - 标签/页数索引位于 res://assets/rules/rules_index.json
class_name RulesDocs
extends RefCounted

const RulesViewerDialogScene: PackedScene = preload("res://ui/dialogs/rules_viewer_dialog.tscn")
const InfoDialogClass = preload("res://ui/dialogs/info_dialog.gd")

static func show_rules_dialog(parent: Node, book_id: String = "base", page: int = 1) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if OS.has_feature("headless"):
		return

	if RulesViewerDialogScene == null:
		_show_error(parent, "规则", "无法创建规则查看面板（RulesViewerDialogScene 为空）。")
		return

	# 尝试复用已存在的查看面板（避免重复打开多个）
	for ch in parent.get_children():
		if ch == null or not is_instance_valid(ch):
			continue
		if ch is RulesViewerDialog:
			var existing: RulesViewerDialog = ch
			existing.open_for_book(book_id, page)
			return

	var dlg_val := RulesViewerDialogScene.instantiate()
	var dlg := dlg_val as RulesViewerDialog
	if dlg == null:
		if dlg_val != null:
			dlg_val.queue_free()
		_show_error(parent, "规则", "无法创建规则查看面板（类型不匹配）。")
		return

	parent.add_child(dlg)
	dlg.open_for_book(book_id, page)


static func _show_error(parent: Node, title_text: String, message: String) -> void:
	if OS.has_feature("headless"):
		return
	if parent == null or not is_instance_valid(parent):
		return
	if InfoDialogClass == null:
		push_warning("%s: %s" % [str(title_text), str(message)])
		return

	var dlg := InfoDialogClass.new()
	if dlg == null:
		push_warning("%s: %s" % [str(title_text), str(message)])
		return

	parent.add_child(dlg)
	if dlg.has_signal("closed"):
		dlg.closed.connect(func() -> void:
			if is_instance_valid(dlg):
				dlg.queue_free()
		)
	if dlg.has_method("show_info"):
		dlg.show_info(title_text, message, Vector2i(560, 320), "确定")
