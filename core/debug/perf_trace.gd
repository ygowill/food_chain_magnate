# 轻量性能打点（用于定位启动/开局卡顿）
# - 默认关闭；通过命令行 user args 启用：`-- --profile_startup`
# - 输出格式：`[StartupProfile] ...`（便于 grep/机器解析）
# （已外移至 tools/perf_trace.gd；此处保留 shim，避免 core/engine 等调用方改路径）
extends RefCounted

const Impl = preload("res://tools/perf_trace.gd")

static func enabled() -> bool:
	return Impl.enabled()

static func begin_span(name: String) -> int:
	return Impl.begin_span(name)

static func end_span(id: int) -> void:
	Impl.end_span(id)

static func counter_add(key: String, delta: int = 1) -> void:
	Impl.counter_add(key, delta)

static func counter_set(key: String, value: int) -> void:
	Impl.counter_set(key, value)

static func report(top_n: int = 15) -> void:
	Impl.report(top_n)
