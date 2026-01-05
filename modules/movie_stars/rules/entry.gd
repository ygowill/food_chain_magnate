extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const MODULE_ID := "movie_stars"
const STAR_IDS: Array[String] = ["movie_star_b", "movie_star_c", "movie_star_d"]
const STAR_RANK := {
	"movie_star_b": 3,
	"movie_star_c": 2,
	"movie_star_d": 1,
}

const EFFECT_ID_TIEBREAK_B := "movie_stars:dinnertime:tiebreaker:movie_star_b"
const EFFECT_ID_TIEBREAK_C := "movie_stars:dinnertime:tiebreaker:movie_star_c"
const EFFECT_ID_TIEBREAK_D := "movie_stars:dinnertime:tiebreaker:movie_star_d"

func register(registrar) -> Result:
	var r = registrar.register_effect(EFFECT_ID_TIEBREAK_B, Callable(self, "_effect_dinnertime_tiebreaker_movie_star_b"))
	if not r.ok:
		return r
	r = registrar.register_effect(EFFECT_ID_TIEBREAK_C, Callable(self, "_effect_dinnertime_tiebreaker_movie_star_c"))
	if not r.ok:
		return r
	r = registrar.register_effect(EFFECT_ID_TIEBREAK_D, Callable(self, "_effect_dinnertime_tiebreaker_movie_star_d"))
	if not r.ok:
		return r

	# 受控 patch：将 waitress.train_to 追加 movie_star_b/c/d（Strict Mode：目标员工不存在则 init fail）
	r = registrar.register_employee_patch("waitress", {
		"add_train_to": STAR_IDS
	})
	if not r.ok:
		return r

	# OrderOfBusiness：由模块在 AFTER_ENTER 重排 selection_order（避免 core 硬编码）。
	r = registrar.register_phase_hook(Phase.ORDER_OF_BUSINESS, HookType.AFTER_ENTER, Callable(self, "_on_order_of_business_after_enter"), 0)
	if not r.ok:
		return r

	# 训练限制：每位玩家最多拥有 1 张电影明星（B/C/D 任意其一）
	r = registrar.register_action_validator("train", "%s:movie_star_exclusive" % MODULE_ID, Callable(self, "_validate_train_movie_star_exclusive"), 0)
	if not r.ok:
		return r

	return Result.success()

