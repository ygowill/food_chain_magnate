# StateSchemaRegistry 未注册 int-key dict 的告警测试（F3）
# 目的：当模块自有字段仍含 "0"/"1"... 这类字符串玩家 key 时，读档应产生可定位 warning。
class_name StateSchemaUnregisteredModuleKeyWarningTest
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var e1 := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"lobbyists",
	]
	var init := e1.initialize(player_count, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var s1: GameState = e1.get_state()

	var archive := {
		"schema_version": GameState.SCHEMA_VERSION,
		"modules_v2_base_dir": e1.modules_v2_base_dir,
		"rng": e1.random_manager.to_dict(),
		"initial_state": s1.to_dict(),
		"commands": [],
		"current_index": -1,
	}

	# 注入一个“未注册 schema 的模块自有 per-player Dict”，模拟读档后的 string 玩家 key 漂移。
	var initial_state: Dictionary = archive["initial_state"]
	var rs_val = initial_state.get("round_state", null)
	if not (rs_val is Dictionary):
		return Result.failure("测试构造失败：initial_state.round_state 类型错误")
	var rs: Dictionary = rs_val
	rs["lobbyists_unregistered_test"] = {"0": true, "1": false}
	initial_state["round_state"] = rs
	archive["initial_state"] = initial_state

	var e2 := GameEngine.new()
	var load_r := e2.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("load_from_archive 失败: %s" % load_r.error)

	var found := false
	for w in load_r.warnings:
		if w is String and str(w).find("lobbyists_unregistered_test") != -1:
			found = true
			break
	if not found:
		return Result.failure("预期读档 warnings 包含 lobbyists_unregistered_test，但实际: %s" % str(load_r.warnings))

	return Result.success()

