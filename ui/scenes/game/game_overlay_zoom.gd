# Game scene：缩放控制初始化与回调
extends RefCounted

const ZoomControlScene = preload("res://ui/components/zoom_control/zoom_control.tscn")

var _scene = null
var _map_view = null

var zoom_control = null

func _init(scene, map_view) -> void:
	_scene = scene
	_map_view = map_view

func initialize() -> void:
	if _scene == null:
		return

	if zoom_control == null:
		zoom_control = ZoomControlScene.instantiate()
		# 连接信号
		if zoom_control.has_signal("zoom_in_pressed"):
			zoom_control.zoom_in_pressed.connect(_on_zoom_in_pressed)
		if zoom_control.has_signal("zoom_out_pressed"):
			zoom_control.zoom_out_pressed.connect(_on_zoom_out_pressed)
		if zoom_control.has_signal("reset_pressed"):
			zoom_control.reset_pressed.connect(_on_zoom_reset_pressed)
		if zoom_control.has_signal("fit_pressed"):
			zoom_control.fit_pressed.connect(_on_zoom_fit_pressed)

		# 将缩放控制添加到地图区域
		# 查找 GameArea 节点并添加
		var game_area = _scene.get_node_or_null("MainContent/CenterSplit/GameArea")
		if game_area != null:
			zoom_control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			zoom_control.position = Vector2(-50, -160)
			game_area.add_child(zoom_control)
		else:
			_scene.add_child(zoom_control)

	# 连接 map_view 的缩放变化信号
	if is_instance_valid(_map_view) and _map_view.has_signal("zoom_changed"):
		if not _map_view.zoom_changed.is_connected(_on_map_zoom_changed):
			_map_view.zoom_changed.connect(_on_map_zoom_changed)

func _on_zoom_in_pressed() -> void:
	if is_instance_valid(_map_view) and _map_view.has_method("zoom_in"):
		_map_view.zoom_in()

func _on_zoom_out_pressed() -> void:
	if is_instance_valid(_map_view) and _map_view.has_method("zoom_out"):
		_map_view.zoom_out()

func _on_zoom_reset_pressed() -> void:
	if is_instance_valid(_map_view) and _map_view.has_method("reset_zoom"):
		_map_view.reset_zoom()

func _on_zoom_fit_pressed() -> void:
	if is_instance_valid(_map_view) and _map_view.has_method("fit_to_view"):
		_map_view.fit_to_view()

func _on_map_zoom_changed(zoom_level: float) -> void:
	if is_instance_valid(zoom_control) and zoom_control.has_method("set_zoom_level"):
		zoom_control.set_zoom_level(zoom_level)

