extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单：里程碑部分（聚合）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const BaseManifest = preload("res://tools/manual_test_saves/manifest_milestones_base.gd")
const CoffeeManifest = preload("res://tools/manual_test_saves/manifest_milestones_coffee.gd")
const KetchupManifest = preload("res://tools/manual_test_saves/manifest_milestones_ketchup.gd")
const LobbyistsManifest = preload("res://tools/manual_test_saves/manifest_milestones_lobbyists.gd")
const RuralMarketeersManifest = preload("res://tools/manual_test_saves/manifest_milestones_rural_marketeers.gd")
const NewMilestonesManifest = preload("res://tools/manual_test_saves/manifest_milestones_new_milestones.gd")

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	cases.append_array(BaseManifest.get_cases())
	cases.append_array(CoffeeManifest.get_cases())
	cases.append_array(KetchupManifest.get_cases())
	cases.append_array(LobbyistsManifest.get_cases())
	cases.append_array(RuralMarketeersManifest.get_cases())
	cases.append_array(NewMilestonesManifest.get_cases())
	return cases
