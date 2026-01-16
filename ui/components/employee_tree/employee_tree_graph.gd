# 员工升级路线树：图形层（节点 + 连接线绘制）
class_name EmployeeTreeGraph
extends Control

signal employee_clicked(employee_id: String)

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const LayoutClass = preload("res://ui/components/employee_tree/employee_tree_layout.gd")

const NODE_SIZE := Vector2(130, 90)
const NODE_SPACING_Y := 32.0
const LAYER_SPACING := 200.0

const EDGE_COLOR := Color("#666666")
const EDGE_HIGHLIGHT_COLOR := Color("#4A90D9")
const EDGE_WIDTH := 2.0
const ARROW_SIZE := 8.0

var _nodes: Dictionary = {} # employee_id -> EmployeeCard
var _positions: Dictionary = {} # employee_id -> Vector2 (top-left)
var _edges: Array[Dictionary] = [] # [{from,to}]
var _edges_out: Dictionary = {} # employee_id -> Array[String]
var _edges_in: Dictionary = {} # employee_id -> Array[String]

var _highlight_nodes: Dictionary = {}
var _highlight_edges: Dictionary = {}
var _hover_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func rebuild_from_registry() -> void:
	_clear_all()

	if not EmployeeRegistryClass.is_loaded():
		_show_placeholder("EmployeeRegistry 未初始化")
		return

	var raw_ids: Array[String] = EmployeeRegistryClass.get_all_ids()
	var ids: Array[String] = []
	for id in raw_ids:
		var eid := str(id).strip_edges()
		if eid.is_empty() or eid == "ceo":
			continue
		ids.append(eid)
	if ids.is_empty():
		_show_placeholder("无员工定义")
		return

	var id_set: Dictionary = {}
	for id in ids:
		id_set[id] = true

	var entry_ids: Array[String] = []
	var role_by_id: Dictionary = {}
	for id in ids:
		var def_val = EmployeeRegistryClass.get_def(id)
		if not (def_val is EmployeeDefClass):
			continue
		var def: EmployeeDef = def_val
		role_by_id[id] = str(def.get_role())
		if def.is_entry_level():
			entry_ids.append(id)

		_edges_out[id] = []
		for t in def.train_to:
			var tid := str(t).strip_edges()
			if tid.is_empty():
				continue
			if not id_set.has(tid):
				continue
			var arr: Array = _edges_out[id]
			if not arr.has(tid):
				arr.append(tid)
			_edges_out[id] = arr

	_edges_in = _build_edges_in(_edges_out)

	var layout: Dictionary = LayoutClass.layout(ids, _edges_out, entry_ids, role_by_id, NODE_SIZE, LAYER_SPACING, NODE_SPACING_Y)
	_positions = layout.get("positions", {}) if layout.get("positions", {}) is Dictionary else {}

	var bounds_val = layout.get("bounds", null)
	if bounds_val is Rect2:
		custom_minimum_size = bounds_val.size
		size = bounds_val.size
	else:
		custom_minimum_size = Vector2(800, 600)

	_build_edges(ids)
	_build_nodes(ids)

	queue_redraw()

func clear_highlight() -> void:
	_hover_id = ""
	_highlight_nodes.clear()
	_highlight_edges.clear()
	for id in _nodes.keys():
		var card: EmployeeCard = _nodes[id]
		if is_instance_valid(card):
			card.set_selected(false)
	queue_redraw()

func _draw() -> void:
	for e_val in _edges:
		if not (e_val is Dictionary):
			continue
		var e: Dictionary = e_val
		var from_id := str(e.get("from", ""))
		var to_id := str(e.get("to", ""))
		if from_id.is_empty() or to_id.is_empty():
			continue
		if not _nodes.has(from_id) or not _nodes.has(to_id):
			continue
		var from_card: EmployeeCard = _nodes[from_id]
		var to_card: EmployeeCard = _nodes[to_id]
		if not is_instance_valid(from_card) or not is_instance_valid(to_card):
			continue

		var from_pos := from_card.position
		var to_pos := to_card.position

		var p1 := from_pos + Vector2(NODE_SIZE.x, NODE_SIZE.y * 0.5)
		var p2 := to_pos + Vector2(0, NODE_SIZE.y * 0.5)
		if p2.x <= p1.x:
			continue

		var dx := maxf(40.0, (p2.x - p1.x) * 0.5)
		var c1 := p1 + Vector2(dx, 0)
		var c2 := p2 - Vector2(dx, 0)

		var key := _edge_key(from_id, to_id)
		var highlight := _highlight_edges.has(key)
		var col := EDGE_HIGHLIGHT_COLOR if highlight else EDGE_COLOR

		_draw_cubic_bezier(p1, c1, c2, p2, col, EDGE_WIDTH)
		_draw_arrow(p2, (p2 - c2).normalized(), col)

func _draw_cubic_bezier(p0: Vector2, c1: Vector2, c2: Vector2, p3: Vector2, col: Color, width: float) -> void:
	var segments: int = 16
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var omt: float = 1.0 - t
		var p: Vector2 = (omt * omt * omt) * p0
		p += (3.0 * omt * omt * t) * c1
		p += (3.0 * omt * t * t) * c2
		p += (t * t * t) * p3
		pts.append(p)
	draw_polyline(pts, col, width, true)

