class_name ReserveCardsFullScreenViewPrivacyTest
extends RefCounted

const ViewScene: PackedScene = preload("res://ui/components/reserve_cards/reserve_cards_full_screen_view.tscn")

static func run(seed_val: int = 12345) -> Result:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return Result.failure("MainLoop 不是 SceneTree（无法运行 UI 测试）")
	var st: SceneTree = tree

	var host := st.current_scene
	if host == null or not is_instance_valid(host):
		return Result.failure("current_scene 为空（无法挂载视图）")

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), null, engine)

	var state := engine.get_state()
	if state == null:
		return _finish(Result.failure("state 为空"), null, engine)

	state.current_player_index = 0
	state.players[0]["reserve_card_selected"] = 1
	state.players[0]["reserve_card_revealed"] = false
	state.players[1]["reserve_card_selected"] = 2
	state.players[1]["reserve_card_revealed"] = false
	state.players[0]["can_peek_all_reserve_cards"] = false

	var view = ViewScene.instantiate()
	if view == null or not is_instance_valid(view):
		return _finish(Result.failure("实例化 ReserveCardsFullScreenView 失败"), view, engine)
	host.add_child(view)
	(view as Control).visible = true
	await st.process_frame

	if not view.has_method("open_with_state"):
		return _finish(Result.failure("ReserveCardsFullScreenView 缺少 open_with_state"), view, engine)
	if view.has_method("set_viewer_player_id_override"):
		view.call("set_viewer_player_id_override", 0)

	view.call("open_with_state", state, -1)
	await st.process_frame

	var sections = view.get("sections")
	if sections == null or not is_instance_valid(sections) or not (sections is VBoxContainer):
		return _finish(Result.failure("Sections 容器缺失"), view, engine)
	if sections.get_child_count() < 2:
		return _finish(Result.failure("玩家区块数量不足，实际: %d" % sections.get_child_count()), view, engine)
	var player1_section = sections.get_child(1)
	if player1_section == null or not is_instance_valid(player1_section):
		return _finish(Result.failure("玩家1 Section 节点缺失"), view, engine)

	var hidden_selection: Node = player1_section.find_child("SelectionLabel", true, false)
	if not (hidden_selection is Label):
		return _finish(Result.failure("玩家1 SelectionLabel 节点缺失"), view, engine)
	if str((hidden_selection as Label).text).find("未公开") < 0:
		return _finish(Result.failure("未获得能力时，玩家1 的选择应保持未公开，实际: %s" % str((hidden_selection as Label).text)), view, engine)

	var cards_row = player1_section.find_child("CardsRow", true, false)
	if cards_row == null or not is_instance_valid(cards_row):
		return _finish(Result.failure("玩家1 CardsRow 节点缺失"), view, engine)
	if cards_row.get_child_count() != 1:
		return _finish(Result.failure("面板应仅展示每位玩家已选储备卡，实际卡片数: %d" % cards_row.get_child_count()), view, engine)
	var card0 = cards_row.get_child(0)
	if card0 == null or not is_instance_valid(card0):
		return _finish(Result.failure("玩家1 已选卡节点缺失"), view, engine)
	var hidden_title: Node = card0.find_child("TitleLabel", true, false)
	if not (hidden_title is Label):
		return _finish(Result.failure("玩家1 已选卡标题节点缺失"), view, engine)
	if str((hidden_title as Label).text) != "未公开":
		return _finish(Result.failure("未获得能力时，其他玩家已选卡应隐藏，实际: %s" % str((hidden_title as Label).text)), view, engine)

	state.players[0]["can_peek_all_reserve_cards"] = true
	view.call("open_with_state", state, 0)
	await st.process_frame

	sections = view.get("sections")
	if sections == null or not is_instance_valid(sections) or not (sections is VBoxContainer):
		return _finish(Result.failure("Sections 容器缺失（peek 后）"), view, engine)
	if sections.get_child_count() < 2:
		return _finish(Result.failure("玩家区块数量不足（peek 后），实际: %d" % sections.get_child_count()), view, engine)
	player1_section = sections.get_child(1)
	if player1_section == null or not is_instance_valid(player1_section):
		return _finish(Result.failure("玩家1 Section 节点缺失（peek 后）"), view, engine)

	var revealed_selection: Node = player1_section.find_child("SelectionLabel", true, false)
	if not (revealed_selection is Label):
		return _finish(Result.failure("玩家1 SelectionLabel 节点缺失（peek 后）"), view, engine)
	if str((revealed_selection as Label).text).find("储备卡 3") < 0:
		return _finish(Result.failure("获得能力后应看到玩家1 的已选项，实际: %s" % str((revealed_selection as Label).text)), view, engine)

	cards_row = player1_section.find_child("CardsRow", true, false)
	if cards_row == null or not is_instance_valid(cards_row):
		return _finish(Result.failure("玩家1 CardsRow 节点缺失（peek 后）"), view, engine)
	if cards_row.get_child_count() != 1:
		return _finish(Result.failure("peek 后面板应仅展示每位玩家已选储备卡，实际卡片数: %d" % cards_row.get_child_count()), view, engine)
	var card2 = cards_row.get_child(0)
	if card2 == null or not is_instance_valid(card2):
		return _finish(Result.failure("玩家1 已选卡节点缺失（peek 后）"), view, engine)
	var visible_title: Node = card2.find_child("TitleLabel", true, false)
	if not (visible_title is Label):
		return _finish(Result.failure("玩家1 已选卡标题节点缺失（peek 后）"), view, engine)
	if str((visible_title as Label).text).find("类型") >= 0:
		return _finish(Result.failure("已选卡标题不应显示类型信息，实际: %s" % str((visible_title as Label).text)), view, engine)

	return _finish(Result.success({}), view, engine)

static func _finish(result: Result, view, engine) -> Result:
	if view != null and is_instance_valid(view) and view is Node:
		(view as Node).free()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
