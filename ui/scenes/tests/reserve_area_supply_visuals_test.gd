class_name ReserveAreaSupplyVisualsTest
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const TokensClass = preload("res://ui/components/reserve_area/reserve_area_full_screen_view_tokens.gd")
const ReserveAreaViewClass = preload("res://ui/components/reserve_area/reserve_area_full_screen_view.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map_canvas_drawer_structures_pass.gd")

static func run() -> Result:
	var modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"coffee",
	]

	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345, modules)
	if not init_r.ok:
		return Result.failure("初始化失败: %s" % init_r.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var skin_r := MapSkinBuilderClass.build_for_modules("res://modules", modules, 40)
	if not skin_r.ok:
		return Result.failure("MapSkinBuilder.build_for_modules 失败: %s" % skin_r.error).with_warnings(skin_r.warnings)
	var skin = skin_r.value
	if skin == null:
		return Result.failure("MapSkinBuilder 返回空 skin").with_warnings(skin_r.warnings)

	var placeholder: Texture2D = skin.get_piece_texture("__missing__")
	var coffee_piece_tex: Texture2D = skin.get_piece_texture("coffee_shop")
	if coffee_piece_tex == null or coffee_piece_tex == placeholder:
		return Result.failure("coffee_shop 贴图缺失或仍为占位（应来自 coffee 模组视觉资源）").with_warnings(skin_r.warnings)

	var logo_ids_val = skin.get_restaurant_logo_piece_ids() if skin.has_method("get_restaurant_logo_piece_ids") else null
	if not (logo_ids_val is Array) or (logo_ids_val as Array).is_empty():
		return Result.failure("缺少 restaurant_logo_piece_ids（无法推导 coffee_shop 的玩家 Logo 变体）").with_warnings(skin_r.warnings)
	var logo_ids: Array = logo_ids_val

	var p0_val = state.players[0]
	if not (p0_val is Dictionary):
		return Result.failure("state.players[0] 类型错误")
	var p0: Dictionary = p0_val
	var logo_id := int(p0.get("restaurant_logo_id", -1))
	if logo_id < 0 or logo_id >= logo_ids.size():
		logo_id = 0

	var token := TokensClass.PieceFootprintToken.new()
	token.piece_id = "coffee_shop"
	token.owner_logo_id = logo_id
	token.set_skin(skin)
	var resolved_tex: Texture2D = token._resolve_texture_for_draw()
	if resolved_tex == null:
		return Result.failure("coffee_shop token 未解析到贴图")

	var base_key := str(logo_ids[logo_id]).strip_edges()
	if base_key.is_empty():
		return Result.failure("restaurant_logo_piece_ids[%d] 为空" % logo_id)
	var expected_key := base_key
	var var_key := "%s_coffee" % base_key
	var piece_textures_val = skin.get("piece_textures")
	if piece_textures_val is Dictionary and Dictionary(piece_textures_val).has(var_key):
		expected_key = var_key
	var expected_tex: Texture2D = skin.get_piece_texture(expected_key)
	if resolved_tex != expected_tex:
		return Result.failure("coffee_shop token 应使用玩家 Logo 的 coffee 变体贴图: expected=%s" % expected_key)

	var garden_token := TokensClass.GardenExtensionToken.new()
	var garden_bg: Color = garden_token._get_garden_bg_color()
	if garden_bg != StructuresPassClass.GARDEN_BG_COLOR:
		return Result.failure("供应堆花园底色应与地图 house_with_garden 花园底色一致: got=%s expect=%s" % [str(garden_bg), str(StructuresPassClass.GARDEN_BG_COLOR)])

	var modules2: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"lobbyists",
		"rural_marketeers",
	]
	var engine2 := GameEngine.new()
	var init2_r := engine2.initialize(2, 12345, modules2)
	if not init2_r.ok:
		return Result.failure("初始化失败(lobbyists+rural_marketeers): %s" % init2_r.error)
	var state2 := engine2.get_state()
	if state2 == null:
		return Result.failure("state2 为空")
	if state2.map is Dictionary:
		state2.map["tile_supply_remaining"] = ["tile_b", "tile_z", "tile_z"]

	var skin2_r := MapSkinBuilderClass.build_for_modules("res://modules", modules2, 40)
	if not skin2_r.ok:
		return Result.failure("MapSkinBuilder.build_for_modules(lobbyists+rural_marketeers) 失败: %s" % skin2_r.error).with_warnings(skin2_r.warnings)
	var skin2 = skin2_r.value
	if skin2 == null:
		return Result.failure("MapSkinBuilder 返回空 skin2").with_warnings(skin2_r.warnings)
	var placeholder2: Texture2D = skin2.get_piece_texture("__missing__")
	for pid in ["lobbyists_road_straight", "lobbyists_park_line", "highway_offramp", "rural_billboard"]:
		var tex: Texture2D = skin2.get_piece_texture(pid)
		if tex == null or tex == placeholder2:
			return Result.failure("模块 piece 贴图缺失或仍为占位: %s" % pid).with_warnings(skin2_r.warnings)

	var view := ReserveAreaViewClass.new()
	var module_supply_counts: Dictionary = view._collect_module_supply_counts(state2, modules2)
	for key in [
		"lobbyists_road_straight_supply_remaining",
		"lobbyists_road_long_supply_remaining",
		"lobbyists_road_l_supply_remaining",
		"lobbyists_park_line_supply_remaining",
		"lobbyists_park_t_supply_remaining",
		"lobbyists_park_l_supply_remaining",
		"rural_marketeers_offramp_supply_remaining",
		"rural_billboard_supply_remaining",
	]:
		if not module_supply_counts.has(key):
			return Result.failure("模块供给应展示该条目，但缺失: %s" % key)

	var piece_ids2: Array[String] = []
	if PieceRegistry.is_loaded():
		piece_ids2 = PieceRegistry.get_all_ids()
	var offramp_piece_id := view._guess_piece_id_for_supply("rural_marketeers_offramp", modules2, piece_ids2)
	if offramp_piece_id != "highway_offramp":
		return Result.failure("rural_marketeers_offramp 应映射到 highway_offramp，实际: %s" % offramp_piece_id)

	var tile_entries: Array[Dictionary] = view._collect_module_tile_supply_entries(state2, modules2)
	var tile_counts := {}
	for e in tile_entries:
		var tid := str(e.get("tile_id", ""))
		var cnt := int(e.get("count", 0))
		if not tid.is_empty() and cnt > 0:
			tile_counts[tid] = cnt
	if int(tile_counts.get("tile_b", 0)) != 1:
		return Result.failure("地图板块供给应包含 tile_b ×1（非模块板块也应展示），实际: %s" % str(tile_counts))
	if int(tile_counts.get("tile_z", 0)) != 2:
		return Result.failure("地图板块供给应包含 tile_z ×2（模块板块），实际: %s" % str(tile_counts))

	return Result.success({
		"coffee_logo_key": expected_key,
		"garden_bg": str(garden_bg),
		"module_tile_counts": str(tile_counts),
	}).with_warnings(skin_r.warnings)
