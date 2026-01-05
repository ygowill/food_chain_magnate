# 模块系统 V2：每局游戏的内容目录（Strict Mode）
# 说明：此 Catalog 仅包含“启用模块集合”提供的内容；禁用模块内容在运行期不应存在。
class_name ContentCatalog
extends RefCounted

var employees: Dictionary = {}          # employee_id -> EmployeeDef
var employee_sources: Dictionary = {}   # employee_id -> module_id

var milestones: Dictionary = {}         # milestone_id -> MilestoneDef
var milestone_sources: Dictionary = {}  # milestone_id -> module_id

var marketing: Dictionary = {}          # board_number -> MarketingDef
var marketing_sources: Dictionary = {}  # board_number -> module_id

var products: Dictionary = {}           # product_id -> ProductDef
var product_sources: Dictionary = {}    # product_id -> module_id

var tiles: Dictionary = {}              # tile_id -> TileDef
var tile_sources: Dictionary = {}       # tile_id -> module_id

var maps: Dictionary = {}               # map_id -> MapOptionDef
var map_sources: Dictionary = {}        # map_id -> module_id

var pieces: Dictionary = {}             # piece_id -> PieceDef
var piece_sources: Dictionary = {}      # piece_id -> module_id

func get_employee_def(employee_id: String) -> Variant:
	return employees.get(employee_id, null)

func has_employee(employee_id: String) -> bool:
	return employees.has(employee_id)

func get_milestone_def(milestone_id: String) -> Variant:
	return milestones.get(milestone_id, null)

func has_milestone(milestone_id: String) -> bool:
	return milestones.has(milestone_id)

func get_marketing_def(board_number: int) -> Variant:
	return marketing.get(board_number, null)

func has_marketing(board_number: int) -> bool:
	return marketing.has(board_number)

func get_product_def(product_id: String) -> Variant:
	return products.get(product_id, null)

func has_product(product_id: String) -> bool:
	return products.has(product_id)

func get_tile_def(tile_id: String) -> Variant:
	return tiles.get(tile_id, null)

func has_tile(tile_id: String) -> bool:
	return tiles.has(tile_id)

func get_map_def(map_id: String) -> Variant:
	return maps.get(map_id, null)

func has_map(map_id: String) -> bool:
	return maps.has(map_id)

func get_piece_def(piece_id: String) -> Variant:
	return pieces.get(piece_id, null)

func has_piece(piece_id: String) -> bool:
	return pieces.has(piece_id)
