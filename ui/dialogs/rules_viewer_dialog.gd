# 规则书查看（游戏内阅读）：每页图片 + 标签跳转
class_name RulesViewerDialog
extends ModalDialogBase

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")
const UiZClass = preload("res://ui/utils/ui_z.gd")
const InfoDialogClass = preload("res://ui/dialogs/info_dialog.gd")

const RULES_INDEX_PATH := "res://assets/rules/rules_index.json"

const _ZOOM_MIN := 0.5
const _ZOOM_MAX := 3.0

@onready var overlay_rect: ColorRect = $Overlay
@onready var background_panel: Panel = $BackgroundPanel
@onready var title_label: Label = $MarginContainer/VBoxContainer/TopBar/TitleLabel
@onready var book_option: OptionButton = $MarginContainer/VBoxContainer/TopBar/BookOption
@onready var close_button: Button = $MarginContainer/VBoxContainer/TopBar/CloseButton

@onready var tag_scroll: ScrollContainer = $MarginContainer/VBoxContainer/Body/LeftPanel/TagScroll
@onready var tag_list: VBoxContainer = $MarginContainer/VBoxContainer/Body/LeftPanel/TagScroll/TagList

@onready var page_scroll: ScrollContainer = $MarginContainer/VBoxContainer/Body/RightPanel/PageScroll
@onready var page_content: Control = $MarginContainer/VBoxContainer/Body/RightPanel/PageScroll/PageContent
@onready var page_texture: TextureRect = $MarginContainer/VBoxContainer/Body/RightPanel/PageScroll/PageContent/PageTexture
@onready var missing_label: Label = $MarginContainer/VBoxContainer/Body/RightPanel/PageScroll/PageContent/MissingLabel

@onready var prev_button: Button = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/PrevButton
@onready var next_button: Button = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/NextButton
@onready var page_label: Label = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/PageLabel
@onready var zoom_out_button: Button = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/ZoomOutButton
@onready var zoom_in_button: Button = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/ZoomInButton
@onready var fit_width_button: Button = $MarginContainer/VBoxContainer/Body/RightPanel/BottomBar/FitWidthButton

var _index: Dictionary = {}
var _books: Array[Dictionary] = []
var _book_id: String = "base"
var _book: Dictionary = {}
var _tags: Array[Dictionary] = []
var _tag_buttons: Array[Button] = []
var _active_tag_index: int = -1

var _page: int = 1
var _page_count: int = 1

var _zoom: float = 1.0
var _fit_width: bool = true
var _texture_size: Vector2i = Vector2i.ZERO

var _pending_open: bool = false
var _pending_open_book_id: String = ""
var _pending_open_page: int = 1


func _ready() -> void:
	super._ready()

	UiZClass.apply_absolute(self, UiZClass.RULES_DIALOG)

	UiStylesClass.apply_overlay_dim(overlay_rect)
	UiStylesClass.apply_dialog_surface(background_panel)
	UiStylesClass.apply_label_dark(title_label)
	UiStylesClass.apply_option_button_field(book_option)

	for btn in [close_button, prev_button, next_button, zoom_out_button, zoom_in_button, fit_width_button]:
		if btn is Button:
			UiStylesClass.apply_button_secondary(btn)
	if close_button != null:
		UiStylesClass.apply_button_primary(close_button)

	if missing_label != null:
		UiStylesClass.apply_label_hint_dark(missing_label)

	if close_button != null:
		close_button.pressed.connect(_on_close_pressed)
	if book_option != null:
		book_option.item_selected.connect(_on_book_selected)

	if prev_button != null:
		prev_button.pressed.connect(_on_prev_pressed)
	if next_button != null:
		next_button.pressed.connect(_on_next_pressed)
	if zoom_out_button != null:
		zoom_out_button.pressed.connect(_on_zoom_out_pressed)
	if zoom_in_button != null:
		zoom_in_button.pressed.connect(_on_zoom_in_pressed)
	if fit_width_button != null:
		fit_width_button.pressed.connect(_on_fit_width_pressed)

	_load_index()
	_rebuild_book_option()

	if _pending_open:
		var pending_id := _pending_open_book_id
		var pending_page := _pending_open_page
		_pending_open = false
		_pending_open_book_id = ""
		_pending_open_page = 1
		open_for_book(pending_id, pending_page)


func open_for_book(book_id: String, page: int = 1) -> void:
	if not is_node_ready():
		_pending_open = true
		_pending_open_book_id = str(book_id)
		_pending_open_page = int(page)
		return

	_book_id = str(book_id).strip_edges()
	_page = maxi(1, int(page))
	_fit_width = true
	_zoom = 1.0

	_apply_book(_book_id)
	_select_book_option(_book_id)
	_go_to_page(_page)
	show_dialog()
	if _fit_width:
		call_deferred("_apply_zoom")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if visible and _fit_width:
			call_deferred("_apply_zoom")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var e: InputEventKey = event
		if not e.pressed or e.echo:
			return
		match e.keycode:
			KEY_ESCAPE:
				_on_close_pressed()
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_on_prev_pressed()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_on_next_pressed()
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_on_zoom_out_pressed()
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_KP_ADD:
				_on_zoom_in_pressed()
				get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	close()
	queue_free()


