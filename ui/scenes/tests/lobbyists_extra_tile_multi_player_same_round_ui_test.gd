class_name LobbyistsExtraTileMultiPlayerSameRoundUiTest
extends RefCounted

const GameScene: PackedScene = preload("res://ui/scenes/game/game.tscn")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const TilePreviewFactoryClass = preload("res://ui/components/reserve_area/tile_preview_factory.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map_canvas_drawer_structures_pass.gd")

const FLOW_CONTROLLER_SCRIPT_PATH := "res://modules/lobbyists/ui/lobbyists_extra_tile_flow_controller.gd"
const MANUAL_SAVE_RES_PATH := "res://testdata/saves/manual_cases/milestones/first_lobbyist_used_multi_player_same_round.json"

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载 game.tscn）")

	if NetClient != null:
		NetClient.shutdown()
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	Globals.reset_game_config()

	var abs_path := ProjectSettings.globalize_path(MANUAL_SAVE_RES_PATH)
	var engine := GameEngine.new()
	var load_r: Result = engine.load_from_file(abs_path)
	if not load_r.ok:
		Globals.reset_game_config()
		return Result.failure("载入存档失败: %s" % load_r.error)

	Globals.current_game_engine = engine
	Globals.is_game_active = true

	var game := GameScene.instantiate()
	if game == null:
		Globals.reset_game_config()
		return Result.failure("实例化 game.tscn 失败")
	host.add_child(game)

	await st.process_frame
	await st.process_frame

	if game.game_engine == null:
		await _cleanup_game_instance(game)
		return Result.failure("game.game_engine 为空（初始化失败或节点结构变更）")

	var flow = _find_lobbyists_flow_controller(game)
	if flow == null:
		await _cleanup_game_instance(game)
		return Result.failure("未找到 LobbyistsExtraTileFlowController（模块 UI 未加载或脚本路径变更）")

	# === 玩家 0：触发里程碑 -> 选择“使用”打开 picker -> 再放弃（确保 overlay 已创建且会被复用）===
	var state: GameState = game.game_engine.get_state()
	if state == null:
		await _cleanup_game_instance(game)
		return Result.failure("state 为空")
	if str(state.phase) != "Working" or str(state.sub_phase) != "Lobbyists":
		await _cleanup_game_instance(game)
		return Result.failure("初始不在 Working/Lobbyists（实际=%s/%s）" % [str(state.phase), str(state.sub_phase)])

	var actor0 := int(state.get_current_player_id())
	if actor0 != 0:
		await _cleanup_game_instance(game)
		return Result.failure("初始当前玩家应为 0，实际=%d" % actor0)

	var cmd0_r := _find_first_valid_lobbyists_road(game.game_engine, actor0)
	if not cmd0_r.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家0找不到可放置的说客道路: %s" % cmd0_r.error)

	var exec0: Result = game._execute_command(cmd0_r.value)
	if not exec0.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家0 place_lobbyists_road 失败: %s" % exec0.error)

	await st.process_frame

	var choose0 := _choose_extra_tile_use_via_choice_dialog(flow)
	if not choose0.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家0选择“使用”失败: %s" % choose0.error)
	for _i in range(10):
		await st.process_frame

	# Mimic real UI flow: player must hide the picker before interacting with the map / completing placement.
	var ov0 = flow.call("get_context_overlay") if flow.has_method("get_context_overlay") else null
	if ov0 != null and is_instance_valid(ov0) and ov0.has_method("hide_picker"):
		ov0.call("hide_picker")
	await st.process_frame

	var place0_r := _find_first_valid_lobbyists_extra_map_tile(game.game_engine, actor0)
	if not place0_r.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家0找不到可放置的扩边 tile: %s" % place0_r.error)

	var place0: Result = game._execute_command(place0_r.value)
	if not place0.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家0 place_lobbyists_extra_map_tile 失败: %s" % place0.error)

	# === 推进到玩家 1 的 Lobbyists 子阶段 ===
	var adv0 := await _advance_to_player_working_sub_phase(game, 1, "Lobbyists", 80)
	if not adv0.ok:
		await _cleanup_game_instance(game)
		return adv0

	# === 玩家 1：触发里程碑 -> 选择“使用”（这里曾出现卡顿/闪退）===
	state = game.game_engine.get_state()
	var actor1 := int(state.get_current_player_id())
	if actor1 != 1:
		await _cleanup_game_instance(game)
		return Result.failure("预期轮到玩家1，实际=%d" % actor1)

	var cmd1_r := _find_first_valid_lobbyists_road(game.game_engine, actor1)
	if not cmd1_r.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家1找不到可放置的说客道路: %s" % cmd1_r.error)

	var exec1: Result = game._execute_command(cmd1_r.value)
	if not exec1.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家1 place_lobbyists_road 失败: %s" % exec1.error)

	await st.process_frame

	var choose1 := _choose_extra_tile_use_via_choice_dialog(flow)
	if not choose1.ok:
		await _cleanup_game_instance(game)
		return Result.failure("玩家1选择“使用”失败: %s" % choose1.error)
	for _j in range(10):
		await st.process_frame

	var ov = flow.call("get_context_overlay")
	if ov == null or not is_instance_valid(ov):
		await _cleanup_game_instance(game)
		return Result.failure("玩家1选择“使用”后未显示扩边 overlay")
	if ov.has_method("is_picker_visible") and not bool(ov.call("is_picker_visible")):
		await _cleanup_game_instance(game)
		return Result.failure("玩家1选择“使用”后 picker 未显示")

	await _cleanup_game_instance(game)
	return Result.success({})

