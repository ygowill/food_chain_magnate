# 存档/回放 Fail Fast 回归测试（T1 扩展）
# 覆盖：
# - archive.schema_version / archive.current_index 的严格整数解析（拒绝非整数 float）
# - archive.current_index 缺失/越界必须直接失败（不允许默认值继续跑）
class_name ArchiveFailFastTest
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 生成至少 1 条命令，便于验证 commands 的 fail-fast 解析
	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("预置命令 advance_phase 失败: %s" % adv.error)

	var archive_result := engine.create_archive()
	if not archive_result.ok:
		return Result.failure("创建存档失败: %s" % archive_result.error)
	var base_archive: Dictionary = archive_result.value

	var r1 := _case_missing_current_index(base_archive)
	if not r1.ok:
		return r1

	var r2 := _case_schema_version_non_integer_float(base_archive)
	if not r2.ok:
		return r2

	var r3 := _case_current_index_non_integer_float(base_archive)
	if not r3.ok:
		return r3

	var r4 := _case_current_index_out_of_range(base_archive)
	if not r4.ok:
		return r4

	var r5 := _case_command_timestamp_missing(base_archive)
	if not r5.ok:
		return r5

	var r6 := _case_command_timestamp_non_integer_float(base_archive)
	if not r6.ok:
		return r6

	return Result.success({
		"cases": 6,
	})

static func _case_missing_current_index(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	archive.erase("current_index")

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("current_index 缺失时应失败，但返回 ok")
	if str(load.error).find("current_index") < 0:
		return Result.failure("错误信息应包含 current_index，实际: %s" % str(load.error))
	return Result.success()

static func _case_schema_version_non_integer_float(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	archive["schema_version"] = 2.5

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("schema_version=2.5 时应失败，但返回 ok")
	var err := str(load.error)
	if err.find("schema_version") < 0 or err.find("必须为整数") < 0:
		return Result.failure("错误信息应包含 schema_version 与 必须为整数，实际: %s" % err)
	return Result.success()

static func _case_current_index_non_integer_float(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	archive["current_index"] = 0.5

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("current_index=0.5 时应失败，但返回 ok")
	var err := str(load.error)
	if err.find("current_index") < 0 or err.find("必须为整数") < 0:
		return Result.failure("错误信息应包含 current_index 与 必须为整数，实际: %s" % err)
	return Result.success()

static func _case_current_index_out_of_range(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	archive["current_index"] = 999

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("current_index 越界时应失败，但返回 ok")
	var err := str(load.error)
	if err.find("无效的 current_index") < 0:
		return Result.failure("错误信息应包含 '无效的 current_index'，实际: %s" % err)
	return Result.success()

static func _case_command_timestamp_missing(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	if not archive.has("commands") or not (archive["commands"] is Array):
		return Result.failure("测试前提不成立：archive.commands 缺失或类型错误")
	var commands: Array = archive["commands"]
	if commands.is_empty():
		return Result.failure("测试前提不成立：archive.commands 不能为空")
	if not (commands[0] is Dictionary):
		return Result.failure("测试前提不成立：commands[0] 类型错误")
	var cmd0: Dictionary = commands[0].duplicate(true)
	cmd0.erase("timestamp")
	commands[0] = cmd0
	archive["commands"] = commands

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("commands[0].timestamp 缺失时应失败，但返回 ok")
	var err := str(load.error)
	if err.find("timestamp") < 0:
		return Result.failure("错误信息应包含 timestamp，实际: %s" % err)
	return Result.success()

static func _case_command_timestamp_non_integer_float(base_archive: Dictionary) -> Result:
	var archive := base_archive.duplicate(true)
	if not archive.has("commands") or not (archive["commands"] is Array):
		return Result.failure("测试前提不成立：archive.commands 缺失或类型错误")
	var commands: Array = archive["commands"]
	if commands.is_empty():
		return Result.failure("测试前提不成立：archive.commands 不能为空")
	if not (commands[0] is Dictionary):
		return Result.failure("测试前提不成立：commands[0] 类型错误")
	var cmd0: Dictionary = commands[0].duplicate(true)
	cmd0["timestamp"] = 1.5
	commands[0] = cmd0
	archive["commands"] = commands

	var engine := GameEngine.new()
	var load := engine.load_from_archive(archive)
	if load.ok:
		return Result.failure("commands[0].timestamp=1.5 时应失败，但返回 ok")
	var err := str(load.error)
	if err.find("timestamp") < 0 or err.find("必须为整数") < 0:
		return Result.failure("错误信息应包含 timestamp 与 必须为整数，实际: %s" % err)
	return Result.success()
