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

	if not _map_mode_bar.has_method("show_mode"):
		return

	match m:
		"marketing":
			var mt := str(payload.get("marketing_type", ""))
			var title := "📍 营销放置" if mt.is_empty() else "📍 营销放置：%s" % mt
			var hint := "点击地图选择位置｜ESC 取消"
			if mt == "airplane":
				hint = "点击地图边缘选择位置｜角落需选择横/竖飞｜ESC 取消"
			_map_mode_bar.call("show_mode", title, hint)
		"restaurant_placement":
			var action_id := str(payload.get("action_id", ""))
			var title2 := "🏪 放置餐厅" if action_id != "move_restaurant" else "🏪 移动餐厅"
			_map_mode_bar.call("show_mode", title2, "点击地图选择位置｜R 旋转｜右侧确认/取消｜ESC 取消")
		"house_placement":
			var action_id2 := str(payload.get("action_id", ""))
			var title3 := "🏠 放置房屋" if action_id2 != "add_garden" else "🌳 添加花园"
			if action_id2 == "add_garden":
				_map_mode_bar.call("show_mode", title3, "点击地图选择房屋｜右侧选择方向并确认｜ESC 取消")
			else:
				_map_mode_bar.call("show_mode", title3, "点击地图选择位置｜R 旋转｜右侧确认/取消｜ESC 取消")
		"distance_tool":
			_map_mode_bar.call("show_mode", "📏 距离工具", "支持道路↔道路，或房屋+餐厅｜点起点再点终点｜测完后点击任意目标重开｜D/ESC 关闭")
		_:
			_map_mode_bar.call("show_mode", "模式：%s" % m, "ESC 取消")
