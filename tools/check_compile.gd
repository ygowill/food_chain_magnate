# 编译/预加载检查（Headless）
# 用途：快速发现“脚本语法错误导致 preload/load 失败”的问题。
# 运行示例（推荐使用包装脚本，先做 import/class cache 预热）：
#   tools/run_headless_script.sh res://tools/check_compile.gd
# 可选：传入扫描根目录（默认扫描常用脚本目录）
#   tools/run_headless_script.sh res://tools/check_compile.gd res://core res://gameplay

extends SceneTree

const ResultClass = preload("res://core/types/result.gd")
const NAME := "CheckCompile"
const DEFAULT_ROOTS: Array[String] = [
	"res://autoload",
	"res://core",
	"res://gameplay",
	"res://modules",
	"res://modules_test",
	"res://tools",
	"res://ui",
]

static func run_scan(roots: Array[String] = []):
	var scan_roots: Array[String] = []
	if roots.is_empty():
		scan_roots = DEFAULT_ROOTS.duplicate()
	else:
		scan_roots = roots.duplicate()

	var normalized_roots: Array[String] = []
	for root in scan_roots:
		var s: String = str(root).strip_edges()
		if s.is_empty():
			continue
		normalized_roots.append(s)

	var errors: Array[String] = []
	var files_checked := 0
	for root in normalized_roots:
		files_checked += _scan_dir_static(root, errors)

	if errors.is_empty():
		return ResultClass.success({
			"roots": normalized_roots,
			"files_checked": files_checked,
			"errors": [],
		})

	var preview: Array[String] = []
	for i in range(min(errors.size(), 50)):
		preview.append(errors[i])

	return ResultClass.failure("检查到 %d 个编译/预加载错误（files=%d）" % [errors.size(), files_checked]).with_value({
		"roots": normalized_roots,
		"files_checked": files_checked,
		"errors": errors,
		"preview": preview,
	})

func _initialize() -> void:
	_register_core_global_classes()
	var roots := _get_roots()
	print("[%s] START roots=%s" % [NAME, str(roots)])

	var scan_result = run_scan(roots)
	var details: Dictionary = scan_result.value if (scan_result.value is Dictionary) else {}
	var files_checked := int(details.get("files_checked", 0))
	var errors: Array[String] = Array(details.get("errors", []), TYPE_STRING, "", null)

	if scan_result.ok:
		print("[%s] PASS files=%d" % [NAME, files_checked])
		quit(0)
		return

	push_error("[%s] FAIL count=%d (showing first 50)" % [NAME, errors.size()])
	for i in range(min(errors.size(), 50)):
		push_error(errors[i])
	quit(1)

func _register_core_global_classes() -> void:
	# 在干净工作区中运行 headless 脚本时，class_name 缓存可能尚未生成。
	# 先显式加载常用全局脚本，避免后续 scan 因类型解析顺序报伪错误。
	var bootstrap_paths := [
		"res://core/types/result.gd",
		"res://core/modules/v2/module_dir_spec.gd",
		"res://ui/audio/sound_manager.gd",
		"res://ui/audio/music_manager.gd",
		"res://ui/components/modal_dialog/modal_dialog_base.gd",
	]
	for path in bootstrap_paths:
		var script = load(path)
		if script == null:
			push_warning("预注册全局脚本失败: %s" % path)

func _get_roots() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return DEFAULT_ROOTS.duplicate()

	var roots: Array[String] = []
	for i in range(args.size()):
		var v = args[i]
		if not (v is String):
			continue
		var s: String = str(v)
		if s.is_empty():
			continue
		roots.append(s)
	return roots

func _scan_dir(dir_path: String, errors: Array[String]) -> int:
	return _scan_dir_static(dir_path, errors)

static func _scan_dir_static(dir_path: String, errors: Array[String]) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		errors.append("无法读取目录: %s" % dir_path)
		return 0

	var checked := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = dir.get_next()
			continue

		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			checked += _scan_dir_static(path, errors)
		else:
			if name.to_lower().ends_with(".gd"):
				checked += 1
				var res = load(path)
				if res == null:
					errors.append("load 失败: %s" % path)
				elif res is Script:
					var script: Script = res
					if not script.can_instantiate():
						errors.append("脚本无法实例化（可能存在编译错误）: %s" % path)

		name = dir.get_next()
	dir.list_dir_end()
	return checked