func _effect_dinnertime_tiebreaker_movie_star_b(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	return _apply_star_tiebreak(ctx, "movie_star_b")

func _effect_dinnertime_tiebreaker_movie_star_c(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	return _apply_star_tiebreak(ctx, "movie_star_c")

func _effect_dinnertime_tiebreaker_movie_star_d(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
	return _apply_star_tiebreak(ctx, "movie_star_d")

func _apply_star_tiebreak(ctx: Dictionary, star_id: String) -> Result:
	if not ctx.has("score") or not (ctx["score"] is int):
		return Result.failure("%s:tiebreaker: ctx.score 缺失或类型错误（期望 int）" % MODULE_ID)
	if not STAR_RANK.has(star_id):
		return Result.failure("%s:tiebreaker: 未知 movie_star: %s" % [MODULE_ID, star_id])
	# 自动赢得“女服务员数量”平局链路：使用远大于 waitress 计数的加成，并保持 B>C>D 的严格排序。
	var rank: int = int(STAR_RANK[star_id])
	ctx["score"] = int(ctx["score"]) + rank * 1000
	return Result.success()

func _on_order_of_business_after_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("%s: state 为空" % MODULE_ID)
	if state.phase != "OrderOfBusiness":
		return Result.success()
	if not (state.round_state is Dictionary):
		return Result.failure("%s: state.round_state 类型错误（期望 Dictionary）" % MODULE_ID)
	if not state.round_state.has("order_of_business") or not (state.round_state["order_of_business"] is Dictionary):
		return Result.failure("%s: order_of_business 未初始化" % MODULE_ID)

	var oob: Dictionary = state.round_state["order_of_business"]
	var prev_turn: Array = oob.get("previous_turn_order", [])
	if not (prev_turn is Array) or prev_turn.size() != state.players.size():
		return Result.failure("%s: order_of_business.previous_turn_order 缺失或类型错误" % MODULE_ID)

	# 1) 收集每位玩家的 star_rank（若同级别出现则报错）
	var star_players: Array[Dictionary] = [] # {pid, rank, star_id}
	var non_star: Array[int] = []
	var seen_rank := {}
	for pid in range(state.players.size()):
		var rank_read := _get_player_star_rank(state.players[pid])
		if not rank_read.ok:
			return rank_read
		var info: Dictionary = rank_read.value
		var rank: int = int(info.get("rank", 0))
		if rank > 0:
			if seen_rank.has(rank):
				return Result.failure("%s: 不可能存在同级别电影明星（rank=%d）" % [MODULE_ID, rank])
			seen_rank[rank] = true
			star_players.append({
				"pid": pid,
				"rank": rank,
				"star_id": str(info.get("star_id", ""))
			})
		else:
			non_star.append(pid)

	# 2) 明星玩家按 rank 降序（B=3,C=2,D=1）；其余玩家按空槽数降序（同原规则）
	star_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rank"]) > int(b["rank"])
	)

	var prev_index := {}
	for i in range(prev_turn.size()):
		prev_index[int(prev_turn[i])] = i

	non_star.sort_custom(func(a: int, b: int) -> bool:
		var a_slots := WorkingFlowClass._compute_order_of_business_empty_slots(state, state.players[a])
		var b_slots := WorkingFlowClass._compute_order_of_business_empty_slots(state, state.players[b])
		if a_slots != b_slots:
			return a_slots > b_slots
		assert(prev_index.has(a), "%s: previous_turn_order 缺少玩家: %d" % [MODULE_ID, a])
		assert(prev_index.has(b), "%s: previous_turn_order 缺少玩家: %d" % [MODULE_ID, b])
		return int(prev_index[a]) < int(prev_index[b])
	)

	var selection: Array[int] = []
	for item in star_players:
		selection.append(int(item["pid"]))
	for pid in non_star:
		selection.append(int(pid))

	state.selection_order = selection
	state.turn_order = selection
	state.current_player_index = 0

	oob["selection_order"] = selection
	state.round_state["order_of_business"] = oob

	return Result.success()

func _validate_train_movie_star_exclusive(state: GameState, command: Command) -> Result:
	if state == null or command == null:
		return Result.success()
	if not (command.params is Dictionary):
		return Result.success()
	var to_val = command.params.get("to_employee", null)
	if not (to_val is String):
		return Result.success()
	var to_id: String = str(to_val)
	if not STAR_IDS.has(to_id):
		return Result.success()

	var player_id: int = int(command.actor)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("%s: player_id 越界: %d" % [MODULE_ID, player_id])
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("%s: players[%d] 类型错误（期望 Dictionary）" % [MODULE_ID, player_id])
	var player: Dictionary = p_val

	var existing := _collect_player_movie_stars(player)
	if not existing.ok:
		return existing
	var stars: Array[String] = existing.value
	if stars.size() > 0:
		return Result.failure("每位玩家最多拥有 1 张电影明星（已拥有: %s）" % str(stars))

	return Result.success()

func _collect_player_movie_stars(player: Dictionary) -> Result:
	if player == null:
		return Result.failure("%s: player 为空" % MODULE_ID)
	var ids: Array[String] = []
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var v = player.get(key, null)
		if v == null:
			continue
		if not (v is Array):
			return Result.failure("%s: player.%s 类型错误（期望 Array）" % [MODULE_ID, key])
		var arr: Array = v
		for i in range(arr.size()):
			var item = arr[i]
			if not (item is String):
				return Result.failure("%s: player.%s[%d] 类型错误（期望 String）" % [MODULE_ID, key, i])
			var eid: String = str(item)
			if STAR_IDS.has(eid) and not ids.has(eid):
				ids.append(eid)
	ids.sort()
	return Result.success(ids)

func _get_player_star_rank(player_val) -> Result:
	if not (player_val is Dictionary):
		return Result.failure("%s: player 类型错误（期望 Dictionary）" % MODULE_ID)
	var player: Dictionary = player_val
	var employees_val = player.get("employees", null)
	if not (employees_val is Array):
		return Result.failure("%s: player.employees 缺失或类型错误（期望 Array）" % MODULE_ID)
	var employees: Array = employees_val

	var found: String = ""
	for i in range(employees.size()):
		var e_val = employees[i]
		if not (e_val is String):
			return Result.failure("%s: player.employees[%d] 类型错误（期望 String）" % [MODULE_ID, i])
		var eid: String = str(e_val)
		if STAR_IDS.has(eid):
			if not found.is_empty():
				return Result.failure("%s: 每位玩家最多拥有 1 张电影明星（当前发现多个在岗: %s, %s）" % [MODULE_ID, found, eid])
			found = eid
	if found.is_empty():
		return Result.success({"rank": 0, "star_id": ""})
	return Result.success({"rank": int(STAR_RANK.get(found, 0)), "star_id": found})
