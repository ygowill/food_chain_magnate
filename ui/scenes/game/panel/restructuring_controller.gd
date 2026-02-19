# Game scene：重组阶段控制器
# 负责：重组弹窗生命周期、视角隐私规则、拖拽重组命令分发。
class_name GamePanelRestructuringController
extends RefCounted

const RestructuringModalScene = preload("res://ui/components/modal_panel/restructuring_modal.tscn")
const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _scene = null
var _execute_command: Callable = Callable()
var _get_view_player_id: Callable = Callable()
var _view_player_selected: Callable = Callable()

var _restructuring_modal = null

func _init(scene, execute_command: Callable, get_view_player_id: Callable, view_player_selected: Callable) -> void:
	_scene = scene
	_execute_command = execute_command
	_get_view_player_id = get_view_player_id
	_view_player_selected = view_player_selected

func dispose() -> void:
	_execute_command = Callable()
	_get_view_player_id = Callable()
	_view_player_selected = Callable()

	if is_instance_valid(_restructuring_modal):
		_restructuring_modal.queue_free()
	_restructuring_modal = null
	_scene = null

func has_open_modal_ui() -> bool:
	return is_instance_valid(_restructuring_modal) and bool(_restructuring_modal.visible)

func hide_modal() -> void:
	_hide_restructuring_modal()

func sync_modal(state: GameState, covered: Rect2, requested_view_player_id: int) -> int:
	var should_show_restructuring := false
	if state != null and state.phase == DefsClass.PHASE_RESTRUCTURING and state.players.size() > 0:
		var all_submitted := false
		if state.round_state is Dictionary:
			var r_val = state.round_state.get("restructuring", null)
			if r_val is Dictionary:
				var r: Dictionary = r_val
				var finalized_val = r.get("finalized", null)
				if finalized_val is bool and bool(finalized_val):
					all_submitted = true
				elif r.has("submitted") and (r["submitted"] is Dictionary):
					var submitted: Dictionary = r["submitted"]
					all_submitted = true
					for pid in range(state.players.size()):
						var v = submitted.get(pid, null)
						if v == null and submitted.has(str(pid)):
							v = submitted.get(str(pid), null)
						if not bool(v):
							all_submitted = false
							break
		should_show_restructuring = not all_submitted

	if not should_show_restructuring:
		_hide_restructuring_modal()
		return requested_view_player_id

	_show_restructuring_modal(covered)

	var view_player_id := _get_effective_view_player_id(state, requested_view_player_id)
	var privacy_view_id := apply_view_privacy(state, view_player_id)
	_sync_restructuring_modal_ui(state, privacy_view_id)

	# 仅在“隐私规则强制切换”时写回 view_player_id；默认回退（例如 requested 不在范围内）不写回。
	var is_online := (NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT)
	if is_online:
		var local_pid := int(NetContext.local_player_id)
		return local_pid if local_pid >= 0 else -1
	if privacy_view_id != view_player_id:
		return privacy_view_id
	return requested_view_player_id

func is_player_submitted(state: GameState, player_id: int) -> bool:
	var submitted := _get_restructuring_submitted_map(state)
	if submitted.is_empty():
		return false
	return _is_restructuring_player_submitted(submitted, player_id)

func apply_view_privacy(state: GameState, view_player_id: int) -> int:
	if state == null:
		return view_player_id
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return view_player_id

	# Online：仅允许查看自己；旁观者不允许查看任何玩家结构。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		return local_pid if local_pid >= 0 else -1

	# Hotseat：已提交玩家不可再查看（用于保密）。
	var submitted := _get_restructuring_submitted_map(state)
	if submitted.is_empty():
		return view_player_id
	if _is_restructuring_player_submitted(submitted, view_player_id):
		var picked := _pick_first_unsubmitted_player_id(state, submitted)
		if picked >= 0:
			return picked

	return view_player_id

