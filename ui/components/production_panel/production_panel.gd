# 生产面板组件
# 对齐 gameplay：`produce_food` 仅需 `employee_type`；`procure_drinks`：`errand_boy` 需 `drink_type`，其它员工需 `route/selected_sources`（由上层组装下发）
class_name ProductionPanel
extends "res://ui/components/common/right_panel_embeddable_panel.gd"

signal production_requested(employee_type: String, production_type: String, staff_id: int)
signal cancelled()
signal producer_changed(employee_type: String, production_type: String, staff_id: int)
signal drinks_clear_requested()
signal drinks_undo_requested()
signal drinks_restaurant_changed(restaurant_id: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var mode_label: Label = $MarginContainer/VBoxContainer/ModeLabel
@onready var products_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ProductsContainer
@onready var summary_label: Label = $MarginContainer/VBoxContainer/SummaryLabel
@onready var confirm_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/CancelButton
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const ModulesBaseDirClass = preload("res://ui/utils/modules_base_dir.gd")
const UiRebuildHelpersClass = preload("res://ui/utils/rebuild_helpers.gd")
const EmployeePickerClass = preload("res://ui/components/employee_picker/employee_picker.gd")
const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const FoodControllerClass = preload("res://ui/components/production_panel/production_panel_food_controller.gd")
const DrinksControllerClass = preload("res://ui/components/production_panel/production_panel_drinks_controller.gd")

var _production_type: String = "food"  # food | drinks
var _available_producers: Array[String] = []
var _producer_items: Array[Dictionary] = []
var _producer_by_key: Dictionary = {}
var _current_inventory: Dictionary = {}

var _employee_picker = null
var _info_label: Label = null
var _selected_employee_type: String = ""
var _selected_employee_key: String = ""
var _selected_staff_id: int = -1
var _has_any_enabled_employee: bool = false

var _usage_token: String = ""
var _used_employee_keys_by_mode: Dictionary = {
	"food": {},
	"drinks": {},
}

var _food_type_container: HFlowContainer = null
var _food_type_items: Dictionary = {} # product_id -> token node
var _food_type_label: Label = null
var _available_food_types: Array[String] = []
var _selected_food_type: String = ""

var _drink_type_label: Label = null
var _drink_type_container: HFlowContainer = null
var _drink_type_items: Dictionary = {} # product_id -> token node
var _drinks_restaurant_option: OptionButton = null
var _drinks_restaurant_label: Label = null
var _drinks_selection_label: Label = null
var _drinks_error_label: Label = null
var _drinks_undo_btn: Button = null
var _drinks_clear_btn: Button = null

var _available_drink_types: Array[String] = []
var _selected_drink_type: String = ""
var _drinks_selected_sources_count: int = 0
var _drinks_confirm_ready: bool = false
var _drinks_available_restaurants: Array[String] = []
var _drinks_restaurant_label_by_id: Dictionary = {} # restaurant_id -> display label
var _drinks_selected_restaurant_id: String = ""
var _drinks_restaurant_require_selection: bool = false
var _drinks_restaurant_show_selector: bool = false
var _drinks_hover_preview_text: String = ""
var _suppress_drinks_restaurant_signal: bool = false

var _skin = null
var _food_controller = null
var _drinks_controller = null

func _get_confirm_button() -> Button:
	return confirm_btn

func _get_cancel_button() -> Button:
	return cancel_btn

func _on_panel_ready() -> void:
	UiStylesClass.apply_button_primary(confirm_btn)
	UiStylesClass.apply_button_secondary(cancel_btn)
	_rebuild()
	_apply_embedding_layout()

func _apply_embedding(embedded: bool) -> void:
	super._apply_embedding(embedded)
	_apply_embedding_layout()

func set_production_type(production_type: String) -> void:
	_production_type = production_type
	_rebuild()

func set_usage_token(token: String) -> void:
	# 用于跨关闭/重开面板保持“本次用了哪张卡”的禁用态；当 token 变化（换玩家/换回合/换子阶段）时清空。
	var t := str(token).strip_edges()
	if t == _usage_token:
		return
	_usage_token = t
	_used_employee_keys_by_mode["food"] = {}
	_used_employee_keys_by_mode["drinks"] = {}
	_selected_employee_type = ""
	_selected_employee_key = ""
	_selected_staff_id = -1

func set_used_employee_counts(used_counts_by_employee_id: Dictionary) -> void:
	# 用于“载入/回放/时间线回退”等场景：根据 GameState.round_state 中的计数来同步禁用态，
	# 避免面板内缓存的 _used_employee_keys_by_mode 残留导致 UI 灰显不一致。
	var used_set: Dictionary = {}
	for k in used_counts_by_employee_id.keys():
		var emp_id := str(k).strip_edges()
		if emp_id.is_empty():
			continue
		var v = used_counts_by_employee_id.get(k, 0)
		var used := 0
		if v is int:
			used = int(v)
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				used = int(f)
		used = maxi(0, used)
		for idx in range(1, used + 1):
			used_set["%s#%d" % [emp_id, idx]] = true

	_used_employee_keys_by_mode[_production_type] = used_set

	_rebuild_employee_options()
	if _production_type == "food":
		_ensure_food_controller()
		if _food_controller != null and is_instance_valid(_food_controller):
			_food_controller.rebuild_food_type_options()

	_ensure_food_controller()
	if _food_controller != null and is_instance_valid(_food_controller):
		_food_controller.update_food_controls_visibility()

	_ensure_drinks_controller()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.update_drinks_controls_visibility()
	else:
		pass
	_update_confirm_state()
	_update_info()

func set_available_producers(producers: Array[String]) -> void:
	_producer_items.clear()
	_available_producers = producers.duplicate()
	_rebuild()

func set_producer_items(items: Array) -> void:
	_available_producers.clear()
	_producer_items.clear()
	for item_val in items:
		if not (item_val is Dictionary):
			continue
		_producer_items.append(Dictionary(item_val).duplicate(true))
	_rebuild()

func set_current_inventory(inventory: Dictionary) -> void:
	_current_inventory = inventory.duplicate()
	_update_info()

func set_available_drink_types(types: Array[String]) -> void:
	_available_drink_types.clear()
	for t in types:
		if t.is_empty():
			continue
		if _available_drink_types.has(t):
			continue
		_available_drink_types.append(t)
	_available_drink_types.sort()
	_ensure_drinks_controller()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.rebuild_drink_type_options()
	_update_confirm_state()
	_update_info()

func get_selected_drink_type() -> String:
	return _selected_drink_type

func get_selected_food_type() -> String:
	return _selected_food_type

func get_selected_staff_id() -> int:
	return _selected_staff_id

func set_drinks_procure_restaurants(restaurants: Array[Dictionary], selected_restaurant_id: String = "", require_selection: bool = false) -> void:
	var prev_selected := _drinks_selected_restaurant_id

	_drinks_available_restaurants.clear()
	_drinks_restaurant_label_by_id.clear()
	_drinks_selected_restaurant_id = ""
	_drinks_restaurant_require_selection = bool(require_selection)

	var seen := {}
	for r_val in restaurants:
		if not (r_val is Dictionary):
			continue
		var r: Dictionary = r_val
		var rid := str(r.get("id", "")).strip_edges()
		if rid.is_empty():
			continue
		if seen.has(rid):
			continue
		seen[rid] = true
		_drinks_available_restaurants.append(rid)
		var label := str(r.get("label", rid)).strip_edges()
		_drinks_restaurant_label_by_id[rid] = label if not label.is_empty() else rid
	_drinks_available_restaurants.sort()

	_drinks_restaurant_show_selector = (_drinks_available_restaurants.size() > 1) or _drinks_restaurant_require_selection

	if _drinks_restaurant_option != null:
		_suppress_drinks_restaurant_signal = true
		_drinks_restaurant_option.clear()

		if _drinks_restaurant_show_selector:
			if _drinks_restaurant_require_selection:
				_drinks_restaurant_option.add_item("请选择起点餐厅")
				_drinks_restaurant_option.set_item_metadata(0, "")

			for rid2 in _drinks_available_restaurants:
				_drinks_restaurant_option.add_item(str(_drinks_restaurant_label_by_id.get(rid2, rid2)))
				var idx := _drinks_restaurant_option.get_item_count() - 1
				_drinks_restaurant_option.set_item_metadata(idx, rid2)

			var requested := str(selected_restaurant_id).strip_edges()
			if requested.is_empty():
				requested = str(prev_selected).strip_edges()

			var select_idx := -1
			if not requested.is_empty():
				for i in range(_drinks_restaurant_option.get_item_count()):
					var meta = _drinks_restaurant_option.get_item_metadata(i)
					if str(meta).strip_edges() == requested:
						select_idx = i
						break

			if select_idx < 0:
				if _drinks_restaurant_require_selection:
					select_idx = 0
				else:
					select_idx = 0

			if select_idx >= 0 and select_idx < _drinks_restaurant_option.get_item_count():
				_drinks_restaurant_option.select(select_idx)
				# 视觉可用性：当餐厅很多时，确保下拉列表滚动到当前选中项（例如通过地图点击切换起点）。
				var popup := _drinks_restaurant_option.get_popup()
				if popup != null and is_instance_valid(popup):
					if popup.has_method("set_focused_item"):
						popup.call("set_focused_item", select_idx)
					if popup.has_method("scroll_to_item"):
						popup.call("scroll_to_item", select_idx)
				var meta2 = _drinks_restaurant_option.get_item_metadata(select_idx)
				_drinks_selected_restaurant_id = str(meta2).strip_edges()
		else:
			_drinks_selected_restaurant_id = ""

		_suppress_drinks_restaurant_signal = false

	_ensure_drinks_controller()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.update_drinks_controls_visibility()
	_update_confirm_state()
	_update_info()

func get_selected_drinks_procure_restaurant_id() -> String:
	return _drinks_selected_restaurant_id

func set_drinks_procurement_state(selected_sources_count: int, confirm_ready: bool, error_text: String = "") -> void:
	_drinks_selected_sources_count = maxi(0, selected_sources_count)
	_drinks_confirm_ready = confirm_ready
	if _drinks_error_label != null:
		_drinks_error_label.text = str(error_text).strip_edges()
		_drinks_error_label.visible = not _drinks_error_label.text.is_empty()
	_ensure_drinks_controller()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.update_drinks_selection_label()
	_update_confirm_state()
	_update_info()

func set_drinks_hover_preview_text(text: String) -> void:
	_drinks_hover_preview_text = str(text).strip_edges()
	_update_info()
	_update_confirm_state()
	_update_info()

func _rebuild() -> void:
	_update_header()
	_rebuild_content()
	_update_confirm_state()
	_update_info()

func _update_header() -> void:
	var is_drinks := _production_type == "drinks"
	if title_label != null:
		title_label.text = "采购饮料" if is_drinks else "生产食物"
	if mode_label != null:
		mode_label.text = "选择员工并执行采购（饮料需要手动选点生成路线）" if is_drinks else "选择厨师并执行生产（产品由员工卡决定）"
	if confirm_btn != null:
		confirm_btn.text = "确认采购" if is_drinks else "确认生产"

func _rebuild_content() -> void:
	if products_container == null:
		return

	UiRebuildHelpersClass.free_children(products_container)

	_employee_picker = EmployeePickerClass.new()
	_employee_picker.card_display_scale = 1.25
	_employee_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_employee_picker.add_theme_constant_override("h_separation", 10)
	_employee_picker.add_theme_constant_override("v_separation", 10)
	_employee_picker.employee_selected.connect(_on_employee_selected)
	products_container.add_child(_employee_picker)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 1))
	products_container.add_child(_info_label)

	_food_type_label = null
	_food_type_container = null
	_food_type_items.clear()
	_available_food_types.clear()
	_selected_food_type = ""

	_drink_type_label = null
	_drink_type_container = null
	_drink_type_items.clear()
	_drinks_restaurant_label = null
	_drinks_restaurant_option = null
	_drinks_selection_label = null
	_drinks_error_label = null
	_drinks_undo_btn = null
	_drinks_clear_btn = null
	_drinks_selected_sources_count = 0
	_drinks_confirm_ready = false
	_selected_drink_type = ""

	if _production_type == "food":
		_ensure_food_controller()
		if _food_controller != null and is_instance_valid(_food_controller):
			_food_controller.build_food_controls(products_container)

	if _production_type == "drinks":
		_ensure_drinks_controller()
		if _drinks_controller != null and is_instance_valid(_drinks_controller):
			_drinks_controller.build_drinks_controls(products_container)

	_ensure_food_controller()
	_ensure_drinks_controller()
	_rebuild_employee_options()
	if _food_controller != null and is_instance_valid(_food_controller):
		_food_controller.rebuild_food_type_options()
		_food_controller.update_food_controls_visibility()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.update_drinks_controls_visibility()
		_drinks_controller.update_drinks_selection_label()
	_apply_embedding_layout()

