# Game scene：教学/引导控制器
# 负责：
# - 规则教学模式下的主界面导览
# - 重组 / 顺位 / 餐厅放置等上下文导览
# - 首局流程提示卡
class_name GameTutorialsController
extends RefCounted

const TutorialControllerClass = preload("res://ui/tutorial/tutorial_controller.gd")
const TutorialFlowHintCardScene = preload("res://ui/components/tutorial/tutorial_flow_hint_card.tscn")
const GameTutorialContentClass = preload("res://ui/scenes/game/controllers/tutorial_content.gd")
const GameTutorialMatchContentClass = preload("res://ui/scenes/game/controllers/tutorial_match_content.gd")
const GameTutorialTargetsResolverClass = preload("res://ui/scenes/game/controllers/tutorial_targets_resolver.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _host: Control = null
var _status_bar: Control = null
var _map_view: Control = null
var _action_panel: Control = null
var _left_panel: Control = null
var _toolbar: Control = null
var _turn_order_track: Control = null

var _get_game_engine: Callable = Callable()
var _ensure_right_panel_visible: Callable = Callable()
var _get_restructuring_modal: Callable = Callable()
var _get_turn_order_modal: Callable = Callable()
var _get_active_context_overlay: Callable = Callable()
var _get_active_docked_panel: Callable = Callable()
var _get_employee_tree_panel: Callable = Callable()
var _is_headless_runtime: Callable = Callable()
var _is_startup_intro_running: Callable = Callable()
var _is_replay_mode_active: Callable = Callable()
var _is_timeline_read_only_active: Callable = Callable()
var _is_online_resync_in_progress: Callable = Callable()

var _tutorial_controller = null
var _targets_resolver = null
var _tutorial_game_ui_tour_started: bool = false
var _tutorial_restructuring_tour_started: bool = false
var _employee_tree_tutorial_layout_pending: bool = false
var _tutorial_flow_hint_card = null

var _contextual_update_queued: bool = false
var _game_ui_tour_check_queued: bool = false

func _init(
	host: Control,
	status_bar: Control,
	map_view: Control,
	action_panel: Control,
	left_panel: Control,
	toolbar: Control,
	turn_order_track: Control,
	get_game_engine: Callable,
	ensure_right_panel_visible: Callable,
	get_restructuring_modal: Callable,
	get_turn_order_modal: Callable,
	get_active_context_overlay: Callable,
	get_active_docked_panel: Callable,
	get_employee_tree_panel: Callable,
	is_headless_runtime: Callable,
	is_startup_intro_running: Callable,
	is_replay_mode_active: Callable,
	is_timeline_read_only_active: Callable,
	is_online_resync_in_progress: Callable
) -> void:
	_host = host
	_status_bar = status_bar
	_map_view = map_view
	_action_panel = action_panel
	_left_panel = left_panel
	_toolbar = toolbar
	_turn_order_track = turn_order_track
	_get_game_engine = get_game_engine
	_ensure_right_panel_visible = ensure_right_panel_visible
	_get_restructuring_modal = get_restructuring_modal
	_get_turn_order_modal = get_turn_order_modal
	_get_active_context_overlay = get_active_context_overlay
	_get_active_docked_panel = get_active_docked_panel
	_get_employee_tree_panel = get_employee_tree_panel
	_is_headless_runtime = is_headless_runtime
	_is_startup_intro_running = is_startup_intro_running
	_is_replay_mode_active = is_replay_mode_active
	_is_timeline_read_only_active = is_timeline_read_only_active
	_is_online_resync_in_progress = is_online_resync_in_progress

func initialize() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_tutorial_controller = TutorialControllerClass.new(_host)
	_targets_resolver = GameTutorialTargetsResolverClass.new(
		_status_bar,
		_map_view,
		_action_panel,
		_left_panel,
		_toolbar,
		_turn_order_track,
		_get_restructuring_modal,
		_get_turn_order_modal,
		_get_active_context_overlay,
		_get_active_docked_panel,
		_get_employee_tree_panel
	)
	_ensure_tutorial_flow_hint_card()

func dispose() -> void:
	_contextual_update_queued = false
	_game_ui_tour_check_queued = false
	_employee_tree_tutorial_layout_pending = false

	if _tutorial_controller != null and _tutorial_controller.has_method("dispose"):
		_tutorial_controller.dispose()
	elif _tutorial_controller != null and _tutorial_controller.has_method("close_tour"):
		_tutorial_controller.close_tour(false)
	_tutorial_controller = null
	if _targets_resolver != null and _targets_resolver.has_method("dispose"):
		_targets_resolver.dispose()
	_targets_resolver = null

	if _tutorial_flow_hint_card != null and is_instance_valid(_tutorial_flow_hint_card):
		_tutorial_flow_hint_card.queue_free()
	_tutorial_flow_hint_card = null

	_get_game_engine = Callable()
	_ensure_right_panel_visible = Callable()
	_get_restructuring_modal = Callable()
	_get_turn_order_modal = Callable()
	_get_active_context_overlay = Callable()
	_get_active_docked_panel = Callable()
	_get_employee_tree_panel = Callable()
	_is_headless_runtime = Callable()
	_is_startup_intro_running = Callable()
	_is_replay_mode_active = Callable()
	_is_timeline_read_only_active = Callable()
	_is_online_resync_in_progress = Callable()

	_host = null
	_status_bar = null
	_map_view = null
	_action_panel = null
	_left_panel = null
	_toolbar = null
	_turn_order_track = null

func on_ui_updated() -> void:
	if _contextual_update_queued:
		return
	_contextual_update_queued = true
	call_deferred("_flush_contextual_update")

func on_startup_intro_finished() -> void:
	if _game_ui_tour_check_queued:
		return
	_game_ui_tour_check_queued = true
	call_deferred("_flush_game_ui_tour_check")

func _flush_contextual_update() -> void:
	_contextual_update_queued = false
	if _maybe_start_restructuring_tutorial():
		return
	if _maybe_start_turn_order_tutorial():
		return
	if _maybe_start_restaurant_placement_tutorial():
		return
	if _maybe_start_employee_tree_tutorial():
		return
	if _maybe_start_tutorial_match_contextual_tour():
		return
	_maybe_update_flow_tutorial()

func _flush_game_ui_tour_check() -> void:
	_game_ui_tour_check_queued = false
	_maybe_start_game_ui_tour()

func _maybe_start_game_ui_tour() -> void:
	if _tutorial_game_ui_tour_started:
		return
	if _tutorial_controller == null:
		return
	if not _is_tutorial_runtime_enabled():
		return
	if not Globals.tutorial_pending_game_ui_tour or Globals.tutorial_game_ui_tour_seen:
		return
	if _is_tutorial_runtime_blocked():
		return
	if not _is_hotseat_runtime():
		return
	if _tutorial_controller.is_tour_running():
		return

	var state := _get_game_state()
	if state == null:
		return
	if int(state.round_number) != 0:
		return
	if str(state.phase) != DefsClass.PHASE_SETUP:
		return
	if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		return

	if _ensure_right_panel_visible.is_valid():
		_ensure_right_panel_visible.call()

	var steps := _build_game_ui_tour_steps(get_tutorial_targets())
	if steps.is_empty():
		_on_game_ui_tour_finished()
		return

	_tutorial_game_ui_tour_started = true
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_game_ui_tour_finished"),
		Callable(self, "_on_game_ui_tour_skipped")
	)