static func _choose_extra_tile_use_via_choice_dialog(flow) -> Result:
	if flow == null or not is_instance_valid(flow):
		return Result.failure("flow 为空")
	var dialog = flow.get("_choice_dialog")
	if dialog == null or not is_instance_valid(dialog):
		return Result.failure("choice_dialog 为空（未弹出二选一窗口）")
	if dialog.has_method("_on_option_pressed"):
		dialog.call("_on_option_pressed", "use")
		return Result.success()
	if dialog.has_signal("option_selected"):
		dialog.option_selected.emit("use")
		return Result.success()
	return Result.failure("choice_dialog 缺少 option_selected/_on_option_pressed")

static func _cleanup_game_instance(game: Node) -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		for _i in range(6):
			await (tree as SceneTree).process_frame
	if NetClient != null:
		NetClient.shutdown()
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	if tree is SceneTree:
		for _j in range(4):
			await (tree as SceneTree).process_frame

static func _find_lobbyists_flow_controller(game: Node):
	if game == null or not is_instance_valid(game):
		return null
	var panel = game.get("_panel_controller")
	if panel == null:
		return null
	var overlays = panel.get("_placement_overlays")
	if overlays == null:
		return null

	# Ensure module controllers are loaded.
	if overlays.has_method("_ensure_module_overlay_controllers_loaded"):
		overlays.call("_ensure_module_overlay_controllers_loaded")

	var list_val = overlays.get("_module_overlay_controllers")
	if not (list_val is Array):
		return null
	var list: Array = list_val
	for c in list:
		if c == null or not is_instance_valid(c):
			continue
		var s = c.get_script()
		if s is Script and str((s as Script).resource_path) == FLOW_CONTROLLER_SCRIPT_PATH:
			return c
	return null

static func _find_first_valid_lobbyists_road(engine: GameEngine, actor_id: int) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var ex = engine.get_action_registry().get_executor("place_lobbyists_road")
	if ex == null:
		return Result.failure("缺少 place_lobbyists_road 执行器")

	var piece_ids: Array[String] = []
	if ex.ui_piece_ids is Array:
		for v in Array(ex.ui_piece_ids):
			var s := str(v).strip_edges()
			if not s.is_empty():
				piece_ids.append(s)
	if piece_ids.is_empty():
		piece_ids = ["lobbyists_road_straight"]

	var grid_size := _get_grid_size(state)
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("无效的地图 grid_size: %s" % str(grid_size))

	for piece_id in piece_ids:
		for rot in [0, 90, 180, 270]:
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					var cmd := Command.create("place_lobbyists_road", actor_id, {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": int(rot),
					})
					var gate: Result = engine.get_action_registry().run_validators(state, cmd)
					if not gate.ok:
						continue
					var vr: Result = ex.validate(state, cmd)
					if vr.ok:
						return Result.success(cmd)

	return Result.failure("未找到任何可放置位置（piece_ids=%s）" % str(piece_ids))

