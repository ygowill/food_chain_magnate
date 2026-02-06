# 餐厅 Logo 分配（确定性 + 尊重显式选择）
class_name RestaurantLogoAssignmentTest
extends RefCounted

const GameConfigClass = preload("res://core/data/game_config.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

const EXPECTED_LOGO_COUNT := 6

static func run(_player_count: int = 6, seed_val: int = 12345) -> Result:
	var cfg_read := GameConfigClass.load_default()
	if not cfg_read.ok:
		return Result.failure("加载 GameConfig 失败: %s" % cfg_read.error)
	var cfg = cfg_read.value

	# 1) 默认随机：同 seed 必须确定性一致，且每位玩家唯一。
	var player_count := int(_player_count)
	if player_count <= 0:
		return Result.failure("player_count 无效: %d" % player_count)
	var rng0 := RandomManager.new(seed_val)
	var s0_read := GameStateClass.create_initial_state_with_rng(player_count, seed_val, rng0, cfg, [])
	if not s0_read.ok:
		return Result.failure("create_initial_state_with_rng 失败: %s" % s0_read.error)
	var s0: GameState = s0_read.value

	var logos0: Array[int] = []
	var seen0 := {}
	for pid in range(player_count):
		var p_val = s0.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % pid)
		var p: Dictionary = p_val
		var lid := int(p.get("restaurant_logo_id", -1))
		if lid < 0 or lid >= EXPECTED_LOGO_COUNT:
			return Result.failure("restaurant_logo_id 超出范围: pid=%d lid=%d" % [pid, lid])
		if player_count <= EXPECTED_LOGO_COUNT and seen0.has(lid):
			return Result.failure("restaurant_logo_id 重复: %s" % str(logos0))
		seen0[lid] = true
		logos0.append(lid)

	var rng1 := RandomManager.new(seed_val)
	var s1_read := GameStateClass.create_initial_state_with_rng(player_count, seed_val, rng1, cfg, [])
	if not s1_read.ok:
		return Result.failure("create_initial_state_with_rng(2) 失败: %s" % s1_read.error)
	var s1: GameState = s1_read.value

	var logos1: Array[int] = []
	for pid in range(player_count):
		logos1.append(int(Dictionary(s1.players[pid]).get("restaurant_logo_id", -1)))
	if str(logos1) != str(logos0):
		return Result.failure("默认 Logo 分配不确定性: %s vs %s" % [str(logos0), str(logos1)])

	# 2) 显式选择：指定的 pid 必须保持指定值；其余仍确定性且不重复。
	var choices: Array[int] = []
	for _i in range(player_count):
		choices.append(-1)
	if player_count >= 1:
		choices[0] = 2
	if player_count >= 3:
		choices[2] = 0
	var rng2 := RandomManager.new(seed_val)
	var s2_read := GameStateClass.create_initial_state_with_rng(player_count, seed_val, rng2, cfg, choices)
	if not s2_read.ok:
		return Result.failure("create_initial_state_with_rng(choices) 失败: %s" % s2_read.error)
	var s2: GameState = s2_read.value
	if player_count >= 1:
		var p0: Dictionary = s2.players[0]
		if int(p0.get("restaurant_logo_id", -1)) != 2:
			return Result.failure("显式选择未生效: pid0")
	if player_count >= 3:
		var p2: Dictionary = s2.players[2]
		if int(p2.get("restaurant_logo_id", -1)) != 0:
			return Result.failure("显式选择未生效: pid2")
	var seen2 := {}
	for pid in range(player_count):
		var lid := int(Dictionary(s2.players[pid]).get("restaurant_logo_id", -1))
		if player_count <= EXPECTED_LOGO_COUNT and seen2.has(lid):
			return Result.failure("显式选择后仍出现重复: %s" % str(s2.players))
		seen2[lid] = true

	var rng3 := RandomManager.new(seed_val)
	var s3_read := GameStateClass.create_initial_state_with_rng(player_count, seed_val, rng3, cfg, choices)
	if not s3_read.ok:
		return Result.failure("create_initial_state_with_rng(choices2) 失败: %s" % s3_read.error)
	var s3: GameState = s3_read.value
	for pid in range(player_count):
		var a := int(Dictionary(s2.players[pid]).get("restaurant_logo_id", -1))
		var b := int(Dictionary(s3.players[pid]).get("restaurant_logo_id", -1))
		if a != b:
			return Result.failure("显式选择下仍不确定性: pid=%d %d!=%d" % [pid, a, b])

	# 3) 重复显式选择：后续重复项应回退到随机（确保唯一）。
	var dup_choices: Array[int] = []
	for _i in range(player_count):
		dup_choices.append(-1)
	if player_count >= 2:
		dup_choices[0] = 1
		dup_choices[1] = 1
	var rng4 := RandomManager.new(seed_val)
	var s4_read := GameStateClass.create_initial_state_with_rng(player_count, seed_val, rng4, cfg, dup_choices)
	if not s4_read.ok:
		return Result.failure("create_initial_state_with_rng(dup) 失败: %s" % s4_read.error)
	var s4: GameState = s4_read.value
	if player_count >= 1:
		if int(Dictionary(s4.players[0]).get("restaurant_logo_id", -1)) != 1:
			return Result.failure("重复选择时第一个显式值应保留")
	var seen4 := {}
	for pid in range(player_count):
		var lid := int(Dictionary(s4.players[pid]).get("restaurant_logo_id", -1))
		if player_count <= EXPECTED_LOGO_COUNT and seen4.has(lid):
			return Result.failure("重复显式选择未被消解: %s" % str(s4.players))
		seen4[lid] = true

	return Result.success()
