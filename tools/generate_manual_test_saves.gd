extends SceneTree

# 批量生成“手工复核用存档”（员工/里程碑）
# 用法：
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd
# 可选过滤：
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --kind employee
#   godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --id kitchen_trainee

const ManifestClass = preload("res://tools/generate_manual_test_saves_manifest.gd")

# 注意：避免在脚本编译期 preload core/tests 或依赖 autoload 的脚本，
# 否则在 `--script` 模式下可能出现“Identifier not found: GameLog/EventBus”的噪音编译报错。
# 这里优先使用 class_name（TestPhaseUtils/StateUpdater/MapUtils），以及在运行期 load() 无 class_name 的脚本（Coords）。
const CoordsScriptPath := "res://core/map/map_runtime/coords.gd"

const OUTPUT_ROOT := "res://.savings/manual_cases"

const BASELINE_MODULES: Array[String] = [
	"base_rules",
	"base_products",
	"base_pieces",
	"base_employees",
	"base_milestones",
	"base_marketing",
	"base_tiles",
	"base_maps",
]

var _coords_script_cache = null

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter_kind := ""
	var filter_id := ""

	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == "--kind" and i + 1 < args.size():
			filter_kind = str(args[i + 1]).strip_edges()
			i += 2
			continue
		if a == "--id" and i + 1 < args.size():
			filter_id = str(args[i + 1]).strip_edges()
			i += 2
			continue
		i += 1

	print("[ManualTestSaves] START kind=%s id=%s" % [filter_kind, filter_id])

	var cases: Array[Dictionary] = ManifestClass.get_cases()
	if cases.is_empty():
		push_error("[ManualTestSaves] FAIL manifest is empty")
		quit(1)
		return

	var generated := 0
	for case_val in cases:
		if not (case_val is Dictionary):
			push_error("[ManualTestSaves] FAIL case is not a Dictionary: %s" % str(case_val))
			quit(1)
			return
		var c: Dictionary = case_val
		var kind := str(c.get("kind", "")).strip_edges()
		var cid := str(c.get("id", "")).strip_edges()
		if kind.is_empty() or cid.is_empty():
			push_error("[ManualTestSaves] FAIL case missing kind/id: %s" % str(c))
			quit(1)
			return

		if not filter_kind.is_empty() and kind != filter_kind:
			continue
		if not filter_id.is_empty() and cid != filter_id:
			continue

		var r := _generate_case(c)
		if not r.ok:
			push_error("[ManualTestSaves] FAIL %s/%s: %s" % [kind, cid, r.error])
			quit(1)
			return
		generated += 1
		print("[ManualTestSaves] OK   %s/%s -> %s" % [kind, cid, str(r.value)])

	if generated <= 0:
		push_error("[ManualTestSaves] FAIL no cases matched the filter")
		quit(1)
		return

	print("[ManualTestSaves] PASS generated=%d" % generated)
	quit(0)

func _generate_case(c: Dictionary) -> Result:
	var kind := str(c.get("kind", "")).strip_edges()
	var cid := str(c.get("id", "")).strip_edges()
	var title := str(c.get("title", "")).strip_edges()
	var player_count := int(c.get("player_count", 2))
	var seed := int(c.get("seed", 0))
	var enabled_modules: Array[String] = []
	var enabled_val = c.get("enabled_modules", [])
	if enabled_val is Array:
		for v in Array(enabled_val):
			if v is String and not str(v).strip_edges().is_empty():
				enabled_modules.append(str(v).strip_edges())
	enabled_modules = _merge_enabled_modules(enabled_modules)
	var exclude_modules: Array[String] = []
	var exclude_val = c.get("exclude_modules", [])
	if exclude_val is Array:
		for v in Array(exclude_val):
			if v is String and not str(v).strip_edges().is_empty():
				exclude_modules.append(str(v).strip_edges())
	if not exclude_modules.is_empty():
		enabled_modules = _exclude_modules(enabled_modules, exclude_modules)

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed, enabled_modules)
	if not init.ok:
		return Result.failure("GameEngine.initialize failed: %s" % init.error)

	var build := _run_builder(engine, c)
	if not build.ok:
		return build
	var build_ctx: Dictionary = build.value if (build.value is Dictionary) else {}

	# 把当前状态“冻结”为 archive.initial_state（减少命令历史噪音，便于手工复核）
	_freeze_engine_as_initial(engine)

	var dir_name := _kind_to_dir(kind)
	if dir_name.is_empty():
		return Result.failure("unknown kind: %s" % kind)

	var rel_json_res_path := "%s/%s/%s.json" % [OUTPUT_ROOT, dir_name, cid]
	var abs_json_path := ProjectSettings.globalize_path(rel_json_res_path)
	var abs_dir := abs_json_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)

	var save := engine.save_to_file(abs_json_path)
	if not save.ok:
		return Result.failure("save_to_file failed: %s" % save.error)

	var md_text := _build_markdown(c, build_ctx, rel_json_res_path, engine.get_state())
	var abs_md_path := abs_json_path.trim_suffix(".json") + ".md"
	var md_write := _write_text(abs_md_path, md_text)
	if not md_write.ok:
		return Result.failure("write md failed: %s" % md_write.error)

	# 生成后做一次 load 校验，避免写出坏档。
	var verify_engine := GameEngine.new()
	var load := verify_engine.load_from_file(abs_json_path)
	if not load.ok:
		return Result.failure("load verification failed: %s" % load.error)

	return Result.success({
		"json": rel_json_res_path,
		"md": abs_md_path,
		"title": title,
	})

