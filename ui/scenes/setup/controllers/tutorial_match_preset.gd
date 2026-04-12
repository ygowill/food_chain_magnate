# GameSetup scene：教学局预设
# 负责：
# - 提供固定的首局教学配置
# - 避免把教学局细节散落在 setup 主场景脚本里
class_name GameSetupTutorialMatchPreset
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")

const FIXED_SEED := 20260411

static func build_preset() -> Dictionary:
	return {
		"player_count": 2,
		"seed": FIXED_SEED,
		"enabled_modules_v2": GameDefaultsClass.build_default_enabled_modules_v2(),
		"game_option_overrides": {
			"rules.salary_cost": 0,
			"rules.bankruptcy_max_breaks": 1,
			"rules.bankruptcy_extra_reserve_per_player": 75,
			"milestones.enabled": false,
		},
	}