func _on_game_ui_tour_finished() -> void:
	_complete_game_ui_tour()

func _on_game_ui_tour_skipped() -> void:
	_complete_game_ui_tour()

func _complete_game_ui_tour() -> void:
	_tutorial_game_ui_tour_started = true
	if Globals != null:
		Globals.tutorial_game_ui_tour_seen = true
		Globals.tutorial_pending_game_ui_tour = false
		Globals.save_settings()
	on_ui_updated()

func _maybe_start_restructuring_tutorial() -> bool:
	if _tutorial_restructuring_tour_started:
		return false
	if not _can_start_contextual_tour():
		return false
	var tour_id := GameTutorialContentClass.get_restructuring_tour_id()
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(tour_id):
		_tutorial_restructuring_tour_started = true
		return false

	var state := _get_game_state()
	if state == null or str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return false

	var steps := GameTutorialContentClass.build_restructuring_tour_steps(get_tutorial_targets())
	if steps.is_empty():
		return false

	_tutorial_restructuring_tour_started = true
	_hide_flow_hint_card()
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_restructuring_tour_finished"),
		Callable(self, "_on_restructuring_tour_skipped")
	)
	return true

func _on_restructuring_tour_finished() -> void:
	_complete_context_tour(GameTutorialContentClass.get_restructuring_tour_id())

