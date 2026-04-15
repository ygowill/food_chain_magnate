extends RefCounted

const _PREFIX := "[OnlinePerf]"

static var _initialized: bool = false
static var _enabled: bool = false

static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	var env_raw := str(OS.get_environment("FCM_ONLINE_PERF")).strip_edges().to_lower()
	if env_raw == "1" or env_raw == "true" or env_raw == "yes" or env_raw == "on":
		_enabled = true

	if not _enabled:
		_enabled = _is_enabled_from_web_query()

	if not _enabled:
		var args := OS.get_cmdline_user_args()
		for arg in args:
			var s := str(arg).strip_edges().to_lower()
			if s == "online_perf" or s == "--online_perf" or s == "profile_online_sync" or s == "--profile_online_sync":
				_enabled = true
				break

	if _enabled:
		_print_json({
			"event": "enabled",
			"wall_unix_ms": _raw_now_unix_ms(),
			"mono_usec": _raw_now_mono_usec(),
			"args": _normalize_value(OS.get_cmdline_user_args()),
		})

static func enabled() -> bool:
	_ensure_init()
	return _enabled

static func now_unix_ms() -> int:
	_ensure_init()
	return _raw_now_unix_ms()

static func now_mono_usec() -> int:
	_ensure_init()
	return _raw_now_mono_usec()

static func begin_span(name: String, fields: Dictionary = {}) -> Dictionary:
	if not enabled():
		return {}
	return {
		"name": str(name).strip_edges(),
		"start_unix_ms": _raw_now_unix_ms(),
		"start_mono_usec": _raw_now_mono_usec(),
		"fields": _normalize_dictionary(fields),
	}

static func end_span(span: Dictionary, fields: Dictionary = {}) -> void:
	if not enabled():
		return
	if span == null or span.is_empty():
		return

	var start_mono_usec := int(span.get("start_mono_usec", _raw_now_mono_usec()))
	var out := _normalize_dictionary(Dictionary(span.get("fields", {})))
	var extra := _normalize_dictionary(fields)
	for key in extra.keys():
		out[str(key)] = extra[key]
	out["start_unix_ms"] = int(span.get("start_unix_ms", 0))
	out["duration_ms"] = float(maxi(0, _raw_now_mono_usec() - start_mono_usec)) / 1000.0
	emit_event(str(span.get("name", "")).strip_edges(), out)

static func emit_event(event: String, fields: Dictionary = {}) -> void:
	if not enabled():
		return

	var row := {
		"event": str(event).strip_edges(),
		"wall_unix_ms": _raw_now_unix_ms(),
		"mono_usec": _raw_now_mono_usec(),
	}
	var extra := _normalize_dictionary(fields)
	for key in extra.keys():
		row[str(key)] = extra[key]
	_print_json(row)

static func _raw_now_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

static func _raw_now_mono_usec() -> int:
	return Time.get_ticks_usec()

static func _normalize_dictionary(value: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if value == null or value.is_empty():
		return out
	for key in value.keys():
		out[str(key)] = _normalize_value(value[key])
	return out

static func _normalize_value(value):
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_DICTIONARY:
			return _normalize_dictionary(Dictionary(value))
		TYPE_ARRAY:
			var out: Array = []
			for item in Array(value):
				out.append(_normalize_value(item))
			return out
		_:
			return str(value)

static func _print_json(row: Dictionary) -> void:
	print("%s %s" % [_PREFIX, JSON.stringify(row)])

static func _is_enabled_from_web_query() -> bool:
	if not OS.has_feature("web"):
		return false
	if not ClassDB.class_exists("JavaScriptBridge"):
		return false

	var raw = JavaScriptBridge.eval("""
		(() => {
			try {
				const params = new URLSearchParams(window.location.search || "");
				const keys = ["online_perf", "profile_online_sync"];
				for (const key of keys) {
					const value = (params.get(key) || "").trim().toLowerCase();
					if (value === "1" || value === "true" || value === "yes" || value === "on") {
						return "1";
					}
				}
			} catch (_err) {}
			return "";
		})()
	""", true)
	return str(raw).strip_edges() == "1"
