class_name PlayerStateAccess
extends RefCounted

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

static func require_player(state: GameState, player_id: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if state == null:
		return Result.failure("%sstate 为空" % prefix)
	if not (state.players is Array):
		return Result.failure("%sstate.players 类型错误（期望 Array）" % prefix)
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("%splayer_id 越界: %d" % [prefix, player_id])
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("%splayers[%d] 类型错误（期望 Dictionary）" % [prefix, player_id])
	return Result.success(player_val)

static func require_milestones(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("%s%s.milestones 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["milestones"])

static func require_employees(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("%s%s.employees 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["employees"])

static func require_reserve_employees(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("reserve_employees") or not (player["reserve_employees"] is Array):
		return Result.failure("%s%s.reserve_employees 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["reserve_employees"])

static func require_busy_marketers(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("busy_marketers") or not (player["busy_marketers"] is Array):
		return Result.failure("%s%s.busy_marketers 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["busy_marketers"])

static func require_staff_registry(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("staff_registry") or not (player["staff_registry"] is Dictionary):
		return Result.failure("%s%s.staff_registry 缺失或类型错误（期望 Dictionary）" % [prefix, player_label])
	return Result.success(player["staff_registry"])

static func require_employees_staff_ids(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("employees_staff_ids") or not (player["employees_staff_ids"] is Array):
		return Result.failure("%s%s.employees_staff_ids 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["employees_staff_ids"])

static func require_reserve_staff_ids(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("reserve_staff_ids") or not (player["reserve_staff_ids"] is Array):
		return Result.failure("%s%s.reserve_staff_ids 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["reserve_staff_ids"])

static func require_busy_staff_ids(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("busy_staff_ids") or not (player["busy_staff_ids"] is Array):
		return Result.failure("%s%s.busy_staff_ids 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["busy_staff_ids"])

static func require_company_structure(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("company_structure") or not (player["company_structure"] is Dictionary):
		return Result.failure("%s%s.company_structure 缺失或类型错误（期望 Dictionary）" % [prefix, player_label])
	return Result.success(player["company_structure"])

static func require_inventory(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("inventory") or not (player["inventory"] is Dictionary):
		return Result.failure("%s%s.inventory 缺失或类型错误（期望 Dictionary）" % [prefix, player_label])
	return Result.success(player["inventory"])

static func require_restaurants(player: Dictionary, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has("restaurants") or not (player["restaurants"] is Array):
		return Result.failure("%s%s.restaurants 缺失或类型错误（期望 Array）" % [prefix, player_label])
	return Result.success(player["restaurants"])

static func require_int_field(player: Dictionary, field_name: String, player_label: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if not player.has(field_name) or not (player[field_name] is int):
		return Result.failure("%s%s.%s 缺失或类型错误（期望 int）" % [prefix, player_label, field_name])
	return Result.success(player[field_name])

static func require_player_milestones(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_milestones(player, "player[%d]" % player_id, prefix_label)

static func require_player_inventory(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_inventory(player, "player[%d]" % player_id, prefix_label)

static func require_player_employees(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_employees(player, "player[%d]" % player_id, prefix_label)

static func require_player_reserve_employees(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_reserve_employees(player, "player[%d]" % player_id, prefix_label)

static func require_player_busy_marketers(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_busy_marketers(player, "player[%d]" % player_id, prefix_label)

static func require_player_company_structure(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_company_structure(player, "player[%d]" % player_id, prefix_label)

static func require_player_restaurants(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_restaurants(player, "player[%d]" % player_id, prefix_label)

static func require_player_staff_registry(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_staff_registry(player, "player[%d]" % player_id, prefix_label)

static func require_player_employees_staff_ids(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_employees_staff_ids(player, "player[%d]" % player_id, prefix_label)

static func require_player_reserve_staff_ids(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_reserve_staff_ids(player, "player[%d]" % player_id, prefix_label)

static func require_player_busy_staff_ids(state: GameState, player_id: int, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_busy_staff_ids(player, "player[%d]" % player_id, prefix_label)

static func require_player_int_field(state: GameState, player_id: int, field_name: String, prefix_label: String) -> Result:
	var player_read := require_player(state, player_id, prefix_label)
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	return require_int_field(player, field_name, "player[%d]" % player_id, prefix_label)
