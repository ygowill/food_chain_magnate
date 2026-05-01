# PlatformApi：HTTP JSON 解析与错误包装契约
# - 避免 error body 为 Array/非 Dictionary 时写入字段导致崩溃
# - 允许 ok body 为任意合法 JSON（Dictionary/Array/primitive/null）
# - 2xx 响应体解析失败必须按协议错误返回 error
class_name PlatformApiResponseParseTest
extends RefCounted

const PlatformApiScript = preload("res://autoload/platform_api.gd")

static func run() -> Result:
	# ok: Dictionary
	var r1: Dictionary = PlatformApiScript.parse_http_json_response(200, "{\"a\":1}")
	if not r1.has("ok"):
		return Result.failure("200 应返回 ok，但实际 keys=%s" % str(Array(r1.keys())))
	if not (r1.get("ok", null) is Dictionary):
		return Result.failure("200 ok body 类型错误（期望 Dictionary）: %s" % str(typeof(r1.get("ok", null))))
	if int(Dictionary(r1["ok"]).get("a", -1)) != 1:
		return Result.failure("200 ok body 内容错误: %s" % str(r1.get("ok", null)))

	# ok: Array
	var r2: Dictionary = PlatformApiScript.parse_http_json_response(200, "[]")
	if not r2.has("ok"):
		return Result.failure("200 应返回 ok（Array body），但实际 keys=%s" % str(Array(r2.keys())))
	if not (r2.get("ok", null) is Array):
		return Result.failure("200 ok body 类型错误（期望 Array）: %s" % str(typeof(r2.get("ok", null))))

	# ok: null（合法 JSON null 不能和解析失败混淆）
	var r_null: Dictionary = PlatformApiScript.parse_http_json_response(200, "null")
	if not r_null.has("ok"):
		return Result.failure("200 应返回 ok（null body），但实际 keys=%s" % str(Array(r_null.keys())))
	if r_null.get("ok", "not_null") != null:
		return Result.failure("200 ok body 内容错误（期望 null）: %s" % str(r_null.get("ok", null)))

	# protocol error: 2xx invalid JSON
	var r_invalid_ok: Dictionary = PlatformApiScript.parse_http_json_response(200, "{")
	if not r_invalid_ok.has("error"):
		return Result.failure("200 非 JSON body 应返回 error，但实际 keys=%s" % str(Array(r_invalid_ok.keys())))
	if not (r_invalid_ok.get("error", null) is Dictionary):
		return Result.failure("200 非 JSON error 类型错误（期望 Dictionary）: %s" % str(typeof(r_invalid_ok.get("error", null))))
	var invalid_error := Dictionary(r_invalid_ok["error"])
	if int(invalid_error.get("_http_status", 0)) != 200:
		return Result.failure("200 非 JSON error 缺少/错误 _http_status: %s" % str(invalid_error))
	if str(invalid_error.get("parse_error", "")).is_empty():
		return Result.failure("200 非 JSON error 缺少 parse_error: %s" % str(invalid_error))

	# error: Dictionary body
	var r3: Dictionary = PlatformApiScript.parse_http_json_response(400, "{\"detail\":\"bad\"}")
	if not r3.has("error"):
		return Result.failure("400 应返回 error，但实际 keys=%s" % str(Array(r3.keys())))
	if not (r3.get("error", null) is Dictionary):
		return Result.failure("400 error body 类型错误（期望 Dictionary）: %s" % str(typeof(r3.get("error", null))))
	if int(Dictionary(r3["error"]).get("_http_status", 0)) != 400:
		return Result.failure("400 error 缺少/错误 _http_status: %s" % str(r3.get("error", null)))

	# error: Array body（必须被包装为 Dictionary）
	var r4: Dictionary = PlatformApiScript.parse_http_json_response(500, "[]")
	if not r4.has("error"):
		return Result.failure("500 应返回 error，但实际 keys=%s" % str(Array(r4.keys())))
	if not (r4.get("error", null) is Dictionary):
		return Result.failure("500 error body 类型错误（期望 Dictionary）: %s" % str(typeof(r4.get("error", null))))
	if int(Dictionary(r4["error"]).get("_http_status", 0)) != 500:
		return Result.failure("500 error 缺少/错误 _http_status: %s" % str(r4.get("error", null)))
	var body_val = Dictionary(r4["error"]).get("body", null)
	if not (body_val is Array):
		return Result.failure("500 error.body 类型错误（期望 Array）: %s" % str(typeof(body_val)))

	return Result.success()