func on_hand_card_dropped(employee_id: String, target: Control) -> void:
	if _scene == null or _scene.get("game_engine") == null:
		return
	if employee_id.is_empty():
		return
	if not is_instance_valid(target):
		return

	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		return

	var state: GameState = engine.get_state()
	if state == null:
		return
	if state.phase != DefsClass.PHASE_RESTRUCTURING:
		return

	var stored_view_id := -1
	if _get_view_player_id.is_valid():
		var v = _get_view_player_id.call()
		if v is int:
			stored_view_id = int(v)
		elif v is float:
			var vf: float = float(v)
			if vf == floor(vf):
				stored_view_id = int(vf)

	var actor_id := _get_effective_view_player_id(state, stored_view_id)
	if actor_id < 0:
		return
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0:
			return
		if actor_id != local_pid:
			GameLog.warn("Game", "联机模式下只能调整自己的公司结构")
			return
	if state.round_state is Dictionary:
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			var submitted_val = r.get("submitted", null)
			if submitted_val is Dictionary:
				var submitted: Dictionary = submitted_val
				var submitted_flag = submitted.get(actor_id, null)
				if submitted_flag == null and submitted.has(str(actor_id)):
					submitted_flag = submitted.get(str(actor_id), null)
				if bool(submitted_flag):
					return

	# 放到公司结构（经理下属区）
	if target.is_in_group("company_structure_reports_drop_target"):
		var manager_slot_index := -1
		if target.has_meta("manager_slot_index"):
			var mv = target.get_meta("manager_slot_index")
			if mv is int:
				manager_slot_index = int(mv)
			elif mv is float:
				var mf: float = float(mv)
				if mf == floor(mf):
					manager_slot_index = int(mf)
		if manager_slot_index < 0:
			GameLog.warn("Game", "无法获取经理槽位索引")
			return

		var manager_employee_id := ""
		if target.has_meta("manager_employee_id"):
			var m_id_val = target.get_meta("manager_employee_id")
			if m_id_val is String:
				manager_employee_id = str(m_id_val)
		if manager_employee_id.is_empty():
			GameLog.warn("Game", "无法获取该经理槽位的员工 id（manager_employee_id），无法分配下属")
			return

		var player := state.get_player(actor_id)
		var needs_direct_sync := true
		if not player.is_empty():
			var cs_val = player.get("company_structure", null)
			if cs_val is Dictionary:
				var cs: Dictionary = cs_val
				var struct_val = cs.get("structure", null)
				if struct_val is Array:
					var structure: Array = struct_val
					if manager_slot_index < structure.size():
						var entry_val = structure[manager_slot_index]
						if entry_val is Dictionary:
							var entry: Dictionary = entry_val
							var stored_id := str(entry.get("employee_id", ""))
							if stored_id == manager_employee_id and not stored_id.is_empty():
								needs_direct_sync = false

		# 当 UI 显示的“经理”与 state.company_structure.structure 不一致（或未初始化）时，
		# 先同步一次直属槽，避免 set_company_structure_report 直接失败/看起来“拖拽无效”。
		if needs_direct_sync:
			var init_r: Result = _execute_command.call(Command.create("set_company_structure_direct", actor_id, {
				"slot_index": manager_slot_index,
				"employee_id": manager_employee_id
			}))
			if not init_r.ok:
				GameLog.warn("Game", "初始化 CEO 直属槽失败: %s" % init_r.error)
				return

		var set_r: Result = _execute_command.call(Command.create("set_company_structure_report", actor_id, {
			"manager_slot_index": manager_slot_index,
			"employee_id": employee_id
		}))
		if not set_r.ok:
			GameLog.warn("Game", "设置经理下属失败: %s" % set_r.error)
		return

	# 放到公司结构（CEO 直属槽）
	if target.is_in_group("company_structure_direct_slot"):
		var slot_index := -1
		if target.has_method("get_slot_index"):
			var v = target.call("get_slot_index")
			if v is int:
				slot_index = int(v)
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					slot_index = int(f)
		if slot_index < 0:
			GameLog.warn("Game", "无法获取公司结构槽位索引")
			return

		var direct_r: Result = _execute_command.call(Command.create("set_company_structure_direct", actor_id, {
			"slot_index": slot_index,
			"employee_id": employee_id
		}))
		if not direct_r.ok:
			GameLog.warn("Game", "设置 CEO 直属槽失败: %s" % direct_r.error)
		return

	var to_reserve := false
	if _scene != null:
		var hand_area = _scene.get("hand_area")
		if hand_area is HandArea:
				var ha: HandArea = hand_area
				var mode := ""
				if ha.has_method("get_display_mode"):
					mode = str(ha.call("get_display_mode"))

				# In restructuring, allow dropping anywhere within the reserve scroll area (issue_tracker #46).
				if mode == "restructuring":
					if target.is_in_group("hand_area_reserve_drop_target"):
						to_reserve = true
					elif is_instance_valid(ha.reserve_container):
						to_reserve = (target == ha.reserve_container) or ha.reserve_container.is_ancestor_of(target) or target.is_ancestor_of(ha.reserve_container)
					# 新规则：不允许“把待命员工拖到 active 区”来激活；激活仅由放入 company_structure 完成。
					# 因此在重组模式下，除了拖回待命区以外，其它落点一律忽略（卡片会回弹）。
					if not to_reserve:
						return
				else:
					if is_instance_valid(ha.reserve_container):
						to_reserve = (target == ha.reserve_container) or ha.reserve_container.is_ancestor_of(target) or target.is_ancestor_of(ha.reserve_container)
					if is_instance_valid(ha.active_container):
						if (target == ha.active_container) or ha.active_container.is_ancestor_of(target) or target.is_ancestor_of(ha.active_container):
							to_reserve = false

	var move_r: Result = _execute_command.call(Command.create("restructure_employee", actor_id, {
		"employee_id": employee_id,
		"to_reserve": to_reserve
	}))
	if not move_r.ok:
		GameLog.warn("Game", "移动员工失败: %s" % move_r.error)

