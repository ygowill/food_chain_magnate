# Gameplay：新游戏餐厅 Logo 分配
# 负责：根据 seed +（可选）玩家显式选择，确定性分配每位玩家的 restaurant_logo_id。
extends RefCounted

const DEFAULT_LOGO_COUNT := 5

static func assign_logo_ids(player_count: int, rng_seed: int, restaurant_logo_choices_by_player) -> Result:
	var logo_count := DEFAULT_LOGO_COUNT
	var remaining: Array[int] = []
	for i in range(logo_count):
		remaining.append(i)

	var fixed := {} # logo_id -> true（防重复）
	var needs_random: Array[bool] = []
	for pid in range(player_count):
		needs_random.append(true)

	var assigned: Array[int] = []
	for pid in range(player_count):
		assigned.append(-1)

	for pid in range(player_count):
		var choice := _read_choice_id(restaurant_logo_choices_by_player, pid)
		if choice >= 0 and choice < logo_count and not fixed.has(choice):
			fixed[choice] = true
			needs_random[pid] = false
			assigned[pid] = choice
			remaining.erase(choice)

	var logo_rng := RandomNumberGenerator.new()
	var logo_seed := int(rng_seed) ^ int(0x4C4F474F) # 'LOGO'
	logo_rng.seed = logo_seed
	logo_rng.state = int(logo_seed)
	for i in range(remaining.size() - 1, 0, -1):
		var j := logo_rng.randi_range(0, i)
		var tmp = remaining[i]
		remaining[i] = remaining[j]
		remaining[j] = tmp

	var next_idx := 0
	for pid in range(player_count):
		if not needs_random[pid]:
			continue
		if next_idx < remaining.size():
			assigned[pid] = int(remaining[next_idx])
			next_idx += 1
		else:
			assigned[pid] = int(pid % logo_count)

	return Result.success(assigned)

static func _read_choice_id(choices, player_id: int) -> int:
	if choices == null:
		return -1
	if not (choices is Array):
		return -1
	var arr: Array = Array(choices)
	if player_id < 0 or player_id >= arr.size():
		return -1
	var v = arr[player_id]
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f)
	return -1