func _merge_enabled_modules(extra: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for m in BASELINE_MODULES:
		if m.is_empty():
			continue
		if seen.has(m):
			continue
		seen[m] = true
		out.append(m)
	for m2 in extra:
		var s := str(m2).strip_edges()
		if s.is_empty():
			continue
		if seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out

func _exclude_modules(enabled: Array[String], exclude: Array[String]) -> Array[String]:
	var blocked := {}
	for m in exclude:
		var s := str(m).strip_edges()
		if s.is_empty():
			continue
		blocked[s] = true

	var out: Array[String] = []
	for m2 in enabled:
		var s2 := str(m2).strip_edges()
		if s2.is_empty():
			continue
		if blocked.has(s2):
			continue
		out.append(s2)
	return out

func _kind_to_dir(kind: String) -> String:
	match kind:
		"employee":
			return "employees"
		"milestone":
			return "milestones"
		_:
			return ""

func _freeze_engine_as_initial(engine: GameEngine) -> void:
	if engine == null:
		return
	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1
	engine._create_checkpoint(0)

func _write_text(abs_path: String, text: String) -> Result:
	if abs_path.is_empty():
		return Result.failure("path is empty")
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return Result.failure("cannot open file: %s" % abs_path)
	file.store_string(text)
	file.close()
	return Result.success(abs_path)

func _build_markdown(c: Dictionary, build_ctx: Dictionary, rel_json_res_path: String, state: GameState) -> String:
	var kind := str(c.get("kind", "")).strip_edges()
	var cid := str(c.get("id", "")).strip_edges()
	var title := str(c.get("title", "")).strip_edges()
	var purpose := str(c.get("purpose", "")).strip_edges()
	var steps: Array = c.get("steps", [])
	var expected: Array = c.get("expected", [])
	var related: Array = c.get("related_tests", [])

	var player_count := int(c.get("player_count", 2))
	var seed := int(c.get("seed", 0))

	var header := "# %s/%s" % [kind, cid]
	if not title.is_empty():
		header += " - %s" % title
	var out := header + "\n\n"

	out += "## 存档\n\n"
	out += "- JSON: `%s`\n" % rel_json_res_path
	out += "- 玩家数: %d\n" % player_count
	out += "- Seed: %d\n" % seed
	if state != null:
		out += "- 当前位置: %s/%s (round=%d current_player=%d)\n" % [
			str(state.phase),
			str(state.sub_phase),
			int(state.round_number),
			int(state.get_current_player_id()),
		]

	if not purpose.is_empty():
		out += "\n## 目的\n\n"
		out += "- %s\n" % purpose

	out += "\n## 复核步骤\n\n"
	if steps is Array and not steps.is_empty():
		for idx in range(steps.size()):
			out += "%d. %s\n" % [idx + 1, str(steps[idx])]
	else:
		out += "1. （待补充）\n"

	out += "\n## 预期结果\n\n"
	if expected is Array and not expected.is_empty():
		for e in expected:
			out += "- %s\n" % str(e)
	else:
		out += "- （待补充）\n"

	var suggested_val = build_ctx.get("suggested_command", null)
	if suggested_val is Dictionary:
		var sc: Dictionary = suggested_val
		var action_id := str(sc.get("action_id", "")).strip_edges()
		if not action_id.is_empty():
			out += "\n## 推荐参数（可选）\n\n"
			out += "- action_id: `%s`\n" % action_id
			if sc.has("actor"):
				out += "- actor: `%s`\n" % str(sc.get("actor"))
			if sc.has("params") and (sc["params"] is Dictionary):
				out += "- params:\n"
				for k in (sc["params"] as Dictionary).keys():
					out += "	- `%s`: `%s`\n" % [str(k), str((sc["params"] as Dictionary)[k])]

	out += "\n## 关联单元测试\n\n"
	if related is Array and not related.is_empty():
		for t in related:
			out += "- `%s`\n" % str(t)
	else:
		out += "- （暂无）\n"

	return out

func _run_builder(engine: GameEngine, c: Dictionary) -> Result:
	var name := str(c.get("builder", "")).strip_edges()
	if name.is_empty():
		return Result.failure("builder is empty")
	match name:
		"employee_produce_food_fixed":
			return _build_employee_produce_food_fixed(engine, c)
		"employee_kitchen_trainee_get_food":
			return _build_employee_kitchen_trainee_get_food(engine, c)
		"employee_restructuring_showcase":
			return _build_employee_restructuring_showcase(engine, c)
		"employee_waitress_tips":
			return _build_employee_waitress_tips(engine, c)
		"employee_cfo_bonus_on_tips":
			return _build_employee_cfo_bonus_on_tips(engine, c)
		"employee_kimchi_master_cleanup":
			return _build_employee_kimchi_master_cleanup(engine, c)
		"employee_fry_chef_dinnertime_bonus":
			return _build_employee_fry_chef_dinnertime_bonus(engine, c)
		"employee_movie_star_order_of_business":
			return _build_employee_movie_star_order_of_business(engine, c)
		"employee_mass_marketeer_marketing_rounds":
			return _build_employee_mass_marketeer_marketing_rounds(engine, c)
		"employee_procure_drinks_errand_boy":
			return _build_employee_procure_drinks_errand_boy(engine, c)
		"employee_procure_drinks_route":
			return _build_employee_procure_drinks_route(engine, c)
		"employee_initiate_marketing":
			return _build_employee_initiate_marketing(engine, c)
		"employee_marketing_trainee_billboard":
			return _build_employee_marketing_trainee_billboard(engine, c)
		"employee_mandatory_action":
			return _build_employee_mandatory_action(engine, c)
		"employee_recruit_capacity":
			return _build_employee_recruit_capacity(engine, c)
		"employee_train_once":
			return _build_employee_train_once(engine, c)
		"employee_place_restaurant":
			return _build_employee_place_restaurant(engine, c)
		"employee_move_restaurant":
			return _build_employee_move_restaurant(engine, c)
		"employee_place_house":
			return _build_employee_place_house(engine, c)
		"employee_add_garden":
			return _build_employee_add_garden(engine, c)
		"employee_lobbyist_place_road":
			return _build_employee_lobbyist_place_road(engine, c)
		"employee_lobbyist_place_park":
			return _build_employee_lobbyist_place_park(engine, c)
		"employee_rural_marketeer_giant_billboard":
			return _build_employee_rural_marketeer_giant_billboard(engine, c)
		"employee_night_shift_manager_double_action":
			return _build_employee_night_shift_manager_double_action(engine, c)
		"milestone_first_lower_prices":
			return _build_milestone_first_lower_prices(engine, c)
		"milestone_first_train":
			return _build_milestone_first_train(engine, c)
		"milestone_first_airplane":
			return _build_milestone_first_airplane(engine, c)
		"milestone_first_billboard":
			return _build_milestone_first_billboard(engine, c)
		"milestone_first_radio":
			return _build_milestone_first_radio(engine, c)
		"milestone_first_burger_marketed":
			return _build_milestone_first_burger_marketed(engine, c)
		"milestone_first_drink_marketed":
			return _build_milestone_first_drink_marketed(engine, c)
		"milestone_first_pizza_marketed":
			return _build_milestone_first_pizza_marketed(engine, c)
		"milestone_first_burger_produced":
			return _build_milestone_first_burger_produced(engine, c)
		"milestone_first_pizza_produced":
			return _build_milestone_first_pizza_produced(engine, c)
		"milestone_first_hire_3":
			return _build_milestone_first_hire_3(engine, c)
		"milestone_first_pay_20_salaries":
			return _build_milestone_first_pay_20_salaries(engine, c)
		"milestone_first_have_20":
			return _build_milestone_first_have_20(engine, c)
		"milestone_first_have_100":
			return _build_milestone_first_have_100(engine, c)
		"milestone_first_throw_away":
			return _build_milestone_first_throw_away(engine, c)
		"milestone_first_waitress":
			return _build_milestone_first_waitress(engine, c)
		"milestone_first_cart_operator":
			return _build_milestone_first_cart_operator(engine, c)
		"milestone_first_errand_boy":
			return _build_milestone_first_errand_boy(engine, c)
		"milestone_first_lobbyist_used":
			return _build_milestone_first_lobbyist_used(engine, c)
		"milestone_first_rural_marketeer_used":
			return _build_milestone_first_rural_marketeer_used(engine, c)
		"milestone_ketchup_sold_your_demand":
			return _build_milestone_ketchup_sold_your_demand(engine, c)
		"milestone_first_marketing_trainee_used":
			return _build_milestone_first_marketing_trainee_used(engine, c)
		"milestone_first_campaign_manager_used":
			return _build_milestone_first_campaign_manager_used(engine, c)
		"milestone_first_brand_manager_used":
			return _build_milestone_first_brand_manager_used(engine, c)
		"milestone_first_brand_director_used":
			return _build_milestone_first_brand_director_used(engine, c)
		"milestone_first_marketeer_used":
			return _build_milestone_first_marketeer_used(engine, c)
		"milestone_first_trainer_used":
			return _build_milestone_first_trainer_used(engine, c)
		"milestone_first_recruiting_girl_used":
			return _build_milestone_first_recruiting_girl_used(engine, c)
		"milestone_first_discount_manager_used":
			return _build_milestone_first_discount_manager_used(engine, c)
		"milestone_first_cart_operator_used":
			return _build_milestone_first_cart_operator_used(engine, c)
		"milestone_first_waitress_used":
			return _build_milestone_first_waitress_used(engine, c)
		"milestone_first_new_restaurant":
			return _build_milestone_first_new_restaurant(engine, c)
		"milestone_first_house_built":
			return _build_milestone_first_house_built(engine, c)
		"milestone_first_beer_sold":
			return _build_milestone_first_beer_sold(engine, c)
		"milestone_first_coke_sold":
			return _build_milestone_first_coke_sold(engine, c)
		"milestone_first_lemonade_sold":
			return _build_milestone_first_lemonade_sold(engine, c)
		"milestone_first_burger_sold":
			return _build_milestone_first_burger_sold(engine, c)
		"milestone_first_pizza_sold":
			return _build_milestone_first_pizza_sold(engine, c)
		_:
			return Result.failure("unknown builder: %s" % name)

func _get_coords_script():
	if _coords_script_cache == null:
		_coords_script_cache = load(CoordsScriptPath)
	return _coords_script_cache

func _advance_to_phase(engine: GameEngine, target_phase: String, force_turn_order: bool = true) -> Result:
	var adv := TestPhaseUtils.advance_until_phase(engine, target_phase, 80)
	if not adv.ok:
		return adv
	var state := engine.get_state()
	if force_turn_order:
		_force_turn_order(state)
	if str(state.phase) != target_phase:
		return Result.failure("expected phase=%s, got: %s" % [target_phase, str(state.phase)])
	return Result.success()

func _force_turn_order(state: GameState) -> void:
	if state == null:
		return
	var count := state.players.size()
	state.turn_order.clear()
	for i in range(count):
		state.turn_order.append(i)
	state.current_player_index = 0

func _advance_to_working(engine: GameEngine) -> Result:
	var to_working := TestPhaseUtils.advance_until_phase(engine, "Working", 60)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	_force_turn_order(state)
	if state.phase != "Working":
		return Result.failure("expected Working, got: %s" % str(state.phase))
	return Result.success()

func _advance_to_working_sub_phase(engine: GameEngine, target_sub_phase: String) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv
	var to_target := TestPhaseUtils.advance_until_working_sub_phase(engine, target_sub_phase, 60)
	if not to_target.ok:
		# fallback：直接设置子阶段（子阶段顺序可能因模块插入/跳过策略变化而失败）
		engine.get_state().sub_phase = target_sub_phase
	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = target_sub_phase
	if state.phase != "Working" or state.sub_phase != target_sub_phase:
		return Result.failure("expected Working/%s, got: %s/%s" % [target_sub_phase, str(state.phase), str(state.sub_phase)])
	return Result.success()

func _ensure_employee(state: GameState, player_id: int, employee_id: String, to_reserve: bool, count: int = 1) -> Result:
	if state == null:
		return Result.failure("state is null")
	if employee_id.is_empty():
		return Result.failure("employee_id is empty")
	if count <= 0:
		return Result.failure("count must be > 0")

	var player := state.get_player(player_id)
	var key := "reserve_employees" if to_reserve else "employees"
	var arr_val = player.get(key, [])
	if not (arr_val is Array):
		return Result.failure("player.%s is not an Array" % key)
	var arr: Array = arr_val

	var existing := 0
	for v in arr:
		if v is String and str(v) == employee_id:
			existing += 1
	if existing >= count:
		return Result.success()

	var need := count - existing
	# 起始 CEO 不在 employee_pool；其余员工必须从池中取，避免写入无效状态。
	if employee_id != "ceo":
		if not (state.employee_pool is Dictionary) or not state.employee_pool.has(employee_id):
			return Result.failure("employee_id not in employee_pool: %s (module missing?)" % employee_id)
		var take := StateUpdater.take_from_pool(state, employee_id, need)
		if not take.ok:
			return Result.failure("take_from_pool(%s) failed: %s" % [employee_id, take.error])

	for _i in range(need):
		var add := StateUpdater.add_employee(state, player_id, employee_id, to_reserve)
		if not add.ok:
			return Result.failure("add_employee(%s) failed: %s" % [employee_id, add.error])
	return Result.success()

func _exec_system(engine: GameEngine, action_id: String, params: Dictionary) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if action_id.is_empty():
		return Result.failure("action_id is empty")
	var cmd := Command.create_system(action_id, params)
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("%s failed: %s" % [action_id, r.error])
	return Result.success(r.value).with_warnings(r.warnings)

func _get_road_graph(state: GameState):
	var rg_cache_script = load("res://core/map/map_runtime/road_graph_cache.gd")
	if rg_cache_script == null:
		return null
	return rg_cache_script.get_road_graph(state)

func _build_employee_kitchen_trainee_get_food(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "kitchen_trainee", false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({})

func _build_employee_restructuring_showcase(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Restructuring")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var to_reserve := bool(params.get("to_reserve", true))
	var count := int(params.get("count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if count <= 0:
		count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, to_reserve, count)
	if not ensure.ok:
		return ensure

	return Result.success()

func _build_employee_waitress_tips(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 waitress 在晚餐阶段提供固定小费（默认 $3），无需依赖售卖发生。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "waitress", false, 1)
	if not ensure.ok:
		return ensure

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_cfo_bonus_on_tips(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：用“waitress tips”制造 base_gain，避免额外构造售卖场景；
	# 这样 CFO 的 +50%（向上取整）会稳定触发：ceil(3 * 50%) = 2。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	# 让双方都有 waitress（都获得 $3 tips），仅玩家 0 有 CFO（额外获得 $2）。
	for pid in range(state.players.size()):
		var ensure_w := _ensure_employee(state, pid, "waitress", false, 1)
		if not ensure_w.ok:
			return ensure_w

	var ensure_cfo := _ensure_employee(state, 0, "cfo", false, 1)
	if not ensure_cfo.ok:
		return ensure_cfo

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_kimchi_master_cleanup(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 Cleanup 丢弃食物后 kimchi_master 自动产出 1 个 kimchi 并保留到下一阶段。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "kimchi_master", false, 1)
	if not ensure.ok:
		return ensure

	# 构造“会被丢弃”的食物库存：不设置需求，确保晚餐不会消耗。
	var inv := _exec_system(engine, "debug_add_inventory", {
		"player_id": actor,
		"product": "burger",
		"amount": 1,
	})
	if not inv.ok:
		return inv

	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _get_player_first_restaurant_id(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.players is Array):
		return Result.failure("state.players is not an Array")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("invalid player_id: %d" % player_id)
	var p_val = state.players[player_id]
	if not (p_val is Dictionary):
		return Result.failure("players[%d] is not a Dictionary" % player_id)
	var p: Dictionary = p_val
	var restaurants_val = p.get("restaurants", [])
	if not (restaurants_val is Array) or restaurants_val.is_empty():
		return Result.failure("player %d has no restaurants" % player_id)
	var rid := str(restaurants_val[0])
	if rid.is_empty():
		return Result.failure("invalid restaurant_id for player %d" % player_id)
	return Result.success(rid)

func _get_distance_rest_to_house(road_graph, state: GameState, grid_size: Vector2i, rest_id: String, rest: Dictionary, house_id: String, house: Dictionary) -> Result:
	var r := DinnertimeDistance.get_restaurant_to_house_distance(road_graph, state, grid_size, rest_id, rest, house_id, house)
	if not r.ok:
		return r
	if not (r.value is Dictionary):
		return Result.success(-1)
	var v: Dictionary = r.value
	if not v.has("distance") or not (v["distance"] is int):
		return Result.success(-1)
	return Result.success(int(v["distance"]))

func _build_employee_fry_chef_dinnertime_bonus(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：构造“玩家 0 卖出 1 个房屋”的局面，验证 fry_chef 会为该房屋结算额外 +$10（按房屋算）。
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure := _ensure_employee(state, 0, "fry_chef", false, 1)
	if not ensure.ok:
		return ensure

	var rid0_r := _get_player_first_restaurant_id(state, 0)
	if not rid0_r.ok:
		return rid0_r
	var rid1_r := _get_player_first_restaurant_id(state, 1)
	if not rid1_r.ok:
		return rid1_r
	var rid0: String = rid0_r.value
	var rid1: String = rid1_r.value

	if not (state.map is Dictionary):
		return Result.failure("state.map is not a Dictionary")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("state.map.grid_size missing or invalid")
	var grid_size: Vector2i = state.map["grid_size"]

	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants missing or invalid")
	var restaurants: Dictionary = state.map["restaurants"]
	if not restaurants.has(rid0) or not restaurants.has(rid1):
		return Result.failure("restaurants missing player restaurant ids")
	if not (restaurants[rid0] is Dictionary) or not (restaurants[rid1] is Dictionary):
		return Result.failure("restaurants[%s/%s] invalid type" % [rid0, rid1])
	var rest0: Dictionary = restaurants[rid0]
	var rest1: Dictionary = restaurants[rid1]

	if not state.map.has("houses") or not (state.map["houses"] is Dictionary):
		return Result.failure("state.map.houses missing or invalid")
	var houses: Dictionary = state.map["houses"]
	var house_ids: Array[String] = []
	for k in houses.keys():
		if k is String:
			house_ids.append(str(k))
	house_ids.sort()
	if house_ids.is_empty():
		return Result.failure("no houses on map")

	var road_graph = _get_road_graph(state)
	if road_graph == null:
		return Result.failure("road_graph is null")

	var house0 := ""
	for hid in house_ids:
		if not (houses[hid] is Dictionary):
			continue
		var house: Dictionary = houses[hid]
		var d0_r := _get_distance_rest_to_house(road_graph, state, grid_size, rid0, rest0, hid, house)
		if not d0_r.ok:
			continue
		var d1_r := _get_distance_rest_to_house(road_graph, state, grid_size, rid1, rest1, hid, house)
		if not d1_r.ok:
			continue
		var d0 := int(d0_r.value)
		var d1 := int(d1_r.value)
		if d0 >= 0 and d1 >= 0 and d0 < d1:
			house0 = hid
			break
	if house0.is_empty():
		return Result.failure("cannot find a house where player 0 is strictly closer")

	# 1) 放 1 个 burger 需求（确保为“非饮品 food”，可触发 fry_chef 奖励）
	var dem0 := _exec_system(engine, "debug_add_house_demand", {"house_id": house0, "product": "burger", "amount": 1})
	if not dem0.ok:
		return dem0

	# 2) 给玩家 0 1 个 burger 库存（避免因缺货导致需求无法满足）
	var inv0 := _exec_system(engine, "debug_add_inventory", {"player_id": 0, "product": "burger", "amount": 1})
	if not inv0.ok:
		return inv0

	# 3) 推进到 Payday（中间会自动结算 Dinnertime/Marketing/Cleanup）
	var to_payday := _advance_to_phase(engine, "Payday")
	if not to_payday.ok:
		return to_payday

	return Result.success()

func _build_employee_movie_star_order_of_business(engine: GameEngine, c: Dictionary) -> Result:
	# 目标：让“无电影明星时应由玩家 1 先选顺序”的局面，在拥有 movie_star_* 后被强制改为玩家 0 优先。
	var to_restructuring := _advance_to_phase(engine, "Restructuring")
	if not to_restructuring.ok:
		return to_restructuring

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var star_id := str(params.get("star_id", "movie_star_d")).strip_edges()
	if star_id.is_empty():
		return Result.failure("builder_params.star_id is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	# 玩家 0：movie_star + 2 张填充员工，使 empty_slots 降到 0（CEO slots=3）
	var ensure_star := _ensure_employee(state, 0, star_id, false, 1)
	if not ensure_star.ok:
		return ensure_star
	var ensure_fill_1 := _ensure_employee(state, 0, "kitchen_trainee", false, 1)
	if not ensure_fill_1.ok:
		return ensure_fill_1
	var ensure_fill_2 := _ensure_employee(state, 0, "marketing_trainee", false, 1)
	if not ensure_fill_2.ok:
		return ensure_fill_2

	# 推进到 OrderOfBusiness：注意不要覆盖 turn_order/selection_order（这里不调用 _force_turn_order）
	var to_oob := TestPhaseUtils.advance_until_phase(engine, "OrderOfBusiness", 80)
	if not to_oob.ok:
		return to_oob
	if str(engine.get_state().phase) != "OrderOfBusiness":
		return Result.failure("expected OrderOfBusiness, got: %s" % str(engine.get_state().phase))

	return Result.success()

func _build_employee_mass_marketeer_marketing_rounds(engine: GameEngine, _c: Dictionary) -> Result:
	# 目标：验证 mass_marketeer 会把当回合的 marketing_rounds 从 1 提升为 1 + 在岗数量。
	# 这里用 marketing_trainee 放置 1 个 billboard，便于手工观察“需求增加次数=2”。
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_mm := _ensure_employee(state, actor, "mass_marketeer", false, 1)
	if not ensure_mm.ok:
		return ensure_mm
	var ensure_mt := _ensure_employee(state, actor, "marketing_trainee", false, 1)
	if not ensure_mt.ok:
		return ensure_mt

	var find := _find_first_valid_initiate_marketing(engine, actor, "marketing_trainee", 14, "burger", 1)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_marketing_trainee_billboard(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "marketing_trainee", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var board_number := int(params.get("board_number", 14))
	var product := str(params.get("product", "burger")).strip_edges()
	var duration := int(params.get("duration", 1))
	var find := _find_first_valid_initiate_marketing(engine, actor, "marketing_trainee", board_number, product, duration)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_initiate_marketing(engine: GameEngine, actor: int, employee_type: String, board_number: int, product: String, duration: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("initiate_marketing")
	if ex == null:
		return Result.failure("cannot find executor: initiate_marketing")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("initiate_marketing", actor, {
					"employee_type": employee_type,
					"board_number": board_number,
					"product": product,
					"duration": duration,
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "initiate_marketing",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})

	return Result.failure("no valid initiate_marketing placement found (board=%d product=%s)" % [board_number, product])

func _build_employee_produce_food_fixed(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": "produce_food",
			"actor": actor,
			"params": {
				"employee_type": employee_type,
			},
		}
	})

func _build_employee_procure_drinks_errand_boy(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetDrinks")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "errand_boy", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var drink_type := str(params.get("drink_type", "soda")).strip_edges()
	if drink_type.is_empty():
		drink_type = "soda"

	return Result.success({
		"suggested_command": {
			"action_id": "procure_drinks",
			"actor": actor,
			"params": {
				"employee_type": "errand_boy",
				"drink_type": drink_type,
			},
		}
	})

func _build_employee_procure_drinks_route(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "GetDrinks")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	# 采购路线/来源由 UI 交互生成（route/selected_sources），这里不强行指定参数，避免误导。
	return Result.success()

func _build_employee_initiate_marketing(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	var board_number := int(params.get("board_number", 14))
	var product := str(params.get("product", "burger")).strip_edges()
	var duration := int(params.get("duration", 1))

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_initiate_marketing(engine, actor, employee_type, board_number, product, duration)
	if not find.ok:
		return find

	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_mandatory_action(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var action_id := str(params.get("action_id", "")).strip_edges()
	if employee_type.is_empty() or action_id.is_empty():
		return Result.failure("builder_params.employee_type/action_id is empty")

	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": action_id,
			"actor": actor,
			"params": {},
		}
	})

func _build_employee_recruit_capacity(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Recruit")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	var recruit_target := str(params.get("recruit_target", "waitress")).strip_edges()
	if recruit_target.is_empty():
		recruit_target = "waitress"

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	return Result.success({
		"suggested_command": {
			"action_id": "recruit",
			"actor": actor,
			"params": {
				"employee_type": recruit_target,
			},
		}
	})

func _build_employee_train_once(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Train")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var trainer_type := str(params.get("trainer_type", "trainer")).strip_edges()
	var from_employee := str(params.get("from_employee", "management_trainee")).strip_edges()
	var to_employee := str(params.get("to_employee", "new_business_developer")).strip_edges()
	if trainer_type.is_empty() or from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("builder_params trainer_type/from_employee/to_employee is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_trainer := _ensure_employee(state, actor, trainer_type, false, 1)
	if not ensure_trainer.ok:
		return ensure_trainer

	var ensure_from := _ensure_employee(state, actor, from_employee, true, 1)
	if not ensure_from.ok:
		return ensure_from

	# 目标员工需要在池中存在（train.validate 会检查）
	if not (state.employee_pool is Dictionary) or int(state.employee_pool.get(to_employee, 0)) <= 0:
		return Result.failure("employee_pool has no %s (required for training)" % to_employee)

	return Result.success({
		"suggested_command": {
			"action_id": "train",
			"actor": actor,
			"params": {
				"from_employee": from_employee,
				"to_employee": to_employee,
			},
		}
	})

func _build_milestone_first_airplane(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_billboard(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_radio(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_burger_produced(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_produce_food_fixed(engine, c)

func _build_milestone_first_pizza_produced(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_produce_food_fixed(engine, c)

func _build_milestone_first_hire_3(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_recruit_capacity(engine, c)

func _build_milestone_first_cart_operator(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_route(engine, c)

func _build_milestone_first_errand_boy(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_errand_boy(engine, c)

func _build_milestone_first_lobbyist_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_lobbyist_place_road(engine, c)

func _build_milestone_first_rural_marketeer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_rural_marketeer_giant_billboard(engine, c)

func _build_milestone_first_marketing_trainee_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_campaign_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_brand_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_brand_director_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_marketeer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_initiate_marketing(engine, c)

func _build_milestone_first_trainer_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_train_once(engine, c)

func _build_milestone_first_recruiting_girl_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_recruit_capacity(engine, c)

func _build_milestone_first_discount_manager_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_mandatory_action(engine, c)

func _build_milestone_first_cart_operator_used(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_procure_drinks_route(engine, c)

func _build_milestone_first_new_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	# 为“首个新餐厅”准备一个确定性小地图：
	# - 方便后续手工复核 place_new_restaurant_mailbox（推荐 position=[0,2]）
	# - 用竖向道路 x=3 将地图分成左右两个 mailbox block
	_apply_test_map_new_restaurant_mailbox(state)

	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_place_restaurant(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_milestone_first_house_built(engine: GameEngine, c: Dictionary) -> Result:
	return _build_employee_place_house(engine, c)

func _invalidate_road_graph(state: GameState) -> void:
	var rg_cache_script = load("res://core/map/map_runtime/road_graph_cache.gd")
	if rg_cache_script == null:
		return
	rg_cache_script.invalidate_road_graph(state)

func _mark_all_players_passed_for_working(state: GameState) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state is not Dictionary")
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed
	return Result.success()

func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)
	return cells

func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

func _set_house_1x1(cells: Array, house_id: String, house_number: int, pos: Vector2i) -> void:
	cells[pos.y][pos.x]["structure"] = {
		"piece_id": "house",
		"house_id": house_id,
		"house_number": house_number,
		"has_garden": false,
		"dynamic": true
	}

func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

func _apply_test_map_single_sale(state: GameState) -> void:
	var grid_size := Vector2i(5, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 3), dirs)

	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	_set_house_1x1(cells, "h0", 1, Vector2i(3, 2))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h0": {
				"house_id": "h0",
				"house_number": 1,
				"anchor_pos": Vector2i(3, 2),
				"cells": [Vector2i(3, 2)],
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			}
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(1, 3),
				"cells": rest_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	_invalidate_road_graph(state)

func _apply_test_map_pizza_sale(state: GameState) -> void:
	var grid_size := Vector2i(5, 5) # 1 tile
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var rest_cells: Array[Vector2i] = [
		Vector2i(0, 4), Vector2i(1, 4),
		Vector2i(0, 3), Vector2i(1, 3),
	]
	_set_restaurant(cells, "rest_0", 0, rest_cells)
	_set_house_1x1(cells, "h1", 1, Vector2i(2, 1))
	_set_house_1x1(cells, "h2", 2, Vector2i(3, 1))
	_set_house_1x1(cells, "h3", 3, Vector2i(4, 1))

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": {
			"h1": {"house_id": "h1", "house_number": 1, "anchor_pos": Vector2i(2, 1), "cells": [Vector2i(2, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h2": {"house_id": "h2", "house_number": 2, "anchor_pos": Vector2i(3, 1), "cells": [Vector2i(3, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
			"h3": {"house_id": "h3", "house_number": 3, "anchor_pos": Vector2i(4, 1), "cells": [Vector2i(4, 1)], "has_garden": false, "is_apartment": false, "printed": false, "owner": -1, "demands": []},
		},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 3), "entrance_pos": Vector2i(1, 2), "cells": rest_cells},
		},
		"drink_sources": [],
		"next_house_number": 4,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	_invalidate_road_graph(state)

func _apply_test_map_ketchup(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var left_house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": left_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)

func _apply_test_map_new_restaurant_mailbox(state: GameState) -> void:
	# 10x5：用竖向道路 x=3 将地图分成左右两个 mailbox block，
	# 且确保 mailbox #5（3x2）可在 position=[0,2] 合法放置并邻接道路（x=3）。
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for y in range(grid_size.y):
		var dirs: Array = []
		if y > 0:
			dirs.append("N")
		if y < grid_size.y - 1:
			dirs.append("S")
		_set_road_segment(cells, Vector2i(3, y), dirs)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {},
		"restaurants": {
			"rest_0": {"restaurant_id": "rest_0", "owner": 0, "anchor_pos": Vector2i(0, 0), "entrance_pos": Vector2i(0, 0), "cells": rest0_cells},
			"rest_1": {"restaurant_id": "rest_1", "owner": 1, "anchor_pos": Vector2i(8, 0), "entrance_pos": Vector2i(8, 0), "cells": rest1_cells},
		},
		"drink_sources": [],
		"next_house_number": 1,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	_invalidate_road_graph(state)

func _build_billboard_map_for_demand_marked() -> Dictionary:
	var grid_size := Vector2i(3, 3)
	var cells: Array = _build_empty_cells(grid_size)

	cells[1][1]["structure"] = {
		"piece_id": "house",
		"house_id": "house_1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": true
	}

	var houses := {
		"house_1": {
			"house_id": "house_1",
			"house_number": 1,
			"anchor_pos": Vector2i(1, 1),
			"cells": [Vector2i(1, 1)],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}
	}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": houses,
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}

func _build_milestone_first_burger_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "burger")

func _build_milestone_first_drink_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "soda")

func _build_milestone_first_pizza_marketed(engine: GameEngine, _c: Dictionary) -> Result:
	return _build_milestone_demand_marked(engine, "pizza")

func _build_milestone_demand_marked(engine: GameEngine, product: String) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv
	if product.is_empty():
		return Result.failure("product is empty")

	var state := engine.get_state()
	_force_turn_order(state)

	state.map = _build_billboard_map_for_demand_marked()
	_invalidate_road_graph(state)

	var board_number := 14
	var owner := 0
	var employee_type := "marketing_trainee"

	var take := StateUpdater.take_from_pool(state, employee_type, 1)
	if not take.ok:
		return Result.failure("take_from_pool(%s) failed: %s" % [employee_type, take.error])
	state.players[owner]["busy_marketers"] = [employee_type]

	state.marketing_instances = [{
		"board_number": board_number,
		"type": "billboard",
		"owner": owner,
		"employee_type": employee_type,
		"product": product,
		"world_pos": Vector2i(1, 2),
		"rotation": 0,
		"footprint_size": Vector2i(2, 1),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}]
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": "billboard",
		"owner": owner,
		"product": product,
		"world_pos": Vector2i(1, 2),
		"rotation": 0,
		"footprint_size": Vector2i(2, 1),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}

	return Result.success()

func _build_milestone_first_pay_20_salaries(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv
	var state := engine.get_state()
	_force_turn_order(state)
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "burger_cook", false, 4)
	if not ensure.ok:
		return ensure

	var grant := StateUpdater.player_receive_from_bank(state, actor, 50)
	if not grant.ok:
		return Result.failure("player_receive_from_bank failed: %s" % grant.error)

	return Result.success()

func _build_milestone_first_throw_away(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_phase(engine, "Payday")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var p_val = state.players[0]
	if not (p_val is Dictionary):
		return Result.failure("player[0] is not Dictionary")
	var p: Dictionary = p_val
	var inv_val = p.get("inventory", null)
	if not (inv_val is Dictionary):
		return Result.failure("player[0].inventory is not Dictionary")
	var inv: Dictionary = inv_val
	inv["burger"] = 2
	inv["soda"] = 1
	p["inventory"] = inv
	state.players[0] = p

	return Result.success()

func _build_milestone_first_waitress(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure := _ensure_employee(state, 0, "waitress", false, 1)
	if not ensure.ok:
		return ensure

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_waitress_used(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)

	var ensure_w := _ensure_employee(state, 0, "waitress", false, 1)
	if not ensure_w.ok:
		return ensure_w
	var ensure_paid := _ensure_employee(state, 0, "burger_cook", false, 1)
	if not ensure_paid.ok:
		return ensure_paid

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_have_20(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["cash"] = 15

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_have_100(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["cash"] = 95

	return _mark_all_players_passed_for_working(state)

func _build_milestone_ketchup_sold_your_demand(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_ketchup(state)

	var houses: Dictionary = state.map["houses"]
	var house: Dictionary = houses["house_left"]
	house["demands"] = [{
		"product": "burger",
		"from_player": 0,
		"board_number": 11,
		"type": "billboard"
	}]
	houses["house_left"] = house
	state.map["houses"] = houses

	state.players[0]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["burger"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_beer_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var ensure := _ensure_employee(state, 0, "burger_cook", false, 4)
	if not ensure.ok:
		return ensure

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "beer"}]
	houses["h0"] = h
	state.map["houses"] = houses

	var inv: Dictionary = state.players[0]["inventory"]
	inv["beer"] = 1
	inv["pizza"] = 2
	state.players[0]["inventory"] = inv
	state.players[0]["cash"] = 0

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_coke_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "soda"}]
	houses["h0"] = h
	state.map["houses"] = houses

	var inv: Dictionary = state.players[0]["inventory"]
	inv["soda"] = 12
	state.players[0]["inventory"] = inv

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_lemonade_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "lemonade"}]
	houses["h0"] = h
	state.map["houses"] = houses

	state.players[0]["inventory"]["lemonade"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_burger_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_single_sale(state)

	var houses: Dictionary = state.map["houses"]
	var h: Dictionary = houses["h0"]
	h["demands"] = [{"product": "burger"}]
	houses["h0"] = h
	state.map["houses"] = houses

	state.players[0]["inventory"]["burger"] = 1

	return _mark_all_players_passed_for_working(state)

func _build_milestone_first_pizza_sold(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	_apply_test_map_pizza_sale(state)

	var inv: Dictionary = state.players[0]["inventory"]
	inv["pizza"] = 3
	state.players[0]["inventory"] = inv

	var houses: Dictionary = state.map["houses"]
	for hid in ["h1", "h2", "h3"]:
		var h: Dictionary = houses[hid]
		h["demands"] = [{"product": "pizza"}]
		houses[hid] = h
	state.map["houses"] = houses

	return _mark_all_players_passed_for_working(state)

func _find_first_valid_place_restaurant(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("place_restaurant")
	if ex == null:
		return Result.failure("cannot find executor: place_restaurant")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("place_restaurant", actor, {
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "place_restaurant",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid place_restaurant placement found")

func _build_employee_place_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_place_restaurant(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_move_restaurant(engine: GameEngine, actor: int, restaurant_id: String) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if restaurant_id.is_empty():
		return Result.failure("restaurant_id is empty")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("move_restaurant")
	if ex == null:
		return Result.failure("cannot find executor: move_restaurant")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("move_restaurant", actor, {
					"restaurant_id": restaurant_id,
					"position": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "move_restaurant",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid move_restaurant placement found (restaurant_id=%s)" % restaurant_id)

func _build_employee_move_restaurant(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceRestaurants")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, 1)
	if not ensure.ok:
		return ensure

	var player := state.get_player(actor)
	var restaurants_val = player.get("restaurants", [])
	if not (restaurants_val is Array) or restaurants_val.is_empty():
		return Result.failure("player has no restaurants to move")
	var restaurant_id := str(restaurants_val[0])
	if restaurant_id.is_empty():
		return Result.failure("invalid restaurant_id")

	var find := _find_first_valid_move_restaurant(engine, actor, restaurant_id)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _get_remaining_house_numbers_from_state(state: GameState) -> Array[int]:
	var default_list: Array[int] = [1, 3, 6, 9, 11, 14, 17, 19]
	if state == null or not (state.map is Dictionary):
		return default_list
	var map: Dictionary = state.map
	var list_val = map.get("house_number_supply_remaining", null)
	if list_val is Array:
		var out: Array[int] = []
		for v in Array(list_val):
			if v is int:
				out.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					out.append(int(f))
		out.sort()
		var dedup: Array[int] = []
		for n in out:
			if dedup.has(n):
				continue
			dedup.append(n)
		return dedup

	# fallback：默认列表扣掉已存在 house_number（兼容旧存档逻辑）
	var used := {}
	var houses_val = map.get("houses", null)
	if houses_val is Dictionary:
		var houses: Dictionary = houses_val
		for hid in houses.keys():
			var h_val = houses.get(hid, null)
			if not (h_val is Dictionary):
				continue
			var h: Dictionary = h_val
			var hn_val = h.get("house_number", null)
			if hn_val is int:
				used[int(hn_val)] = true
			elif hn_val is float:
				var f2: float = float(hn_val)
				if f2 == floor(f2):
					used[int(f2)] = true

	var remaining: Array[int] = []
	for n in default_list:
		if used.has(int(n)):
			continue
		remaining.append(int(n))
	return remaining

func _find_first_valid_place_house(engine: GameEngine, actor: int, house_number: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("place_house")
	if ex == null:
		return Result.failure("cannot find executor: place_house")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("place_house", actor, {
					"position": [x, y],
					"rotation": int(rot),
					"house_number": int(house_number),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "place_house",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid place_house placement found (house_number=%d)" % house_number)

func _build_employee_place_house(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var employee_count := int(params.get("employee_count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if employee_count <= 0:
		employee_count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, employee_count)
	if not ensure.ok:
		return ensure

	var numbers := _get_remaining_house_numbers_from_state(state)
	if numbers.is_empty():
		return Result.failure("no remaining house numbers")
	var house_number := int(numbers[0])

	var find := _find_first_valid_place_house(engine, actor, house_number)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_add_garden(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")

	var ex := engine.action_registry.get_executor("add_garden")
	if ex == null:
		return Result.failure("cannot find executor: add_garden")

	var houses_val = state.map.get("houses", null) if (state.map is Dictionary) else null
	if not (houses_val is Dictionary):
		return Result.failure("state.map.houses missing or invalid")
	var houses: Dictionary = houses_val
	var house_ids: Array[String] = []
	for k in houses.keys():
		if k is String:
			house_ids.append(str(k))
	house_ids.sort()

	for house_id in house_ids:
		for dir in ["N", "E", "S", "W"]:
			var cmd := Command.create("add_garden", actor, {
				"house_id": house_id,
				"direction": dir,
			})
			var vr := ex.validate(state, cmd)
			if vr.ok:
				return Result.success({
					"action_id": "add_garden",
					"actor": actor,
					"params": cmd.params.duplicate(true),
				})

	return Result.failure("no valid add_garden target found")

func _build_employee_add_garden(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "PlaceHouses")
	if not adv.ok:
		return adv

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var employee_type := str(params.get("employee_type", "")).strip_edges()
	var employee_count := int(params.get("employee_count", 1))
	if employee_type.is_empty():
		return Result.failure("builder_params.employee_type is empty")
	if employee_count <= 0:
		employee_count = 1

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, employee_type, false, employee_count)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_add_garden(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_lobbyists_road(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	var ex := engine.action_registry.get_executor("place_lobbyists_road")
	if ex == null:
		return Result.failure("cannot find executor: place_lobbyists_road")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for piece_id in ["lobbyists_road_straight", "lobbyists_road_l"]:
		for y in range(minp.y, maxp.y + 1):
			for x in range(minp.x, maxp.x + 1):
				for rot in MapUtils.VALID_ROTATIONS:
					var cmd := Command.create("place_lobbyists_road", actor, {
						"piece_id": piece_id,
						"anchor_pos": [x, y],
						"rotation": int(rot),
					})
					var vr := ex.validate(state, cmd)
					if vr.ok:
						return Result.success({
							"action_id": "place_lobbyists_road",
							"actor": actor,
							"params": cmd.params.duplicate(true),
						})
	return Result.failure("no valid place_lobbyists_road placement found")

func _build_employee_lobbyist_place_road(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Lobbyists")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "lobbyist", false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_lobbyists_road(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _find_first_valid_lobbyists_park(engine: GameEngine, actor: int) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	var ex := engine.action_registry.get_executor("place_lobbyists_park")
	if ex == null:
		return Result.failure("cannot find executor: place_lobbyists_park")

	var coords_script = _get_coords_script()
	if coords_script == null:
		return Result.failure("cannot load Coords: %s" % CoordsScriptPath)
	var minp: Vector2i = coords_script.get_world_min(state)
	var maxp: Vector2i = coords_script.get_world_max(state)
	for y in range(minp.y, maxp.y + 1):
		for x in range(minp.x, maxp.x + 1):
			for rot in MapUtils.VALID_ROTATIONS:
				var cmd := Command.create("place_lobbyists_park", actor, {
					"anchor_pos": [x, y],
					"rotation": int(rot),
				})
				var vr := ex.validate(state, cmd)
				if vr.ok:
					return Result.success({
						"action_id": "place_lobbyists_park",
						"actor": actor,
						"params": cmd.params.duplicate(true),
					})
	return Result.failure("no valid place_lobbyists_park placement found")

func _build_employee_lobbyist_place_park(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Lobbyists")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "lobbyist", false, 1)
	if not ensure.ok:
		return ensure

	var find := _find_first_valid_lobbyists_park(engine, actor)
	if not find.ok:
		return find
	return Result.success({
		"suggested_command": find.value
	})

func _build_employee_rural_marketeer_giant_billboard(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working_sub_phase(engine, "Marketing")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure := _ensure_employee(state, actor, "rural_marketeer", false, 1)
	if not ensure.ok:
		return ensure

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var side := str(params.get("side", "N")).strip_edges()
	if side.is_empty():
		side = "N"
	var product := str(params.get("product", "burger")).strip_edges()
	if product.is_empty():
		product = "burger"

	return Result.success({
		"suggested_command": {
			"action_id": "place_giant_billboard",
			"actor": actor,
			"params": {
				"side": side,
				"product": product,
			},
		}
	})

func _build_employee_night_shift_manager_double_action(engine: GameEngine, c: Dictionary) -> Result:
	# 目标：验证夜班经理让“免薪员工”本子阶段可用次数 *2（最简单：kitchen_trainee produce_food 两次）
	var adv := _advance_to_working_sub_phase(engine, "GetFood")
	if not adv.ok:
		return adv

	var state := engine.get_state()
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var ensure_nsm := _ensure_employee(state, actor, "night_shift_manager", false, 1)
	if not ensure_nsm.ok:
		return ensure_nsm

	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var target_employee := str(params.get("target_employee", "kitchen_trainee")).strip_edges()
	if target_employee.is_empty():
		target_employee = "kitchen_trainee"
	var ensure_target := _ensure_employee(state, actor, target_employee, false, 1)
	if not ensure_target.ok:
		return ensure_target

	return Result.success({
		"suggested_command": {
			"action_id": "produce_food",
			"actor": actor,
			"params": {
				"employee_type": target_employee,
				# multi-produce 的员工需要 food_type；留空会在 validate 阶段提示测试者选择。
			},
		}
	})

func _build_milestone_first_lower_prices(engine: GameEngine, _c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Recruit"
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	var take := StateUpdater.take_from_pool(state, "pricing_manager", 1)
	if not take.ok:
		return Result.failure("take_from_pool(pricing_manager) failed: %s" % take.error)
	var add := StateUpdater.add_employee(state, actor, "pricing_manager", false)
	if not add.ok:
		return Result.failure("add_employee(pricing_manager) failed: %s" % add.error)

	return Result.success({
		"suggested_command": {
			"action_id": "set_price",
			"actor": actor,
			"params": {},
		}
	})

func _build_milestone_first_train(engine: GameEngine, c: Dictionary) -> Result:
	var adv := _advance_to_working(engine)
	if not adv.ok:
		return adv

	var to_train := TestPhaseUtils.advance_until_working_sub_phase(engine, "Train", 30)
	if not to_train.ok:
		engine.get_state().sub_phase = "Train"

	var state := engine.get_state()
	_force_turn_order(state)
	state.sub_phase = "Train"
	var actor := state.get_current_player_id()
	if actor < 0:
		return Result.failure("cannot resolve current player")

	# 1) 准备 trainer（提供 train_limit）
	var take_trainer := StateUpdater.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("take_from_pool(trainer) failed: %s" % take_trainer.error)
	var add_trainer := StateUpdater.add_employee(state, actor, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("add_employee(trainer) failed: %s" % add_trainer.error)

	# 2) 准备待培训员工：放在 reserve_employees
	var params: Dictionary = c.get("builder_params", {}) if c.get("builder_params", null) is Dictionary else {}
	var from_employee := str(params.get("from_employee", "management_trainee")).strip_edges()
	var to_employee := str(params.get("to_employee", "new_business_developer")).strip_edges()
	if from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("builder_params.from_employee/to_employee is empty")

	var take_from := StateUpdater.take_from_pool(state, from_employee, 1)
	if not take_from.ok:
		return Result.failure("take_from_pool(%s) failed: %s" % [from_employee, take_from.error])
	var add_from := StateUpdater.add_employee(state, actor, from_employee, true)
	if not add_from.ok:
		return Result.failure("add_employee(%s,reserve) failed: %s" % [from_employee, add_from.error])

	# 目标员工需要在池中存在（train.validate 会检查）
	if int(state.employee_pool.get(to_employee, 0)) <= 0:
		return Result.failure("employee_pool has no %s (required for training)" % to_employee)

	return Result.success({
		"suggested_command": {
			"action_id": "train",
			"actor": actor,
			"params": {
				"from_employee": from_employee,
				"to_employee": to_employee,
			},
		}
	})