func _on_restructuring_tour_skipped() -> void:
	_complete_context_tour(GameTutorialContentClass.get_restructuring_tour_id())

func _maybe_start_turn_order_tutorial() -> bool:
	if not _can_start_contextual_tour():
		return false
	var tour_id := GameTutorialContentClass.get_turn_order_tour_id()
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(tour_id):
		return false

	var state := _get_game_state()
	if state == null or str(state.phase) != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return false

	var targets := get_tutorial_targets()
	if not _is_target_visible(targets.get("turn_order_modal_display", null)):
		return false

	var steps := GameTutorialContentClass.build_turn_order_tour_steps(targets)
	if steps.is_empty():
		return false

	_hide_flow_hint_card()
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_turn_order_tour_finished"),
		Callable(self, "_on_turn_order_tour_skipped")
	)
	return true

func _on_turn_order_tour_finished() -> void:
	_complete_context_tour(GameTutorialContentClass.get_turn_order_tour_id())

func _on_turn_order_tour_skipped() -> void:
	_complete_context_tour(GameTutorialContentClass.get_turn_order_tour_id())

func _maybe_start_restaurant_placement_tutorial() -> bool:
	if not _can_start_contextual_tour():
		return false
	var tour_id := GameTutorialContentClass.get_restaurant_placement_tour_id()
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(tour_id):
		return false

	var state := _get_game_state()
	if state == null:
		return false
	var phase_name := str(state.phase)
	var sub_phase_name := str(state.sub_phase)
	var is_setup_restaurant := phase_name == DefsClass.PHASE_SETUP and sub_phase_name.is_empty()
	var is_working_restaurant := phase_name == DefsClass.PHASE_WORKING and sub_phase_name == DefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if not is_setup_restaurant and not is_working_restaurant:
		return false

	var targets := get_tutorial_targets()
	var overlay = targets.get("active_context_overlay", null)
	if overlay == null or not is_instance_valid(overlay):
		return false
	if not overlay.has_method("get_selected_restaurant"):
		return false

	var steps: Array = []
	if _use_tutorial_match_content():
		steps = GameTutorialMatchContentClass.build_restaurant_placement_tour_steps(targets)
	else:
		steps = GameTutorialContentClass.build_restaurant_placement_tour_steps(targets)
	if steps.is_empty():
		return false

	_hide_flow_hint_card()
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_restaurant_placement_tour_finished"),
		Callable(self, "_on_restaurant_placement_tour_skipped")
	)
	return true

func _on_restaurant_placement_tour_finished() -> void:
	_complete_context_tour(GameTutorialContentClass.get_restaurant_placement_tour_id())

func _on_restaurant_placement_tour_skipped() -> void:
	_complete_context_tour(GameTutorialContentClass.get_restaurant_placement_tour_id())

func _maybe_start_employee_tree_tutorial() -> bool:
	if not _can_start_contextual_tour():
		_employee_tree_tutorial_layout_pending = false
		return false

	var tour_id := _get_employee_tree_tour_id()
	if tour_id.is_empty():
		_employee_tree_tutorial_layout_pending = false
		return false
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(tour_id):
		_employee_tree_tutorial_layout_pending = false
		return false

	var panel := _get_visible_employee_tree_panel()
	if panel == null:
		_employee_tree_tutorial_layout_pending = false
		return false
	if not _ensure_employee_tree_tutorial_layout_ready(panel):
		return false

	var targets := get_tutorial_targets()
	if not _is_target_visible(targets.get("employee_tree_viewport", null)):
		return false
	if not _is_target_visible(targets.get("employee_tree_sample_card", null)):
		return false

	var steps := _build_employee_tree_tour_steps(targets)
	if steps.is_empty():
		return false

	_employee_tree_tutorial_layout_pending = false
	_hide_flow_hint_card()
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_employee_tree_tour_finished").bind(tour_id),
		Callable(self, "_on_employee_tree_tour_skipped").bind(tour_id)
	)
	return true

