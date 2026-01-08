extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

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

	var discarded: Array[Dictionary] = []
	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("coffee:cleanup: player[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		var inv_val = player.get("inventory", null)
		if not (inv_val is Dictionary):
			return Result.failure("coffee:cleanup: player[%d].inventory 类型错误（期望 Dictionary）" % pid)
		var inv: Dictionary = inv_val
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
