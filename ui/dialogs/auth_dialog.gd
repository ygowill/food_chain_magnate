# 认证对话框
# 支持登录、注册、游客绑定邮箱
extends ModalDialogBase

signal auth_completed(result: Dictionary)

enum Tab { LOGIN, REGISTER, BIND }

var _tab: Tab = Tab.LOGIN
var _email_edit: LineEdit
var _password_edit: LineEdit
var _error_label: Label
var _submit_btn: Button
var _tab_bar: TabBar
var _panel: PanelContainer

func _ready() -> void:
	super._ready()
	_build_ui()


func _build_ui() -> void:
	# Overlay
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = overlay_color
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Center panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(400, 0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = -120
	_panel.offset_bottom = 120
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# Tab bar
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("登录")
	_tab_bar.add_tab("注册")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Email
	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = "邮箱"
	vbox.add_child(_email_edit)

	# Password
	_password_edit = LineEdit.new()
	_password_edit.placeholder_text = "密码"
	_password_edit.secret = true
	vbox.add_child(_password_edit)

	# Error label
	_error_label = Label.new()
	_error_label.add_theme_color_override("font_color", Color.RED)
	_error_label.visible = false
	vbox.add_child(_error_label)

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(close)
	hbox.add_child(cancel_btn)

	_submit_btn = Button.new()
	_submit_btn.text = "登录"
	_submit_btn.pressed.connect(_on_submit)
	hbox.add_child(_submit_btn)


func open_for_bind() -> void:
	_tab = Tab.BIND
	_tab_bar.visible = false
	_submit_btn.text = "绑定邮箱"
	_clear_fields()
	open()


func _on_tab_changed(idx: int) -> void:
	_tab = idx as Tab
	_submit_btn.text = "注册" if _tab == Tab.REGISTER else "登录"
	_clear_fields()


func _clear_fields() -> void:
	_email_edit.text = ""
	_password_edit.text = ""
	_error_label.visible = false


func _on_submit() -> void:
	var email := _email_edit.text.strip_edges()
	var password := _password_edit.text
	if email.is_empty() or password.is_empty():
		_show_error("请填写邮箱和密码")
		return
	_submit_btn.disabled = true
	var result: Dictionary
	match _tab:
		Tab.LOGIN:
			result = await PlatformSession.login(email, password)
		Tab.REGISTER:
			result = await PlatformSession.register(email, password)
		Tab.BIND:
			result = await PlatformSession.bind_email(email, password)
	_submit_btn.disabled = false
	if result.has("error"):
		_show_error(str(result["error"]))
		return
	close()
	auth_completed.emit(result)


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
