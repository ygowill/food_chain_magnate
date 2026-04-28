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
@onready var rollback_row: HBoxContainer = $RollbackRow
@onready var rollback_last_button: Button = $RollbackRow/RollbackLastButton
@onready var rewind_button: Button = $RollbackRow/RewindButton
@onready var rollback_proposal_button: Button = $RollbackRow/RollbackProposalButton

var _confirm_end_disabled_reason: String = ""
var _skip_step_disabled_reason: String = ""
var _rollback_last_disabled_reason: String = ""
var _rollback_proposal_disabled_reason: String = ""
var _confirm_end_action_id: String = "skip"
var _skip_step_action_id: String = "skip_sub_phase"
var _rollback_last_action_id: String = "rollback_last_command"
var _rollback_proposal_action_id: String = "rollback_proposal"
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
	if is_instance_valid(rollback_last_button):
		UiStylesClass.apply_button_secondary(rollback_last_button)
	if is_instance_valid(rollback_proposal_button):
		UiStylesClass.apply_button_secondary(rollback_proposal_button)
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
	if is_instance_valid(rollback_last_button):
		UiSignalHelpersClass.safe_connect(rollback_last_button, "pressed", _on_rollback_last_pressed)
		UiSignalHelpersClass.safe_connect(rollback_last_button, "mouse_entered", _on_rollback_last_mouse_entered)
		UiSignalHelpersClass.safe_connect(rollback_last_button, "mouse_exited", _on_rollback_last_mouse_exited)
	if is_instance_valid(rollback_proposal_button):
		UiSignalHelpersClass.safe_connect(rollback_proposal_button, "pressed", _on_rollback_proposal_pressed)
		UiSignalHelpersClass.safe_connect(rollback_proposal_button, "mouse_entered", _on_rollback_proposal_mouse_entered)
		UiSignalHelpersClass.safe_connect(rollback_proposal_button, "mouse_exited", _on_rollback_proposal_mouse_exited)
	if is_instance_valid(rewind_button):
		UiSignalHelpersClass.safe_connect(rewind_button, "pressed", _on_rewind_pressed)

func apply_flow_config(config: Dictionary) -> void:
	# config schema:
	# {
	#   "confirm_end": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "skip_step": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "rollback_last": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "rollback_proposal": {"visible": bool, "text": String, "enabled": bool, "disabled_reason": String, "action_id": String},
	#   "rewind": {"visible": bool, "enabled": bool, "action_id": String}
	# }
	var ce: Dictionary = Dictionary(config.get("confirm_end", {}))
	var ss: Dictionary = Dictionary(config.get("skip_step", {}))
	var rb: Dictionary = Dictionary(config.get("rollback_last", {}))
	var rp: Dictionary = Dictionary(config.get("rollback_proposal", {}))
	var rw: Dictionary = Dictionary(config.get("rewind", {}))
	var signature := _build_flow_config_signature(ce, ss, rb, rp, rw)
	var controls_ready := is_instance_valid(confirm_end_button) \
		and is_instance_valid(skip_step_button) \
		and is_instance_valid(rollback_row) \
		and is_instance_valid(rollback_last_button) \
		and is_instance_valid(rollback_proposal_button) \
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

	if is_instance_valid(rollback_last_button):
		rollback_last_button.visible = bool(rb.get("visible", false))
		rollback_last_button.text = str(rb.get("text", "回退一步"))
		rollback_last_button.disabled = not bool(rb.get("enabled", true))
		_rollback_last_action_id = str(rb.get("action_id", "rollback_last_command")).strip_edges()
		if _rollback_last_action_id.is_empty():
			_rollback_last_action_id = "rollback_last_command"
		_rollback_last_disabled_reason = str(rb.get("disabled_reason", "")).strip_edges()
		if rollback_last_button.disabled and not _rollback_last_disabled_reason.is_empty():
			rollback_last_button.tooltip_text = "不可用：%s" % _rollback_last_disabled_reason
		else:
			rollback_last_button.tooltip_text = "撤销你刚刚执行的上一条操作"

	if is_instance_valid(rollback_proposal_button):
		rollback_proposal_button.visible = bool(rp.get("visible", false))
		rollback_proposal_button.text = str(rp.get("text", "提议回退"))
		rollback_proposal_button.disabled = not bool(rp.get("enabled", true))
		_rollback_proposal_action_id = str(rp.get("action_id", "rollback_proposal")).strip_edges()
		if _rollback_proposal_action_id.is_empty():
			_rollback_proposal_action_id = "rollback_proposal"
		_rollback_proposal_disabled_reason = str(rp.get("disabled_reason", "")).strip_edges()
		if rollback_proposal_button.disabled and not _rollback_proposal_disabled_reason.is_empty():
			rollback_proposal_button.tooltip_text = "不可用：%s" % _rollback_proposal_disabled_reason
		else:
			rollback_proposal_button.tooltip_text = "房主选择时间点并发起全员回滚投票"

	if is_instance_valid(rewind_button):
		rewind_button.visible = bool(rw.get("visible", true))
		rewind_button.text = str(rw.get("text", "回退到回合开始"))
		rewind_button.disabled = not bool(rw.get("enabled", true))
		_rewind_action_id = str(rw.get("action_id", "rewind_to_turn_start")).strip_edges()
		if _rewind_action_id.is_empty():
			_rewind_action_id = "rewind_to_turn_start"
	if is_instance_valid(rollback_row):
		var rollback_row_visible := false
		if is_instance_valid(rollback_last_button):
			rollback_row_visible = rollback_row_visible or bool(rollback_last_button.visible)
		if is_instance_valid(rewind_button):
			rollback_row_visible = rollback_row_visible or bool(rewind_button.visible)
		if is_instance_valid(rollback_proposal_button):
			rollback_row_visible = rollback_row_visible or bool(rollback_proposal_button.visible)
		rollback_row.visible = rollback_row_visible
	if controls_ready:
		_last_flow_config_signature = signature
		_has_applied_flow_config_signature = true
		_flow_config_apply_count += 1

