class_name ModalOverlayOpacityContractTest
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const _MAX_OVERLAY_ALPHA := 0.95
const _COLOR_EPSILON := 0.002

const _SCENE_PATHS := [
	"res://ui/components/modal_panel/reserve_card_selection_modal.tscn",
	"res://ui/components/modal_panel/restructuring_modal.tscn",
	"res://ui/components/modal_panel/turn_order_selection_modal.tscn",
	"res://ui/components/tutorial/tutorial_spotlight_overlay.tscn",
	"res://ui/components/bank_break/bank_break_panel.tscn",
	"res://modules/base_rules/ui/components/modal_panel/fridge_keep_modal.tscn",
	"res://modules/kimchi/ui/components/modal_panel/kimchi_storage_modal.tscn",
	"res://ui/dialogs/confirm_dialog.tscn",
	"res://ui/dialogs/choice_dialog.tscn",
	"res://ui/dialogs/game_config_dialog.tscn",
	"res://ui/dialogs/rules_viewer_dialog.tscn",
	"res://ui/dialogs/settings_dialog.tscn",
]

const _SCRIPT_PATHS := [
	"res://ui/dialogs/info_dialog.gd",
	"res://ui/dialogs/password_dialog.gd",
	"res://ui/dialogs/auth_dialog.gd",
	"res://ui/dialogs/create_room_dialog.gd",
	"res://ui/dialogs/account_settings_dialog.gd",
	"res://ui/dialogs/save_load_dialog.gd",
]

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行弹窗遮罩测试）")
	var st: SceneTree = tree

	var host: Node = st.current_scene
	if host == null or not is_instance_valid(host):
		host = st.root
	if host == null or not is_instance_valid(host):
		return Result.failure("找不到可挂载的场景节点")

	for path_val in _SCENE_PATHS:
		var scene_result := await _check_scene_overlay(host, st, str(path_val))
		if not scene_result.ok:
			return scene_result

	for path_val in _SCRIPT_PATHS:
		var script_result := await _check_script_overlay(host, st, str(path_val))
		if not script_result.ok:
			return script_result

	return Result.success({})

static func _check_scene_overlay(host: Node, st: SceneTree, path: String) -> Result:
	var scene_res = load(path)
	if not (scene_res is PackedScene):
		return Result.failure("无法加载弹窗场景: %s" % path)

	var node = (scene_res as PackedScene).instantiate()
	if node == null or not is_instance_valid(node):
		return Result.failure("无法实例化弹窗场景: %s" % path)

	host.add_child(node)
	await st.process_frame

	var result := _assert_overlay_alpha(path, node)
	_safe_free(node)
	return result

static func _check_script_overlay(host: Node, st: SceneTree, path: String) -> Result:
	var script_res = load(path)
	if not (script_res is Script):
		return Result.failure("无法加载弹窗脚本: %s" % path)

	var node_val = (script_res as Script).new()
	if node_val == null or not is_instance_valid(node_val) or not (node_val is Node):
		return Result.failure("无法实例化弹窗脚本: %s" % path)

	var node: Node = node_val
	host.add_child(node)
	await st.process_frame

	var result := _assert_overlay_alpha(path, node)
	_safe_free(node)
	return result

static func _assert_overlay_alpha(path: String, node: Node) -> Result:
	var overlay = node.get_node_or_null("Overlay")
	if overlay == null:
		overlay = node.get_node_or_null("Background")
	if overlay == null or not (overlay is ColorRect):
		return Result.failure("弹窗缺少遮罩节点: %s" % path)

	var expected := UiStylesClass.get_overlay_dim_color()
	var actual := (overlay as ColorRect).color
	var alpha := float(actual.a)
	if alpha >= _MAX_OVERLAY_ALPHA:
		return Result.failure("弹窗遮罩透明度过高（应保持半透明）: %s alpha=%.3f" % [path, alpha])
	if absf(actual.r - expected.r) > _COLOR_EPSILON or absf(actual.g - expected.g) > _COLOR_EPSILON or absf(actual.b - expected.b) > _COLOR_EPSILON:
		return Result.failure("弹窗遮罩主色不统一: %s actual=%s expected=%s" % [path, str(actual), str(expected)])
	if absf(alpha - expected.a) > _COLOR_EPSILON:
		return Result.failure("弹窗遮罩透明度不统一: %s actual=%.3f expected=%.3f" % [path, alpha, float(expected.a)])

	return Result.success({})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
