# ActionPanel：动作列表与可用性计算（拆分自 action_panel.gd）
extends RefCounted

const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

# 定价类强制动作在 UI 中隐藏，并在执行 skip 前由 Game 自动补完（见 Game._maybe_auto_complete_mandatory_actions_before_skip）。
# 为避免软锁：当 skip 仅因“缺少这些可自动补完的强制动作”而不可用时，ActionPanel 仍应允许点击 skip。
const AUTO_MANDATORY_ACTION_IDS := {
	ActionIdsClass.SET_PRICE: true,
	ActionIdsClass.SET_DISCOUNT: true,
	ActionIdsClass.SET_LUXURY_PRICE: true,
}

var _panel = null
var _rendered_button_ids_snapshot: Array[String] = []

func setup(panel) -> void:
	_panel = panel

func set_available_actions(action_ids: Array) -> void:
	# 测试/调试入口：不依赖 GameState/ActionRegistry 的简化路径
	if _panel == null or not is_instance_valid(_panel):
		return
	_set_visible_actions_from_list(action_ids, [], true)

func refresh() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	if is_instance_valid(p.rewind_phase_button):
		p.rewind_phase_button.disabled = (p._game_state == null)
	if p._game_state == null:
		_clear_actions_cache()
		return

	var available_ids: Array[String] = []
	var executable_ids: Array[String] = []
	var has_player_executable_info := false
	p._mandatory_action_ids.clear()

	# 通过 ActionRegistry 获取可用动作
	if p._action_registry != null and p._action_registry.has_method("get_available_actions"):
		available_ids = p._action_registry.get_available_actions(p._game_state)
		if p._action_registry.has_method("get_mandatory_actions"):
			for mid in p._action_registry.get_mandatory_actions(p._game_state):
				p._mandatory_action_ids[str(mid)] = true
		if p._current_player_id >= 0:
			# UI 侧需要“可启动”判定：允许先点击进入面板/选点，再补齐参数执行
			if p._action_registry.has_method("get_player_initiatable_actions"):
				executable_ids = p._action_registry.get_player_initiatable_actions(p._game_state, p._current_player_id)
				has_player_executable_info = true
			elif p._action_registry.has_method("get_player_available_actions"):
				executable_ids = p._action_registry.get_player_available_actions(p._game_state, p._current_player_id)
				has_player_executable_info = true
	else:
		# 备用：根据阶段硬编码部分常用动作
		available_ids = _get_fallback_actions(p._game_state.phase, p._game_state.sub_phase)

	var hidden_ids_val: Variant = p._get_hidden_action_ids()
	var hidden_ids: Dictionary = hidden_ids_val if hidden_ids_val is Dictionary else {}

	# 隐藏内部动作
	var visible_ids: Array[String] = []
	for aid in available_ids:
		if hidden_ids.has(aid):
			continue
		visible_ids.append(aid)

	var visible_executable: Array[String] = []
	for aid2 in executable_ids:
		if hidden_ids.has(aid2):
			continue
		visible_executable.append(aid2)

	# Restructuring（hotseat 提交制）：隐藏“确认结束(skip)”，避免误解/误点造成卡住
	if p._game_state.phase == DefsClass.PHASE_RESTRUCTURING and int(p._game_state.round_number) > 1:
		var filtered_ids: Array[String] = []
		for aid_skip in visible_ids:
			if aid_skip == ActionIdsClass.SKIP:
				continue
			filtered_ids.append(aid_skip)
		visible_ids = filtered_ids

		var filtered_executable: Array[String] = []
		for aid_skip2 in visible_executable:
			if aid_skip2 == ActionIdsClass.SKIP:
				continue
			filtered_executable.append(aid_skip2)
		visible_executable = filtered_executable

	# Working：即使当前子阶段无任何可执行动作，也必须保留“跳过子阶段”，否则会造成软锁
	# （例如 Train 子阶段没有可培训来源/次数时，skip 被 validate 拒绝，只能用 skip_sub_phase 推进）。
	#
	# 但当 skip_sub_phase 实际效果等于“结束回合/结束工作阶段”（例如最后子阶段），不应再展示该按钮以避免误导。
	if visible_ids.has(ActionIdsClass.SKIP_SUB_PHASE) and not p._should_show_skip_sub_phase_button():
		var filtered_skip_sub: Array[String] = []
		for v in visible_ids:
			if v == ActionIdsClass.SKIP_SUB_PHASE:
				continue
			filtered_skip_sub.append(v)
		visible_ids = filtered_skip_sub

		if has_player_executable_info:
			var filtered_exec_skip_sub: Array[String] = []
			for v2 in visible_executable:
				if v2 == ActionIdsClass.SKIP_SUB_PHASE:
					continue
				filtered_exec_skip_sub.append(v2)
			visible_executable = filtered_exec_skip_sub

	# P1：默认不再自动隐藏“玩家依赖动作”，改为灰显 + 原因（提升发现性）。
	# 但对少数“模块/里程碑动作”，若对当前玩家不可启动则直接隐藏（issue_tracker #78）。
	if has_player_executable_info:
		var filtered_visible: Array[String] = []
		for aid_hide in visible_ids:
			if p._should_auto_hide_if_not_initiatable(aid_hide) and not visible_executable.has(aid_hide):
				continue
			filtered_visible.append(aid_hide)
		visible_ids = filtered_visible

	# 强制动作优先显示
	if not p._mandatory_action_ids.is_empty():
		var ordered: Array[String] = []
		for aidm in visible_ids:
			if p._mandatory_action_ids.has(aidm):
				ordered.append(aidm)
		for aidn in visible_ids:
			if not p._mandatory_action_ids.has(aidn):
				ordered.append(aidn)
		visible_ids = ordered

	_set_visible_actions_from_list(visible_ids, visible_executable if has_player_executable_info else [], false)

	# 若能计算“当前玩家可执行动作”，则对不可执行动作做灰显，并写入原因
	if has_player_executable_info:
		for aid3 in visible_ids:
			var enabled := visible_executable.has(aid3)
			if (not enabled) and aid3 == ActionIdsClass.SKIP and _should_enable_skip_via_auto_mandatory_actions():
				enabled = true
			# 保留调试用强制推进按钮
			if aid3 == ActionIdsClass.ADVANCE_PHASE:
				enabled = true
			p.set_action_enabled(aid3, enabled)
			if enabled:
				p.set_action_disabled_reason(aid3, "")
			else:
				p.set_action_disabled_reason(aid3, _compute_disabled_reason(aid3))
	else:
		for aid4 in visible_ids:
			p.set_action_enabled(aid4, true)
			p.set_action_disabled_reason(aid4, "")

	_apply_external_block_reasons(visible_ids)

	_compute_guided_flow_visibility()
	p._apply_global_disabled_state()
	_rebuild_action_buttons()