func _on_employee_tree_tour_finished(tour_id: String) -> void:
	_complete_context_tour(tour_id)

func _on_employee_tree_tour_skipped(tour_id: String) -> void:
	_complete_context_tour(tour_id)

func _maybe_start_tutorial_match_contextual_tour() -> bool:
	if not _use_tutorial_match_content():
		return false
	if _is_employee_tree_open():
		return false
	if _maybe_start_match_recruit_tutorial():
		return true
	if _maybe_start_match_train_tutorial():
		return true
	if _maybe_start_match_marketing_tutorial():
		return true
	if _maybe_start_match_food_tutorial():
		return true
	if _maybe_start_match_drinks_tutorial():
		return true
	return false

func _maybe_start_match_recruit_tutorial() -> bool:
	return _maybe_start_match_sub_phase_tour(
		GameTutorialMatchContentClass.get_recruit_tour_id(),
		DefsClass.SUB_PHASE_RECRUIT,
		"recruit_panel_items_container",
		Callable(GameTutorialMatchContentClass, "build_recruit_tour_steps")
	)

func _maybe_start_match_train_tutorial() -> bool:
	return _maybe_start_match_sub_phase_tour(
		GameTutorialMatchContentClass.get_train_tour_id(),
		DefsClass.SUB_PHASE_TRAIN,
		"train_panel_sources_section",
		Callable(GameTutorialMatchContentClass, "build_train_tour_steps")
	)

func _maybe_start_match_marketing_tutorial() -> bool:
	return _maybe_start_match_sub_phase_tour(
		GameTutorialMatchContentClass.get_marketing_tour_id(),
		DefsClass.SUB_PHASE_MARKETING,
		"marketing_panel_type_section",
		Callable(GameTutorialMatchContentClass, "build_marketing_tour_steps")
	)

func _maybe_start_match_food_tutorial() -> bool:
	return _maybe_start_match_sub_phase_tour(
		GameTutorialMatchContentClass.get_food_tour_id(),
		DefsClass.SUB_PHASE_GET_FOOD,
		"production_panel_products_container",
		Callable(GameTutorialMatchContentClass, "build_food_tour_steps")
	)

func _maybe_start_match_drinks_tutorial() -> bool:
	return _maybe_start_match_sub_phase_tour(
		GameTutorialMatchContentClass.get_drinks_tour_id(),
		DefsClass.SUB_PHASE_GET_DRINKS,
		"production_panel_products_container",
		Callable(GameTutorialMatchContentClass, "build_drinks_tour_steps")
	)

func _maybe_start_match_sub_phase_tour(tour_id: String, sub_phase_name: String, required_target_key: String, build_steps: Callable) -> bool:
	if not _can_start_contextual_tour():
		return false
	if not build_steps.is_valid():
		return false
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(tour_id):
		return false

	var state := _get_game_state()
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return false
	if str(state.sub_phase) != sub_phase_name:
		return false

	var targets := get_tutorial_targets()
	if not _is_target_visible(targets.get(required_target_key, null)):
		return false

	var steps_val = build_steps.call(targets)
	if not (steps_val is Array):
		return false
	var steps: Array = Array(steps_val)
	if steps.is_empty():
		return false

	_hide_flow_hint_card()
	_tutorial_controller.start_tour(
		steps,
		Callable(self, "get_tutorial_targets"),
		Callable(self, "_on_match_contextual_tour_finished").bind(tour_id),
		Callable(self, "_on_match_contextual_tour_skipped").bind(tour_id)
	)
	return true

func _on_match_contextual_tour_finished(tour_id: String) -> void:
	_complete_context_tour(tour_id)

func _on_match_contextual_tour_skipped(tour_id: String) -> void:
	_complete_context_tour(tour_id)

