# 营销板件数据对齐测试（board_number 1-16）
# 目的：防止模块内容 JSON 命名/类型/尺寸错位导致 UI/规则层出现“板件不符合真实数据”。
class_name MarketingBoardDataTest
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	MarketingRegistryClass.reset()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	if not MarketingRegistryClass.is_loaded():
		return Result.failure("MarketingRegistry 未加载")

	var expected: Array[Dictionary] = [
		{"bn": 1, "id": "radio_1", "type": "radio", "size": Vector2i(1, 1)},
		{"bn": 2, "id": "radio_2", "type": "radio", "size": Vector2i(1, 1)},
		{"bn": 3, "id": "radio_3", "type": "radio", "size": Vector2i(1, 1)},
		{"bn": 4, "id": "airplane_4", "type": "airplane", "size": Vector2i(1, 2)},
		{"bn": 5, "id": "airplane_5", "type": "airplane", "size": Vector2i(3, 2)},
		{"bn": 6, "id": "airplane_6", "type": "airplane", "size": Vector2i(5, 2)},
		{"bn": 7, "id": "mailbox_7", "type": "mailbox", "size": Vector2i(2, 2)},
		{"bn": 8, "id": "mailbox_8", "type": "mailbox", "size": Vector2i(2, 2)},
		{"bn": 9, "id": "mailbox_9", "type": "mailbox", "size": Vector2i(1, 1)},
		{"bn": 10, "id": "mailbox_10", "type": "mailbox", "size": Vector2i(1, 1)},
		{"bn": 11, "id": "billboard_11", "type": "billboard", "size": Vector2i(3, 2)},
		{"bn": 12, "id": "billboard_12", "type": "billboard", "size": Vector2i(2, 2)},
		{"bn": 13, "id": "billboard_13", "type": "billboard", "size": Vector2i(3, 1)},
		{"bn": 14, "id": "billboard_14", "type": "billboard", "size": Vector2i(2, 1)},
		{"bn": 15, "id": "billboard_15", "type": "billboard", "size": Vector2i(1, 1)},
		{"bn": 16, "id": "billboard_16", "type": "billboard", "size": Vector2i(1, 1)},
	]

	for item in expected:
		var bn: int = int(item.get("bn", 0))
		var def_val = MarketingRegistryClass.get_def(bn)
		if def_val == null or not (def_val is MarketingDef):
			return Result.failure("MarketingDef #%d 未加载或类型错误" % bn)
		var def: MarketingDef = def_val

		var want_id := str(item.get("id", ""))
		var want_type := str(item.get("type", ""))
		var want_size: Vector2i = item.get("size", Vector2i.ZERO)

		if def.id != want_id:
			return Result.failure("MarketingDef #%d id 不匹配: %s != %s" % [bn, def.id, want_id])
		if def.type != want_type:
			return Result.failure("MarketingDef #%d type 不匹配: %s != %s" % [bn, def.type, want_type])
		if def.footprint_size != want_size:
			return Result.failure("MarketingDef #%d footprint_size 不匹配: %s != %s" % [bn, str(def.footprint_size), str(want_size)])

	return Result.success()

