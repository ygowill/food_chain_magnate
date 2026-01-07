# 地图缩放控制组件
# 提供缩放按钮和缩放级别显示
class_name ZoomControl
extends VBoxContainer

signal zoom_in_pressed()
signal zoom_out_pressed()
signal reset_pressed()
signal fit_pressed()

@onready var zoom_in_btn: Button = $ZoomInButton
@onready var zoom_out_btn: Button = $ZoomOutButton
@onready var zoom_label: Label = $ZoomLabel
@onready var reset_btn: Button = $ResetButton
@onready var fit_btn: Button = $FitButton

var _current_zoom: float = 1.0

func _ready() -> void:
	_setup_ui()
	_connect_signals()
	_update_display()

func _setup_ui() -> void:
	# 设置容器属性
	add_theme_constant_override("separation", 4)

	# 创建按钮（如果不存在）
	if zoom_in_btn == null:
		zoom_in_btn = Button.new()
		zoom_in_btn.name = "ZoomInButton"
		zoom_in_btn.text = "+"
		zoom_in_btn.custom_minimum_size = Vector2(32, 32)
		add_child(zoom_in_btn)

	if zoom_label == null:
		zoom_label = Label.new()
		zoom_label.name = "ZoomLabel"
		zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zoom_label.add_theme_font_size_override("font_size", 12)
		add_child(zoom_label)

	if zoom_out_btn == null:
		zoom_out_btn = Button.new()
		zoom_out_btn.name = "ZoomOutButton"
		zoom_out_btn.text = "-"
		zoom_out_btn.custom_minimum_size = Vector2(32, 32)
		add_child(zoom_out_btn)

	if reset_btn == null:
		reset_btn = Button.new()
		reset_btn.name = "ResetButton"
		reset_btn.text = "1:1"
		reset_btn.custom_minimum_size = Vector2(32, 24)
		reset_btn.add_theme_font_size_override("font_size", 10)
		add_child(reset_btn)

	if fit_btn == null:
		fit_btn = Button.new()
		fit_btn.name = "FitButton"
		fit_btn.text = "Fit"
		fit_btn.custom_minimum_size = Vector2(32, 24)
		fit_btn.add_theme_font_size_override("font_size", 10)
		add_child(fit_btn)

func _connect_signals() -> void:
	if is_instance_valid(zoom_in_btn):
		zoom_in_btn.pressed.connect(_on_zoom_in_pressed)
	if is_instance_valid(zoom_out_btn):
		zoom_out_btn.pressed.connect(_on_zoom_out_pressed)
	if is_instance_valid(reset_btn):
		reset_btn.pressed.connect(_on_reset_pressed)
	if is_instance_valid(fit_btn):
		fit_btn.pressed.connect(_on_fit_pressed)

func _update_display() -> void:
	if is_instance_valid(zoom_label):
		zoom_label.text = "%d%%" % int(_current_zoom * 100)

func set_zoom_level(zoom: float) -> void:
	_current_zoom = zoom
	_update_display()

func _on_zoom_in_pressed() -> void:
	zoom_in_pressed.emit()

func _on_zoom_out_pressed() -> void:
	zoom_out_pressed.emit()

func _on_reset_pressed() -> void:
	reset_pressed.emit()

func _on_fit_pressed() -> void:
	fit_pressed.emit()