func _complete_context_tour(tour_id: String) -> void:
	_employee_tree_tutorial_layout_pending = false
	if Globals != null and Globals.has_method("mark_tutorial_flow_hint_seen"):
		Globals.mark_tutorial_flow_hint_seen(tour_id, true)
	on_ui_updated()

func get_tutorial_targets(target_key: String = "") -> Dictionary:
	if _targets_resolver == null or not _targets_resolver.has_method("get_targets"):
		return {}
	return _targets_resolver.get_targets(target_key)

func _ensure_tutorial_flow_hint_card() -> void:
	if _tutorial_flow_hint_card != null and is_instance_valid(_tutorial_flow_hint_card):
		return
	if _host == null or not is_instance_valid(_host):
		return
	_tutorial_flow_hint_card = TutorialFlowHintCardScene.instantiate()
	_host.add_child(_tutorial_flow_hint_card)
	if _tutorial_flow_hint_card.has_signal("dismissed"):
		_tutorial_flow_hint_card.dismissed.connect(_on_tutorial_flow_hint_dismissed)
	if _tutorial_flow_hint_card.has_signal("disable_requested"):
		_tutorial_flow_hint_card.disable_requested.connect(_on_tutorial_flow_hint_disable_requested)

func _maybe_update_flow_tutorial() -> void:
	if not _is_flow_tutorial_active():
		_hide_flow_hint_card()
		return

	var state := _get_game_state()
	if state == null:
		return
	if _is_flow_tutorial_complete():
		Globals.tutorial_pending_flow_tutorial = false
		_hide_flow_hint_card()
		return

	var hint := _get_flow_tutorial_hint_for_state(state)
	if hint.is_empty():
		return

	var hint_id := str(hint.get("id", "")).strip_edges()
	if hint_id.is_empty():
		return
	if Globals.has_method("has_tutorial_flow_hint_seen") and Globals.has_tutorial_flow_hint_seen(hint_id):
		return

	Globals.mark_tutorial_flow_hint_seen(hint_id, true)
	_ensure_tutorial_flow_hint_card()
	if _tutorial_flow_hint_card != null and is_instance_valid(_tutorial_flow_hint_card) and _tutorial_flow_hint_card.has_method("show_hint"):
		_tutorial_flow_hint_card.show_hint(
			hint_id,
			str(hint.get("title", "流程提示")),
			str(hint.get("body", "")),
			hint
		)

func _is_flow_tutorial_active() -> bool:
	if not _is_tutorial_runtime_enabled():
		return false
	if not Globals.tutorial_pending_flow_tutorial:
		return false
	if _is_tutorial_runtime_blocked():
		return false
	if not _is_hotseat_runtime():
		return false
	if Globals.tutorial_pending_game_ui_tour:
		return false
	if _tutorial_controller != null and _tutorial_controller.is_tour_running():
		return false
	if _is_employee_tree_open():
		return false
	return _get_game_engine_instance() != null

func _is_flow_tutorial_complete() -> bool:
	if Globals == null:
		return true
	for hint_id in _get_required_flow_hint_ids():
		if not Globals.has_tutorial_flow_hint_seen(hint_id):
			return false
	return true

func _on_tutorial_flow_hint_dismissed(_hint_id: String) -> void:
	_hide_flow_hint_card()

func _on_tutorial_flow_hint_disable_requested(_hint_id: String) -> void:
	if Globals != null:
		Globals.tutorial_pending_flow_tutorial = false
	_hide_flow_hint_card()

func _hide_flow_hint_card() -> void:
	if _tutorial_flow_hint_card != null and is_instance_valid(_tutorial_flow_hint_card) and _tutorial_flow_hint_card.has_method("hide_hint"):
		_tutorial_flow_hint_card.hide_hint()

func _build_game_ui_tour_steps(targets: Dictionary) -> Array:
	if _use_tutorial_match_content():
		return GameTutorialMatchContentClass.build_game_ui_tour_steps(targets)
	return GameTutorialContentClass.build_game_ui_tour_steps(targets)

