# 模块系统 V2：视觉目录（UI 可选）
# 说明：
# - 该目录只包含“资源路径 + 渲染元数据”的纯数据，不加载 Texture/Node。
# - 缺失视觉资源应由 UI 使用占位渲染（Q12=C）。
class_name VisualCatalog
extends RefCounted

var cell_visuals: Dictionary = {}  # key -> {texture: String}
var road_visuals: Dictionary = {}  # key -> {texture: String}
var piece_visuals: Dictionary = {} # piece_id -> {texture: String, offset_px: Vector2i, scale: Vector2}
var product_icons: Dictionary = {} # product_id -> {texture: String}
var marketing_visuals: Dictionary = {} # key -> {texture: String}

var cell_visual_sources: Dictionary = {}  # key -> module_id
var road_visual_sources: Dictionary = {}  # key -> module_id
var piece_visual_sources: Dictionary = {} # piece_id -> module_id
var product_icon_sources: Dictionary = {} # product_id -> module_id
var marketing_visual_sources: Dictionary = {} # key -> module_id

