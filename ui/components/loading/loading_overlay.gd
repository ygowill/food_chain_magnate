# 全屏加载遮罩（用于长任务期间的视觉反馈）
class_name LoadingOverlay
extends CanvasLayer

@onready var blocker: Control = $Root/Blocker
@onready var title_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var detail_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/DetailLabel
@onready var progress_bar: ProgressBar = $Root/Center/Panel/MarginContainer/VBoxContainer/ProgressBar

func _ready() -> void:
	visible = false
	if is_instance_valid(blocker):
		# 阻止交互，避免用户在加载期间误触 UI
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP

func show_loading(title: String = "加载中...", detail: String = "", show_progress: bool = false) -> void:
	visible = true
	if is_instance_valid(title_label):
		title_label.text = title
	set_detail(detail)
	if is_instance_valid(progress_bar):
		progress_bar.visible = show_progress
		if show_progress:
			progress_bar.value = 0.0

func set_detail(detail: String) -> void:
	if not is_instance_valid(detail_label):
		return
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()

func set_progress(value: float, max_value: float = 100.0) -> void:
	if not is_instance_valid(progress_bar):
		return
	progress_bar.visible = true
	progress_bar.max_value = max_value
	progress_bar.value = clampf(value, progress_bar.min_value, progress_bar.max_value)

func hide_loading() -> void:
	visible = false

