class_name TimeBudget
extends RefCounted

var started_ms: int = 0
var budget_ms: int = 0

static func start(p_budget_ms: int) -> TimeBudget:
	var budget := TimeBudget.new()
	budget.started_ms = Time.get_ticks_msec()
	budget.budget_ms = maxi(0, p_budget_ms)
	return budget

func elapsed_ms() -> int:
	return maxi(0, Time.get_ticks_msec() - started_ms)

func remaining_ms() -> int:
	return maxi(0, budget_ms - elapsed_ms())

func expired() -> bool:
	return remaining_ms() <= 0

func to_debug_dict() -> Dictionary:
	return {
		"started_ms": started_ms,
		"budget_ms": budget_ms,
		"elapsed_ms": elapsed_ms(),
		"remaining_ms": remaining_ms(),
	}
