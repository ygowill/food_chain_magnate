# 全屏加载遮罩（用于长任务期间的视觉反馈）
class_name LoadingOverlay
extends CanvasLayer

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var blocker: Control = $Root/Blocker
@onready var title_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var stage_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/StageLabel
@onready var detail_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/DetailLabel
@onready var progress_bar: ProgressBar = $Root/Center/Panel/MarginContainer/VBoxContainer/ProgressBar
@onready var wait_label: Label = $Root/Center/Panel/MarginContainer/VBoxContainer/WaitLabel

func _ready() -> void:
	visible = false
	UiStylesClass.apply_dialog_surface($Root/Center/Panel)
	if is_instance_valid(blocker):
		# 阻止交互，避免用户在加载期间误触 UI
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP

func show_loading(title: String = "加载中...", detail: String = "", show_progress: bool = false, stage: String = "", wait_text: String = "") -> void:
	visible = true
	if is_instance_valid(title_label):
		title_label.text = title
	set_stage(stage)
	set_detail(detail)
	set_wait_text(wait_text)
	if is_instance_valid(progress_bar):
		progress_bar.visible = show_progress
		if show_progress:
			progress_bar.value = 0.0

func apply_loading_state(state: Dictionary) -> void:
	show_loading(
		str(state.get("title", "加载中...")),
		str(state.get("detail", "")),
		bool(state.get("show_progress", false)),
		str(state.get("stage", "")),
		str(state.get("wait_text", ""))
	)
	if bool(state.get("show_progress", false)):
		set_progress(float(state.get("progress_value", 0.0)), float(state.get("progress_max", 100.0)))

func set_detail(detail: String) -> void:
	if not is_instance_valid(detail_label):
		return
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()

func set_stage(stage: String) -> void:
	if not is_instance_valid(stage_label):
		return
	stage_label.text = stage
	stage_label.visible = not stage.is_empty()

func set_progress(value: float, max_value: float = 100.0) -> void:
	if not is_instance_valid(progress_bar):
		return
	progress_bar.visible = true
	progress_bar.max_value = max_value
	progress_bar.value = clampf(value, progress_bar.min_value, progress_bar.max_value)

func set_wait_text(wait_text: String) -> void:
	if not is_instance_valid(wait_label):
		return
	wait_label.text = wait_text
	wait_label.visible = not wait_text.is_empty()

func hide_loading() -> void:
	visible = false
