class_name ReserveAreaSupplyVisualsTest
extends RefCounted

const MapSkinBuilderClass = preload("res://ui/visual/map_skin_builder.gd")
const TokensClass = preload("res://ui/components/reserve_area/reserve_area_full_screen_view_tokens.gd")
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

	return Result.success({
		"coffee_logo_key": expected_key,
		"garden_bg": str(garden_bg),
	}).with_warnings(skin_r.warnings)
