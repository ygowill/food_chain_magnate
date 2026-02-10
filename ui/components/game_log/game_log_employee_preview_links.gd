# GameLog：员工名字交互链接（悬停/点击 -> 员工卡片预览）
# - 不改变文本样式：仅对指定员工名称片段 push_meta。
# - 员工列表来自 entry.details 中的员工字段（employee_id/employee_type/from_employee/to_employee/trainer_id）。
class_name GameLogEmployeePreviewLinks
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

const META_PREFIX := "employee:"
const MILESTONE_META_PREFIX := "milestone:"

static func is_employee_meta(meta) -> bool:
	if meta == null:
		return false
	return str(meta).begins_with(META_PREFIX)

static func is_milestone_meta(meta) -> bool:
	if meta == null:
		return false
	return str(meta).begins_with(MILESTONE_META_PREFIX)

static func is_preview_meta(meta) -> bool:
	return is_employee_meta(meta) or is_milestone_meta(meta)

static func employee_id_from_meta(meta) -> String:
	if meta == null:
		return ""
	var s := str(meta)
	if not s.begins_with(META_PREFIX):
		return ""
	return s.substr(META_PREFIX.length()).strip_edges()

static func milestone_id_from_meta(meta) -> String:
	if meta == null:
		return ""
	var s := str(meta)
	if not s.begins_with(MILESTONE_META_PREFIX):
		return ""
	return s.substr(MILESTONE_META_PREFIX.length()).strip_edges()

static func preview_ref_from_meta(meta) -> Dictionary:
	if is_employee_meta(meta):
		return {"kind": "employee", "id": employee_id_from_meta(meta)}
	if is_milestone_meta(meta):
		return {"kind": "milestone", "id": milestone_id_from_meta(meta)}
	return {}

static func build_label(label: RichTextLabel, message: String, details: Dictionary) -> void:
	if label == null or not is_instance_valid(label):
		return

	var msg := str(message)
	var refs := _collect_employee_refs(details)
	refs.append_array(_collect_milestone_refs(details))
	if refs.is_empty():
		label.text = msg
		return

	if not (label.has_method("clear") and label.has_method("append_text") and label.has_method("push_meta") and label.has_method("pop")):
		label.text = msg
		return

	label.clear()

	var cursor := 0
	while cursor < msg.length():
		var best_idx := -1
		var best_ref: Dictionary = {}
		var best_match := ""

		for ref_val in refs:
			if not (ref_val is Dictionary):
				continue
			var ref: Dictionary = ref_val
			var kind := str(ref.get("kind", "")).strip_edges()
			var id := str(ref.get("id", "")).strip_edges()
			if id.is_empty():
				continue
			var name := str(ref.get("name", "")).strip_edges()
			if name.is_empty():
				name = id

			var idx := msg.find(name, cursor)
			var matched := name
			if idx < 0:
				idx = msg.find(id, cursor)
				matched = id
			if idx < 0:
				continue

			if best_idx < 0 or idx < best_idx or (idx == best_idx and matched.length() > best_match.length()):
				best_idx = idx
				best_ref = {"kind": kind, "id": id}
				best_match = matched

		if best_idx < 0 or best_ref.is_empty() or best_match.is_empty():
			label.append_text(msg.substr(cursor))
			break

		if best_idx > cursor:
			label.append_text(msg.substr(cursor, best_idx - cursor))

		var meta := ""
		if str(best_ref.get("kind", "")) == "milestone":
			meta = MILESTONE_META_PREFIX + str(best_ref.get("id", ""))
		else:
			meta = META_PREFIX + str(best_ref.get("id", ""))
		label.push_meta(meta)
		label.append_text(best_match)
		label.pop()

		cursor = best_idx + best_match.length()

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

static func _collect_milestone_refs(details: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if details == null or not (details is Dictionary):
		return out
	_add_milestone_ref(out, str(details.get("milestone_id", "")).strip_edges())
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

	out.append({"kind": "employee", "id": eid, "name": name})

static func _add_milestone_ref(out: Array[Dictionary], milestone_id: String) -> void:
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return
	for e in out:
		if e != null and e is Dictionary and str((e as Dictionary).get("id", "")) == mid and str((e as Dictionary).get("kind", "")) == "milestone":
			return

	var name := mid
	if MilestoneRegistryClass.is_loaded():
		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val != null and def_val is MilestoneDefClass:
			var def: MilestoneDef = def_val
			var n := str(def.name).strip_edges()
			if not n.is_empty():
				name = _strip_milestone_id_suffix(n, mid)

	out.append({"kind": "milestone", "id": mid, "name": name})

static func _strip_milestone_id_suffix(raw_name: String, milestone_id: String) -> String:
	var s := str(raw_name).strip_edges()
	var mid := str(milestone_id).strip_edges()
	if mid.is_empty():
		return s

	var suffixes: Array[String] = [
		" (" + mid + ")",
		"(" + mid + ")",
		" （" + mid + "）",
		"（" + mid + "）",
	]
	for suffix in suffixes:
		if s.ends_with(suffix):
			return s.substr(0, s.length() - suffix.length()).strip_edges()
	return s
