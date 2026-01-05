# GameEngine：动作装配（ruleset wiring + availability 编译）
# 负责：基于 ActionSetup 构建内建 ActionRegistry，并应用 ruleset_v2 注入的校验器/执行器/动作可用性覆盖。
extends RefCounted

const ActionSetupClass = preload("res://core/engine/game_engine/action_setup.gd")
const ActionAvailabilityRegistryClass = preload("res://core/actions/action_availability_registry.gd")

static func setup_action_registry(engine, piece_registry: Dictionary = {}) -> Result:
	if engine == null:
		return Result.failure("内部错误：GameEngine 为空")
	if engine.phase_manager == null:
		return Result.failure("内部错误：PhaseManager 为空")

	engine.action_registry = ActionSetupClass.build_registry(engine.phase_manager, piece_registry)
	var registry: ActionRegistry = engine.action_registry

	var ruleset = engine.ruleset_v2
	if ruleset != null:
		if ruleset.global_action_validators is Array:
			var globals: Array = ruleset.global_action_validators
			for i in range(globals.size()):
				var item_val = globals[i]
				if not (item_val is Dictionary):
					continue
				var item: Dictionary = item_val
				var vid: String = str(item.get("validator_id", ""))
				var cb: Callable = item.get("callback", Callable())
				var prio: int = int(item.get("priority", 100))
				if not vid.is_empty() and cb.is_valid():
					registry.register_global_validator(vid, cb, prio)

		if ruleset.action_validators is Array:
			var list: Array = ruleset.action_validators
			for i in range(list.size()):
				var item_val2 = list[i]
				if not (item_val2 is Dictionary):
					continue
				var item2: Dictionary = item_val2
				var action_id: String = str(item2.get("action_id", ""))
				var validator_id: String = str(item2.get("validator_id", ""))
				var cb2: Callable = item2.get("callback", Callable())
				var prio2: int = int(item2.get("priority", 100))
				if not action_id.is_empty() and not validator_id.is_empty() and cb2.is_valid():
					registry.register_validator(action_id, validator_id, cb2, prio2)

		var execs_val = ruleset.action_executors
		if execs_val is Array:
			var execs: Array = execs_val
			for i in range(execs.size()):
				var ex = execs[i]
				if ex is ActionExecutor:
					registry.register_executor(ex)

	# 动作可用性（phase/sub_phase -> action_ids）
	var availability := ActionAvailabilityRegistryClass.new()
	var all_execs: Array = []
	for aid_val in registry.get_all_action_ids():
		if not (aid_val is String):
			continue
		var aid: String = str(aid_val)
		if aid.is_empty():
			continue
		var ex2 := registry.get_executor(aid)
		if ex2 != null:
			all_execs.append(ex2)
	var defaults_r := availability.build_defaults_from_executors(all_execs)
	if not defaults_r.ok:
		return defaults_r

	# 覆盖（按 action_id 选择优先级最高的那个）
	if ruleset != null and ruleset.action_availability_overrides is Array:
		var list2: Array = ruleset.action_availability_overrides
		var applied := {}
		for item_val3 in list2:
			if not (item_val3 is Dictionary):
				continue
			var item3: Dictionary = item_val3
			var action_id2: String = str(item3.get("action_id", ""))
			if action_id2.is_empty():
				continue
			if applied.has(action_id2):
				continue
			var points_val = item3.get("points", [])
			if not (points_val is Array):
				continue
			var points: Array = points_val
			var prio3: int = int(item3.get("priority", 100))
			var src: String = str(item3.get("source", ""))
			var reg_r := availability.register_action_points_override(action_id2, points, prio3, src)
			if not reg_r.ok:
				return reg_r
			applied[action_id2] = true

	var compile_r := availability.compile_with_validation(registry.get_all_action_ids())
	if not compile_r.ok:
		return compile_r
	registry.set_availability_registry(availability)

	return Result.success()