func _show_restructuring_modal(covered: Rect2) -> void:
	if _scene == null:
		return

	if not is_instance_valid(_restructuring_modal):
		var inst = RestructuringModalScene.instantiate()
		if not is_instance_valid(inst):
			return
		_scene.add_child(inst)
		if inst is Control:
			(inst as Control).z_index = 900
		_restructuring_modal = inst

		UiSignalHelpersClass.safe_connect(_restructuring_modal, "completed", _on_restructuring_modal_completed)
		UiSignalHelpersClass.safe_connect(_restructuring_modal, "cancelled", _on_restructuring_modal_cancelled)
		if _view_player_selected.is_valid():
			UiSignalHelpersClass.safe_connect(_restructuring_modal, "player_selected", _view_player_selected)

	var hand_area = _scene.get("hand_area")
	if is_instance_valid(hand_area) and _restructuring_modal.has_method("attach_hand_area"):
		_restructuring_modal.call("attach_hand_area", hand_area)
	var company_structure = _scene.get("company_structure")
	if is_instance_valid(company_structure) and _restructuring_modal.has_method("attach_company_structure"):
		_restructuring_modal.call("attach_company_structure", company_structure)

	if _restructuring_modal.has_method("open"):
		_restructuring_modal.call("open", covered)
	elif _restructuring_modal is Control:
		var c: Control = _restructuring_modal
		c.position = covered.position
		c.size = covered.size
		c.visible = true

func _hide_restructuring_modal() -> void:
	if not is_instance_valid(_restructuring_modal):
		return

	if _restructuring_modal.has_method("close"):
		_restructuring_modal.call("close")
	elif _restructuring_modal is Control:
		(_restructuring_modal as Control).visible = false

	_restore_info_panels_after_restructuring()

func _restore_info_panels_after_restructuring() -> void:
	if _scene == null:
		return

	var hand_area = _scene.get("hand_area")
	var company_structure = _scene.get("company_structure")
	if not is_instance_valid(hand_area) and not is_instance_valid(company_structure):
		return

	var bottom_panel = _scene.get("bottom_panel")
	if not is_instance_valid(bottom_panel):
		return

	if is_instance_valid(hand_area):
		_reparent_control(hand_area, bottom_panel)
	if is_instance_valid(company_structure):
		_reparent_control(company_structure, bottom_panel)

func _reparent_control(node: Node, target_parent: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if target_parent == null or not is_instance_valid(target_parent):
		return
	if node.get_parent() == target_parent:
		return
	var old_parent := node.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(node)
	target_parent.add_child(node)

func _on_restructuring_modal_completed(_result: Dictionary) -> void:
	if _scene == null or _scene.get("game_engine") == null:
		return
	if not is_instance_valid(_restructuring_modal):
		return

	if _restructuring_modal.has_method("set_confirm_enabled"):
		_restructuring_modal.call("set_confirm_enabled", false)

	var engine = _scene.get("game_engine")
	if engine == null or not (engine is GameEngine):
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return
	var state: GameState = engine.get_state()
	if state == null:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return

	var stored_view_id := -1
	if _get_view_player_id.is_valid():
		var v = _get_view_player_id.call()
		if v is int:
			stored_view_id = int(v)
		elif v is float:
			var vf: float = float(v)
			if vf == floor(vf):
				stored_view_id = int(vf)

	var actor_id := _get_effective_view_player_id(state, stored_view_id)
	if actor_id < 0:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		var local_pid := int(NetContext.local_player_id)
		if local_pid < 0 or actor_id != local_pid:
			if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
				_restructuring_modal.call("set_confirm_enabled", true)
			GameLog.warn("Game", "联机模式下只能提交自己的公司结构")
			return

	var exec_result = _execute_command.call(Command.create("submit_restructuring", actor_id, {}))
	if not (exec_result is Result):
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)
		return
	if not (exec_result as Result).ok:
		if is_instance_valid(_restructuring_modal) and _restructuring_modal.has_method("set_confirm_enabled"):
			_restructuring_modal.call("set_confirm_enabled", true)

func _on_restructuring_modal_cancelled() -> void:
	_hide_restructuring_modal()

