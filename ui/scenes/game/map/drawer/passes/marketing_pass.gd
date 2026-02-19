# MapCanvasDrawer：营销板件绘制下沉
extends RefCounted

const TextureUtilsClass = preload("res://ui/scenes/game/map/drawer/texture_utils.gd")

static func draw_marketing(canvas, cell_size: int) -> void:
	for pos_val in canvas._marketing_by_pos.keys():
		if not (pos_val is Vector2i):
			continue
		var world_pos: Vector2i = pos_val
		var p: Dictionary = canvas._marketing_by_pos[world_pos]

		# _marketing_by_pos indexes all occupied cells; draw each placement only once (at its anchor).
		var anchor_val = p.get("world_pos", null)
		if not (anchor_val is Vector2i):
			continue
		var anchor: Vector2i = anchor_val
		if anchor != world_pos:
			continue
		if not canvas._is_valid_world_pos(anchor):
			continue

		var base_size := Vector2i.ONE
		var fs_val = p.get("footprint_size", null)
		if fs_val is Vector2i:
			base_size = Vector2i(fs_val)
		elif fs_val is Array:
			var arr: Array = fs_val
			if arr.size() == 2:
				base_size = Vector2i(int(arr[0]), int(arr[1]))
		if base_size.x <= 0 or base_size.y <= 0:
			base_size = Vector2i.ONE

		var rot := 0
		var rot_val = p.get("rotation", null)
		if rot_val is int:
			rot = int(rot_val)
		elif rot_val is float:
			var f: float = float(rot_val)
			if f == floor(f):
				rot = int(f)
		if not rot in [0, 90, 180, 270]:
			rot = 0

		var size := base_size
		if rot == 90 or rot == 270:
			size = Vector2i(base_size.y, base_size.x)

		var pos = canvas._world_to_view(anchor)

		var key: String = "default"
		var type_val = p.get("type", null)
		if type_val is String and not str(type_val).is_empty():
			key = str(type_val)
		var tex: Texture2D = canvas._skin.get_marketing_texture(key)

		# airplane: rotation has no meaning; treat footprint_size where one dimension==2 as outward thickness,
		# and orient it based on the attached edge (issue_tracker #40).
		if key == "airplane":
			var thickness := 2
			var length := 0
			if base_size.x == 2 and base_size.y != 2:
				length = base_size.y
			elif base_size.y == 2 and base_size.x != 2:
				length = base_size.x
			else:
				thickness = mini(base_size.x, base_size.y)
				length = maxi(base_size.x, base_size.y)
			var axis2 := str(p.get("axis", ""))
			# New semantics: axis decides orientation directly (issue_tracker #42).
			if axis2 == "row":
				size = Vector2i(maxi(1, thickness), maxi(1, length)) # left/right
			else:
				size = Vector2i(maxi(1, length), maxi(1, thickness)) # top/bottom

		var rect := Rect2(
			Vector2(pos.x * cell_size, pos.y * cell_size),
			Vector2(size.x * cell_size, size.y * cell_size)
		)

		# outside marketing：视觉上贴地图外侧边缘（不在地图内），并与格子对齐（issue_tracker #30/#64）。
		if key == "airplane":
			var map_origin: Vector2i = canvas._map_data.get("map_origin", Vector2i.ZERO)
			var base_grid_size: Vector2i = canvas._base_grid_size
			if base_grid_size == Vector2i.ZERO:
				var gs_val = canvas._map_data.get("grid_size", null)
				if gs_val is Vector2i:
					base_grid_size = gs_val

			var minp := -map_origin
			var maxp := Vector2i(base_grid_size.x - map_origin.x - 1, base_grid_size.y - map_origin.y - 1)

			var axis := str(p.get("axis", ""))
			if axis != "row" and axis != "col":
				# Fallback inference for older data.
				if anchor.x == minp.x or anchor.x >= maxp.x - 1:
					axis = "row"
				elif anchor.y == minp.y or anchor.y >= maxp.y - 1:
					axis = "col"
			var attach := ""
			if axis == "row":
				attach = "left" if anchor.x == minp.x else "right" if anchor.x >= maxp.x - 1 else ""
			else:
				attach = "top" if anchor.y == minp.y else "bottom" if anchor.y >= maxp.y - 1 else ""

			# Base map rect in view-space pixels (excludes external cells).
			var vmin = canvas._world_to_view(minp)
			var map_pos := Vector2(float(vmin.x * cell_size), float(vmin.y * cell_size))
			var map_size := Vector2(float(base_grid_size.x * cell_size), float(base_grid_size.y * cell_size))
			var map_left := map_pos.x
			var map_top := map_pos.y
			var map_right := map_pos.x + map_size.x
			var map_bottom := map_pos.y + map_size.y

			if attach == "left":
				rect.position.x = map_left - rect.size.x
			elif attach == "right":
				rect.position.x = map_right
			elif attach == "top":
				rect.position.y = map_top - rect.size.y
			elif attach == "bottom":
				rect.position.y = map_bottom

		# Footprint background (subtle) + border so multi-cell boards are visible.
		draw_marketing_placement(canvas, cell_size, p, 1.0, rect)

