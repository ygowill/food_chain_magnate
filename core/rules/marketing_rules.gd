# 营销规则（M4）
# 目标：集中维护“按玩家人数移除的营销板件编号”等规则，避免散落多处导致不一致。
class_name MarketingRules
extends RefCounted

static func get_removed_board_numbers(player_count: int) -> Array[int]:
	# 对齐 docs/rules.md
	if player_count <= 2:
		return [12, 15, 16]
	if player_count == 3:
		return [15, 16]
	if player_count == 4:
		return [16]
	return []