func _build_flow_config_signature(ce: Dictionary, ss: Dictionary, rb: Dictionary, rp: Dictionary, rw: Dictionary) -> Dictionary:
	var confirm_reason := str(ce.get("disabled_reason", "")).strip_edges()
	var skip_reason := str(ss.get("disabled_reason", "")).strip_edges()
	var rollback_reason := str(rb.get("disabled_reason", "")).strip_edges()
	var proposal_reason := str(rp.get("disabled_reason", "")).strip_edges()
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
		"rollback_last": {
			"visible": bool(rb.get("visible", false)),
			"text": str(rb.get("text", "回退一步")),
			"enabled": bool(rb.get("enabled", true)),
			"disabled_reason": rollback_reason,
			"action_id": str(rb.get("action_id", "rollback_last_command")).strip_edges(),
		},
		"rollback_proposal": {
			"visible": bool(rp.get("visible", false)),
			"text": str(rp.get("text", "提议回退")),
			"enabled": bool(rp.get("enabled", true)),
			"disabled_reason": proposal_reason,
			"action_id": str(rp.get("action_id", "rollback_proposal")).strip_edges(),
		},
		"rewind": {
			"visible": bool(rw.get("visible", true)),
			"text": str(rw.get("text", "回退到回合开始")),
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

func _on_rollback_last_pressed() -> void:
	action_requested.emit(_rollback_last_action_id, {})

func _on_rollback_proposal_pressed() -> void:
	action_requested.emit(_rollback_proposal_action_id, {})

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

func _on_rollback_last_mouse_entered() -> void:
	if rollback_last_button != null and is_instance_valid(rollback_last_button) and rollback_last_button.disabled and not _rollback_last_disabled_reason.is_empty():
		rollback_last_button.tooltip_text = "不可用：%s" % _rollback_last_disabled_reason

func _on_rollback_last_mouse_exited() -> void:
	if rollback_last_button != null and is_instance_valid(rollback_last_button) and (not rollback_last_button.disabled):
		rollback_last_button.tooltip_text = "撤销你刚刚执行的上一条操作"

func _on_rollback_proposal_mouse_entered() -> void:
	if rollback_proposal_button != null and is_instance_valid(rollback_proposal_button) and rollback_proposal_button.disabled and not _rollback_proposal_disabled_reason.is_empty():
		rollback_proposal_button.tooltip_text = "不可用：%s" % _rollback_proposal_disabled_reason

func _on_rollback_proposal_mouse_exited() -> void:
	if rollback_proposal_button != null and is_instance_valid(rollback_proposal_button) and (not rollback_proposal_button.disabled):
		rollback_proposal_button.tooltip_text = "房主选择时间点并发起全员回滚投票"
