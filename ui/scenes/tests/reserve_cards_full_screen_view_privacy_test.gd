class_name ReserveCardsFullScreenViewPrivacyTest
extends RefCounted

const ViewScene: PackedScene = preload("res://ui/components/reserve_cards/reserve_cards_full_screen_view.tscn")
const FIRST_HAVE_20_SAVE_PATH := "res://testdata/saves/manual_cases/milestones/first_have_20.json"

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
	_apply_full_rect_for_test(view as Control)
	(view as Control).visible = true
	await st.process_frame

	if not view.has_method("open_with_state"):
		return _finish(Result.failure("ReserveCardsFullScreenView 缺少 open_with_state"), view, engine)
	if view.has_method("set_viewer_player_id_override"):
		view.call("set_viewer_player_id_override", 0)

	view.call("open_with_state", state, -1)
	await st.process_frame

	var sections = view.get("sections")
	if sections == null or not is_instance_valid(sections) or not (sections is Container):
		return _finish(Result.failure("Sections 容器缺失"), view, engine)
	if sections.get_child_count() < 2:
		return _finish(Result.failure("玩家区块数量不足，实际: %d" % sections.get_child_count()), view, engine)
	var player1_section = sections.get_child(1)
	if player1_section == null or not is_instance_valid(player1_section):
		return _finish(Result.failure("玩家1 Section 节点缺失"), view, engine)

	var cards_row = player1_section.find_child("CardsVBox", true, false)
	if cards_row == null or not is_instance_valid(cards_row):
		return _finish(Result.failure("玩家1 CardsVBox 节点缺失"), view, engine)
	if cards_row.get_child_count() != 1:
		return _finish(Result.failure("面板应仅展示每位玩家已选储备卡，实际卡片数: %d" % cards_row.get_child_count()), view, engine)
	var card0 = cards_row.get_child(0)
	if card0 == null or not is_instance_valid(card0):
		return _finish(Result.failure("玩家1 已选卡节点缺失"), view, engine)
	var hidden_title: Node = card0.find_child("TitleLabel", true, false)
	if not (hidden_title is Label):
		return _finish(Result.failure("玩家1 已选卡标题节点缺失"), view, engine)
	if str((hidden_title as Label).text) != "?":
		return _finish(Result.failure("未获得能力时，其他玩家已选卡应隐藏，实际: %s" % str((hidden_title as Label).text)), view, engine)
	var hidden_desc: Node = card0.find_child("DescLabel", true, false)
	if not (hidden_desc is Label):
		return _finish(Result.failure("玩家1 已选卡描述节点缺失"), view, engine)
	if str((hidden_desc as Label).text).strip_edges() != "":
		return _finish(Result.failure("未获得能力时，其他玩家已选卡描述应隐藏，实际: %s" % str((hidden_desc as Label).text)), view, engine)
	if card0.find_child("FooterRow", true, false) != null or card0.find_child("FooterLabel", true, false) != null:
		return _finish(Result.failure("储备卡总览不应在卡图下方显示状态尾注"), view, engine)
	var hidden_image: Node = card0.find_child("CardImage", true, false)
	if hidden_image != null:
		return _finish(Result.failure("未获得能力时，其他玩家已选卡不应暴露卡图节点"), view, engine)
	var hidden_art: Node = card0.find_child("HiddenCardArt", true, false)
	if not (hidden_art is PanelContainer):
		return _finish(Result.failure("未获得能力时，其他玩家已选卡应展示黑底卡背"), view, engine)
	if (hidden_art as Control).custom_minimum_size != Vector2(180, 280):
		return _finish(Result.failure("隐藏卡背尺寸应与卡图轮廓一致，实际: %s" % str((hidden_art as Control).custom_minimum_size)), view, engine)
	var hidden_style := (hidden_art as PanelContainer).get_theme_stylebox("panel")
	if not (hidden_style is StyleBoxFlat):
		return _finish(Result.failure("隐藏卡背应使用黑底 StyleBoxFlat"), view, engine)
	var bg := (hidden_style as StyleBoxFlat).bg_color
	if bg.r > 0.08 or bg.g > 0.08 or bg.b > 0.08:
		return _finish(Result.failure("隐藏卡背背景应为黑色，实际: %s" % str(bg)), view, engine)
	var hidden_question: Node = card0.find_child("HiddenQuestionLabel", true, false)
	if not (hidden_question is Label):
		return _finish(Result.failure("隐藏卡背应展示问号标签"), view, engine)
	if str((hidden_question as Label).text) != "?":
		return _finish(Result.failure("隐藏卡背问号文案错误，实际: %s" % str((hidden_question as Label).text)), view, engine)
	var question_color := (hidden_question as Label).get_theme_color("font_color")
	if question_color.r < 0.9 or question_color.g < 0.9 or question_color.b < 0.9:
		return _finish(Result.failure("隐藏卡背问号应为白色，实际: %s" % str(question_color)), view, engine)
	var hidden_rect_r := _assert_art_rect_size(hidden_art as Control, "隐藏卡背")
	if not hidden_rect_r.ok:
		return _finish(hidden_rect_r, view, engine)

	state.players[0]["can_peek_all_reserve_cards"] = true
	view.call("open_with_state", state, 0)
	await st.process_frame

	sections = view.get("sections")
	if sections == null or not is_instance_valid(sections) or not (sections is Container):
		return _finish(Result.failure("Sections 容器缺失（peek 后）"), view, engine)
	if sections.get_child_count() < 2:
		return _finish(Result.failure("玩家区块数量不足（peek 后），实际: %d" % sections.get_child_count()), view, engine)
	player1_section = sections.get_child(1)
	if player1_section == null or not is_instance_valid(player1_section):
		return _finish(Result.failure("玩家1 Section 节点缺失（peek 后）"), view, engine)

	cards_row = player1_section.find_child("CardsVBox", true, false)
	if cards_row == null or not is_instance_valid(cards_row):
		return _finish(Result.failure("玩家1 CardsVBox 节点缺失（peek 后）"), view, engine)
	if cards_row.get_child_count() != 1:
		return _finish(Result.failure("peek 后面板应仅展示每位玩家已选储备卡，实际卡片数: %d" % cards_row.get_child_count()), view, engine)
	var card2 = cards_row.get_child(0)
	if card2 == null or not is_instance_valid(card2):
		return _finish(Result.failure("玩家1 已选卡节点缺失（peek 后）"), view, engine)
	var visible_title: Node = card2.find_child("TitleLabel", true, false)
	if not (visible_title is Label):
		return _finish(Result.failure("玩家1 已选卡标题节点缺失（peek 后）"), view, engine)
	if str((visible_title as Label).text) == "?":
		return _finish(Result.failure("获得能力后不应继续隐藏玩家1 的已选卡标题"), view, engine)
	if str((visible_title as Label).text).find("类型") >= 0:
		return _finish(Result.failure("已选卡标题不应显示类型信息，实际: %s" % str((visible_title as Label).text)), view, engine)
	var visible_desc: Node = card2.find_child("DescLabel", true, false)
	if not (visible_desc is Label):
		return _finish(Result.failure("玩家1 已选卡描述节点缺失（peek 后）"), view, engine)
	if str((visible_desc as Label).text).strip_edges() == "":
		return _finish(Result.failure("获得能力后应看到玩家1 已选卡的详情，实际: %s" % str((visible_desc as Label).text)), view, engine)
	if card2.find_child("FooterRow", true, false) != null or card2.find_child("FooterLabel", true, false) != null:
		return _finish(Result.failure("获得能力后也不应在卡图下方显示已选择尾注"), view, engine)
	var visible_image: Node = card2.find_child("CardImage", true, false)
	if not (visible_image is TextureRect):
		return _finish(Result.failure("获得能力后应展示玩家1 已选卡卡图"), view, engine)
	if (visible_image as TextureRect).texture == null:
		return _finish(Result.failure("获得能力后玩家1 已选卡卡图纹理为空"), view, engine)
	var visible_rect_r := _assert_art_rect_size(visible_image as Control, "可见卡图")
	if not visible_rect_r.ok:
		return _finish(visible_rect_r, view, engine)

	var manual_r: Result = await _validate_first_have_20_manual_save_view(st, view)
	if not manual_r.ok:
		return _finish(manual_r, view, engine)

	return _finish(Result.success({}), view, engine)

