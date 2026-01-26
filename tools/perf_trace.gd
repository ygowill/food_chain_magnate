# 轻量性能打点（用于定位启动/开局卡顿）
# - 默认关闭；通过命令行 user args 启用：`-- --profile_startup`
# - 输出格式：`[StartupProfile] ...`（便于 grep/机器解析）
extends RefCounted

static var _initialized: bool = false
static var _enabled: bool = false
static var _t0_usec: int = 0

static var _next_span_id: int = 1
static var _open_spans: Dictionary = {} # id -> {name,start_usec,depth}
static var _spans: Array[Dictionary] = [] # [{name,dur_usec,depth}]
static var _counters: Dictionary = {} # key -> int

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_t0_usec = Time.get_ticks_usec()

	# 仅通过 cmdline user args 启用，避免污染正常日志。
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := str(a).strip_edges()
		if s == "profile_startup" or s == "--profile_startup" or s == "startup_profile" or s == "--startup_profile":
			_enabled = true
			break

	if _enabled:
		_print("ENABLED args=%s" % str(args))

static func enabled() -> bool:
	_ensure_init()
	return _enabled

static func begin_span(name: String) -> int:
	if not enabled():
		return -1
	var id := _next_span_id
	_next_span_id += 1
	var depth := _open_spans.size()
	_open_spans[id] = {
		"name": str(name),
		"start_usec": Time.get_ticks_usec(),
		"depth": depth,
	}
	return id

static func end_span(id: int) -> void:
	if not enabled():
		return
	if id < 0:
		return
	var data_val = _open_spans.get(id, null)
	if not (data_val is Dictionary):
		return
	var data: Dictionary = data_val
	_open_spans.erase(id)

	var end_usec := Time.get_ticks_usec()
	var start_usec := int(data.get("start_usec", end_usec))
	var name := str(data.get("name", ""))
	var depth := int(data.get("depth", 0))
	var dur_usec: int = maxi(0, int(end_usec - start_usec))

	_spans.append({
		"name": name,
		"dur_usec": dur_usec,
		"depth": depth,
	})
	_print("%s dur_ms=%.2f" % [name, float(dur_usec) / 1000.0])

static func counter_add(key: String, delta: int = 1) -> void:
	if not enabled():
		return
	var k := str(key)
	_counters[k] = int(_counters.get(k, 0)) + int(delta)

static func counter_set(key: String, value: int) -> void:
	if not enabled():
		return
	_counters[str(key)] = int(value)

static func report(top_n: int = 15) -> void:
	if not enabled():
		return

	var now_usec := Time.get_ticks_usec()
	var total_ms := float(maxi(0, int(now_usec - _t0_usec))) / 1000.0

	_print("REPORT total_ms=%.2f spans=%d counters=%d" % [total_ms, _spans.size(), _counters.size()])

	# 聚合同名 span（便于定位 top-N）
	var agg: Dictionary = {} # name -> {count,total_usec,max_usec}
	for s_val in _spans:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var name := str(s.get("name", ""))
		if name.is_empty():
			continue
		var dur := int(s.get("dur_usec", 0))
		var a_val = agg.get(name, null)
		if not (a_val is Dictionary):
			agg[name] = {"count": 1, "total_usec": dur, "max_usec": dur}
		else:
			var a: Dictionary = a_val
			a["count"] = int(a.get("count", 0)) + 1
			a["total_usec"] = int(a.get("total_usec", 0)) + dur
			a["max_usec"] = maxi(int(a.get("max_usec", 0)), dur)
			agg[name] = a

	var rows: Array[Dictionary] = []
	for k in agg.keys():
		var a2_val = agg.get(k, null)
		if not (a2_val is Dictionary):
			continue
		var a2: Dictionary = a2_val
		rows.append({
			"name": str(k),
			"count": int(a2.get("count", 0)),
			"total_usec": int(a2.get("total_usec", 0)),
			"max_usec": int(a2.get("max_usec", 0)),
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("total_usec", 0)) > int(b.get("total_usec", 0))
	)

	_print("TOP_SPANS n=%d" % min(top_n, rows.size()))
	for i in range(min(top_n, rows.size())):
		var r: Dictionary = rows[i]
		_print("#%02d %s total_ms=%.2f max_ms=%.2f count=%d" % [
			i + 1,
			str(r.get("name", "")),
			float(int(r.get("total_usec", 0))) / 1000.0,
			float(int(r.get("max_usec", 0))) / 1000.0,
			int(r.get("count", 0)),
		])

	if not _counters.is_empty():
		_print("COUNTERS %s" % str(_counters))

static func _print(msg: String) -> void:
	print("[StartupProfile] %s" % str(msg))

