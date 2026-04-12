class_name TutorialController
extends RefCounted

const TutorialSpotlightOverlayScene = preload("res://ui/components/tutorial/tutorial_spotlight_overlay.tscn")

var _host = null
var _spotlight_overlay = null

func _init(host) -> void:
	_host = host

func start_tour(
	steps: Array,
	targets_provider: Callable,
	on_completed: Callable = Callable(),
	on_skipped: Callable = Callable()
) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_ensure_spotlight_overlay()
	if _spotlight_overlay == null:
		return
	if _spotlight_overlay.has_method("start_tour"):
		_spotlight_overlay.call("start_tour", steps, targets_provider, on_completed, on_skipped)

func is_tour_running() -> bool:
	return _spotlight_overlay != null and is_instance_valid(_spotlight_overlay) and _spotlight_overlay.has_method("is_tour_running") and bool(_spotlight_overlay.call("is_tour_running"))

func close_tour(mark_completed: bool = false) -> void:
	if _spotlight_overlay == null or not is_instance_valid(_spotlight_overlay):
		return
	if _spotlight_overlay.has_method("cancel_tour"):
		_spotlight_overlay.call("cancel_tour", mark_completed)

func dispose() -> void:
	close_tour(false)
	if _spotlight_overlay != null and is_instance_valid(_spotlight_overlay):
		_spotlight_overlay.queue_free()
	_spotlight_overlay = null
	_host = null

func _ensure_spotlight_overlay() -> void:
	if _spotlight_overlay != null and is_instance_valid(_spotlight_overlay):
		return
	_spotlight_overlay = TutorialSpotlightOverlayScene.instantiate()
	_host.add_child(_spotlight_overlay)
