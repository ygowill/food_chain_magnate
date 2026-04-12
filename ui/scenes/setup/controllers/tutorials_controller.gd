# GameSetup scene：规则教学入口控制器
# 负责：
# - 响应主菜单“规则教学”入口
# - 开局设置页导览
# - 将教学局启动标记同步到 Globals
class_name GameSetupTutorialsController
extends RefCounted

const TutorialControllerClass = preload("res://ui/tutorial/tutorial_controller.gd")
const GameSetupTutorialContentClass = preload("res://ui/scenes/setup/controllers/tutorial_content.gd")
const GameSetupTutorialTargetsResolverClass = preload("res://ui/scenes/setup/controllers/tutorial_targets_resolver.gd")

var _host: Control = null
var _player_count_section: Control = null
var _modules_section: Control = null
var _start_button: Control = null

var _get_module_selector_tutorial_targets: Callable = Callable()
var _apply_tutorial_match_preset: Callable = Callable()

var _tutorial_controller = null
var _targets_resolver = null
var _tutorial_start_requested: bool = false
var _tutorial_match_requested: bool = false
var _pending_setup_tour_check_queued: bool = false

func _init(
	host: Control,
	player_count_section: Control,
	modules_section: Control,
	start_button: Control,
	get_module_selector_tutorial_targets: Callable,
	apply_tutorial_match_preset: Callable
) -> void:
	_host = host
	_player_count_section = player_count_section
	_modules_section = modules_section
	_start_button = start_button
	_get_module_selector_tutorial_targets = get_module_selector_tutorial_targets
	_apply_tutorial_match_preset = apply_tutorial_match_preset

func initialize() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_tutorial_controller = TutorialControllerClass.new(_host)
	_targets_resolver = GameSetupTutorialTargetsResolverClass.new(
		_player_count_section,
		_modules_section,
		_start_button,
		_get_module_selector_tutorial_targets
	)
	queue_pending_setup_tour_if_needed()

func dispose() -> void:
	_pending_setup_tour_check_queued = false
	if Globals != null:
		Globals.tutorial_pending_setup_tour = false

	if _tutorial_controller != null and _tutorial_controller.has_method("dispose"):
		_tutorial_controller.dispose()
	elif _tutorial_controller != null and _tutorial_controller.has_method("close_tour"):
		_tutorial_controller.close_tour(false)
	_tutorial_controller = null
	if _targets_resolver != null and _targets_resolver.has_method("dispose"):
		_targets_resolver.dispose()
	_targets_resolver = null

	_get_module_selector_tutorial_targets = Callable()
	_apply_tutorial_match_preset = Callable()

	_host = null
	_player_count_section = null
	_modules_section = null
	_start_button = null

func queue_pending_setup_tour_if_needed() -> void:
	if _pending_setup_tour_check_queued:
		return
	_pending_setup_tour_check_queued = true
	call_deferred("_flush_pending_setup_tour_if_needed")

func sync_start_flags() -> void:
	if Globals == null:
		return
	Globals.tutorial_pending_setup_tour = false
	Globals.tutorial_pending_game_ui_tour = _tutorial_start_requested and not Globals.tutorial_game_ui_tour_seen
	Globals.tutorial_pending_flow_tutorial = _tutorial_start_requested
	Globals.tutorial_match_enabled = _tutorial_start_requested and _tutorial_match_requested

func should_apply_tutorial_match_preset_on_start() -> bool:
	return _tutorial_start_requested and _tutorial_match_requested

func _flush_pending_setup_tour_if_needed() -> void:
	_pending_setup_tour_check_queued = false
	_maybe_start_pending_setup_tour()

func _maybe_start_pending_setup_tour() -> void:
	if Globals == null:
		return
	if not Globals.tutorial_pending_setup_tour:
		return
	if _host == null or not is_instance_valid(_host):
		return

	_tutorial_start_requested = true
	_tutorial_match_requested = true
	if _tutorial_match_requested and _apply_tutorial_match_preset.is_valid():
		_apply_tutorial_match_preset.call()
	call_deferred("_start_setup_tour")

func _start_setup_tour() -> void:
	if _tutorial_controller == null:
		return

	var steps := GameSetupTutorialContentClass.build_setup_tour_steps(get_tutorial_targets())
	if steps.is_empty():
		_on_setup_tour_finished()
		return

	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_setup_tour_finished"),
		Callable(self, "_on_setup_tour_skipped")
	)

func _on_setup_tour_finished() -> void:
	if Globals == null:
		return
	Globals.tutorial_setup_tour_seen = true
	Globals.save_settings()

func _on_setup_tour_skipped() -> void:
	if Globals == null:
		return
	Globals.tutorial_setup_tour_seen = true
	Globals.save_settings()

func get_tutorial_targets() -> Dictionary:
	if _targets_resolver == null or not _targets_resolver.has_method("get_targets"):
		return {}
	return _targets_resolver.get_targets()
