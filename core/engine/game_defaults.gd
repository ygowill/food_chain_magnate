# 游戏默认配置（core）
# 说明：集中管理默认启用模块与模块根目录，避免在 autoload/UI/core 多处重复硬编码。
class_name GameDefaults
extends RefCounted

const DEFAULT_MODULES_V2_BASE_DIR := "res://modules"

const _DEFAULT_ENABLED_MODULES_V2 := [
	"base_rules",
	"base_products",
	"base_pieces",
	"base_tiles",
	"base_maps",
	"base_employees",
	"base_milestones",
	"base_marketing",
]

static func build_default_enabled_modules_v2() -> Array[String]:
	return Array(_DEFAULT_ENABLED_MODULES_V2, TYPE_STRING, "", null)

