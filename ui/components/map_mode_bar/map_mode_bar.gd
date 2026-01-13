# 地图模式提示条
# 负责在地图交互（选点/工具模式）时提示当前模式与下一步操作。
class_name MapModeBar
extends Control

@onready var title_label: Label = $Bar/MarginContainer/VBoxContainer/TitleLabel
@onready var hint_label: Label = $Bar/MarginContainer/VBoxContainer/HintLabel

func show_mode(title: String, hint: String) -> void:
	if title_label != null:
		title_label.text = title
	if hint_label != null:
		hint_label.text = hint
	visible = true

func hide_mode() -> void:
	visible = false