func _on_book_selected(index: int) -> void:
	if book_option == null:
		return
	var meta = book_option.get_item_metadata(index)
	var next_id := str(meta).strip_edges()
	if next_id.is_empty() or next_id == _book_id:
		return
	_book_id = next_id
	_apply_book(_book_id)
	_go_to_page(1)


func _on_prev_pressed() -> void:
	_go_to_page(_page - 1)


func _on_next_pressed() -> void:
	_go_to_page(_page + 1)


func _on_zoom_out_pressed() -> void:
	_fit_width = false
	_zoom = clampf(_zoom / 1.1, _ZOOM_MIN, _ZOOM_MAX)
	_apply_zoom()


func _on_zoom_in_pressed() -> void:
	_fit_width = false
	_zoom = clampf(_zoom * 1.1, _ZOOM_MIN, _ZOOM_MAX)
	_apply_zoom()


func _on_fit_width_pressed() -> void:
	_fit_width = true
	_apply_zoom()


func _load_index() -> void:
	_index = {}
	_books.clear()

	if not FileAccess.file_exists(RULES_INDEX_PATH):
		_show_error("规则书资源缺失", "缺少规则索引文件：\n%s" % RULES_INDEX_PATH)
		return

	var text := FileAccess.get_file_as_string(RULES_INDEX_PATH)
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_show_error("规则书索引损坏", "无法解析规则索引文件：\n%s" % RULES_INDEX_PATH)
		return

	_index = Dictionary(parsed)
	var books_val = _index.get("books", [])
	if books_val is Array:
		for v in books_val:
			if v is Dictionary:
				_books.append(Dictionary(v))


func _rebuild_book_option() -> void:
	if book_option == null:
		return
	book_option.clear()

	for i in range(_books.size()):
		var b_val = _books[i]
		if not (b_val is Dictionary):
			continue
		var b: Dictionary = Dictionary(b_val)
		var id := str(b.get("id", "")).strip_edges()
		var title := str(b.get("title", id)).strip_edges()
		if id.is_empty():
			continue
		book_option.add_item(title, i)
		book_option.set_item_metadata(i, id)


func _select_book_option(book_id: String) -> void:
	if book_option == null:
		return
	for i in range(book_option.item_count):
		var meta = book_option.get_item_metadata(i)
		if str(meta) == book_id:
			book_option.select(i)
			return


func _apply_book(book_id: String) -> void:
	_book = _find_book(book_id)
	if _book.is_empty():
		_book = _find_book("base")
	_book_id = str(_book.get("id", "base"))

	_page_count = maxi(1, int(_book.get("page_count", 1)))

	var tags_val = _book.get("tags", [])
	_tags.clear()
	if tags_val is Array:
		for v in tags_val:
			if not (v is Dictionary):
				continue
			var d: Dictionary = Dictionary(v)
			var label := str(d.get("label", "")).strip_edges()
			if label.is_empty():
				continue
			var page_num := clampi(int(d.get("page", 1)), 1, _page_count)
			_tags.append({"label": label, "page": page_num})
	_rebuild_tags()


func _find_book(book_id: String) -> Dictionary:
	var target := str(book_id).strip_edges()
	for b_val in _books:
		if not (b_val is Dictionary):
			continue
		var b: Dictionary = Dictionary(b_val)
		if str(b.get("id", "")).strip_edges() == target:
			return b
	return {}


func _rebuild_tags() -> void:
	_tag_buttons.clear()
	_active_tag_index = -1
	if tag_list == null:
		return

	for ch in tag_list.get_children():
		ch.queue_free()

	for i in range(_tags.size()):
		var tag: Dictionary = _tags[i]
		var label := str(tag.get("label", "")).strip_edges()
		var page_num := clampi(int(tag.get("page", 1)), 1, _page_count)

		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStylesClass.apply_button_secondary(btn)
		btn.tooltip_text = "%s\n第 %d 页" % [label, page_num]
		btn.pressed.connect(_on_tag_pressed.bind(page_num, i))
		tag_list.add_child(btn)
		_tag_buttons.append(btn)

	_update_active_tag_highlight()


func _on_tag_pressed(page_num: int, tag_index: int) -> void:
	_active_tag_index = clampi(int(tag_index), -1, _tags.size() - 1)
	_go_to_page(page_num)
	call_deferred("_scroll_to_tag", _active_tag_index)


