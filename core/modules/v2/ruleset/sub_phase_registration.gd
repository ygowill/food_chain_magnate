# RulesetV2：Working/Cleanup 子阶段插入与 hook 注册下沉
class_name RulesetV2SubPhaseRegistration
extends RefCounted

static func register_working_sub_phase_insertion(
	ruleset,
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if after_sub_phase_name.is_empty() and before_sub_phase_name.is_empty():
		return Result.failure("RulesetV2: after/before 不能同时为空")

	for item_val in ruleset.working_sub_phase_insertions:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("sub_phase", "")) == sub_phase_name:
			return Result.failure("RulesetV2: working sub_phase 重复插入: %s (module:%s)" % [sub_phase_name, source_module_id])

	ruleset.working_sub_phase_insertions.append({
		"sub_phase": sub_phase_name,
		"after": after_sub_phase_name,
		"before": before_sub_phase_name,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.working_sub_phase_insertions.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

static func register_working_sub_phase_hook(
	ruleset,
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)

	ruleset.working_sub_phase_name_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.working_sub_phase_name_hooks.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

static func register_cleanup_sub_phase_insertion(
	ruleset,
	sub_phase_name: String,
	after_sub_phase_name: String,
	before_sub_phase_name: String,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")

	for item_val in ruleset.cleanup_sub_phase_insertions:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("sub_phase", "")) == sub_phase_name:
			return Result.failure("RulesetV2: cleanup sub_phase 重复插入: %s (module:%s)" % [sub_phase_name, source_module_id])

	ruleset.cleanup_sub_phase_insertions.append({
		"sub_phase": sub_phase_name,
		"after": after_sub_phase_name,
		"before": before_sub_phase_name,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.cleanup_sub_phase_insertions.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

static func register_cleanup_sub_phase_hook(
	ruleset,
	sub_phase_name: String,
	hook_type: int,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if sub_phase_name.is_empty():
		return Result.failure("RulesetV2: sub_phase_name 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: sub_phase hook callback 无效")
	if hook_type < 0 or hook_type > 3:
		return Result.failure("RulesetV2: sub_phase hook hook_type 越界: %d" % hook_type)

	ruleset.cleanup_sub_phase_name_hooks.append({
		"sub_phase": sub_phase_name,
		"hook_type": hook_type,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	ruleset.cleanup_sub_phase_name_hooks.sort_custom(func(a, b) -> bool:
		if int(a.priority) != int(b.priority):
			return int(a.priority) < int(b.priority)
		if str(a.sub_phase) != str(b.sub_phase):
			return str(a.sub_phase) < str(b.sub_phase)
		return str(a.source) < str(b.source)
	)
	return Result.success()

