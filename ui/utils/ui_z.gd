# UI 绘制层级（z_index）统一管理：
# - z_index 仅在同一 CanvasLayer 内比较；本项目大多数 UI 在默认 CanvasLayer（layer=0）。
# - 这些值假定配合 `z_as_relative = false` 使用（即“绝对 z”）。
# - 约定：数值越大越靠上，避免菜单/弹窗/高亮等互相遮盖产生意外。
class_name UiZ
extends RefCounted

# 轻量弹窗（居中/右侧抽屉）
const POPUP := 500

# 地图交互提示/局部覆盖（放置模式提示条、内联 tooltip 等）
const MAP_OVERLAY := 1000

# 全屏浏览视图（里程碑/供应堆/员工树等），应盖住 MAP_OVERLAY，但低于阻塞性弹窗
const FULLSCREEN_VIEW := 1050

# 晚餐时间逐笔结算动画覆盖层（地图 token、高亮、路线闪烁等）
const DINNERTIME_OVERLAY := 1100
const DINNERTIME_CONTROL_BAR := 1150

# 游戏内菜单
const MENU := 1200

# 阻塞性弹窗（储备卡选择/顺位选择/重组 modal/银行破产等）
const MODAL := 1300

# ConfirmDialog（返回主菜单确认等）
const CONFIRM_DIALOG := 1350

# 终局面板 / 规则书 / Toast
const GAME_OVER := 1400
const RULES_DIALOG := 1500
const TOAST := 1600

static func apply_absolute(item: CanvasItem, z: int) -> void:
	if item == null or not is_instance_valid(item):
		return
	item.z_as_relative = false
	item.z_index = int(z)