func _scroll_to_tag(tag_index: int) -> void:
	if tag_index < 0 or tag_index >= _tags.size():
		return
	if page_scroll == null or page_content == null:
		return

	var tag_page := clampi(int(_tags[tag_index].get("page", 1)), 1, _page_count)
	if tag_page != _page:
		return

	# 同一页可能有多个目录标签。没有更精确的坐标信息时，用“同页标签序号”做一个近似滚动定位，
	# 让点击不同标签时不至于总落在页面顶部。
	var same_page_indices: Array[int] = []
	for i in range(_tags.size()):
		var p := clampi(int(_tags[i].get("page", 1)), 1, _page_count)
		if p == tag_page:
			same_page_indices.append(i)
	if same_page_indices.size() <= 1:
		return

	var rank := same_page_indices.find(tag_index)
	if rank < 0:
		return

	var viewport_h := float(page_scroll.size.y)
	var content_h := float(page_content.custom_minimum_size.y)
	if viewport_h <= 1.0 or content_h <= viewport_h:
		return

	var denom := float(maxi(1, same_page_indices.size() - 1))
	var ratio := clampf(float(rank) / denom, 0.0, 1.0)

	var max_scroll := maxi(0, int(round(content_h - viewport_h)))
	var target := clampi(int(round(float(max_scroll) * ratio)), 0, max_scroll)
	page_scroll.scroll_vertical = target


func _go_to_page(page_num: int) -> void:
	_page = clampi(int(page_num), 1, _page_count)
	_load_page_texture()
	_apply_zoom()
	if page_scroll != null:
		page_scroll.scroll_horizontal = 0
		page_scroll.scroll_vertical = 0
	_update_page_label()
	_update_active_tag_highlight()


func _load_page_texture() -> void:
	_texture_size = Vector2i.ZERO
	if page_texture != null:
		page_texture.texture = null
	if missing_label != null:
		missing_label.visible = false

	var fmt := str(_book.get("pages_path", "")).strip_edges()
	if fmt.is_empty():
		_show_missing("未配置 pages_path。")
		return
	if fmt.find("%") < 0:
		_show_missing("pages_path 不是格式字符串：\n%s" % fmt)
		return

	var path := fmt % _page
	var tex_val := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
	var tex := tex_val as Texture2D
	if tex == null:
		_show_missing("缺少页面图片：\n%s" % path)
		return

	_texture_size = Vector2i(tex.get_size())
	if page_texture != null:
		page_texture.texture = tex


func _show_missing(message: String) -> void:
	if missing_label != null:
		missing_label.visible = true
		missing_label.text = "页面加载失败：\n%s\n\n请先生成规则书页图（见 tools/build_rules_pages.sh）。" % str(message)


func _apply_zoom() -> void:
	if _texture_size == Vector2i.ZERO:
		return

	if _fit_width and page_scroll != null:
		var viewport_w := float(page_scroll.size.x) - 18.0
		if viewport_w > 0.0 and _texture_size.x > 0:
			_zoom = clampf(viewport_w / float(_texture_size.x), _ZOOM_MIN, _ZOOM_MAX)

	var target := Vector2(float(_texture_size.x), float(_texture_size.y)) * _zoom
	if page_content != null:
		page_content.custom_minimum_size = target
		page_content.size = target
	if page_texture != null:
		page_texture.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, 0)
		page_texture.position = Vector2.ZERO
		page_texture.custom_minimum_size = target
		page_texture.size = target
		page_texture.stretch_mode = TextureRect.STRETCH_SCALE


func _update_page_label() -> void:
	if page_label == null:
		return
	page_label.text = "%d / %d" % [_page, _page_count]


func _update_active_tag_highlight() -> void:
	if _tags.is_empty() or _tag_buttons.is_empty():
		return

	var active_index := -1
	var best_page := -1
	for i in range(_tags.size()):
		var p := clampi(int(_tags[i].get("page", 1)), 1, _page_count)
		if p <= _page and p > best_page:
			best_page = p
			active_index = i

	# 当多个标签映射到同一页时，优先高亮玩家最近点击的那个。
	if _active_tag_index >= 0 and _active_tag_index < _tags.size():
		var selected_page := clampi(int(_tags[_active_tag_index].get("page", 1)), 1, _page_count)
		if selected_page == _page:
			active_index = _active_tag_index

	_active_tag_index = active_index

	for i2 in range(_tag_buttons.size()):
		var btn := _tag_buttons[i2]
		if btn == null or not is_instance_valid(btn):
			continue
		if i2 == active_index:
			UiStylesClass.apply_button_primary(btn)
		else:
			UiStylesClass.apply_button_secondary(btn)

	if active_index >= 0 and active_index < _tag_buttons.size():
		if tag_scroll != null and tag_scroll.has_method("ensure_control_visible"):
			tag_scroll.call("ensure_control_visible", _tag_buttons[active_index])


func _show_error(title_text: String, message: String) -> void:
	if OS.has_feature("headless"):
		return
	var dlg := InfoDialogClass.new()
	if dlg == null:
		push_warning("%s: %s" % [str(title_text), str(message)])
		return
	add_child(dlg)
	if dlg.has_signal("closed"):
		dlg.closed.connect(func() -> void:
			if is_instance_valid(dlg):
				dlg.queue_free()
		)
	if dlg.has_method("show_info"):
		dlg.show_info(title_text, message, Vector2i(620, 360), "确定")