func _apply_embedding_layout() -> void:
	var embedded := is_embedded_in_right_panel()
	if scroll_container != null:
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if embedded else ScrollContainer.SCROLL_MODE_DISABLED
	if _drinks_restaurant_option != null:
		_drinks_restaurant_option.custom_minimum_size = Vector2.ZERO if embedded else Vector2(380, 0)

func _ensure_food_controller() -> void:
	if _food_controller == null or not is_instance_valid(_food_controller):
		_food_controller = FoodControllerClass.new()
	if _food_controller != null and is_instance_valid(_food_controller):
		_food_controller.setup(self)

func _ensure_drinks_controller() -> void:
	if _drinks_controller == null or not is_instance_valid(_drinks_controller):
		_drinks_controller = DrinksControllerClass.new()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.setup(self)

func _rebuild_employee_options() -> void:
	if _employee_picker == null:
		return

	var prev_type := _selected_employee_type
	var prev_staff_id := _selected_staff_id

	var items: Array[Dictionary] = []
	_producer_by_key.clear()
	_has_any_enabled_employee = false

	if not _producer_items.is_empty():
		for provider_val in _producer_items:
			if not (provider_val is Dictionary):
				continue
			var provider: Dictionary = provider_val
			var emp_id := str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
			if emp_id.is_empty():
				continue
			var staff_id := int(provider.get("staff_id", -1))
			var key := "staff:%d" % staff_id if staff_id > 0 else "%s#legacy_provider_%d" % [emp_id, items.size() + 1]
			var capacity := int(provider.get("capacity", provider.get("cap_per_instance", 0)))
			var remaining := int(provider.get("remaining", 0))
			var enabled := remaining > 0
			if enabled:
				_has_any_enabled_employee = true
			_producer_by_key[key] = provider.duplicate(true)
			items.append({
				"id": emp_id,
				"key": key,
				"employee_def": _get_employee_def_for_card(emp_id),
				"badge_text": "%d/%d" % [maxi(0, remaining), maxi(0, capacity)],
				"tag_text": "可用" if enabled else "已用",
				"enabled": enabled,
			})
	else:
		var counts: Dictionary = {}
		for v in _available_producers:
			var emp_id2 := str(v)
			if emp_id2.is_empty():
				continue
			counts[emp_id2] = int(counts.get(emp_id2, 0)) + 1

		var ids: Array[String] = []
		for k in counts.keys():
			ids.append(str(k))
		ids.sort()

		var used_set: Dictionary = {}
		if _used_employee_keys_by_mode.has(_production_type) and (_used_employee_keys_by_mode[_production_type] is Dictionary):
			used_set = _used_employee_keys_by_mode[_production_type]

		for emp_id3 in ids:
			var count: int = int(counts.get(emp_id3, 0))
			for idx in range(1, count + 1):
				var key2 := "%s#%d" % [emp_id3, idx]
				var enabled2 := not used_set.has(key2)
				if enabled2:
					_has_any_enabled_employee = true
				_producer_by_key[key2] = {
					"staff_id": -idx,
					"employee_type": emp_id3,
					"capacity": 1,
					"used": 0 if enabled2 else 1,
					"remaining": 1 if enabled2 else 0,
				}
				items.append({
					"id": emp_id3,
					"key": key2,
					"employee_def": _get_employee_def_for_card(emp_id3),
					"badge_text": "",
					"enabled": enabled2,
				})

	var selected_key := _resolve_preferred_selected_key(items)
	_employee_picker.set_items(items, selected_key)

	_refresh_selected_employee_from_picker()

	if prev_type != _selected_employee_type or prev_staff_id != _selected_staff_id:
		_selected_changed()

