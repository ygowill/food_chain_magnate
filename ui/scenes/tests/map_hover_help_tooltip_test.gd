# 地图 hover 帮助提示：房屋/餐厅/饮料进货点应展示主题化信息卡
class_name MapHoverHelpTooltipTest
extends RefCounted

const GameMapInteractionControllerClass = preload("res://ui/scenes/game/map_interaction/controller.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

class FakeEngine:
	extends RefCounted
	var state: GameState = null

	func get_state() -> GameState:
		return state

class FakeScene:
	extends RefCounted
	var game_engine = null

class FakeMapCanvas:
	extends RefCounted
	var cells_by_pos: Dictionary = {}

	func _get_cell_world(world_pos: Vector2i) -> Dictionary:
		var v = cells_by_pos.get(world_pos, null)
		if v is Dictionary:
			return v
		return {}

class FakeTooltipManager:
	extends RefCounted
	var entries: Dictionary = {}
	var show_calls: int = 0
	var hide_calls: int = 0
	var last_key: String = ""

	func add_help_entry(key: String, title: String, content: String) -> void:
		entries[str(key)] = {"title": title, "content": content}

	func show_immediate(key: String, _position: Vector2) -> void:
		show_calls += 1
		last_key = str(key)

	func hide_tooltip() -> void:
		hide_calls += 1
		last_key = ""

class FakeOverlayController:
	extends RefCounted
	var tooltip_manager := FakeTooltipManager.new()

	func get_help_tooltip_manager():
		return tooltip_manager

static func run() -> Result:
	var prev_show_hints := true
	var has_globals := Globals != null
	if has_globals:
		prev_show_hints = bool(Globals.show_hints)
		Globals.show_hints = true

	var state := GameStateClass.new()
	state.rules = {
		"demand_cap_normal": 3,
		"demand_cap_with_garden": 5,
	}
	state.players = [
		{"id": 0, "name": "P1"},
		{"id": 1, "name": "P2"},
	]
	state.map = {
		"grid_size": Vector2i(8, 8),
		"map_origin": Vector2i.ZERO,
		"houses": {
			"9": {
				"house_id": "9",
				"house_number": 9,
				"has_garden": true,
				"printed": false,
				"owner": 1,
				"demands": [
					{"product": "burger"},
					{"product": "soda"},
					{"product": "burger"},
				],
			},
		},
		"restaurants": {
			"rest_1": {"restaurant_id": "rest_1", "owner": 0, "anchor_pos": Vector2i(1, 3), "entrance_pos": Vector2i(1, 3), "cells": [Vector2i(1, 3)]},
			"rest_2": {"restaurant_id": "rest_2", "owner": 0, "anchor_pos": Vector2i(3, 3), "entrance_pos": Vector2i(3, 3), "cells": [Vector2i(3, 3)]},
		},
		"drink_sources": [
			{"world_pos": Vector2i(5, 5), "type": "beer", "tile_id": "tile_m"},
		],
	}

	var map_canvas := FakeMapCanvas.new()
	map_canvas.cells_by_pos[Vector2i(1, 1)] = {
		"structure": {
			"piece_id": "house_with_garden",
			"house_id": "9",
			"owner": 1,
			"parent_anchor": Vector2i(1, 1),
		}
	}
	map_canvas.cells_by_pos[Vector2i(3, 3)] = {
		"structure": {
			"piece_id": "restaurant",
			"owner": 0,
			"restaurant_id": "rest_2",
			"parent_anchor": Vector2i(3, 3),
		}
	}
	map_canvas.cells_by_pos[Vector2i(5, 5)] = {
		"drink_source": {"type": "beer"}
	}

	var engine := FakeEngine.new()
	engine.state = state
	var scene := FakeScene.new()
	scene.game_engine = engine
	var overlay := FakeOverlayController.new()

	var controller = GameMapInteractionControllerClass.new(scene, map_canvas, overlay)

	controller._on_map_cell_hovered(Vector2i(1, 1))
	var house_entry = overlay.tooltip_manager.entries.get("map_hover_house", null)
	if not (house_entry is Dictionary):
		return _finish(Result.failure("hover 房屋后未写入 map_hover_house"), controller, has_globals, prev_show_hints)
	var house_content := str((house_entry as Dictionary).get("content", ""))
	if house_content.find("编号：9") == -1:
		return _finish(Result.failure("房屋提示缺少编号: %s" % house_content), controller, has_globals, prev_show_hints)
	if house_content.find("花园：有") == -1:
		return _finish(Result.failure("房屋提示缺少花园信息: %s" % house_content), controller, has_globals, prev_show_hints)
	if house_content.find("需求：3/5") == -1:
		return _finish(Result.failure("房屋提示缺少需求上限信息: %s" % house_content), controller, has_globals, prev_show_hints)
	if house_content.find("burger x2") == -1:
		return _finish(Result.failure("房屋提示缺少需求明细: %s" % house_content), controller, has_globals, prev_show_hints)

	controller._on_map_cell_hovered(Vector2i(3, 3))
	var rest_entry = overlay.tooltip_manager.entries.get("map_hover_restaurant", null)
	if not (rest_entry is Dictionary):
		return _finish(Result.failure("hover 餐厅后未写入 map_hover_restaurant"), controller, has_globals, prev_show_hints)
	var rest_content := str((rest_entry as Dictionary).get("content", ""))
	if rest_content.find("玩家1") == -1:
		return _finish(Result.failure("餐厅提示缺少归属信息: %s" % rest_content), controller, has_globals, prev_show_hints)
	if rest_content.find("第 2 家餐厅") == -1:
		return _finish(Result.failure("餐厅提示缺少玩家内序号: %s" % rest_content), controller, has_globals, prev_show_hints)
	if rest_content.find("餐厅ID：rest_2") == -1:
		return _finish(Result.failure("餐厅提示缺少餐厅ID: %s" % rest_content), controller, has_globals, prev_show_hints)

	controller._on_map_cell_hovered(Vector2i(5, 5))
	var drink_entry = overlay.tooltip_manager.entries.get("map_hover_drink_source", null)
	if not (drink_entry is Dictionary):
		return _finish(Result.failure("hover 进货点后未写入 map_hover_drink_source"), controller, has_globals, prev_show_hints)
	var drink_content := str((drink_entry as Dictionary).get("content", ""))
	if drink_content.find("饮料类型") == -1 or drink_content.find("beer") == -1:
		return _finish(Result.failure("进货点提示缺少类型信息: %s" % drink_content), controller, has_globals, prev_show_hints)

	var hide_before := overlay.tooltip_manager.hide_calls
	controller._on_map_cell_hovered(Vector2i(-1, -1))
	if overlay.tooltip_manager.hide_calls <= hide_before:
		return _finish(Result.failure("移出地图后应隐藏提示"), controller, has_globals, prev_show_hints)

	return _finish(Result.success({}), controller, has_globals, prev_show_hints)

static func _finish(result: Result, controller, has_globals: bool, prev_show_hints: bool) -> Result:
	if controller != null and is_instance_valid(controller) and controller.has_method("dispose"):
		controller.dispose()
	if has_globals:
		Globals.show_hints = prev_show_hints
	return result