func _build_employee_tree_tour_steps(targets: Dictionary) -> Array:
	if _use_tutorial_match_content():
		return GameTutorialMatchContentClass.build_employee_tree_tour_steps(targets)
	return GameTutorialContentClass.build_employee_tree_tour_steps(targets)

func _get_flow_tutorial_hint_for_state(state: GameState) -> Dictionary:
	if _use_tutorial_match_content():
		return GameTutorialMatchContentClass.get_flow_tutorial_hint_for_state(state)
	return GameTutorialContentClass.get_flow_tutorial_hint_for_state(state)

func _get_employee_tree_tour_id() -> String:
	if _use_tutorial_match_content():
		return GameTutorialMatchContentClass.get_employee_tree_tour_id()
	return GameTutorialContentClass.get_employee_tree_tour_id()

func _get_required_flow_hint_ids() -> Array[String]:
	if _use_tutorial_match_content():
		return GameTutorialMatchContentClass.get_required_flow_hint_ids()
	return GameTutorialContentClass.get_required_flow_hint_ids()

func _use_tutorial_match_content() -> bool:
	return Globals != null and bool(Globals.tutorial_match_enabled)

func _can_start_contextual_tour() -> bool:
	if _tutorial_controller == null:
		return false
	if not _is_tutorial_runtime_enabled():
		return false
	if _is_tutorial_runtime_blocked():
		return false
	if not _is_hotseat_runtime():
		return false
	if Globals.tutorial_pending_game_ui_tour:
		return false
	if _tutorial_controller.is_tour_running():
		return false
	return _get_game_engine_instance() != null

func _is_target_visible(target) -> bool:
	if not (target is Control):
		return false
	var control: Control = target
	return is_instance_valid(control) and control.is_visible_in_tree()

func _get_game_engine_instance() -> GameEngine:
	if not _get_game_engine.is_valid():
		return null
	var engine = _get_game_engine.call()
	if engine is GameEngine:
		return engine
	return null

func _get_game_state() -> GameState:
	var engine := _get_game_engine_instance()
	if engine == null:
		return null
	return engine.get_state()

func _is_tutorial_runtime_blocked() -> bool:
	if _call_bool(_is_headless_runtime):
		return true
	if _call_bool(_is_startup_intro_running):
		return true
	if _call_bool(_is_replay_mode_active):
		return true
	if _call_bool(_is_timeline_read_only_active):
		return true
	if _call_bool(_is_online_resync_in_progress):
		return true
	return false

func _is_tutorial_runtime_enabled() -> bool:
	if Globals == null:
		return false
	if Globals.has_method("is_tutorial_runtime_enabled"):
		return bool(Globals.is_tutorial_runtime_enabled())
	return (
		bool(Globals.tutorial_pending_setup_tour)
		or bool(Globals.tutorial_pending_game_ui_tour)
		or bool(Globals.tutorial_pending_flow_tutorial)
		or bool(Globals.tutorial_match_enabled)
	)

func _is_hotseat_runtime() -> bool:
	if NetContext == null:
		return true
	return int(NetContext.mode) == int(NetContext.Mode.HOTSEAT)

func _is_employee_tree_open() -> bool:
	return _get_visible_employee_tree_panel() != null

func _get_visible_employee_tree_panel() -> Control:
	if not _get_employee_tree_panel.is_valid():
		return null
	var panel = _get_employee_tree_panel.call()
	if not (panel is Control):
		return null
	var control: Control = panel
	if not is_instance_valid(control) or not control.visible:
		return null
	return control

func _ensure_employee_tree_tutorial_layout_ready(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		_employee_tree_tutorial_layout_pending = false
		return false
	if not panel.has_method("prepare_tutorial_layout") or not panel.has_method("is_tutorial_layout_ready"):
		_employee_tree_tutorial_layout_pending = false
		return true
	if bool(panel.call("is_tutorial_layout_ready")):
		_employee_tree_tutorial_layout_pending = false
		return true
	if not _employee_tree_tutorial_layout_pending:
		_employee_tree_tutorial_layout_pending = true
		panel.call("prepare_tutorial_layout")
	return false

func _call_bool(callback: Callable) -> bool:
	if not callback.is_valid():
		return false
	return bool(callback.call())
