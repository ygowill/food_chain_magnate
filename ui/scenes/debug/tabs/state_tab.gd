# 状态标签页
# 显示游戏当前的完整状态信息
extends MarginContainer

var _registry: DebugCommandRegistry = null

@onready var state_content: VBoxContainer = $ScrollContainer/StateContent

# 可折叠区域
var _sections: Dictionary = {}

func init(registry: DebugCommandRegistry) -> void:
	_registry = registry

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if not is_instance_valid(state_content):
		return

	# 清空现有内容
	for child in state_content.get_children():
		child.queue_free()

	# 创建各个区域
	_create_section("basic", "基础信息")
	_create_section("bank", "银行状态")
	_create_section("players", "玩家状态")
	_create_section("map", "地图状态")
	_create_section("marketing", "营销实例")
	_create_section("round", "回合状态")

func _create_section(id: String, title: String) -> void:
	var section := VBoxContainer.new()
	section.name = id + "_section"

	# 标题按钮（可折叠）
	var header := Button.new()
	header.text = "▼ " + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.pressed.connect(_on_section_toggle.bind(id))
	section.add_child(header)

	# 内容区域
	var content := VBoxContainer.new()
	content.name = id + "_content"
	section.add_child(content)

	state_content.add_child(section)
	_sections[id] = {
		"header": header,
		"content": content,
		"expanded": true
	}

func _on_section_toggle(id: String) -> void:
	if not _sections.has(id):
		return

	var section: Dictionary = _sections[id]
	section["expanded"] = not section["expanded"]

	var header: Button = section["header"]
	var content: VBoxContainer = section["content"]

	if section["expanded"]:
		header.text = header.text.replace("▶", "▼")
		content.show()
	else:
		header.text = header.text.replace("▼", "▶")
		content.hide()

func refresh() -> void:
	if _registry == null:
		return

	var engine := _registry.get_game_engine()
	if engine == null:
		return

	var state := engine.get_state()
	if state == null:
		return

	_update_basic_section(state, engine)
	_update_bank_section(state)
	_update_players_section(state)
	_update_map_section(state)
	_update_marketing_section(state)
	_update_round_section(state)

func _update_basic_section(state: GameState, engine: GameEngine) -> void:
	if not _sections.has("basic"):
		return

	var content: VBoxContainer = _sections["basic"]["content"]
	_clear_content(content)

	_add_label(content, "回合: %d" % state.round_number)
	_add_label(content, "阶段: %s" % state.phase)
	_add_label(content, "子阶段: %s" % state.sub_phase)
	_add_label(content, "当前玩家: %d" % state.get_current_player_id())
	_add_label(content, "命令数: %d" % engine.get_command_history().size())
	_add_label(content, "哈希: %s" % state.compute_hash().substr(0, 16))

func _update_bank_section(state: GameState) -> void:
	if not _sections.has("bank"):
		return

	var content: VBoxContainer = _sections["bank"]["content"]
	_clear_content(content)

	var bank: Dictionary = state.bank
	_add_label(content, "总额: $%d" % int(bank.get("total", 0)))
	_add_label(content, "已注入: $%d" % int(bank.get("reserve_added_total", 0)))
	_add_label(content, "已移除: $%d" % int(bank.get("removed_total", 0)))

	var denominations = bank.get("denominations", {})
	if denominations is Dictionary and not denominations.is_empty():
		_add_label(content, "面额:")
		for denom in denominations.keys():
			_add_label(content, "  $%s: %d 张" % [str(denom), int(denominations[denom])], true)

func _update_players_section(state: GameState) -> void:
	if not _sections.has("players"):
		return

	var content: VBoxContainer = _sections["players"]["content"]
	_clear_content(content)

	for i in range(state.players.size()):
		var player: Dictionary = state.players[i]
		var cash: int = int(player.get("cash", 0))
		var employees = player.get("employees", [])
		var employee_count: int = employees.size() if employees is Array else 0

		var player_btn := Button.new()
		player_btn.text = "▶ 玩家 %d: $%d, 员工数: %d" % [i, cash, employee_count]
		player_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		player_btn.flat = true
		player_btn.pressed.connect(_on_player_expand.bind(i, player_btn, content))
		content.add_child(player_btn)

func _on_player_expand(player_id: int, button: Button, parent: VBoxContainer) -> void:
	# 简单实现：切换展开状态
	if button.text.begins_with("▶"):
		button.text = button.text.replace("▶", "▼")
		# 可以在这里添加详细信息
	else:
		button.text = button.text.replace("▼", "▶")

func _update_map_section(state: GameState) -> void:
	if not _sections.has("map"):
		return

	var content: VBoxContainer = _sections["map"]["content"]
	_clear_content(content)

	var map_data = state.map
	if not (map_data is Dictionary):
		_add_label(content, "地图数据无效")
		return

	var buildings = map_data.get("buildings", [])
	var building_count: int = buildings.size() if buildings is Array else 0
	_add_label(content, "建筑数: %d" % building_count)

	if buildings is Array:
		for b in buildings:
			if b is Dictionary:
				var pos = b.get("position", {})
				var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
				var type_str := str(b.get("type", "?"))
				var owner_id = b.get("owner_id", -1)
				_add_label(content, "  %s @ %s (玩家 %s)" % [type_str, pos_str, str(owner_id)], true)

func _update_marketing_section(state: GameState) -> void:
	if not _sections.has("marketing"):
		return

	var content: VBoxContainer = _sections["marketing"]["content"]
	_clear_content(content)

	var instances = state.marketing_instances
	if not (instances is Array):
		_add_label(content, "营销数据无效")
		return

	_add_label(content, "数量: %d" % instances.size())

	for inst in instances:
		if inst is Dictionary:
			var type_str := str(inst.get("type", "?"))
			var owner := int(inst.get("owner_id", -1))
			var pos = inst.get("position", {})
			var pos_str := "(%d,%d)" % [int(pos.get("x", 0)), int(pos.get("y", 0))] if pos is Dictionary else "?"
			var range_val := int(inst.get("range", 0))
			_add_label(content, "  %s @ %s (玩家 %d, 范围 %d)" % [type_str, pos_str, owner, range_val], true)

func _update_round_section(state: GameState) -> void:
	if not _sections.has("round"):
		return

	var content: VBoxContainer = _sections["round"]["content"]
	_clear_content(content)

	var round_state = state.round_state
	if not (round_state is Dictionary):
		_add_label(content, "回合状态无效")
		return

	for key in round_state.keys():
		_add_label(content, "%s: %s" % [str(key), str(round_state[key])])

func _clear_content(content: VBoxContainer) -> void:
	for child in content.get_children():
		child.queue_free()

func _add_label(parent: VBoxContainer, text: String, indent: bool = false) -> void:
	var label := Label.new()
	label.text = ("  " if indent else "") + text
	parent.add_child(label)
