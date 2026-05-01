# 存档加载：StateSchemaRegistry 归一化回归测试（C2）
# 覆盖：
# - loader.gd 必须在 GameState.from_dict 之前装配模块系统 V2（以便 state schema 生效）
# - 模块注册的 round_state int-key dict，在 JSON key string 化后读档应恢复为 int key
class_name StateSchemaArchiveLoadTest
extends RefCounted

const LOBBYISTS_PENDING_KEY := "lobbyists_extra_tile_pending"
const RulesRegistryBundleClass = preload("res://core/engine/game_engine/rules_registry_bundle.gd")
const StateSchemaRegistryClass = preload("res://core/state/state_schema_registry.gd")

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

	# 注入 2 个 schema：
	# 1) lobbyists: round_state.<player_id -> bool>
	var pending := {}
	pending[0] = true
	pending[1] = false
	s1.round_state[LOBBYISTS_PENDING_KEY] = pending

	# 2) base_rules: round_state.restructuring.submitted（nested path）
	s1.round_state["restructuring"] = {"submitted": {0: true, 1: false}, "finalized": false}

	var archive := {
		"schema_version": GameState.SCHEMA_VERSION,
		"modules_v2_base_dir": e1.modules_v2_base_dir,
		"rng": e1.random_manager.to_dict(),
		"initial_state": s1.to_dict(),
		"commands": [],
		"current_index": -1,
	}

	var e2 := GameEngine.new()
	var load_r := e2.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("load_from_archive 失败: %s" % load_r.error)
	var s2: GameState = e2.get_state()

	var p_val = s2.round_state.get(LOBBYISTS_PENDING_KEY, null)
	if not (p_val is Dictionary):
		return Result.failure("缺少/错误字段: round_state.%s" % LOBBYISTS_PENDING_KEY)
	var p2: Dictionary = p_val
	if p2.has("0") or p2.has("1"):
		return Result.failure("round_state.%s 不应包含字符串玩家 key（应归一化为 int）" % LOBBYISTS_PENDING_KEY)
	if not (p2.get(0, null) is bool) or not (p2.get(1, null) is bool):
		return Result.failure("round_state.%s 值类型错误（期望 bool）" % LOBBYISTS_PENDING_KEY)

	var r_val = s2.round_state.get("restructuring", null)
	if not (r_val is Dictionary):
		return Result.failure("缺少/错误字段: round_state.restructuring")
	var restructuring: Dictionary = r_val
	var sub_val = restructuring.get("submitted", null)
	if not (sub_val is Dictionary):
		return Result.failure("缺少/错误字段: round_state.restructuring.submitted")
	var submitted: Dictionary = sub_val
	if submitted.has("0") or submitted.has("1"):
		return Result.failure("round_state.restructuring.submitted 不应包含字符串玩家 key（应归一化为 int）")
	if not (submitted.get(0, null) is bool) or not (submitted.get(1, null) is bool):
		return Result.failure("round_state.restructuring.submitted 值类型错误（期望 bool）")

	var strict_r := _test_from_dict_rejects_module_state_without_schema_registry(s1.to_dict())
	if not strict_r.ok:
		return strict_r

	return Result.success()

static func _test_from_dict_rejects_module_state_without_schema_registry(state_dict: Dictionary) -> Result:
	var previous_bundle := RulesRegistryBundleClass.new()
	previous_bundle.state_schema_loaded = StateSchemaRegistryClass.is_loaded()
	previous_bundle.state_int_key_dict_schemas = StateSchemaRegistryClass.get_int_key_dict_schemas()

	StateSchemaRegistryClass.reset_current_bundle()
	var read := GameState.from_dict(state_dict)
	StateSchemaRegistryClass.set_current_bundle(previous_bundle)

	if read.ok:
		return Result.failure("GameState.from_dict 反序列化含模块状态时，StateSchemaRegistry 未加载应失败")
	var err := str(read.error)
	if err.find("StateSchemaRegistry") < 0 or err.find("含模块状态") < 0:
		return Result.failure("错误信息应包含 StateSchemaRegistry 与 含模块状态，实际: %s" % err)
	return Result.success()
