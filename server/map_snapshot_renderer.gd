class_name MapSnapshotRenderer
extends RefCounted

const VERSION := 1
const MapSnapshotCpuCanvasClass = preload("res://tools/map_snapshot_cpu_canvas.gd")

const DEFAULT_CELL_PX := 80
const MAX_IMAGE_DIMENSION := 3200
const MIN_CELL_PX := 8

static func render_state_png(state, options: Dictionary = {}) -> Result:
	var canvas := MapSnapshotCpuCanvasClass.new()
	var canvas_r: Result = canvas.render_state_png(state, {
		"cell_px": int(options.get("cell_px", DEFAULT_CELL_PX)),
		"min_cell_px": int(options.get("min_cell_px", MIN_CELL_PX)),
		"max_image_dimension": int(options.get("max_image_dimension", MAX_IMAGE_DIMENSION)),
	})
	if not canvas_r.ok:
		return canvas_r
	var value: Dictionary = Dictionary(canvas_r.value)
	value["version"] = VERSION
	return canvas_r.with_value(value)