func _get_restructuring_submitted_map(state: GameState) -> Dictionary:
	if state == null:
		return {}
	if not (state.round_state is Dictionary):
		return {}
	var rs: Dictionary = state.round_state
	var r_val = rs.get("restructuring", null)
	if not (r_val is Dictionary):
		return {}
	var r: Dictionary = r_val
	var submitted_val = r.get("submitted", null)
	if not (submitted_val is Dictionary):
		return {}
	return submitted_val

func _is_restructuring_player_submitted(submitted: Dictionary, player_id: int) -> bool:
	if submitted == null or submitted.is_empty():
		return false
	var v = submitted.get(player_id, null)
	if v == null and submitted.has(str(player_id)):
		v = submitted.get(str(player_id), null)
	return bool(v)

func _pick_first_unsubmitted_player_id(state: GameState, submitted: Dictionary) -> int:
	if state == null:
		return -1
	var total := state.players.size()
	if total <= 0:
		return -1

	# 优先按 turn_order（更符合“顺序轨/回合”语义）
	for pid_val in Array(state.turn_order):
		if not (pid_val is int):
			continue
		var pid := int(pid_val)
		if pid < 0 or pid >= total:
			continue
		if not _is_restructuring_player_submitted(submitted, pid):
			return pid

	for pid2 in range(total):
		if not _is_restructuring_player_submitted(submitted, pid2):
			return pid2
	return -1

func _sync_restructuring_modal_ui(state: GameState, view_player_id: int) -> void:
	if not is_instance_valid(_restructuring_modal):
		return
	if state == null:
		return

	var submitted_count := 0
	var total := state.players.size()
	var view_submitted := false
	var submitted: Dictionary = {}

	if state.round_state is Dictionary:
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			var submitted_val = r.get("submitted", null)
			if submitted_val is Dictionary:
				submitted = submitted_val
				for pid in range(total):
					var v = submitted.get(pid, null)
					if v == null and submitted.has(str(pid)):
						v = submitted.get(str(pid), null)
					if bool(v):
						submitted_count += 1

				var v2 = submitted.get(view_player_id, null)
				if v2 == null and submitted.has(str(view_player_id)):
					v2 = submitted.get(str(view_player_id), null)
				view_submitted = bool(v2)

	if _restructuring_modal.has_method("set_player_switcher"):
		_restructuring_modal.call("set_player_switcher", total, view_player_id, submitted)

	var view_name := "-"
	if view_player_id >= 0:
		view_name = Globals.get_player_name(view_player_id) if Globals != null else ("玩家%d" % (view_player_id + 1))
	if _restructuring_modal.has_method("set_title_text"):
		var title := "公司结构重组（同时）"
		if view_player_id >= 0:
			title = "公司结构重组（同时）｜查看: %s" % view_name
		_restructuring_modal.call("set_title_text", title)

	var is_online := false
	var local_pid := -1
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		is_online = true
		local_pid = int(NetContext.local_player_id)

	# Online spectator：不允许查看任何玩家结构（只显示提交进度）
	var show_content := true
	if is_online and local_pid < 0:
		show_content = false
	if view_player_id < 0:
		show_content = false
	if _restructuring_modal.has_method("set_content_visible"):
		_restructuring_modal.call("set_content_visible", show_content)

	var confirm_text := "已提交" if view_submitted else ("确认重组（%s）" % view_name)
	var confirm_enabled := not view_submitted
	var status_text := ""
	var view_status := "已提交" if view_submitted else "未提交"

	if is_online:
		if local_pid < 0:
			confirm_text = "只读"
			confirm_enabled = false
			status_text = "旁观者：重组阶段不可查看玩家公司结构｜提交进度: %d/%d" % [submitted_count, total]
		else:
			confirm_text = "已提交" if view_submitted else "确认重组"
			confirm_enabled = not view_submitted
			status_text = "联机：重组阶段不可查看其他玩家｜你的状态: %s｜提交进度: %d/%d" % [view_status, submitted_count, total]
	else:
		status_text = "当前查看: %s（%s）｜提交进度: %d/%d｜上方仅可切换未提交玩家（已提交将锁定）" % [
			view_name,
			view_status,
			submitted_count,
			total
		]

	if _restructuring_modal.has_method("set_confirm_text"):
		_restructuring_modal.call("set_confirm_text", confirm_text)
	if _restructuring_modal.has_method("set_confirm_enabled"):
		_restructuring_modal.call("set_confirm_enabled", confirm_enabled)
	if _restructuring_modal.has_method("set_status_text"):
		_restructuring_modal.call("set_status_text", status_text)

func _get_effective_view_player_id(state: GameState, requested_view_id: int) -> int:
	if state == null:
		return requested_view_id
	if requested_view_id >= 0 and requested_view_id < state.players.size():
		return requested_view_id
	return state.get_current_player_id()