func _resolve_preferred_selected_key(items: Array[Dictionary]) -> String:
	if not _selected_employee_key.is_empty():
		var selected_provider: Dictionary = Dictionary(_producer_by_key.get(_selected_employee_key, {}))
		if not selected_provider.is_empty() and int(selected_provider.get("remaining", 0)) > 0:
			return _selected_employee_key

	if _selected_staff_id > 0:
		var key := "staff:%d" % _selected_staff_id
		var selected_provider2: Dictionary = Dictionary(_producer_by_key.get(key, {}))
		if not selected_provider2.is_empty() and int(selected_provider2.get("remaining", 0)) > 0:
			return key

	if not _selected_employee_type.is_empty():
		for item_val in items:
			if not (item_val is Dictionary):
				continue
			var item: Dictionary = item_val
			if str(item.get("id", "")).strip_edges() != _selected_employee_type:
				continue
			if bool(item.get("enabled", false)):
				return str(item.get("key", "")).strip_edges()

	for item_val2 in items:
		if not (item_val2 is Dictionary):
			continue
		var item2: Dictionary = item_val2
		if bool(item2.get("enabled", false)):
			return str(item2.get("key", "")).strip_edges()

	return ""

func _refresh_selected_employee_from_picker() -> void:
	_selected_employee_type = ""
	_selected_employee_key = ""
	_selected_staff_id = -1
	if _employee_picker != null and _employee_picker.has_method("get_selected_employee_id"):
		_selected_employee_type = str(_employee_picker.call("get_selected_employee_id")).strip_edges()
	if _employee_picker != null and _employee_picker.has_method("get_selected_key"):
		_selected_employee_key = str(_employee_picker.call("get_selected_key")).strip_edges()
	var provider: Dictionary = Dictionary(_producer_by_key.get(_selected_employee_key, {}))
	if not provider.is_empty():
		_selected_staff_id = int(provider.get("staff_id", -1))

