# 模块供给展示的兜底配置（放在 core，避免 UI 硬编码模块细节）。
class_name ModuleSupplyFallbacks
extends RefCounted

const _LOBBYISTS_SUPPLY_FALLBACKS := {
	"lobbyists_road_straight_supply_remaining": 4,
	"lobbyists_road_long_supply_remaining": 2,
	"lobbyists_road_l_supply_remaining": 2,
	"lobbyists_park_line_supply_remaining": 1,
	"lobbyists_park_t_supply_remaining": 1,
	"lobbyists_park_l_supply_remaining": 2,
}
const _RURAL_OFFRAMP_SUPPLY_FALLBACK_KEY := "rural_marketeers_offramp_supply_remaining"
const _RURAL_OFFRAMP_SUPPLY_FALLBACK_TOTAL := 3
const _RURAL_BILLBOARD_SUPPLY_PSEUDO_KEY := "rural_billboard_supply_remaining"
const _RURAL_BILLBOARD_SUPPLY_TOTAL := 4

static func get_lobbyists_supply_fallbacks() -> Dictionary:
	return _LOBBYISTS_SUPPLY_FALLBACKS.duplicate()

static func get_rural_offramp_supply_fallback_key() -> String:
	return _RURAL_OFFRAMP_SUPPLY_FALLBACK_KEY

static func get_rural_offramp_supply_fallback_total() -> int:
	return _RURAL_OFFRAMP_SUPPLY_FALLBACK_TOTAL

static func get_rural_billboard_supply_pseudo_key() -> String:
	return _RURAL_BILLBOARD_SUPPLY_PSEUDO_KEY

static func get_rural_billboard_supply_total() -> int:
	return _RURAL_BILLBOARD_SUPPLY_TOTAL
