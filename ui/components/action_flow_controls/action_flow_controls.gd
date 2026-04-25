# 动作流控制条（右侧底部常驻）
# - 展示“确认结束(仅当无动作可做)”/“跳过当前动作(子阶段)”/“回退到回合开始”
# - 由 ActionPanel 计算可见性与可用性，GamePanelController 同步本控件
class_name ActionFlowControls
extends VBoxContainer

signal action_requested(action_id: String, params: Dictionary)

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

@onready var confirm_end_button: Button = $ConfirmEndButton
@onready var skip_step_button: Button = $SkipStepButton
@onready var rewind_button: Button = $RewindButton

var _confirm_end_disabled_reason: String = ""
var _skip_step_disabled_reason: String = ""
var _confirm_end_action_id: String = "skip"
var _skip_step_action_id: String = "skip_sub_phase"
var _rewind_action_id: String = "rewind_to_turn_start"
var _last_flow_config_signature: Dictionary = {}
var _has_applied_flow_config_signature: bool = false
var _flow_config_apply_count: int = 0

func _ready() -> void:
	_build_ui()
	_connect_signals()

func _build_ui() -> void:
	if is_instance_valid(confirm_end_button):
		UiStylesClass.apply_button_primary(confirm_end_button)
	if is_instance_valid(skip_step_button):
		UiStylesClass.apply_button_secondary(skip_step_button)
	if is_instance_valid(rewind_button):
		UiStylesClass.apply_button_secondary(rewind_button)

func _connect_signals() -> void:
	if is_instance_valid(confirm_end_button):
		UiSignalHelpersClass.safe_connect(confirm_end_button, "pressed", _on_confirm_end_pressed)
		UiSignalHelpersClass.safe_connect(confirm_end_button, "mouse_entered", _on_confirm_end_mouse_entered)
		UiSignalHelpersClass.safe_connect(confirm_end_button, "mouse_exited", _on_confirm_end_mouse_exited)
	if is_instance_valid(skip_step_button):
		UiSignalHelpersClass.safe_connect(skip_step_button, "pressed", _on_skip_step_pressed)
		UiSignalHelpersClass.safe_connect(skip_step_button, "mouse_entered", _on_skip_step_mouse_entered)
		UiSignalHelpersClass.safe_connect(skip_step_button, "mouse_exited", _on_skip_step_mouse_exited)
	if is_instance_valid(rewind_button):
		UiSignalHelpersClass.safe_connect(rewind_button, "pressed", _on_rewind_pressed)

func apply_flow_config(config: Dictionary) -> void:
	# config schema:
	# {
	#   "confirm_end": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "skip_step": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "rewind": {"visible": bool, "enabled": bool, "action_id": String}
	# }
	var ce: Dictionary = Dictionary(config.get("confirm_end", {}))
	var ss: Dictionary = Dictionary(config.get("skip_step", {}))
	var rw: Dictionary = Dictionary(config.get("rewind", {}))
	var signature := _build_flow_config_signature(ce, ss, rw)
	var controls_ready := is_instance_valid(confirm_end_button) \
		and is_instance_valid(skip_step_button) \
		and is_instance_valid(rewind_button)
	if controls_ready and _has_applied_flow_config_signature and signature == _last_flow_config_signature:
		return

	if is_instance_valid(confirm_end_button):
		confirm_end_button.visible = bool(ce.get("visible", false))
		confirm_end_button.text = str(ce.get("text", "确认结束"))
		confirm_end_button.disabled = not bool(ce.get("enabled", true))
		_confirm_end_action_id = str(ce.get("action_id", "skip")).strip_edges()
		if _confirm_end_action_id.is_empty():
			_confirm_end_action_id = "skip"
		_confirm_end_disabled_reason = str(ce.get("disabled_reason", "")).strip_edges()
		if confirm_end_button.disabled and not _confirm_end_disabled_reason.is_empty():
			confirm_end_button.tooltip_text = "不可用：%s" % _confirm_end_disabled_reason
		else:
			confirm_end_button.tooltip_text = ""

	if is_instance_valid(skip_step_button):
		skip_step_button.visible = bool(ss.get("visible", false))
		skip_step_button.text = str(ss.get("text", "跳过"))
		skip_step_button.disabled = not bool(ss.get("enabled", true))
		_skip_step_action_id = str(ss.get("action_id", "skip_sub_phase")).strip_edges()
		if _skip_step_action_id.is_empty():
			_skip_step_action_id = "skip_sub_phase"
		_skip_step_disabled_reason = str(ss.get("disabled_reason", "")).strip_edges()
		if skip_step_button.disabled and not _skip_step_disabled_reason.is_empty():
			skip_step_button.tooltip_text = "不可用：%s" % _skip_step_disabled_reason
		else:
			skip_step_button.tooltip_text = ""

	if is_instance_valid(rewind_button):
		rewind_button.visible = bool(rw.get("visible", true))
		rewind_button.disabled = not bool(rw.get("enabled", true))
		_rewind_action_id = str(rw.get("action_id", "rewind_to_turn_start")).strip_edges()
		if _rewind_action_id.is_empty():
			_rewind_action_id = "rewind_to_turn_start"
	if controls_ready:
		_last_flow_config_signature = signature
		_has_applied_flow_config_signature = true
		_flow_config_apply_count += 1

