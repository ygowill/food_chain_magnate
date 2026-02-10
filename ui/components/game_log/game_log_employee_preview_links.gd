# GameLog：员工名字交互链接（悬停/点击 -> 员工卡片预览）
# - 不改变文本样式：仅对指定员工名称片段 push_meta。
# - 员工列表来自 entry.details 中的员工字段（employee_id/employee_type/from_employee/to_employee/trainer_id）。
class_name GameLogEmployeePreviewLinks
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")

const META_PREFIX := "employee:"

static func is_employee_meta(meta) -> bool:
	if meta == null:
		return false
	return str(meta).begins_with(META_PREFIX)

static func employee_id_from_meta(meta) -> String:
	if meta == null:
		return ""
	var s := str(meta)
	if not s.begins_with(META_PREFIX):
		return ""
	return s.substr(META_PREFIX.length()).strip_edges()

static func build_label(label: RichTextLabel, message: String, details: Dictionary) -> void:
	if label == null or not is_instance_valid(label):
		return

	var msg := str(message)
	var refs := _collect_employee_refs(details)
	if refs.is_empty():
		label.text = msg
		return

	if not (label.has_method("clear") and label.has_method("append_text") and label.has_method("push_meta") and label.has_method("pop")):
		label.text = msg
		return

	label.clear()

	var cursor := 0
	for ref_val in refs:
		if not (ref_val is Dictionary):
			continue
		var ref: Dictionary = ref_val
		var eid := str(ref.get("id", "")).strip_edges()
		if eid.is_empty():
			continue
		var name := str(ref.get("name", "")).strip_edges()
		if name.is_empty():
			name = eid

		var idx := msg.find(name, cursor)
		var matched := name
		if idx < 0:
			idx = msg.find(eid, cursor)
			matched = eid
		if idx < 0:
			continue

		if idx > cursor:
			label.append_text(msg.substr(cursor, idx - cursor))

		label.push_meta(META_PREFIX + eid)
		label.append_text(matched)
		label.pop()

		cursor = idx + matched.length()

	if cursor < msg.length():
		label.append_text(msg.substr(cursor))

static func _collect_employee_refs(details: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if details == null or not (details is Dictionary):
		return out

	# 顺序尽量匹配 GameEventLogFormatter 的拼接顺序（保证多员工同条日志时逐个可悬停）。
	_add_ref(out, str(details.get("employee_id", "")).strip_edges())
	_add_ref(out, str(details.get("employee_type", "")).strip_edges())
	_add_ref(out, str(details.get("from_employee", "")).strip_edges())
	_add_ref(out, str(details.get("to_employee", "")).strip_edges())
	_add_ref(out, str(details.get("trainer_id", "")).strip_edges())

	return out

static func _add_ref(out: Array[Dictionary], employee_id: String) -> void:
	var eid := str(employee_id).strip_edges()
	if eid.is_empty():
		return
	for e in out:
		if e != null and e is Dictionary and str((e as Dictionary).get("id", "")) == eid:
			return

	var name := eid
	if EmployeeRegistryClass.is_loaded():
		var def_val = EmployeeRegistryClass.get_def(eid)
		if def_val != null and def_val is EmployeeDefClass:
			var def: EmployeeDef = def_val
			var n := str(def.name).strip_edges()
			if not n.is_empty():
				name = n

	out.append({"id": eid, "name": name})