static func _validate_first_have_20_manual_save_view(st: SceneTree, view) -> Result:
	var manual_engine := GameEngine.new()
	var load_r := manual_engine.load_from_file(ProjectSettings.globalize_path(FIRST_HAVE_20_SAVE_PATH))
	if not load_r.ok:
		return _finish(Result.failure("first_have_20 手工存档加载失败: %s" % load_r.error), null, manual_engine)
	var state := manual_engine.get_state()
	if state == null:
		return _finish(Result.failure("first_have_20 手工存档 state 为空"), null, manual_engine)
	if view.has_method("set_viewer_player_id_override"):
		view.call("set_viewer_player_id_override", 0)
	view.call("open_with_state", state, 0)
	await st.process_frame

	var sections = view.get("sections")
	if sections == null or not is_instance_valid(sections) or not (sections is Container):
		return _finish(Result.failure("first_have_20 Sections 容器缺失"), null, manual_engine)
	if sections.get_child_count() != state.players.size():
		return _finish(Result.failure("first_have_20 玩家区块数量错误，实际: %d" % sections.get_child_count()), null, manual_engine)
	for i in range(sections.get_child_count()):
		var section = sections.get_child(i)
		if section == null or not is_instance_valid(section):
			return _finish(Result.failure("first_have_20 Section %d 缺失" % i), null, manual_engine)
		var cards_row = section.find_child("CardsVBox", true, false)
		if cards_row == null or not is_instance_valid(cards_row):
			return _finish(Result.failure("first_have_20 Section %d CardsVBox 缺失" % i), null, manual_engine)
		if cards_row.get_child_count() < 1:
			return _finish(Result.failure("first_have_20 Section %d 未展示储备卡" % i), null, manual_engine)
		var card = cards_row.get_child(0)
		var image: Node = card.find_child("CardImage", true, false)
		if not (image is TextureRect):
			return _finish(Result.failure("first_have_20 Section %d 应展示储备卡卡图" % i), null, manual_engine)
		if (image as TextureRect).texture == null:
			return _finish(Result.failure("first_have_20 Section %d 储备卡卡图纹理为空" % i), null, manual_engine)
		var layout_r := _assert_card_art_layout(view, image as TextureRect, i)
		if not layout_r.ok:
			return _finish(layout_r, null, manual_engine)

	return _finish(Result.success({}), null, manual_engine)

