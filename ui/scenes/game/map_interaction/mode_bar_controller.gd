# Game scene：地图模式提示条控制器
# 负责：根据 MapInteractionController 的 mode_changed 信号更新 MapModeBar 的标题与提示文案。
class_name GameMapModeBarController
extends RefCounted

var _map_mode_bar: Object = null

func _init(map_mode_bar: Object) -> void:
	_map_mode_bar = map_mode_bar

func dispose() -> void:
	_map_mode_bar = null

func on_map_mode_changed(mode: String, payload: Dictionary) -> void:
	if not is_instance_valid(_map_mode_bar):
		return

	var m = str(mode)
	if m.is_empty():
		if _map_mode_bar.has_method("hide_mode"):
			_map_mode_bar.call("hide_mode")
		return

	# 地图顶部提示条仅保留“距离工具”模式；其它选点提示统一在右侧动作面板/面板内说明展示。
	if m != "distance_tool":
		if _map_mode_bar.has_method("hide_mode"):
			_map_mode_bar.call("hide_mode")
		return

	if not _map_mode_bar.has_method("show_mode"):
		return

	_map_mode_bar.call("show_mode", "📏 距离工具", "支持道路↔道路，或房屋+餐厅｜点起点再点终点｜测完后点击任意目标重开｜D 关闭")
