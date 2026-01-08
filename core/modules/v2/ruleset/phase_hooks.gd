# RulesetV2：将 PhaseManager hook/order 应用逻辑下沉
class_name RulesetV2PhaseHooks
extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func apply(ruleset, phase_manager) -> Result:
	if phase_manager == null:
		return Result.failure("RulesetV2: phase_manager 为空")
	if not phase_manager.has_method("register_phase_hook") \
			or not phase_manager.has_method("register_sub_phase_hook") \
			or not phase_manager.has_method("set_working_sub_phase_order") \
			or not phase_manager.has_method("set_cleanup_sub_phase_order") \
			or not phase_manager.has_method("set_phase_order") \
			or not phase_manager.has_method("set_phase_sub_phase_order"):
		return Result.failure("RulesetV2: phase_manager 缺少 hook 注册方法")

	for i in range(ruleset.phase_hooks.size()):
		var h_val = ruleset.phase_hooks[i]
		if not (h_val is Dictionary):
			return Result.failure("RulesetV2: phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
		var h: Dictionary = h_val
		var cb: Callable = h.get("callback", Callable())
		var phase: int = int(h.get("phase", -1))
		var hook_type: int = int(h.get("hook_type", -1))
		var prio: int = int(h.get("priority", 100))
		var src: String = str(h.get("source", ""))
		if not cb.is_valid():
			return Result.failure("RulesetV2: phase_hooks[%d] callback 无效" % i)
		phase_manager.register_phase_hook(phase, hook_type, cb, prio, src)

	for i in range(ruleset.sub_phase_hooks.size()):
		var h2_val = ruleset.sub_phase_hooks[i]
		if not (h2_val is Dictionary):
			return Result.failure("RulesetV2: sub_phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
		var h2: Dictionary = h2_val
		var cb2: Callable = h2.get("callback", Callable())
		var sub_phase: int = int(h2.get("sub_phase", -1))
		var hook_type2: int = int(h2.get("hook_type", -1))
		var prio2: int = int(h2.get("priority", 100))
		var src2: String = str(h2.get("source", ""))
		if not cb2.is_valid():
			return Result.failure("RulesetV2: sub_phase_hooks[%d] callback 无效" % i)
		phase_manager.register_sub_phase_hook(sub_phase, hook_type2, cb2, prio2, src2)

	# custom named subphase hooks (by name, independent of phase)
	if not ruleset.named_sub_phase_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(ruleset.named_sub_phase_hooks.size()):
			var h0_val = ruleset.named_sub_phase_hooks[i]
			if not (h0_val is Dictionary):
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h0: Dictionary = h0_val
			var cb0: Callable = h0.get("callback", Callable())
			var name0: String = str(h0.get("sub_phase", ""))
			var hook_type0: int = int(h0.get("hook_type", -1))
			var prio0: int = int(h0.get("priority", 100))
			var src0: String = str(h0.get("source", ""))
			if name0.is_empty():
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d].sub_phase 不能为空" % i)
			if not cb0.is_valid():
				return Result.failure("RulesetV2: named_sub_phase_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name0, hook_type0, cb0, prio0, src0)

	# working subphase order (base + insertions)
	if ruleset.working_sub_phase_order_override != null and not ruleset.working_sub_phase_insertions.is_empty():
		return Result.failure("RulesetV2: working_sub_phase_order_override 与 insertions 不能同时使用")
	var order_names: Array[String] = []
	for sub_id in PhaseDefsClass.SUB_PHASE_ORDER:
		order_names.append(str(PhaseDefsClass.SUB_PHASE_NAMES[sub_id]))

	for i in range(ruleset.working_sub_phase_insertions.size()):
		var ins_val = ruleset.working_sub_phase_insertions[i]
		if not (ins_val is Dictionary):
			return Result.failure("RulesetV2: working_sub_phase_insertions[%d] 类型错误（期望 Dictionary）" % i)
		var ins: Dictionary = ins_val
		var name: String = str(ins.get("sub_phase", ""))
		var after: String = str(ins.get("after", ""))
		var before: String = str(ins.get("before", ""))
		if name.is_empty():
			return Result.failure("RulesetV2: working_sub_phase_insertions[%d].sub_phase 不能为空" % i)
		if order_names.has(name):
			return Result.failure("RulesetV2: working sub_phase 重复: %s" % name)

		var insert_index := -1
		if not after.is_empty():
			var idx_after := order_names.find(after)
			if idx_after == -1:
				return Result.failure("RulesetV2: working sub_phase after 未找到: %s (insert:%s)" % [after, name])
			insert_index = idx_after + 1
		if not before.is_empty():
			var idx_before := order_names.find(before)
			if idx_before == -1:
				return Result.failure("RulesetV2: working sub_phase before 未找到: %s (insert:%s)" % [before, name])
			if insert_index == -1:
				insert_index = idx_before
			else:
				if insert_index > idx_before:
					return Result.failure("RulesetV2: working sub_phase after/before 顺序冲突: after=%s before=%s (insert:%s)" % [after, before, name])
		if insert_index == -1:
			return Result.failure("RulesetV2: working sub_phase 插入位置非法: %s" % name)

		order_names.insert(insert_index, name)

	if ruleset.working_sub_phase_order_override != null:
		var o2_val = ruleset.working_sub_phase_order_override.get("order", null)
		if not (o2_val is Array):
			return Result.failure("RulesetV2: working_sub_phase_order_override.order 类型错误（期望 Array）")
		var override_names: Array[String] = []
		var raw: Array = o2_val
		for i in range(raw.size()):
			if not (raw[i] is String):
				return Result.failure("RulesetV2: working_sub_phase_order_override.order[%d] 类型错误（期望 String）" % i)
			override_names.append(str(raw[i]))
		order_names = override_names

	var set_order: Result = phase_manager.set_working_sub_phase_order(order_names)
	if not set_order.ok:
		return set_order

	# custom working subphase hooks (by name)
	if not ruleset.working_sub_phase_name_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(ruleset.working_sub_phase_name_hooks.size()):
			var h3_val = ruleset.working_sub_phase_name_hooks[i]
			if not (h3_val is Dictionary):
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h3: Dictionary = h3_val
			var cb3: Callable = h3.get("callback", Callable())
			var name3: String = str(h3.get("sub_phase", ""))
			var hook_type3: int = int(h3.get("hook_type", -1))
			var prio3: int = int(h3.get("priority", 100))
			var src3: String = str(h3.get("source", ""))
			if name3.is_empty():
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d].sub_phase 不能为空" % i)
			if not cb3.is_valid():
				return Result.failure("RulesetV2: working_sub_phase_name_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name3, hook_type3, cb3, prio3, src3)

	# cleanup subphase order (custom only)
	if ruleset.cleanup_sub_phase_order_override != null and not ruleset.cleanup_sub_phase_insertions.is_empty():
		return Result.failure("RulesetV2: cleanup_sub_phase_order_override 与 insertions 不能同时使用")
	var cleanup_order_names: Array[String] = []
	if ruleset.cleanup_sub_phase_order_override != null:
		var o3_val = ruleset.cleanup_sub_phase_order_override.get("order", null)
		if not (o3_val is Array):
			return Result.failure("RulesetV2: cleanup_sub_phase_order_override.order 类型错误（期望 Array）")
		var override_names2: Array[String] = []
		var raw2: Array = o3_val
		for i in range(raw2.size()):
			if not (raw2[i] is String):
				return Result.failure("RulesetV2: cleanup_sub_phase_order_override.order[%d] 类型错误（期望 String）" % i)
			override_names2.append(str(raw2[i]))
		cleanup_order_names = override_names2
	for i in range(ruleset.cleanup_sub_phase_insertions.size()):
		var ins_val2 = ruleset.cleanup_sub_phase_insertions[i]
		if not (ins_val2 is Dictionary):
			return Result.failure("RulesetV2: cleanup_sub_phase_insertions[%d] 类型错误（期望 Dictionary）" % i)
		var ins2: Dictionary = ins_val2
		var name4: String = str(ins2.get("sub_phase", ""))
		var after4: String = str(ins2.get("after", ""))
		var before4: String = str(ins2.get("before", ""))
		if name4.is_empty():
			return Result.failure("RulesetV2: cleanup_sub_phase_insertions[%d].sub_phase 不能为空" % i)
		if cleanup_order_names.has(name4):
			return Result.failure("RulesetV2: cleanup sub_phase 重复: %s" % name4)

		var insert_index2 := -1
		if cleanup_order_names.is_empty() and after4.is_empty() and before4.is_empty():
			insert_index2 = 0
		else:
			if not after4.is_empty():
				var idx_after2 := cleanup_order_names.find(after4)
				if idx_after2 == -1:
					return Result.failure("RulesetV2: cleanup sub_phase after 未找到: %s (insert:%s)" % [after4, name4])
				insert_index2 = idx_after2 + 1
			if not before4.is_empty():
				var idx_before2 := cleanup_order_names.find(before4)
				if idx_before2 == -1:
					return Result.failure("RulesetV2: cleanup sub_phase before 未找到: %s (insert:%s)" % [before4, name4])
				if insert_index2 == -1:
					insert_index2 = idx_before2
				else:
					if insert_index2 > idx_before2:
						return Result.failure("RulesetV2: cleanup sub_phase after/before 顺序冲突: after=%s before=%s (insert:%s)" % [after4, before4, name4])
			if insert_index2 == -1:
				return Result.failure("RulesetV2: cleanup sub_phase 插入位置非法: %s" % name4)

		cleanup_order_names.insert(insert_index2, name4)

	if not cleanup_order_names.is_empty():
		var set_cleanup_order: Result = phase_manager.set_cleanup_sub_phase_order(cleanup_order_names)
		if not set_cleanup_order.ok:
			return set_cleanup_order

	# custom cleanup subphase hooks (by name)
	if not ruleset.cleanup_sub_phase_name_hooks.is_empty():
		if not phase_manager.has_method("register_sub_phase_hook_by_name"):
			return Result.failure("RulesetV2: phase_manager 缺少 register_sub_phase_hook_by_name")
		for i in range(ruleset.cleanup_sub_phase_name_hooks.size()):
			var h4_val = ruleset.cleanup_sub_phase_name_hooks[i]
			if not (h4_val is Dictionary):
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d] 类型错误（期望 Dictionary）" % i)
			var h4: Dictionary = h4_val
			var cb4: Callable = h4.get("callback", Callable())
			var name5: String = str(h4.get("sub_phase", ""))
			var hook_type4: int = int(h4.get("hook_type", -1))
			var prio4: int = int(h4.get("priority", 100))
			var src4: String = str(h4.get("source", ""))
			if name5.is_empty():
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d].sub_phase 不能为空" % i)
			if not cb4.is_valid():
				return Result.failure("RulesetV2: cleanup_sub_phase_name_hooks[%d] callback 无效" % i)
			phase_manager.register_sub_phase_hook_by_name(name5, hook_type4, cb4, prio4, src4)

	# settlement triggers override
	if not ruleset.settlement_triggers_override.is_empty():
		if not phase_manager.has_method("set_settlement_triggers_on_enter") or not phase_manager.has_method("set_settlement_triggers_on_exit"):
			return Result.failure("RulesetV2: phase_manager 缺少 settlement_triggers 设置方法")
		for i in range(ruleset.settlement_triggers_override.size()):
			var item_val5 = ruleset.settlement_triggers_override[i]
			if not (item_val5 is Dictionary):
				return Result.failure("RulesetV2: settlement_triggers_override[%d] 类型错误（期望 Dictionary）" % i)
			var item5: Dictionary = item_val5
			var phase5: int = int(item5.get("phase", -1))
			var timing5: String = str(item5.get("timing", ""))
			var points5 = item5.get("points", null)
			if not (points5 is Array):
				return Result.failure("RulesetV2: settlement_triggers_override[%d].points 类型错误（期望 Array）" % i)
			var set_r: Result
			if timing5 == "enter":
				set_r = phase_manager.set_settlement_triggers_on_enter(phase5, points5)
			elif timing5 == "exit":
				set_r = phase_manager.set_settlement_triggers_on_exit(phase5, points5)
			else:
				return Result.failure("RulesetV2: settlement_triggers_override[%d].timing 不支持: %s" % [i, timing5])
			if not set_r.ok:
				return set_r

	# phase sub phase order overrides
	if not ruleset.phase_sub_phase_order_overrides.is_empty():
		for i in range(ruleset.phase_sub_phase_order_overrides.size()):
			var item_val6 = ruleset.phase_sub_phase_order_overrides[i]
			if not (item_val6 is Dictionary):
				return Result.failure("RulesetV2: phase_sub_phase_order_overrides[%d] 类型错误（期望 Dictionary）" % i)
			var item6: Dictionary = item_val6
			var phase6: int = int(item6.get("phase", -1))
			var order6 = item6.get("order", null)
			if not (order6 is Array):
				return Result.failure("RulesetV2: phase_sub_phase_order_overrides[%d].order 类型错误（期望 Array）" % i)
			var set_r2: Result = phase_manager.set_phase_sub_phase_order(phase6, order6)
			if not set_r2.ok:
				return set_r2

	# phase order override (optional)
	if ruleset.phase_order_override != null:
		var o_val = ruleset.phase_order_override.get("order", null)
		if not (o_val is Array):
			return Result.failure("RulesetV2: phase_order_override.order 类型错误（期望 Array）")
		var r_set_phase: Result = phase_manager.set_phase_order(o_val)
		if not r_set_phase.ok:
			return r_set_phase

	return Result.success()