func _build_flow_config_signature(ce: Dictionary, ss: Dictionary, rw: Dictionary) -> Dictionary:
	var confirm_reason := str(ce.get("disabled_reason", "")).strip_edges()
	var skip_reason := str(ss.get("disabled_reason", "")).strip_edges()
	return {
		"confirm_end": {
			"visible": bool(ce.get("visible", false)),
			"text": str(ce.get("text", "确认结束")),
			"enabled": bool(ce.get("enabled", true)),
			"disabled_reason": confirm_reason,
			"action_id": str(ce.get("action_id", "skip")).strip_edges(),
		},
		"skip_step": {
			"visible": bool(ss.get("visible", false)),
			"text": str(ss.get("text", "跳过")),
			"enabled": bool(ss.get("enabled", true)),
			"disabled_reason": skip_reason,
			"action_id": str(ss.get("action_id", "skip_sub_phase")).strip_edges(),
		},
		"rewind": {
			"visible": bool(rw.get("visible", true)),
			"enabled": bool(rw.get("enabled", true)),
			"action_id": str(rw.get("action_id", "rewind_to_turn_start")).strip_edges(),
		},
	}

func get_flow_config_apply_count() -> int:
	return int(_flow_config_apply_count)

func _on_confirm_end_pressed() -> void:
	action_requested.emit(_confirm_end_action_id, {})

func _on_skip_step_pressed() -> void:
	action_requested.emit(_skip_step_action_id, {})

func _on_rewind_pressed() -> void:
	action_requested.emit(_rewind_action_id, {})

func _on_confirm_end_mouse_entered() -> void:
	if confirm_end_button != null and is_instance_valid(confirm_end_button) and confirm_end_button.disabled and not _confirm_end_disabled_reason.is_empty():
		confirm_end_button.tooltip_text = "不可用：%s" % _confirm_end_disabled_reason

func _on_confirm_end_mouse_exited() -> void:
	if confirm_end_button != null and is_instance_valid(confirm_end_button) and (not confirm_end_button.disabled):
		confirm_end_button.tooltip_text = ""

func _on_skip_step_mouse_entered() -> void:
	if skip_step_button != null and is_instance_valid(skip_step_button) and skip_step_button.disabled and not _skip_step_disabled_reason.is_empty():
		skip_step_button.tooltip_text = "不可用：%s" % _skip_step_disabled_reason

func _on_skip_step_mouse_exited() -> void:
	if skip_step_button != null and is_instance_valid(skip_step_button) and (not skip_step_button.disabled):
		skip_step_button.tooltip_text = ""
