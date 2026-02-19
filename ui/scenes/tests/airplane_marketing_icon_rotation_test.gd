# airplane marketing icon rotation regression test (no real rendering required)
# Covers issue_tracker #47: airplane icon should rotate with placement so it doesn't get squished on vertical boards.
class_name AirplaneMarketingIconRotationTest
extends RefCounted

const MapCanvasDrawerClass = preload("res://ui/scenes/game/map/drawer/drawer.gd")

class FakeSkin extends RefCounted:
	var _tex: Texture2D = null

	func _init(tex: Texture2D) -> void:
		_tex = tex

	func get_marketing_texture(_key: String) -> Texture2D:
		return _tex

	func get_product_icon_texture(_product_id: String) -> Texture2D:
		return null

class FakeCanvas extends RefCounted:
	var _skin = null
	var transforms: Array[Dictionary] = []

	func _init(tex: Texture2D) -> void:
		_skin = FakeSkin.new(tex)

	func draw_rect(_rect: Rect2, _color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		pass

	func draw_circle(_pos: Vector2, _radius: float, _color: Color) -> void:
		pass

	func draw_string(_font: Font, _pos: Vector2, _text: String, _alignment: int, _width: float, _font_size: int, _color: Color) -> void:
		pass

	func draw_texture_rect(_texture: Texture2D, _rect: Rect2, _tile: bool, _modulate: Color = Color(1, 1, 1, 1)) -> void:
		pass

	func draw_set_transform(origin: Vector2, rotation: float, scale: Vector2) -> void:
		transforms.append({
			"origin": origin,
			"rotation": rotation,
			"scale": scale,
		})

static func _make_dummy_texture(size: Vector2i) -> Texture2D:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

static func run() -> Result:
	var cell_size := 10
	var placement := {
		"type": "airplane",
		"axis": "row",
		"product": "",
		"board_number": 4,
	}

	var tex := _make_dummy_texture(Vector2i(64, 32))

	# Tall rect: expect a 90deg rotation transform to be used.
	var canvas1 := FakeCanvas.new(tex)
	MapCanvasDrawerClass._draw_marketing_placement(canvas1, cell_size, placement, 1.0, Rect2(Vector2.ZERO, Vector2(20, 60)))
	var rotated := false
	for t_val in canvas1.transforms:
		if not (t_val is Dictionary):
			continue
		var t: Dictionary = t_val
		var r := float(t.get("rotation", 0.0))
		if is_equal_approx(r, deg_to_rad(90.0)):
			rotated = true
			break
	if not rotated:
		return Result.failure("expected airplane icon draw to use a 90deg transform for vertical rects")

	# Wide rect: expect no rotation transforms.
	var canvas2 := FakeCanvas.new(tex)
	MapCanvasDrawerClass._draw_marketing_placement(canvas2, cell_size, placement, 1.0, Rect2(Vector2.ZERO, Vector2(60, 20)))
	if not canvas2.transforms.is_empty():
		return Result.failure("expected no transform for horizontal rects, got: %s" % str(canvas2.transforms))

	return Result.success({})