func _apply_selected_employee(employee_type: String, staff_id: int = -1) -> void:
	_selected_employee_type = str(employee_type).strip_edges()
	_selected_staff_id = int(staff_id)

func _on_employee_selected(employee_type: String) -> void:
	var selected_key := ""
	if _employee_picker != null and _employee_picker.has_method("get_selected_key"):
		selected_key = str(_employee_picker.call("get_selected_key")).strip_edges()
	var provider: Dictionary = Dictionary(_producer_by_key.get(selected_key, {}))
	var staff_id := int(provider.get("staff_id", -1))
	_selected_employee_key = selected_key
	_apply_selected_employee(employee_type, staff_id)
	_selected_changed()
	_ensure_food_controller()
	if _food_controller != null and is_instance_valid(_food_controller):
		_food_controller.rebuild_food_type_options()
		_food_controller.update_food_controls_visibility()

	_ensure_drinks_controller()
	if _drinks_controller != null and is_instance_valid(_drinks_controller):
		_drinks_controller.update_drinks_controls_visibility()
	_update_confirm_state()
	_update_info()

func _get_employee_def_for_card(employee_type: String) -> Dictionary:
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty():
		return {"id": emp_id, "name": emp_id}
	if not EmployeeRegistryClass.is_loaded():
		return {"id": emp_id, "name": emp_id}
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val != null and def_val.has_method("to_dict"):
		return def_val.to_dict()
	return {"id": emp_id, "name": emp_id}

