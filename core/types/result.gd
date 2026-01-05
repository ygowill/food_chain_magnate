# 通用结果类型
# 用于统一所有操作的返回值，包含成功/失败状态、值和错误信息
class_name Result
extends RefCounted

# 核心属性
var ok: bool = false
var value = null  # 成功时的返回值
var error: String = ""  # 失败时的错误信息
var warnings: Array[String] = []

# 静态工厂方法：创建成功结果
static func success(val = null) -> Result:
	var r := Result.new()
	r.ok = true
	r.value = val
	return r

# 静态工厂方法：创建失败结果
static func failure(err: String) -> Result:
	var r := Result.new()
	r.ok = false
	r.error = err
	return r

# 添加警告（链式调用）
func with_warning(msg: String) -> Result:
	warnings.append(msg)
	return self

# 添加多个警告
func with_warnings(msgs: Array[String]) -> Result:
	warnings.append_array(msgs)
	return self

# 设置值（链式调用）
func with_value(val) -> Result:
	value = val
	return self

# 检查是否有警告
func has_warnings() -> bool:
	return warnings.size() > 0

# 获取所有警告的字符串
func get_warnings_string() -> String:
	return "; ".join(warnings)

# 转为字典（用于序列化）
func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"value": value,
		"error": error,
		"warnings": warnings
	}

# 从字典创建
static func from_dict(data: Dictionary) -> Result:
	var r := Result.new()
	r.ok = data.get("ok", false)
	r.value = data.get("value", null)
	r.error = data.get("error", "")
	r.warnings = Array(data.get("warnings", []), TYPE_STRING, "", null)
	return r

# 调试输出
func _to_string() -> String:
	if ok:
		if has_warnings():
			return "[Result OK with %d warnings]" % warnings.size()
		return "[Result OK]"
	else:
		return "[Result FAILED: %s]" % error

# 解包值（如果失败则返回默认值）
func unwrap(default = null):
	if ok:
		return value
	return default

# 解包值（如果失败则抛出错误）
func unwrap_or_error():
	if ok:
		return value
	push_error("Result unwrap failed: %s" % error)
	return null

# 映射成功值
func map(transform: Callable) -> Result:
	if ok:
		return Result.success(transform.call(value))
	return self

# 链式处理
func and_then(next_fn: Callable) -> Result:
	if ok:
		return next_fn.call(value)
	return self

# 合并多个 Result
static func all(results: Array[Result]) -> Result:
	var values := []
	var all_warnings: Array[String] = []

	for r in results:
		if not r.ok:
			return r
		values.append(r.value)
		all_warnings.append_array(r.warnings)

	return Result.success(values).with_warnings(all_warnings)

# 返回第一个成功的结果
static func first_ok(results: Array[Result]) -> Result:
	for r in results:
		if r.ok:
			return r
	if results.size() > 0:
		return results[-1]
	return Result.failure("No results provided")
