class_name TutorialFlowHintCard
extends Control

signal dismissed(hint_id: String)
signal disable_requested(hint_id: String)

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")

@onready var panel: PanelContainer = $Panel
@onready var eyebrow_label: Label = $Panel/MarginContainer/VBoxContainer/EyebrowLabel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var where_label: Label = $Panel/MarginContainer/VBoxContainer/WhereLabel
@onready var body_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/BodyLabel
@onready var checklist_title_label: Label = $Panel/MarginContainer/VBoxContainer/ChecklistTitleLabel
@onready var checklist_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/ChecklistLabel
@onready var dismiss_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/DismissButton
@onready var disable_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonRow/DisableButton

var _current_hint_id: String = ""

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 0)
	UiZClass.apply_absolute(self, UiZClass.POPUP)
	UiStylesClass.apply_panel_poster_alt(panel)
	UiStylesClass.apply_label_hint_dark(eyebrow_label)
	UiStylesClass.apply_label_dark(title_label)
	UiStylesClass.apply_label_hint_dark(where_label)
	UiStylesClass.apply_rich_text_dark(body_label)
	UiStylesClass.apply_label_dark(checklist_title_label)
	UiStylesClass.apply_rich_text_dark(checklist_label)
	UiStylesClass.apply_button_primary(dismiss_button)
	UiStylesClass.apply_button_secondary(disable_button)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dismiss_button.pressed.connect(_on_dismiss_pressed)
	disable_button.pressed.connect(_on_disable_pressed)

func show_hint(hint_id: String, title: String, body: String, meta: Dictionary = {}) -> void:
	_current_hint_id = str(hint_id).strip_edges()
	eyebrow_label.text = str(meta.get("eyebrow", "流程提示")).strip_edges()
	title_label.text = str(title).strip_edges()
	body_label.text = str(body).strip_edges()
	_apply_where_text(str(meta.get("where", "")).strip_edges())
	_apply_checklist(meta.get("checklist", []))
	visible = true

func hide_hint() -> void:
	visible = false

func get_current_hint_id() -> String:
	return _current_hint_id

func _on_dismiss_pressed() -> void:
	visible = false
	dismissed.emit(_current_hint_id)

func _on_disable_pressed() -> void:
	visible = false
	disable_requested.emit(_current_hint_id)

func _apply_where_text(where_text: String) -> void:
	if not is_instance_valid(where_label):
		return
	var text := str(where_text).strip_edges()
	where_label.visible = not text.is_empty()
	if where_label.visible:
		where_label.text = "先看：%s" % text

func _apply_checklist(checklist_val) -> void:
	if not is_instance_valid(checklist_title_label) or not is_instance_valid(checklist_label):
		return

	var lines: Array[String] = []
	if checklist_val is Array:
		for item_val in Array(checklist_val):
			var text := str(item_val).strip_edges()
			if not text.is_empty():
				lines.append(text)
	elif checklist_val is String:
		var single := str(checklist_val).strip_edges()
		if not single.is_empty():
			lines.append(single)

	var has_items := not lines.is_empty()
	checklist_title_label.visible = has_items
	checklist_label.visible = has_items
	if not has_items:
		checklist_label.text = ""
		return

	var parts: Array[String] = []
	for i in range(lines.size()):
		parts.append("%d. %s" % [i + 1, lines[i]])
	checklist_label.text = "\n".join(parts)
