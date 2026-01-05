# 游戏地图视图（M8：MapCanvas 分层绘制）
extends ScrollContainer

@onready var canvas: Control = $Canvas

func set_game_state(state: GameState) -> void:
	if state == null:
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_game_state"):
		canvas.call("set_game_state", state)

func set_map_data(map_data: Dictionary) -> void:
	if map_data.is_empty():
		clear()
		return
	if is_instance_valid(canvas) and canvas.has_method("set_map_data"):
		canvas.call("set_map_data", map_data)

func clear() -> void:
	if is_instance_valid(canvas) and canvas.has_method("clear"):
		canvas.call("clear")
