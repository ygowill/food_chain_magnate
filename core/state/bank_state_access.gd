class_name BankStateAccess
extends RefCounted

const KEY_TOTAL := "total"
const KEY_BROKE_COUNT := "broke_count"
const KEY_CEO_SLOTS_AFTER_FIRST_BREAK := "ceo_slots_after_first_break"
const KEY_RESERVE_ADDED_TOTAL := "reserve_added_total"
const KEY_REMOVED_TOTAL := "removed_total"

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_bank(state: GameState, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not (state.bank is Dictionary):
		return Result.failure("%sstate.bank 类型错误（期望 Dictionary）" % prefix)
	return Result.success(state.bank)

static func _require_int_field(state: GameState, key: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	var bank_read := require_bank(state, prefix_label)
	if not bank_read.ok:
		return bank_read
	var bank: Dictionary = bank_read.value
	if not bank.has(key) or not (bank[key] is int):
		return Result.failure("%sstate.bank.%s 缺失或类型错误（期望 int）" % [prefix, key])
	return Result.success(int(bank[key]))

static func require_total(state: GameState, prefix_label: String) -> Result:
	return _require_int_field(state, KEY_TOTAL, prefix_label)

static func require_broke_count(state: GameState, prefix_label: String) -> Result:
	return _require_int_field(state, KEY_BROKE_COUNT, prefix_label)

static func require_ceo_slots_after_first_break(state: GameState, prefix_label: String) -> Result:
	return _require_int_field(state, KEY_CEO_SLOTS_AFTER_FIRST_BREAK, prefix_label)

static func require_reserve_added_total(state: GameState, prefix_label: String) -> Result:
	return _require_int_field(state, KEY_RESERVE_ADDED_TOTAL, prefix_label)

static func require_removed_total(state: GameState, prefix_label: String) -> Result:
	return _require_int_field(state, KEY_REMOVED_TOTAL, prefix_label)

static func add_to_total(state: GameState, delta: int, prefix_label: String) -> Result:
	var total_read := require_total(state, prefix_label)
	if not total_read.ok:
		return total_read
	var new_total := int(total_read.value) + delta
	state.bank[KEY_TOTAL] = new_total
	return Result.success(new_total)

static func set_broke_count(state: GameState, broke_count: int, prefix_label: String) -> Result:
	if broke_count < 0:
		return Result.failure("%sbroke_count 不能为负数: %d" % [_prefix(prefix_label), broke_count])
	var current_read := require_broke_count(state, prefix_label)
	if not current_read.ok:
		return current_read
	state.bank[KEY_BROKE_COUNT] = broke_count
	return Result.success(broke_count)

static func set_ceo_slots_after_first_break(state: GameState, slots: int, prefix_label: String) -> Result:
	if slots < 1:
		return Result.failure("%sceo_slots_after_first_break 必须 >= 1，实际: %d" % [_prefix(prefix_label), slots])
	var current_read := require_ceo_slots_after_first_break(state, prefix_label)
	if not current_read.ok:
		return current_read
	state.bank[KEY_CEO_SLOTS_AFTER_FIRST_BREAK] = slots
	return Result.success(slots)

static func add_reserve_added_total(state: GameState, delta: int, prefix_label: String) -> Result:
	if delta < 0:
		return Result.failure("%sdelta 不能为负数: %d" % [_prefix(prefix_label), delta])
	var current_read := require_reserve_added_total(state, prefix_label)
	if not current_read.ok:
		return current_read
	var new_total := int(current_read.value) + delta
	state.bank[KEY_RESERVE_ADDED_TOTAL] = new_total
	return Result.success(new_total)

static func add_removed_total(state: GameState, delta: int, prefix_label: String) -> Result:
	if delta < 0:
		return Result.failure("%sdelta 不能为负数: %d" % [_prefix(prefix_label), delta])
	var current_read := require_removed_total(state, prefix_label)
	if not current_read.ok:
		return current_read
	var new_total := int(current_read.value) + delta
	state.bank[KEY_REMOVED_TOTAL] = new_total
	return Result.success(new_total)

static func apply_reserve_injection(state: GameState, amount: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if amount < 0:
		return Result.failure("%samount 不能为负数: %d" % [prefix, amount])
	var total_read := require_total(state, prefix_label)
	if not total_read.ok:
		return total_read
	var reserve_read := require_reserve_added_total(state, prefix_label)
	if not reserve_read.ok:
		return reserve_read
	var new_total := int(total_read.value) + amount
	var new_reserve_added_total := int(reserve_read.value) + amount
	state.bank[KEY_TOTAL] = new_total
	state.bank[KEY_RESERVE_ADDED_TOTAL] = new_reserve_added_total
	return Result.success({
		"total": new_total,
		"reserve_added_total": new_reserve_added_total,
	})