static func draw_marketing_placement(canvas, cell_size: int, placement: Dictionary, alpha: float, rect_override: Rect2 = Rect2()) -> void:
	if canvas._skin == null:
		return
	var a := clampf(float(alpha), 0.0, 1.0)
	if a <= 0.001:
		return

	var rect := rect_override
	if rect.size == Vector2.ZERO:
		# Fallback: compute rect from placement data (used by map placements). Preview path passes rect_override.
		var anchor_val = placement.get("world_pos", null)
		if not (anchor_val is Vector2i):
			return
		var anchor: Vector2i = anchor_val
		if not canvas._is_valid_world_pos(anchor):
			return

		var base_size := Vector2i.ONE
		var fs_val = placement.get("footprint_size", null)
		if fs_val is Vector2i:
			base_size = Vector2i(fs_val)
		elif fs_val is Array:
			var arr: Array = fs_val
			if arr.size() == 2:
				base_size = Vector2i(int(arr[0]), int(arr[1]))
		if base_size.x <= 0 or base_size.y <= 0:
			base_size = Vector2i.ONE

		var rot := 0
		var rot_val = placement.get("rotation", null)
		if rot_val is int:
			rot = int(rot_val)
		elif rot_val is float:
			var f: float = float(rot_val)
			if f == floor(f):
				rot = int(f)
		if not rot in [0, 90, 180, 270]:
			rot = 0

		var size := base_size
		if rot == 90 or rot == 270:
			size = Vector2i(base_size.y, base_size.x)

		var pos = canvas._world_to_view(anchor)
		rect = Rect2(
			Vector2(pos.x * cell_size, pos.y * cell_size),
			Vector2(size.x * cell_size, size.y * cell_size)
		)

	# Resolve marketing type texture.
	var key: String = "default"
	var type_val = placement.get("type", null)
	if type_val is String and not str(type_val).is_empty():
		key = str(type_val)
	var tex: Texture2D = canvas._skin.get_marketing_texture(key)

	# Background (opaque after placement; semi-transparent for preview via alpha).
	# Marketing piece should NOT have a border (issue_tracker #36).
	var base := Color("#98a295")
	var fill := base
	fill.a = a
	canvas.draw_rect(rect, fill, true)

	# Marketing type texture as a faint background.
	var icon_pad := float(cell_size) * 0.08
	var icon_rect := rect.grow(-icon_pad)
	var type_mod := Color(1, 1, 1, 0.45 * a)
	# airplane texture is authored horizontal; rotate it when the board is vertically oriented (issue_tracker #47).
	if key == "airplane" and icon_rect.size.y > icon_rect.size.x:
		var center := icon_rect.position + icon_rect.size * 0.5
		var draw_size := Vector2(icon_rect.size.y, icon_rect.size.x)
		canvas.draw_set_transform(center, deg_to_rad(90.0), Vector2.ONE)
		TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, Rect2(-draw_size * 0.5, draw_size), type_mod)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		TextureUtilsClass.draw_texture_aspect_fit(canvas, tex, icon_rect, type_mod)

	# Board number badge (top-right): draw before product icon so 1x1 boards keep token readable.
	var bn := 0
	var bn_val = placement.get("board_number", null)
	if bn_val is int:
		bn = int(bn_val)
	elif bn_val is float:
		var f2: float = float(bn_val)
		if f2 == floor(f2):
			bn = int(f2)
	if bn > 0:
		draw_marketing_board_number_badge(canvas, rect, bn, cell_size, a)

	# Product icon centered on the board area (matches “product slot centered” requirement).
	var product_id: String = str(placement.get("product", ""))
	if not product_id.is_empty():
		var pid := product_id
		if pid == "cola":
			pid = "soda"
		var product_tex: Texture2D = canvas._skin.get_product_icon_texture(pid)
		var pad := maxf(2.0, float(cell_size) * 0.12)
		var avail := rect.size - Vector2(pad * 2.0, pad * 2.0)
		var s := minf(avail.x, avail.y) * 0.85
		var icon_size2 := Vector2(s, s)
		var icon_pos2 := rect.position + (rect.size - icon_size2) * 0.5
		var product_rect := Rect2(icon_pos2, icon_size2)
		TextureUtilsClass.draw_texture_aspect_fit(canvas, product_tex, product_rect, Color(1, 1, 1, 0.95 * a))

		# Remaining duration label (center): overlays on top of the product icon.
		var remaining_text := ""
		var rd := 0
		var rd_val = placement.get("remaining_duration", null)
		if rd_val is int:
			rd = int(rd_val)
		elif rd_val is float:
			var f3: float = float(rd_val)
			if f3 == floor(f3):
				rd = int(f3)
		if rd == -1:
			remaining_text = "∞"
		elif rd > 0:
			remaining_text = str(rd)
		if not remaining_text.is_empty():
			var font: Font = ThemeDB.fallback_font
			var font_size := maxi(10, int(round(minf(product_rect.size.x, product_rect.size.y) * 0.55)))
			if remaining_text.length() >= 2:
				font_size = int(round(float(font_size) * 0.85))
			if remaining_text.length() >= 3:
				font_size = int(round(float(font_size) * 0.75))
			font_size = maxi(10, font_size)
			var baseline := Vector2(product_rect.position.x, product_rect.position.y + product_rect.size.y * 0.5 + float(font_size) * 0.35)
			canvas.draw_string(font, baseline + Vector2(1, 1), remaining_text, HORIZONTAL_ALIGNMENT_CENTER, product_rect.size.x, font_size, Color(0, 0, 0, 0.85 * a))
			canvas.draw_string(font, baseline, remaining_text, HORIZONTAL_ALIGNMENT_CENTER, product_rect.size.x, font_size, Color(1, 1, 1, 1.0 * a))

static func draw_marketing_board_number_badge(canvas, rect: Rect2, board_number: int, cell_size: int, alpha: float) -> void:
	var text := str(board_number).strip_edges()
	if text.is_empty():
		return

	var a := clampf(float(alpha), 0.0, 1.0)
	if a <= 0.001:
		return

	var r := maxf(9.0, float(cell_size) * 0.28)
	var pad := maxf(2.0, float(cell_size) * 0.06)
	var center := rect.position + Vector2(rect.size.x - pad - r, pad + r)

	var bg := Color(1, 1, 1, 1)
	bg.a = a
	canvas.draw_circle(center, r, bg)

	var font: Font = ThemeDB.fallback_font
	var font_size := maxi(10, int(round(r * 0.95)))
	var box := Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	# draw_string uses baseline; this places it close to vertical center for fallback font.
	var baseline := Vector2(box.position.x, box.position.y + box.size.y * 0.5 + float(font_size) * 0.35)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, font_size, Color(0, 0, 0, a))