static func _find_first_valid_lobbyists_extra_map_tile(engine: GameEngine, actor_id: int) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var ex = engine.get_action_registry().get_executor("place_lobbyists_extra_map_tile")
	if ex == null:
		return Result.failure("缺少 place_lobbyists_extra_map_tile 执行器")

	var remaining: Array[String] = []
	if state.map is Dictionary and (state.map as Dictionary).has("tile_supply_remaining") and ((state.map as Dictionary)["tile_supply_remaining"] is Array):
		for v in Array((state.map as Dictionary)["tile_supply_remaining"]):
			var s := str(v).strip_edges()
			if not s.is_empty():
				remaining.append(s)
	remaining.sort()
	if remaining.is_empty():
		return Result.failure("tile_supply_remaining 为空")

	var occupied: Array[Vector2i] = _get_occupied_tile_board_positions(state)
	if occupied.is_empty():
		return Result.failure("occupied board_pos 为空")

	for tid in remaining:
		for rot in [0, 90, 180, 270]:
			for bp in occupied:
				var attach: Vector2i = bp
				for side in ["N", "E", "S", "W"]:
					var cmd := Command.create("place_lobbyists_extra_map_tile", actor_id, {
						"tile_id": tid,
						"attach_to_tile_board_pos": [attach.x, attach.y],
						"side": str(side),
						"rotation": int(rot),
					})
					var gate: Result = engine.get_action_registry().run_validators(state, cmd)
					if not gate.ok:
						continue
					var vr: Result = ex.validate(state, cmd)
					if vr.ok:
						return Result.success(cmd)

	return Result.failure("未找到任何合法扩边放置（remaining=%s）" % str(remaining))

static func _get_occupied_tile_board_positions(state: GameState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or not (state.map is Dictionary):
		return result

	var placements: Array = []
	var m: Dictionary = state.map
	if m.has("tile_placements") and (m["tile_placements"] is Array):
		placements.append_array(m["tile_placements"])
	if m.has("external_tile_placements") and (m["external_tile_placements"] is Array):
		placements.append_array(m["external_tile_placements"])

	var seen := {}
	for pv in placements:
		if not (pv is Dictionary):
			continue
		var p: Dictionary = pv
		var bp_val = p.get("board_pos", null)
		if not (bp_val is Vector2i):
			continue
		var bp: Vector2i = bp_val
		if seen.has(bp):
			continue
		seen[bp] = true
		result.append(bp)

	return result

static func _get_grid_size(state: GameState) -> Vector2i:
	if state == null or not (state.map is Dictionary):
		return Vector2i.ZERO
	var gs_val = (state.map as Dictionary).get("grid_size", Vector2i.ZERO)
	if gs_val is Vector2i:
		return gs_val
	if gs_val is Array:
		var arr: Array = gs_val
		if arr.size() == 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

static func _advance_to_player_working_sub_phase(game: Node, target_player_id: int, target_sub_phase: String, limit: int) -> Result:
	if game == null or not is_instance_valid(game):
		return Result.failure("game 为空")
	if game.game_engine == null:
		return Result.failure("game.game_engine 为空")

	var steps := 0
	while steps < limit:
		var state: GameState = game.game_engine.get_state()
		if state == null:
			return Result.failure("state 为空")
		if int(state.get_current_player_id()) == target_player_id and str(state.phase) == "Working" and str(state.sub_phase) == str(target_sub_phase):
			return Result.success({"steps": steps})

		var actor := int(state.get_current_player_id())
		if str(state.phase) != "Working":
			return Result.failure("推进失败：离开 Working（当前=%s/%s）" % [str(state.phase), str(state.sub_phase)])

		var action_id := ActionIdsClass.SKIP_SUB_PHASE
		# Working 最后子阶段：用 skip（触发 UI 层自动补完 mandatory actions）。
		if game.game_engine.phase_manager != null:
			var order: Array = game.game_engine.phase_manager.get_working_sub_phase_order_names()
			if order is Array and not order.is_empty() and str(state.sub_phase) == str(order[order.size() - 1]):
				action_id = ActionIdsClass.SKIP

		var r: Result = game._execute_command(Command.create(action_id, actor))
		if not r.ok:
			return Result.failure("推进失败：%s(%d) @ %s/%s: %s" % [action_id, actor, str(state.phase), str(state.sub_phase), r.error])

		steps += 1

	return Result.failure("推进超时：未在 %d 步内到达 P%d Working/%s" % [limit, target_player_id, str(target_sub_phase)])