func _selected_changed() -> void:
	producer_changed.emit(_selected_employee_type, _production_type, _selected_staff_id)

func _update_confirm_state() -> void:
	if confirm_btn == null:
		return
	var enabled := not _selected_employee_type.is_empty()
	if _production_type == "drinks":
		if _selected_employee_type == "errand_boy":
			enabled = enabled and not _selected_drink_type.is_empty()
		else:
			enabled = enabled and _drinks_confirm_ready
			if _drinks_restaurant_require_selection:
				enabled = enabled and not _drinks_selected_restaurant_id.is_empty()
	elif _production_type == "food":
		if not _available_food_types.is_empty():
			enabled = enabled and not _selected_food_type.is_empty()
	confirm_btn.disabled = not enabled
	right_panel_footer_changed.emit()

func _update_info() -> void:
	if summary_label != null:
		summary_label.text = ""
	if _info_label == null:
		return
	if _selected_employee_type.is_empty():
		_info_label.text = "请选择员工" if _has_any_enabled_employee else "没有可用员工"
		return

	var emp_name := _get_employee_display_name(_selected_employee_type)
	if _production_type == "drinks":
		if _selected_employee_type == "errand_boy":
			var drink_text := _get_product_display_name(_selected_drink_type) if not _selected_drink_type.is_empty() else "（请选择）"
			_info_label.text = "%s：选择 1 种饮料并直接获得 1 瓶（%s）。" % [emp_name, drink_text]
		else:
			var start_text := ""
			if _drinks_restaurant_show_selector:
				if not _drinks_selected_restaurant_id.is_empty():
					var rlabel := str(_drinks_restaurant_label_by_id.get(_drinks_selected_restaurant_id, _drinks_selected_restaurant_id)).strip_edges()
					if not rlabel.is_empty():
						start_text = "起点：%s，" % rlabel
				elif _drinks_restaurant_require_selection:
					start_text = "请先选择起点餐厅，"

			var is_air := _is_air_procure_employee_type(_selected_employee_type)
			var suffix := "（请点击地图上的饮料点）"
			if is_air:
				suffix = "（从餐厅开始选择相连板块）"
				if _drinks_selected_sources_count > 0:
					suffix = "（已选板块: %d）" % _drinks_selected_sources_count
				_info_label.text = "%s：%s从餐厅所在板块开始，连续选择相连板块 -> 系统生成路线 -> 确认后开始采购%s" % [emp_name, start_text, suffix]
			else:
				if _drinks_selected_sources_count > 0:
					suffix = "（已选进货点: %d）" % _drinks_selected_sources_count
				_info_label.text = "%s：%s点击地图饮料点逐个选择 -> 系统生成路线 -> 确认后开始采购%s" % [emp_name, start_text, suffix]
			if _drinks_restaurant_show_selector:
				_info_label.text = "%s（可点击餐厅或按 1-9 切换起点）" % _info_label.text
			if not _drinks_hover_preview_text.is_empty():
				_info_label.text = "%s\n%s" % [_info_label.text, _drinks_hover_preview_text]
		return

	# food
	if not EmployeeRegistryClass.is_loaded():
		_info_label.text = "%s 将执行一次生产（产品由员工卡决定）。" % emp_name
		return

	var def_val = EmployeeRegistryClass.get_def(_selected_employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		_info_label.text = "%s 将执行一次生产（产品由员工卡决定）。" % emp_name
		return
	var def: EmployeeDef = def_val
	var info: Dictionary = def.get_production_info()
	if info.is_empty():
		_info_label.text = "%s 无法生产食物。" % emp_name
		return

	var options_val = info.get("food_options", null)
	if options_val is Array:
		var amount2 := int(info.get("amount", 1))
		var chosen := _selected_food_type
		var chosen_text := "（请选择）"
		var current2 := 0
		if not chosen.is_empty():
			chosen_text = _get_product_display_name(chosen)
			current2 = int(_current_inventory.get(chosen, 0))
		_info_label.text = "%s：选择生产 %s x%d（当前库存: %d）。" % [emp_name, chosen_text, amount2, current2]
		return

	var food_type := str(info.get("food_type", ""))
	var amount := int(info.get("amount", 0))
	var food_name := food_type
	if ProductRegistryClass.is_loaded():
		var p_def_val = ProductRegistryClass.get_def(food_type)
		if p_def_val != null and (p_def_val is ProductDef):
			food_name = str((p_def_val as ProductDef).name)
	var current := int(_current_inventory.get(food_type, 0))
	_info_label.text = "%s 将生产：%s x%d（当前库存: %d）。" % [emp_name, food_name, amount, current]

func _get_employee_display_name(employee_type: String) -> String:
	if employee_type.is_empty():
		return ""
	if not EmployeeRegistryClass.is_loaded():
		return employee_type
	var def_val = EmployeeRegistryClass.get_def(employee_type)
	if def_val == null or not (def_val is EmployeeDef):
		return employee_type
	var def: EmployeeDef = def_val
	return def.name if not def.name.is_empty() else employee_type

func _on_confirm_pressed() -> void:
	if confirm_btn != null and confirm_btn.disabled:
		return
	if _selected_employee_type.is_empty():
		return
	production_requested.emit(_selected_employee_type, _production_type, _selected_staff_id)

func mark_selected_employee_used() -> void:
	if not _producer_items.is_empty():
		return
	if _employee_picker == null:
		return

	var prev_type := _selected_employee_type
	var prev_staff_id := _selected_staff_id
	var key := _selected_employee_key
	if key.is_empty() and _employee_picker.has_method("get_selected_key"):
		key = str(_employee_picker.call("get_selected_key")).strip_edges()
	if key.is_empty():
		return

	if not _used_employee_keys_by_mode.has(_production_type) or not (_used_employee_keys_by_mode[_production_type] is Dictionary):
		_used_employee_keys_by_mode[_production_type] = {}
	var used_set: Dictionary = _used_employee_keys_by_mode[_production_type]
	used_set[key] = true
	_used_employee_keys_by_mode[_production_type] = used_set

	# 重新生成 items，以刷新 enabled/灰显，并尽量选中同类型的下一个可用实例。
	_rebuild_employee_options()
	if prev_type != _selected_employee_type or prev_staff_id != _selected_staff_id:
		_ensure_food_controller()
		if _food_controller != null and is_instance_valid(_food_controller):
			_food_controller.rebuild_food_type_options()
			_food_controller.update_food_controls_visibility()

		_ensure_drinks_controller()
		if _drinks_controller != null and is_instance_valid(_drinks_controller):
			_drinks_controller.update_drinks_controls_visibility()
	_update_confirm_state()
	_update_info()

func _on_cancel_pressed() -> void:
	cancelled.emit()

func _is_air_procure_employee_type(employee_type: String) -> bool:
	if employee_type.is_empty():
		return false
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(employee_type)
		if def_val != null and (def_val is EmployeeDef):
			var def: EmployeeDef = def_val
			return str(def.range_type) == "air"
	return employee_type == "zeppelin_pilot"

func _get_product_display_name(product_id: String) -> String:
	var pid := str(product_id)
	if pid.is_empty():
		return ""
	if not ProductRegistryClass.is_loaded():
		return pid
	var def_val = ProductRegistryClass.get_def(pid)
	if def_val != null and (def_val is ProductDef):
		var def: ProductDef = def_val
		if not def.name.is_empty():
			return def.name
	return pid

func _ensure_skin() -> void:
	if _skin != null:
		return

	var base_dir := ModulesBaseDirClass.get_base_dir()

	var mods: Array[String] = []
	if Globals != null and (Globals.enabled_modules_v2 is Array):
		mods = Array(Globals.enabled_modules_v2, TYPE_STRING, "", null)

	_skin = UiSkinCacheClass.get_skin_for_modules(base_dir, mods, 40)

func _get_product_icon_texture(product_id: String) -> Texture2D:
	_ensure_skin()
	if _skin == null or not _skin.has_method("get_product_icon_texture"):
		return null
	var pid := str(product_id).strip_edges()
	if pid == "cola":
		pid = "soda"
	return _skin.get_product_icon_texture(pid)