static func _apply_full_rect_for_test(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.position = Vector2.ZERO

static func _assert_card_art_layout(view, image: TextureRect, section_index: int) -> Result:
	var panel = view.get("panel_container")
	if not (panel is Control):
		return Result.failure("first_have_20 面板容器缺失")
	if (panel as Control).custom_minimum_size.y < 420.0:
		return Result.failure("first_have_20 面板最小高度不足，实际: %s" % str((panel as Control).custom_minimum_size))

	var scroll = view.get("scroll_container")
	if not (scroll is Control):
		return Result.failure("first_have_20 ScrollContainer 缺失")
	if (scroll as Control).custom_minimum_size.y < 300.0:
		return Result.failure("first_have_20 ScrollContainer 最小高度不足，实际: %s" % str((scroll as Control).custom_minimum_size))
	if (scroll as Control).size.y < 240.0:
		return Result.failure("first_have_20 ScrollContainer 实际高度过小，实际: %s" % str((scroll as Control).size))

	if not image.is_visible_in_tree():
		return Result.failure("first_have_20 Section %d 储备卡卡图不在可见树中" % section_index)
	var image_rect := image.get_global_rect()
	if image_rect.size.x < 120.0 or image_rect.size.y < 180.0:
		return Result.failure("first_have_20 Section %d 储备卡卡图实际尺寸过小，实际: %s" % [section_index, str(image_rect.size)])
	var exact_r := _assert_art_rect_size(image, "first_have_20 Section %d 储备卡卡图" % section_index)
	if not exact_r.ok:
		return exact_r
	return Result.success({})

static func _assert_art_rect_size(ctrl: Control, label: String) -> Result:
	if ctrl == null or not is_instance_valid(ctrl):
		return Result.failure("%s 控件缺失" % label)
	var rect := ctrl.get_global_rect()
	var expected := Vector2(180, 280)
	if absf(rect.size.x - expected.x) > 1.0 or absf(rect.size.y - expected.y) > 1.0:
		return Result.failure("%s 实际轮廓尺寸不一致，实际: %s，期望: %s" % [label, str(rect.size), str(expected)])
	return Result.success({})

static func _finish(result: Result, view, engine) -> Result:
	if view != null and is_instance_valid(view) and view is Node:
		(view as Node).free()
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	return result
