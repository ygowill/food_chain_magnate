# 认证对话框
# 支持登录、注册、游客绑定邮箱
extends ModalDialogBase

signal auth_completed(result: Dictionary)

enum Tab { LOGIN, REGISTER, BIND }

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

var _tab: Tab = Tab.LOGIN
var _dialog_panel: PanelContainer
var _inner_border: PanelContainer
var _title_label: Label
var _tab_bar: TabBar
var _email_edit: LineEdit
var _password_edit: LineEdit
var _confirm_edit: LineEdit
var _confirm_group: VBoxContainer
var _error_label: Label
var _submit_btn: Button
var _cancel_btn: Button
var _browser_btn: Button
var _device_auth_group: VBoxContainer
var _device_status_label: Label
var _device_cancel_btn: Button
var _form_group: VBoxContainer

func _ready() -> void:
	super._ready()
	_build_ui()


func _build_ui() -> void:
	# Overlay
	var overlay_rect := ColorRect.new()
	overlay_rect.name = "Overlay"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	overlay_rect.color = overlay_color
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay_rect)

	# Center
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Dialog panel
	_dialog_panel = PanelContainer.new()
	_dialog_panel.custom_minimum_size = Vector2(460, 0)
	UiStylesClass.apply_dialog_surface(_dialog_panel)
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_dialog_panel)

	# Outer margin
	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 6)
	outer_margin.add_theme_constant_override("margin_top", 6)
	outer_margin.add_theme_constant_override("margin_right", 6)
	outer_margin.add_theme_constant_override("margin_bottom", 6)
	_dialog_panel.add_child(outer_margin)

	# Inner border
	_inner_border = PanelContainer.new()
	UiStylesClass.apply_poster_inner_border(_inner_border)
	outer_margin.add_child(_inner_border)

	# Content margin
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_top", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_bottom", 24)
	_inner_border.add_child(content_margin)

	# Root layout
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	content_margin.add_child(root)

	# 标题
	_title_label = Label.new()
	_title_label.text = "账户"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	UiStylesClass.apply_label_dark(_title_label)
	root.add_child(_title_label)

	# 装饰线
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(200, 2)
	line.color = Color(0.73, 0.23, 0.18, 0.5)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(line)

	# 浏览器登录按钮（仅原生平台显示）
	_browser_btn = Button.new()
	_browser_btn.text = "在浏览器中登录/注册"
	_browser_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_button_secondary(_browser_btn)
	_browser_btn.pressed.connect(_on_browser_login)
	root.add_child(_browser_btn)

	# 设备授权等待区域（默认隐藏）
	_device_auth_group = VBoxContainer.new()
	_device_auth_group.add_theme_constant_override("separation", 10)
	_device_auth_group.visible = false
	root.add_child(_device_auth_group)

	_device_status_label = Label.new()
	_device_status_label.text = "已在浏览器中打开，请完成登录..."
	_device_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStylesClass.apply_label_dark(_device_status_label)
	_device_auth_group.add_child(_device_status_label)

	_device_cancel_btn = Button.new()
	_device_cancel_btn.text = "取消"
	_device_cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiStylesClass.apply_button_secondary(_device_cancel_btn)
	_device_cancel_btn.pressed.connect(_on_device_cancel)
	_device_auth_group.add_child(_device_cancel_btn)

	# 分隔线
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.73, 0.23, 0.18, 0.3)
	root.add_child(sep)

	# Web 平台：隐藏浏览器登录相关 UI（认证由 Vue SPA 处理）
	if OS.get_name() == "Web":
		_browser_btn.visible = false
		sep.visible = false

	# 表单区域
	_form_group = VBoxContainer.new()
	_form_group.add_theme_constant_override("separation", 14)
	root.add_child(_form_group)

	# Tab bar
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("登录")
	_tab_bar.add_tab("注册")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	_apply_tab_bar_style()
	_form_group.add_child(_tab_bar)

	# 邮箱
	var email_group := VBoxContainer.new()
	email_group.add_theme_constant_override("separation", 4)
	_form_group.add_child(email_group)

	var email_label := Label.new()
	email_label.text = "邮箱"
	UiStylesClass.apply_label_dark(email_label)
	email_group.add_child(email_label)

	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "请输入邮箱地址"
	_email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_email_edit)
	email_group.add_child(_email_edit)

	# 密码
	var pw_group := VBoxContainer.new()
	pw_group.add_theme_constant_override("separation", 4)
	_form_group.add_child(pw_group)

	var pw_label := Label.new()
	pw_label.text = "密码"
	UiStylesClass.apply_label_dark(pw_label)
	pw_group.add_child(pw_label)

	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "请输入密码"
	_password_edit.secret = true
	_password_edit.secret_character = "*"
	_password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_password_edit)
	pw_group.add_child(_password_edit)

	# 确认密码（注册/绑定时显示）
	_confirm_group = VBoxContainer.new()
	_confirm_group.add_theme_constant_override("separation", 4)
	_confirm_group.visible = false
	_form_group.add_child(_confirm_group)

	var confirm_label := Label.new()
	confirm_label.text = "确认密码"
	UiStylesClass.apply_label_dark(confirm_label)
	_confirm_group.add_child(confirm_label)

	_confirm_edit = LineEdit.new()
	_confirm_edit.placeholder_text = "请再次输入密码"
	_confirm_edit.secret = true
	_confirm_edit.secret_character = "*"
	_confirm_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesClass.apply_line_edit_field(_confirm_edit)
	_confirm_group.add_child(_confirm_edit)

	# 错误标签
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_error_label.visible = false
	UiStylesClass.apply_label_error(_error_label)
	_form_group.add_child(_error_label)

	# 按钮行
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	_form_group.add_child(btn_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_cancel_btn = Button.new()
	_cancel_btn.text = "取消"
	UiStylesClass.apply_button_secondary(_cancel_btn)
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	_submit_btn = Button.new()
	_submit_btn.text = "登录"
	UiStylesClass.apply_button_primary(_submit_btn)
	_submit_btn.pressed.connect(_on_submit)
	btn_row.add_child(_submit_btn)


func _apply_tab_bar_style() -> void:
	var unselected := StyleBoxFlat.new()
	unselected.bg_color = UiStylesClass.COLOR_FIELD_BG
	unselected.border_color = UiStylesClass.COLOR_FIELD_BORDER
	unselected.set_border_width_all(1)
	unselected.set_corner_radius_all(4)
	unselected.content_margin_left = 12
	unselected.content_margin_top = 6
	unselected.content_margin_right = 12
	unselected.content_margin_bottom = 6

	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(0.97, 0.94, 0.86, 0.98)
	selected.border_color = UiStylesClass.COLOR_FIELD_BORDER_FOCUS
	selected.set_border_width_all(2)
	selected.set_corner_radius_all(4)
	selected.content_margin_left = 12
	selected.content_margin_top = 6
	selected.content_margin_right = 12
	selected.content_margin_bottom = 6

	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(0.97, 0.94, 0.86, 0.98)
	hovered.border_color = UiStylesClass.COLOR_FIELD_BORDER
	hovered.set_border_width_all(1)
	hovered.set_corner_radius_all(4)
	hovered.content_margin_left = 12
	hovered.content_margin_top = 6
	hovered.content_margin_right = 12
	hovered.content_margin_bottom = 6

	_tab_bar.add_theme_stylebox_override("tab_unselected", unselected)
	_tab_bar.add_theme_stylebox_override("tab_selected", selected)
	_tab_bar.add_theme_stylebox_override("tab_hovered", hovered)
	_tab_bar.add_theme_color_override("font_selected_color", UiStylesClass.COLOR_TEXT_PRIMARY)
	_tab_bar.add_theme_color_override("font_unselected_color", UiStylesClass.COLOR_TEXT_MUTED)
	_tab_bar.add_theme_color_override("font_hovered_color", UiStylesClass.COLOR_TEXT_PRIMARY)


func open_for_bind() -> void:
	_tab = Tab.BIND
	_tab_bar.visible = false
	_title_label.text = "绑定邮箱"
	_submit_btn.text = "绑定"
	_confirm_group.visible = true
	_clear_fields()
	open()


func _on_tab_changed(idx: int) -> void:
	_tab = idx as Tab
	if _tab == Tab.REGISTER:
		_submit_btn.text = "注册"
		_confirm_group.visible = true
	else:
		_submit_btn.text = "登录"
		_confirm_group.visible = false
	_clear_fields()


func _on_cancel() -> void:
	PlatformSession.cancel_device_auth()
	close()


func _clear_fields() -> void:
	_email_edit.text = ""
	_password_edit.text = ""
	_confirm_edit.text = ""
	_error_label.visible = false


func _on_submit() -> void:
	var email := _email_edit.text.strip_edges()
	var password := _password_edit.text
	if email.is_empty() or password.is_empty():
		_show_error("请填写邮箱和密码")
		return
	if not "@" in email:
		_show_error("请输入有效的邮箱地址")
		return
	if _tab != Tab.LOGIN:
		if password != _confirm_edit.text:
			_show_error("两次输入的密码不一致")
			return
	_set_submitting(true)
	var result: Dictionary
	match _tab:
		Tab.LOGIN:
			result = await PlatformSession.login(email, password)
		Tab.REGISTER:
			result = await PlatformSession.register(email, password)
		Tab.BIND:
			result = await PlatformSession.bind_email(email, password)
	_set_submitting(false)
	if result.has("error"):
		_show_error(_extract_error_text(result))
		return
	close()
	auth_completed.emit(result)


func _set_submitting(submitting: bool) -> void:
	_submit_btn.disabled = submitting
	_cancel_btn.disabled = submitting
	_email_edit.editable = not submitting
	_password_edit.editable = not submitting
	_confirm_edit.editable = not submitting
	_submit_btn.text = "请稍候..." if submitting else _get_submit_text()


func _get_submit_text() -> String:
	match _tab:
		Tab.REGISTER: return "注册"
		Tab.BIND: return "绑定"
		_: return "登录"


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true


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
	return str(err_val)


func _on_browser_login() -> void:
	_browser_btn.visible = false
	_form_group.visible = false
	_device_auth_group.visible = true
	_device_status_label.text = "已在浏览器中打开，请完成登录..."
	var result: Dictionary = await PlatformSession.start_device_auth()
	_device_auth_group.visible = false
	_browser_btn.visible = true
	_form_group.visible = true
	if result.has("ok"):
		close()
		auth_completed.emit(result["ok"])
	elif result.get("error", "") == "expired":
		_show_error("设备码已过期，请重试")
	elif result.get("error", "") != "cancelled":
		_show_error("浏览器登录失败")


func _on_device_cancel() -> void:
	PlatformSession.cancel_device_auth()


func _grab_default_focus() -> void:
	if _email_edit != null and is_instance_valid(_email_edit):
		_email_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
			_on_cancel()
			get_viewport().set_input_as_handled()
