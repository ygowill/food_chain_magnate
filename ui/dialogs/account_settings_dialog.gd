# 账号设置对话框
# 正式账号：修改邮箱、修改密码、退出登录
extends ModalDialogBase

signal account_updated
signal logout_requested

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _allow_logout: bool = true
var _logout_hint: String = ""
var _title_label: Label
var _account_summary_label: Label
var _email_edit: LineEdit
var _email_password_edit: LineEdit
var _email_submit_btn: Button
var _password_old_edit: LineEdit
var _password_new_edit: LineEdit
var _password_confirm_edit: LineEdit
var _password_submit_btn: Button
var _status_label: Label
var _logout_hint_label: Label
var _logout_btn: Button
var _close_btn: Button


func _ready() -> void:
	super._ready()
	_build_ui()


func open_for_account(allow_logout: bool, logout_hint: String = "") -> void:
	_allow_logout = bool(allow_logout)
	_logout_hint = str(logout_hint).strip_edges()
	_reset_view_state()
	super.open()


func _build_ui() -> void:
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var dialog_panel := PanelContainer.new()
	dialog_panel.custom_minimum_size = Vector2(520, 0)
	UiStylesClass.apply_dialog_surface(dialog_panel)
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(dialog_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 6)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_right", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	dialog_panel.add_child(outer_margin)

	var inner_border := PanelContainer.new()
	UiStylesClass.apply_poster_inner_border(inner_border)
	outer_margin.add_child(inner_border)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_top", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	inner_border.add_child(content_margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	content_margin.add_child(root)

	_title_label = Label.new()
	_title_label.text = "账号设置"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	UiStylesClass.apply_label_dark(_title_label)
	root.add_child(_title_label)

	var title_line := ColorRect.new()
	title_line.custom_minimum_size = Vector2(220, 2)
	title_line.color = Color(0.73, 0.23, 0.18, 0.5)
	title_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(title_line)

	_account_summary_label = Label.new()
	_account_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UiStylesClass.apply_label_dark(_account_summary_label)
	root.add_child(_account_summary_label)

	root.add_child(_build_email_section())
	root.add_child(_build_password_section())
	root.add_child(_build_logout_section())

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.visible = false
	UiStylesClass.apply_label_hint_dark(_status_label)
	root.add_child(_status_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	root.add_child(button_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)

	_close_btn = Button.new()
	_close_btn.text = "关闭"
	UiStylesClass.apply_button_secondary(_close_btn)
	_close_btn.pressed.connect(_on_close_pressed)
	button_row.add_child(_close_btn)


func _build_email_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "修改邮箱"
	UiStylesClass.apply_label_dark(title)
	section.add_child(title)

	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "请输入新邮箱"
	UiStylesClass.apply_line_edit_field(_email_edit)
	section.add_child(_email_edit)

	_email_password_edit = LineEdit.new()
	_email_password_edit.placeholder_text = "请输入当前密码"
	_email_password_edit.secret = true
	_email_password_edit.secret_character = "*"
	UiStylesClass.apply_line_edit_field(_email_password_edit)
	section.add_child(_email_password_edit)

	_email_submit_btn = Button.new()
	_email_submit_btn.text = "保存邮箱"
	UiStylesClass.apply_button_primary(_email_submit_btn)
	_email_submit_btn.pressed.connect(_on_update_email_pressed)
	section.add_child(_email_submit_btn)

	return section


func _build_password_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "修改密码"
	UiStylesClass.apply_label_dark(title)
	section.add_child(title)

	_password_old_edit = LineEdit.new()
	_password_old_edit.placeholder_text = "请输入旧密码"
	_password_old_edit.secret = true
	_password_old_edit.secret_character = "*"
	UiStylesClass.apply_line_edit_field(_password_old_edit)
	section.add_child(_password_old_edit)

	_password_new_edit = LineEdit.new()
	_password_new_edit.placeholder_text = "请输入新密码"
	_password_new_edit.secret = true
	_password_new_edit.secret_character = "*"
	UiStylesClass.apply_line_edit_field(_password_new_edit)
	section.add_child(_password_new_edit)

	_password_confirm_edit = LineEdit.new()
	_password_confirm_edit.placeholder_text = "请再次输入新密码"
	_password_confirm_edit.secret = true
	_password_confirm_edit.secret_character = "*"
	UiStylesClass.apply_line_edit_field(_password_confirm_edit)
	section.add_child(_password_confirm_edit)

	_password_submit_btn = Button.new()
	_password_submit_btn.text = "保存密码"
	UiStylesClass.apply_button_primary(_password_submit_btn)
	_password_submit_btn.pressed.connect(_on_change_password_pressed)
	section.add_child(_password_submit_btn)

	return section


func _build_logout_section() -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "切换账号"
	UiStylesClass.apply_label_dark(title)
	section.add_child(title)

	_logout_hint_label = Label.new()
	_logout_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UiStylesClass.apply_label_hint_dark(_logout_hint_label)
	section.add_child(_logout_hint_label)

	_logout_btn = Button.new()
	_logout_btn.text = "退出登录"
	UiStylesClass.apply_button_secondary(_logout_btn)
	_logout_btn.pressed.connect(_on_logout_pressed)
	section.add_child(_logout_btn)

	return section


func _reset_view_state() -> void:
	_refresh_account_summary()
	_status_label.visible = false
	_status_label.text = ""
	_email_edit.text = str(PlatformSession.email).strip_edges()
	_email_password_edit.text = ""
	_password_old_edit.text = ""
	_password_new_edit.text = ""
	_password_confirm_edit.text = ""
	_logout_btn.disabled = not _allow_logout
	if _allow_logout:
		_logout_hint_label.text = "退出后可重新登录其他账号。"
	else:
		_logout_hint_label.text = _logout_hint if not _logout_hint.is_empty() else "请先离开房间后再退出登录。"


func _refresh_account_summary() -> void:
	var email_text := str(PlatformSession.email).strip_edges()
	if email_text.is_empty():
		email_text = "未绑定"
	_account_summary_label.text = "当前昵称：%s\n账号类型：正式\n当前邮箱：%s\n邮箱状态：%s" % [
		str(PlatformSession.display_name).strip_edges(),
		email_text,
		_get_email_status_text(),
	]


func _get_email_status_text() -> String:
	var bound_email := str(PlatformSession.email).strip_edges()
	if bound_email.is_empty():
		return "未绑定"
	if PlatformSession.email_verification_pending:
		return "待验证"
	return "已绑定"


func _set_busy(busy: bool) -> void:
	_email_edit.editable = not busy
	_email_password_edit.editable = not busy
	_password_old_edit.editable = not busy
	_password_new_edit.editable = not busy
	_password_confirm_edit.editable = not busy
	_email_submit_btn.disabled = busy
	_password_submit_btn.disabled = busy
	_logout_btn.disabled = busy or not _allow_logout
	_close_btn.disabled = busy


func _show_status(text: String, is_error: bool = false) -> void:
	_status_label.text = str(text).strip_edges()
	_status_label.visible = not _status_label.text.is_empty()
	if is_error:
		UiStylesClass.apply_label_error(_status_label)
	else:
		UiStylesClass.apply_label_hint_dark(_status_label)


func _on_update_email_pressed() -> void:
	var target_email := _email_edit.text.strip_edges()
	var password := _email_password_edit.text
	if target_email.is_empty():
		_show_status("邮箱不能为空。", true)
		return
	if not "@" in target_email:
		_show_status("请输入有效的邮箱地址。", true)
		return
	if password.is_empty():
		_show_status("请输入当前密码。", true)
		return
	_set_busy(true)
	var result: Dictionary = await PlatformSession.update_email(target_email, password)
	_set_busy(false)
	if result.has("error"):
		_show_status(_extract_error_text(result), true)
		return
	_email_password_edit.text = ""
	_refresh_account_summary()
	_show_status("邮箱已更新。")
	account_updated.emit()


func _on_change_password_pressed() -> void:
	var old_password := _password_old_edit.text
	var new_password := _password_new_edit.text
	var confirm_password := _password_confirm_edit.text
	if old_password.is_empty():
		_show_status("请输入旧密码。", true)
		return
	if new_password.is_empty():
		_show_status("新密码不能为空。", true)
		return
	if new_password != confirm_password:
		_show_status("两次输入的新密码不一致。", true)
		return
	_set_busy(true)
	var result: Dictionary = await PlatformSession.change_password(old_password, new_password)
	_set_busy(false)
	if result.has("error"):
		_show_status(_extract_error_text(result), true)
		return
	_password_old_edit.text = ""
	_password_new_edit.text = ""
	_password_confirm_edit.text = ""
	_show_status("密码已更新。")


func _on_logout_pressed() -> void:
	if not _allow_logout:
		_show_status(_logout_hint_label.text, true)
		return
	_set_busy(true)
	await PlatformSession.logout()
	_set_busy(false)
	close()
	logout_requested.emit()


func _on_close_pressed() -> void:
	close()


func _extract_error_text(result: Dictionary) -> String:
	var err_val = result.get("error", null)
	if err_val is Dictionary:
		var err: Dictionary = Dictionary(err_val)
		var detail_val = err.get("detail", null)
		if detail_val is Dictionary:
			var detail: Dictionary = Dictionary(detail_val)
			var message := str(detail.get("message", "")).strip_edges()
			if not message.is_empty():
				return message
		elif detail_val != null:
			var detail_text := str(detail_val).strip_edges()
			if not detail_text.is_empty():
				return detail_text
		if err.has("body"):
			var body_text := str(err.get("body", "")).strip_edges()
			if not body_text.is_empty():
				return body_text
		if err.has("detail"):
			var raw_detail := str(err.get("detail", "")).strip_edges()
			if not raw_detail.is_empty():
				return raw_detail
		var fallback := str(err).strip_edges()
		if not fallback.is_empty():
			return fallback
	return "操作失败"


func _grab_default_focus() -> void:
	if _email_edit != null and is_instance_valid(_email_edit):
		_email_edit.grab_focus()