func _draw_arrow(tip: Vector2, dir: Vector2, col: Color) -> void:
	if dir.length_squared() <= 0.0001:
		dir = Vector2.RIGHT
	var d := dir.normalized()
	var perp := Vector2(-d.y, d.x)
	var base := tip - d * ARROW_SIZE
	var p_left := base + perp * (ARROW_SIZE * 0.55)
	var p_right := base - perp * (ARROW_SIZE * 0.55)
	draw_colored_polygon(PackedVector2Array([tip, p_left, p_right]), col)

func _build_edges(ids: Array[String]) -> void:
	_edges.clear()
	for src in ids:
		var arr_val = _edges_out.get(src, [])
		var arr: Array = arr_val if arr_val is Array else []
		for dst_val in arr:
			var dst := str(dst_val).strip_edges()
			if dst.is_empty():
				continue
			if not _positions.has(src) or not _positions.has(dst):
				continue
			_edges.append({"from": src, "to": dst})

func _build_nodes(ids: Array[String]) -> void:
	for id in ids:
		var def_val = EmployeeRegistryClass.get_def(id)
		if not (def_val is EmployeeDefClass):
			continue
		var def: EmployeeDef = def_val

		var card := EmployeeCardClass.new()
		card.variant = EmployeeCardClass.CardVariant.COMPACT
		card.draggable = false
		card.setup(def.to_dict())

		var pos_val = _positions.get(id, Vector2.ZERO)
		card.position = pos_val if pos_val is Vector2 else Vector2.ZERO

		add_child(card)
		_nodes[id] = card

		card.card_clicked.connect(_on_card_clicked)
		card.mouse_entered.connect(_on_card_mouse_entered.bind(id))
		card.mouse_exited.connect(_on_card_mouse_exited.bind(id))

func _build_edges_in(edges_out: Dictionary) -> Dictionary:
	var edges_in: Dictionary = {}
	for src_val in edges_out.keys():
		var src := str(src_val).strip_edges()
		if src.is_empty():
			continue
		var arr_val = edges_out.get(src_val, [])
		var arr: Array = arr_val if arr_val is Array else []
		for dst_val in arr:
			var dst := str(dst_val).strip_edges()
			if dst.is_empty():
				continue
			if not edges_in.has(dst):
				edges_in[dst] = []
			var a: Array = edges_in[dst]
			a.append(src)
			edges_in[dst] = a
	return edges_in

func _set_hover(employee_id: String) -> void:
	var start := str(employee_id).strip_edges()
	if start.is_empty():
		clear_highlight()
		return

	_hover_id = start
	_highlight_nodes.clear()
	_highlight_edges.clear()

	_highlight_nodes[start] = true

	# forward
	var stack_f: Array[String] = [start]
	var visited_f: Dictionary = {start: true}
	while not stack_f.is_empty():
		var u: String = str(stack_f.pop_back())
		var next_val = _edges_out.get(u, [])
		var nexts: Array = next_val if next_val is Array else []
		for v_val in nexts:
			var v := str(v_val).strip_edges()
			if v.is_empty():
				continue
			_highlight_nodes[v] = true
			_highlight_edges[_edge_key(u, v)] = true
			if visited_f.has(v):
				continue
			visited_f[v] = true
			stack_f.append(v)

	# backward
	var stack_b: Array[String] = [start]
	var visited_b: Dictionary = {start: true}
	while not stack_b.is_empty():
		var u2: String = str(stack_b.pop_back())
		var prev_val = _edges_in.get(u2, [])
		var prevs: Array = prev_val if prev_val is Array else []
		for p_val in prevs:
			var p := str(p_val).strip_edges()
			if p.is_empty():
				continue
			_highlight_nodes[p] = true
			_highlight_edges[_edge_key(p, u2)] = true
			if visited_b.has(p):
				continue
			visited_b[p] = true
			stack_b.append(p)

	for id in _nodes.keys():
		var card: EmployeeCard = _nodes[id]
		if is_instance_valid(card):
			card.set_selected(_highlight_nodes.has(str(id)))

	queue_redraw()

func _edge_key(from_id: String, to_id: String) -> String:
	return "%s->%s" % [from_id, to_id]

func _on_card_clicked(employee_id: String) -> void:
	employee_clicked.emit(str(employee_id))

func _on_card_mouse_entered(employee_id: String) -> void:
	_set_hover(employee_id)

func _on_card_mouse_exited(employee_id: String) -> void:
	if str(employee_id) == _hover_id:
		clear_highlight()

func _clear_all() -> void:
	clear_highlight()
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()
	_nodes.clear()
	_positions.clear()
	_edges.clear()
	_edges_out.clear()
	_edges_in.clear()

func _show_placeholder(text: String) -> void:
	var lbl := Label.new()
	lbl.text = str(text)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1))
	add_child(lbl)
