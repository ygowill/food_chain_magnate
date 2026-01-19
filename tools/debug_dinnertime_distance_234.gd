# Debug helper: inspect dinnertime distance calculation for `.savings/234.json`.
# Usage:
#   mkdir -p .tmp_home .godot
#   HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/DebugDinnertime234.log" --path . --script res://tools/debug_dinnertime_distance_234.gd
extends SceneTree

const NAME := "DebugDinnertime234"

func _initialize() -> void:
	print("[%s] START" % NAME)
	# 注意：在 `--script` 模式下，脚本会在 Autoload 名称注册之前先被编译。
	# 若这里使用 `preload()` 预加载依赖（其内部引用了 Autoload 单例名 GameLog/DebugFlags），
	# 会触发“Identifier not found: GameLog/DebugFlags”的编译错误。
	# 因此改为在运行时 `load()` 延迟加载依赖。
	call_deferred("_run")

func _run() -> void:
	var GameEngineClass = load("res://core/engine/game_engine.gd")
	if GameEngineClass == null:
		push_error("[%s] FAIL load GameEngine script" % NAME)
		quit(1)
		return
	var engine = GameEngineClass.new()
	var load_result = engine.load_from_file("res://.savings/234.json")
	if not load_result.ok:
		push_error("[%s] FAIL load archive: %s" % [NAME, load_result.error])
		quit(1)
		return

	var state = engine.get_state()
	print("[%s] phase=%s sub_phase=%s" % [NAME, str(state.phase), str(state.sub_phase)])

	var houses: Dictionary = state.map.get("houses", {})
	var restaurants: Dictionary = state.map.get("restaurants", {})
	print("[%s] houses=%d restaurants=%d" % [NAME, houses.size(), restaurants.size()])

	var house_id := "7"
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		push_error("[%s] FAIL missing house %s" % [NAME, house_id])
		quit(1)
		return
	var house: Dictionary = house_val

	var RoadGraphCacheClass = load("res://core/map/map_runtime/road_graph_cache.gd")
	if RoadGraphCacheClass == null:
		push_error("[%s] FAIL load RoadGraphCache script" % NAME)
		quit(1)
		return
	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		push_error("[%s] FAIL RoadGraph is null" % NAME)
		quit(1)
		return

	var DinnertimeDistanceClass = load("res://core/rules/phase/dinnertime/dinnertime_distance.gd")
	if DinnertimeDistanceClass == null:
		push_error("[%s] FAIL load DinnertimeDistance script" % NAME)
		quit(1)
		return

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)

	for rest_id in restaurants.keys():
		var rest_val = restaurants[rest_id]
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		var dist_result = DinnertimeDistanceClass.get_restaurant_to_house_distance(
			road_graph,
			state,
			grid_size,
			str(rest_id),
			rest,
			house_id,
			house
		)
		if not dist_result.ok:
			push_error("[%s] dist FAIL rest=%s: %s" % [NAME, str(rest_id), dist_result.error])
			continue
		print("[%s] dist rest=%s owner=%s anchor=%s entrance=%s => %s" % [
			NAME,
			str(rest_id),
			str(rest.get("owner", "")),
			str(rest.get("anchor_pos", "")),
			str(rest.get("entrance_pos", "")),
			str(dist_result.value),
		])

	print("[%s] DONE" % NAME)
	quit(0)