func _clear_actions_cache() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	p._visible_action_ids = Array([], TYPE_STRING, "", null)
	p._visible_initiatable_action_ids = Array([], TYPE_STRING, "", null)
	p._action_enabled.clear()
	p._action_disabled_reason.clear()
	p._guided_action_id = ""
	p._flow_confirm_end_visible = false
	p._flow_skip_step_visible = false
	_rendered_button_ids_snapshot = Array([], TYPE_STRING, "", null)
	p._sync_guided_action_placeholder()
	if p.items_container != null and is_instance_valid(p.items_container):
		UiRebuildHelpersClass.free_children(p.items_container)
		p.items_container.visible = false

func _sanitize_action_id_list(action_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for v in action_ids:
		var s := str(v).strip_edges()
		if s.is_empty():
			continue
		out.append(s)
	return out

func _set_visible_actions_from_list(action_ids: Array, initiatable_ids: Array, rebuild_ui: bool = true) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	p._visible_action_ids = _sort_action_ids_for_display(_sanitize_action_id_list(action_ids))
	p._visible_initiatable_action_ids = _sanitize_action_id_list(initiatable_ids)

	p._action_enabled.clear()
	p._action_disabled_reason.clear()
	for aid in p._visible_action_ids:
		p.set_action_enabled(aid, true)
		p.set_action_disabled_reason(aid, "")
	_apply_external_block_reasons(p._visible_action_ids)
	_compute_guided_flow_visibility()
	p._sync_guided_action_placeholder()
	if rebuild_ui:
		_rebuild_action_buttons()

func _compute_guided_flow_visibility() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel

	p._guided_action_id = ""
	var initiatable_ids_val: Variant = p._visible_initiatable_action_ids
	var initiatable_ids: Array = initiatable_ids_val if initiatable_ids_val is Array else []
	var visible_ids_val: Variant = p._visible_action_ids
	var visible_ids: Array = visible_ids_val if visible_ids_val is Array else []

	var candidates: Array = initiatable_ids
	if candidates.is_empty():
		candidates = visible_ids
	var preferred_guided := _get_preferred_guided_action_id(candidates)
	if not preferred_guided.is_empty():
		p._guided_action_id = preferred_guided
	else:
		for aid in candidates:
			if aid == ActionIdsClass.SKIP_SUB_PHASE:
				continue
			if aid == ActionIdsClass.SKIP:
				continue
			p._guided_action_id = aid
			break

	p._flow_skip_step_visible = visible_ids.has(ActionIdsClass.SKIP_SUB_PHASE)

	# “确认结束(skip)”仅在没有其他可启动动作时显示；
	# Working：若仍存在 skip_sub_phase，则永远不显示确认结束（避免误导）。
	var show_skip: bool = visible_ids.has(ActionIdsClass.SKIP)
	if show_skip and p._flow_skip_step_visible:
		show_skip = false
	if show_skip:
		var has_any_other_initiatable := false
		if not initiatable_ids.is_empty():
			for aid2 in initiatable_ids:
				var a2 := str(aid2)
				if a2 == ActionIdsClass.SKIP or a2 == ActionIdsClass.SKIP_SUB_PHASE:
					continue
				has_any_other_initiatable = true
				break
		elif not p._action_enabled.is_empty():
			# 当可启动列表为空时，优先使用“按钮启用态”判断，避免出现“仅剩不可启动动作却隐藏确认结束”的空白面板。
			for aid3 in visible_ids:
				var a3 := str(aid3)
				if a3 == ActionIdsClass.SKIP or a3 == ActionIdsClass.SKIP_SUB_PHASE:
					continue
				if not p.get_action_enabled(a3):
					continue
				has_any_other_initiatable = true
				break
		else:
			# 兜底：无启用态信息时按可见动作判断（保持旧行为）。
			for aid4 in visible_ids:
				var a4 := str(aid4)
				if a4 == ActionIdsClass.SKIP or a4 == ActionIdsClass.SKIP_SUB_PHASE:
					continue
				has_any_other_initiatable = true
				break
		show_skip = not has_any_other_initiatable

	p._flow_confirm_end_visible = show_skip
	p._sync_guided_action_placeholder()

func _get_preferred_guided_action_id(candidates: Array) -> String:
	if candidates.has("place_restaurant") and candidates.has("move_restaurant"):
		return "place_restaurant"
	return ""

func _get_fallback_actions(phase: String, sub_phase: String) -> Array[String]:
	var result: Array[String] = [ActionIdsClass.SKIP]

	match str(phase):
		DefsClass.PHASE_SETUP:
			result.append("place_restaurant")
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			result.append("choose_turn_order")
		DefsClass.PHASE_WORKING:
			match str(sub_phase):
				DefsClass.SUB_PHASE_RECRUIT:
					result.append("recruit")
				DefsClass.SUB_PHASE_TRAIN:
					result.append("train")
				DefsClass.SUB_PHASE_MARKETING:
					result.append("initiate_marketing")
				DefsClass.SUB_PHASE_GET_FOOD:
					result.append("produce_food")
				DefsClass.SUB_PHASE_GET_DRINKS:
					result.append("procure_drinks")
				DefsClass.SUB_PHASE_PLACE_HOUSES:
					result.append("place_house")
					result.append("add_garden")
				DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
					result.append("place_restaurant")
					result.append("move_restaurant")
		DefsClass.PHASE_PAYDAY:
			result.append("fire")

	return result

func _sort_action_ids_for_display(action_ids: Array[String]) -> Array[String]:
	# 固定 UI 顺序：把“跳过子阶段/确认结束”放在列表底部，并保持 skip_sub_phase 在 skip 上方。
	# 其它动作保持相对顺序不变（避免无关面板顺序抖动）。
	var out: Array[String] = []
	var has_skip_sub := false
	var has_skip := false
	for v in action_ids:
		var aid := str(v)
		if aid == ActionIdsClass.SKIP_SUB_PHASE:
			has_skip_sub = true
			continue
		if aid == ActionIdsClass.SKIP:
			has_skip = true
			continue
		out.append(aid)

	if has_skip_sub:
		out.append(ActionIdsClass.SKIP_SUB_PHASE)
	if has_skip:
		out.append(ActionIdsClass.SKIP)
	return out

func _get_rendered_action_button_ids() -> Array[String]:
	if _panel == null or not is_instance_valid(_panel):
		return []
	var p = _panel

	var rendered: Array[String] = []
	var guided := str(p._guided_action_id).strip_edges()
	var visible_ids_val: Variant = p._visible_action_ids
	var visible_ids: Array = visible_ids_val if visible_ids_val is Array else []
	for aid_val in visible_ids:
		var aid := str(aid_val).strip_edges()
		if aid.is_empty():
			continue
		if aid == ActionIdsClass.SKIP or aid == ActionIdsClass.SKIP_SUB_PHASE:
			continue
		if not guided.is_empty() and aid == guided:
			continue
		rendered.append(aid)
	return rendered

func _rebuild_action_buttons() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	if p.items_container == null or not is_instance_valid(p.items_container):
		return

	var rendered_ids := _get_rendered_action_button_ids()
	p.items_container.visible = not rendered_ids.is_empty()
	if rendered_ids == _rendered_button_ids_snapshot:
		sync_rendered_action_buttons()
		return

	_rendered_button_ids_snapshot = Array(rendered_ids, TYPE_STRING, "", null)
	UiRebuildHelpersClass.free_children(p.items_container)
	for action_id in rendered_ids:
		var btn := Button.new()
		btn.name = "ActionButton_%s" % action_id
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.set_meta("action_id", action_id)
		UiStylesClass.apply_button_secondary(btn)
		_configure_action_button(btn, action_id)
		UiSignalHelpersClass.safe_connect(btn, "pressed", Callable(self, "_on_action_button_pressed").bind(action_id))
		p.items_container.add_child(btn)

func sync_rendered_action_buttons() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	if p.items_container == null or not is_instance_valid(p.items_container):
		return
	for child in p.items_container.get_children():
		if not (child is Button):
			continue
		var btn: Button = child
		var aid := str(btn.get_meta("action_id", "")).strip_edges()
		if aid.is_empty():
			continue
		_configure_action_button(btn, aid)

func _configure_action_button(btn: Button, action_id: String) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	var title: String = str(p.get_action_display_name(action_id))
	if p._mandatory_action_ids.has(action_id):
		title = "【强制】%s" % title
	btn.text = title

	var enabled: bool = bool(p.get_action_enabled(action_id))
	btn.disabled = not enabled

	var reason: String = str(p.get_action_disabled_reason(action_id))
	var desc: String = str(p.get_action_description(action_id))
	if not enabled and not reason.is_empty():
		btn.tooltip_text = "不可用：%s" % reason
	else:
		btn.tooltip_text = desc

func _on_action_button_pressed(action_id: String) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return
	if not p.get_action_enabled(aid):
		return
	if not p.has_signal("action_requested"):
		return
	p.emit_signal("action_requested", aid, {})

func _get_missing_mandatory_actions_for_current_player() -> Array[String]:
	if _panel == null or not is_instance_valid(_panel):
		return []
	var p = _panel

	if p._game_state == null:
		return []
	if p._current_player_id < 0:
		return []

	var player: Variant = p._game_state.get_player(p._current_player_id)
	var required: Array[String] = MandatoryActionsRulesClass.get_required_mandatory_actions(player)
	if required.is_empty():
		return []

	if not (p._game_state.round_state is Dictionary):
		return []
	var mac_val = p._game_state.round_state.get("mandatory_actions_completed", null)
	if not (mac_val is Dictionary):
		return []
	var mac: Dictionary = mac_val

	var completed_val = mac.get(p._current_player_id, null)
	if completed_val == null and mac.has(str(p._current_player_id)):
		completed_val = mac.get(str(p._current_player_id), null)
	if not (completed_val is Array):
		return []
	var completed: Array = completed_val

	var missing: Array[String] = []
	for action_id in required:
		var aid := str(action_id).strip_edges()
		if aid.is_empty():
			continue
		if completed.has(aid):
			continue
		missing.append(aid)

	return missing

func _is_missing_params_error(r: Result) -> bool:
	if r == null or r.ok:
		return false
	return int(r.error_code) == Result.ErrorCode.MISSING_PARAMS

func _should_enable_skip_via_auto_mandatory_actions() -> bool:
	if _panel == null or not is_instance_valid(_panel):
		return false
	var p = _panel

	if p._action_registry == null or p._game_state == null:
		return false
	if p._current_player_id < 0:
		return false
	if not p._action_registry.has_method("get_executor"):
		return false

	# 仅当 skip 的失败原因是“缺少强制动作”时才考虑启用；其他原因（例如未到 Working 最后子阶段）不应放行。
	var skip_exec = p._action_registry.get_executor(ActionIdsClass.SKIP)
	if skip_exec == null:
		return false
	var test_command := Command.create(ActionIdsClass.SKIP, p._current_player_id)
	test_command.phase = p._game_state.phase
	test_command.sub_phase = p._game_state.sub_phase
	var r = skip_exec.validate(p._game_state, test_command)
	if not (r is Result) or r.ok:
		return false

	var err := str(r.error).strip_edges()
	if err.find("强制动作") == -1:
		return false

	var missing := _get_missing_mandatory_actions_for_current_player()
	if missing.is_empty():
		return false
	for aid in missing:
		if not AUTO_MANDATORY_ACTION_IDS.has(aid):
			return false

	return true

func _compute_disabled_reason(action_id: String) -> String:
	if _panel == null or not is_instance_valid(_panel):
		return "当前不可用"
	var p = _panel

	if p._action_registry == null or p._game_state == null:
		return "当前不可用"
	if p._current_player_id < 0:
		return "当前不可用"
	if not p._action_registry.has_method("get_executor"):
		return "当前不可用"

	var executor = p._action_registry.get_executor(action_id)
	if executor == null:
		return "未注册动作：%s" % action_id

	var test_command := Command.create(action_id, p._current_player_id)
	test_command.phase = p._game_state.phase
	test_command.sub_phase = p._game_state.sub_phase

	var r = executor.validate(p._game_state, test_command)
	if r is Result and not r.ok:
		var msg := str(r.error)
		if _is_missing_params_error(r) and executor.has_method("can_initiate"):
			var can = executor.can_initiate(p._game_state, p._current_player_id)
			if can is bool and not bool(can):
				return "条件不足，无法启动该动作"
		return msg

	return "当前不可用"

func _apply_external_block_reasons(action_ids: Array[String]) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var p = _panel
	for aid_val in action_ids:
		var aid := str(aid_val).strip_edges()
		if aid.is_empty():
			continue
		var reason := _get_external_block_reason(aid)
		if reason.is_empty():
			continue
		p.set_action_enabled(aid, false)
		p.set_action_disabled_reason(aid, reason)

func _get_external_block_reason(action_id: String) -> String:
	if _panel == null or not is_instance_valid(_panel):
		return ""
	var p = _panel
	if not p.has_method("_get_external_action_block_reason"):
		return ""
	var value = p.call("_get_external_action_block_reason", action_id)
	return str(value).strip_edges()
