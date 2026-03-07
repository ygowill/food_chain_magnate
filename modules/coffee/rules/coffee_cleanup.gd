extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

const MODULE_ID := "coffee"
const COFFEE_ID := "coffee"

func register(registrar) -> Result:
	var r = registrar.register_extension_settlement(Phase.CLEANUP, Point.ENTER, Callable(self, "_cleanup_discard_coffee"), 150)
	if not r.ok:
		return r

	return Result.success()

func _cleanup_discard_coffee(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("coffee:cleanup: state 为空")
	if not (state.players is Array):
		return Result.failure("coffee:cleanup: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("coffee:cleanup: state.round_state 类型错误（期望 Dictionary）")

	var metadata_check := _validate_cleanup_metadata_target(state.round_state)
	if not metadata_check.ok:
		return metadata_check

	var discarded: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var player_read := PlayerStateAccessClass.require_player(state, pid, "coffee:cleanup")
		if not player_read.ok:
			return player_read
		var player: Dictionary = player_read.value
		var inv_read := PlayerStateAccessClass.require_inventory(player, "player[%d]" % pid, "coffee:cleanup")
		if not inv_read.ok:
			return inv_read
		var inv: Dictionary = inv_read.value
		var before: int = int(inv.get(COFFEE_ID, 0))
		if before > 0:
			inv[COFFEE_ID] = 0
			player["inventory"] = inv
			state.players[pid] = player
			discarded.append({
				"player_id": pid,
				"amount": before,
			})

	state.round_state["coffee"] = {
		"discarded": discarded
	}
	return Result.success()

static func _validate_cleanup_metadata_target(round_state: Dictionary) -> Result:
	if not (round_state is Dictionary):
		return Result.failure("coffee:cleanup: round_state 类型错误（期望 Dictionary）")
	if not round_state.has("coffee"):
		return Result.success()
	var coffee_val = round_state.get("coffee", null)
	if not (coffee_val is Dictionary):
		return Result.failure("coffee:cleanup: round_state.coffee 类型错误（期望 Dictionary）")
	var coffee_meta: Dictionary = coffee_val
	if coffee_meta.has("discarded") and not (coffee_meta.get("discarded", null) is Array):
		return Result.failure("coffee:cleanup: round_state.coffee.discarded 类型错误（期望 Array）")
	return Result.success()
