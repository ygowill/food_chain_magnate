# 清理阶段：冰箱保留选择遮罩面板
class_name FridgeKeepModal
extends "res://ui/components/modal_panel/modal_panel_base.gd"

const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/InfoLabel
@onready var summary_label: Label = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/SummaryLabel
@onready var items_vbox: VBoxContainer = $Panel/MarginContainer/VBoxContainer/ContentHost/VBoxContainer/ItemsVBox

var _fridge_cap: int = 0
var _spinners_by_product: Dictionary = {}  # product_id -> SpinBox

func _ready() -> void:
	super._ready()

	set_title_text("冰箱保留选择")
	set_confirm_text("确认保留")
	set_cancel_text("")

	# 强制选择：隐藏取消按钮，并忽略 ESC（否则会反复弹窗，体验更差）
	if is_instance_valid(cancel_button):
		cancel_button.visible = false

	if is_instance_valid(hint_label):
		hint_label.text = "请为各商品选择要保留的数量（允许保留少于容量）。"

func setup(state: GameState, current_player_id: int) -> void:
	_spinners_by_product.clear()
	_fridge_cap = 0

	_clear_items()
	set_confirm_enabled(false)

	if state == null or current_player_id < 0 or current_player_id >= state.players.size():
		_set_labels_invalid("状态无效")
		return

	if not ProductRegistryClass.is_loaded():
		_set_labels_invalid("ProductRegistry 未初始化")
		return

	var p_val = state.players[current_player_id]
	if not (p_val is Dictionary):
		_set_labels_invalid("玩家数据无效")
		return
	var player: Dictionary = p_val

	var ms_val = player.get("milestones", null)
	if not (ms_val is Array):
		_set_labels_invalid("玩家里程碑数据无效")
		return

	var fridge_r := _get_fridge_capacity_from_milestones(ms_val)
	if not fridge_r.ok:
		_set_labels_invalid(fridge_r.error)
		return
	var fridge: Dictionary = fridge_r.value
	_fridge_cap = int(fridge.get("capacity", 0))

	var inv_val = player.get("inventory", null)
	if not (inv_val is Dictionary):
		_set_labels_invalid("库存数据无效")
		return
	var inventory: Dictionary = inv_val

	var items: Array[Dictionary] = []
	var total := 0
	for product_key in inventory.keys():
		var pid: String = str(product_key)
		if pid.is_empty():
			continue
		if not _is_food_or_drink(pid):
			continue
		var count: int = maxi(0, int(inventory.get(pid, 0)))
		if count <= 0:
			continue
		items.append({
			"id": pid,
			"count": count,
		})
		total += count

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	var name := Globals.get_player_name(current_player_id) if Globals != null else ("玩家%d" % (current_player_id + 1))
	if is_instance_valid(info_label):
		info_label.text = "当前玩家：%s | 冰箱容量：%d | 当前总量：%d" % [name, _fridge_cap, total]

	# 默认策略：按产品 id 顺序尽量填满 cap（玩家可再调整）
	var remaining := maxi(0, _fridge_cap)
	for item_val in items:
		var pid: String = str(item_val.get("id", ""))
		var count: int = int(item_val.get("count", 0))
		var keep_default: int = mini(count, remaining)
		remaining -= keep_default
		_add_item_row(pid, count, keep_default)

	_update_summary()

func _on_confirm_pressed() -> void:
	var keep: Dictionary = {}
	for pid in _spinners_by_product.keys():
		var sb_val = _spinners_by_product.get(pid, null)
		if not is_instance_valid(sb_val) or not (sb_val is SpinBox):
			continue
		var sb: SpinBox = sb_val
		var v := int(sb.value)
		if v > 0:
			keep[str(pid)] = v

	# 点击确认后先禁用按钮，避免重复触发；后续由 GamePanelController 根据 state 决定是否继续弹下一位。
	set_confirm_enabled(false)
	completed.emit({
		"keep": keep,
		"command_id": "choose_fridge_keep",
		"command_args": {"keep": keep},
	})

static func _get_fridge_capacity_from_milestones(milestones: Array) -> Result:
	var best_read := MilestoneEffectQueriesClass.max_non_negative_int_value(
		milestones,
		"gain_fridge",
		"FridgeKeepModal: ",
		"player.milestones"
	)
	if not best_read.ok:
		return best_read
	if not (best_read.value is Dictionary):
		return Result.failure("FridgeKeepModal: 内部错误（max_non_negative_int_value 返回值类型错误）")
	var best: Dictionary = best_read.value
	return Result.success({
		"has_fridge": bool(best.get("found", false)),
		"capacity": int(best.get("value", 0)),
	})

func _on_cancel_pressed() -> void:
	# 强制弹窗：不允许取消
	return

func _add_item_row(product_id: String, available: int, keep_default: int) -> void:
	if not is_instance_valid(items_vbox):
		return

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = _get_product_display_name(product_id)
	row.add_child(name_label)

	var count_label := Label.new()
	count_label.custom_minimum_size.x = 120
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.text = "库存：%d" % available
	row.add_child(count_label)

	var sb := SpinBox.new()
	sb.custom_minimum_size.x = 140
	sb.min_value = 0
	sb.max_value = maxi(0, available)
	sb.step = 1
	sb.value = clampi(keep_default, 0, int(sb.max_value))
	sb.allow_greater = false
	sb.allow_lesser = false
	sb.rounded = true
	if not sb.value_changed.is_connected(_on_keep_changed):
		sb.value_changed.connect(_on_keep_changed)
	row.add_child(sb)

	_spinners_by_product[product_id] = sb
	items_vbox.add_child(row)

func _on_keep_changed(_v: float) -> void:
	_update_summary()

func _update_summary() -> void:
	var total := 0
	for sb_val in _spinners_by_product.values():
		if not is_instance_valid(sb_val) or not (sb_val is SpinBox):
			continue
		var sb: SpinBox = sb_val
		total += int(sb.value)

	var ok := total <= _fridge_cap
	if is_instance_valid(summary_label):
		if ok:
			summary_label.text = "已选择保留：%d/%d" % [total, _fridge_cap]
		else:
			summary_label.text = "已选择保留：%d/%d（超出容量）" % [total, _fridge_cap]

	set_confirm_enabled(ok)

func _clear_items() -> void:
	if not is_instance_valid(items_vbox):
		return
	for c in items_vbox.get_children():
		if is_instance_valid(c):
			c.queue_free()

func _set_labels_invalid(msg: String) -> void:
	if is_instance_valid(info_label):
		info_label.text = msg
	if is_instance_valid(summary_label):
		summary_label.text = ""

static func _is_food_or_drink(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	if not ProductRegistryClass.is_loaded():
		return false
	var def_val = ProductRegistryClass.get_def(product_id)
	if def_val == null or not (def_val is ProductDef):
		return false
	var def: ProductDef = def_val
	return def.has_tag("food") or def.has_tag("drink")

static func _get_product_display_name(product_id: String) -> String:
	if ProductRegistryClass.is_loaded():
		var def_val = ProductRegistryClass.get_def(product_id)
		if def_val is ProductDef:
			var def: ProductDef = def_val
			if not def.name.is_empty():
				return "%s（%s）" % [def.name, product_id]
	return product_id
