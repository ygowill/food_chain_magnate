# 只写入事件历史，不通知 EventBus 订阅者。
# 用于联机 resync / pending 命令追赶，避免历史重放再次触发地图即时动效。
extends RefCounted

const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

var _fallback = null

func _init(fallback = null) -> void:
	_fallback = fallback

func emit_event(event_type: String, data: Dictionary) -> void:
	record_event(event_type, data)

func record_event(event_type: String, data: Dictionary = {}) -> void:
	var data_copy := Dictionary(data).duplicate(true)
	if _fallback != null and _fallback.has_method("record_event"):
		_fallback.record_event(event_type, data_copy)
		return
	var bus = AutoloadAccessClass.get_autoload("EventBus")
	if bus != null and bus.has_method("record_event"):
		bus.record_event(event_type, data_copy)

func clear_history_and_reset_sequence() -> void:
	if _fallback != null and _fallback.has_method("clear_history_and_reset_sequence"):
		_fallback.clear_history_and_reset_sequence()
		return
	var bus = AutoloadAccessClass.get_autoload("EventBus")
	if bus != null and bus.has_method("clear_history_and_reset_sequence"):
		bus.clear_history_and_reset_sequence()

func clear_history() -> void:
	if _fallback != null and _fallback.has_method("clear_history"):
		_fallback.clear_history()
		return
	var bus = AutoloadAccessClass.get_autoload("EventBus")
	if bus != null and bus.has_method("clear_history"):
		bus.clear_history()
