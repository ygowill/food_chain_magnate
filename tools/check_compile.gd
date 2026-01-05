# 编译/预加载检查（Headless）
# 用途：快速发现“脚本语法错误导致 preload/load 失败”的问题。
# 运行示例（推荐与 tests 一致的 HOME/log-file，避免沙箱下 user:// 写入崩溃）：
#   PROJECT_PATH="/path/to/project"
#   mkdir -p "$PROJECT_PATH/.tmp_home" "$PROJECT_PATH/.godot"
#   HOME="$PROJECT_PATH/.tmp_home" godot --headless --log-file "$PROJECT_PATH/.godot/CheckCompile.log" --path "$PROJECT_PATH" --script res://tools/check_compile.gd
# 可选：传入扫描根目录（默认扫描常用脚本目录）
#   godot --headless --path . --script res://tools/check_compile.gd -- res://core res://gameplay

extends SceneTree

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

func _initialize() -> void:
	var roots := _get_roots()
	print("[%s] START roots=%s" % [NAME, str(roots)])

	var errors: Array[String] = []
	var files_checked := 0

	for root in roots:
		files_checked += _scan_dir(root, errors)

	if errors.is_empty():
		print("[%s] PASS files=%d" % [NAME, files_checked])
		quit(0)
		return

	push_error("[%s] FAIL count=%d (showing first 50)" % [NAME, errors.size()])
	for i in range(min(errors.size(), 50)):
		push_error(errors[i])
	quit(1)

func _get_roots() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return DEFAULT_ROOTS

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
			checked += _scan_dir(path, errors)
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
