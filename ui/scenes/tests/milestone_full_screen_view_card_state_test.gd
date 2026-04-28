class_name MilestoneFullScreenViewCardStateTest
extends RefCounted

const ViewClass = preload("res://ui/components/milestone_panel/milestone_full_screen_view.gd")

static func run() -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载视图）")

	var card = ViewClass.MilestoneCard.new()
	if card == null or not is_instance_valid(card):
		return Result.failure("无法创建 MilestoneCard")
	card.milestone_id = "test_milestone"
	card.effect_text = "测试效果描述"
	card.accent_color = Color(0.59, 0.77, 0.82, 1.0)
	host.add_child(card)
	await st.process_frame

	var status_label_val = card.get("_status_label")
	if not (status_label_val is Label):
		return _finish(Result.failure("MilestoneCard 缺少 StatusLabel"), card)
	var status_label: Label = status_label_val

	var status_icon_slot_val = card.get("_status_icon_slot")
	if not (status_icon_slot_val is CenterContainer):
		return _finish(Result.failure("MilestoneCard 缺少 StatusIconSlot"), card)
	var status_icon_slot: CenterContainer = status_icon_slot_val

	var status_check_icon_val = card.get("_status_check_icon")
	if not (status_check_icon_val is Control):
		return _finish(Result.failure("MilestoneCard 缺少 StatusCheckIcon"), card)
	var status_check_icon: Control = status_check_icon_val

	var status_cross_icon_val = card.get("_status_cross_icon")
	if not (status_cross_icon_val is TextureRect):
		return _finish(Result.failure("MilestoneCard 缺少 StatusCrossIcon"), card)
	var status_cross_icon: TextureRect = status_cross_icon_val

	var icons_row_val = card.get("_icons_row")
	if not (icons_row_val is HBoxContainer):
		return _finish(Result.failure("MilestoneCard 缺少 OwnerLogoRow"), card)
	var icons_row: HBoxContainer = icons_row_val

	if status_icon_slot.get_parent() != icons_row.get_parent():
		return _finish(Result.failure("状态图标与餐厅 logo 应位于同一行"), card)

	var min_size: Vector2 = card.custom_minimum_size
	if min_size.x < 300.0 or min_size.y < 210.0:
		return _finish(Result.failure("里程碑卡片尺寸过小: %s" % str(min_size)), card)

	if status_icon_slot.custom_minimum_size.x < 38.0 or status_icon_slot.custom_minimum_size.y < 38.0:
		return _finish(Result.failure("状态图标槽尺寸过小: %s" % str(status_icon_slot.custom_minimum_size)), card)
	if status_label.visible:
		return _finish(Result.failure("状态文字应被图标替代，不应可见"), card)

	card.set_state([0], 0, 1, 1)
	await st.process_frame
	if not status_icon_slot.visible:
		return _finish(Result.failure("他人已获得且不可获得时应显示叉图标"), card)
	if status_check_icon.visible:
		return _finish(Result.failure("他人已获得且不可获得时不应显示对钩图标"), card)
	if not status_cross_icon.visible:
		return _finish(Result.failure("他人已获得且不可获得时应显示叉图标"), card)
	if card.modulate.a > 0.85:
		return _finish(Result.failure("他人已获得且不可获得时卡片应灰化: alpha=%.2f" % card.modulate.a), card)
	if icons_row.get_child_count() < 1:
		return _finish(Result.failure("他人已获得时应展示获得者餐厅 logo"), card)

	card.set_state([1], 0, 1, 1)
	await st.process_frame
	if not status_icon_slot.visible:
		return _finish(Result.failure("当前玩家已获得时应显示对钩图标"), card)
	if not status_check_icon.visible:
		return _finish(Result.failure("当前玩家已获得时应显示对钩图标"), card)
	if status_cross_icon.visible:
		return _finish(Result.failure("当前玩家已获得时不应显示叉图标"), card)
	if card.modulate.a < 0.99:
		return _finish(Result.failure("当前玩家已获得时卡片不应灰化: alpha=%.2f" % card.modulate.a), card)

	card.set_state([], 1, 1, 1)
	await st.process_frame
	if status_icon_slot.visible:
		return _finish(Result.failure("当前玩家可获得时不应显示状态图标"), card)
	if status_check_icon.visible or status_cross_icon.visible:
		return _finish(Result.failure("当前玩家可获得时不应显示对钩或叉图标"), card)
	if card.modulate.a < 0.99:
		return _finish(Result.failure("当前玩家可获得时卡片不应灰化: alpha=%.2f" % card.modulate.a), card)

	return _finish(Result.success({}), card)

static func _finish(result: Result, card) -> Result:
	if card != null and is_instance_valid(card) and card is Node:
		(card as Node).free()
	return result
