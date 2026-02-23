# 联机：命令参数脱敏测试（仅银行储备卡）
extends RefCounted

const CommandPrivacyClass = preload("res://core/utils/command_privacy.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var init: Result = engine.initialize(2, 12345)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var params := {"selected_index": 2}

	# 非本人且未揭示：应脱敏
	var other_view: Dictionary = CommandPrivacyClass.sanitize_params("select_reserve_card", 0, params, 1, state)
	if str(other_view.get("selected_index", "")) != "<hidden>":
		return Result.failure("未揭示时应脱敏 selected_index，实际: %s" % str(other_view.get("selected_index", null)))

	# Spectator/未知 viewer（非负、但不对应任何 player_id）：应视为“非本人”
	var spectator_view: Dictionary = CommandPrivacyClass.sanitize_params("select_reserve_card", 0, params, 999999, state)
	if str(spectator_view.get("selected_index", "")) != "<hidden>":
		return Result.failure("spectator 视角未揭示时应脱敏 selected_index，实际: %s" % str(spectator_view.get("selected_index", null)))

	# 本人可见
	var self_view: Dictionary = CommandPrivacyClass.sanitize_params("select_reserve_card", 0, params, 0, state)
	if int(self_view.get("selected_index", -1)) != 2:
		return Result.failure("本人应看到 selected_index=2，实际: %s" % str(self_view.get("selected_index", null)))

	# 揭示后公开
	state.players[0]["reserve_card_revealed"] = true
	var revealed_view: Dictionary = CommandPrivacyClass.sanitize_params("select_reserve_card", 0, params, 1, state)
	if int(revealed_view.get("selected_index", -1)) != 2:
		return Result.failure("揭示后应公开 selected_index=2，实际: %s" % str(revealed_view.get("selected_index", null)))

	# 具备 peek 能力：可见
	state.players[0]["reserve_card_revealed"] = false
	state.players[1]["can_peek_all_reserve_cards"] = true
	var peek_view: Dictionary = CommandPrivacyClass.sanitize_params("select_reserve_card", 0, params, 1, state)
	if int(peek_view.get("selected_index", -1)) != 2:
		return Result.failure("peek 能力下应看到 selected_index=2，实际: %s" % str(peek_view.get("selected_index", null)))

	return Result.success({
		"redacted": other_view,
		"self": self_view,
		"revealed": revealed_view,
		"peek": peek_view,
	})
