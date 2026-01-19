# 回放播放器启动回归测试（无需渲染）
# 覆盖：ReplayPlayer.load_from_file 不应因缺失 GameEngine API 而崩溃，且应能成功载入存档并步进。
class_name ReplayPlayerSmokeTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const ReplayPlayerScene = preload("res://ui/components/replay_player/replay_player.tscn")

static func run() -> Result:
	# 生成一个最小可回放的存档文件（避免依赖工作区中的特定 .json）
	var engine := GameEngine.new()
	var init_result: Result = engine.initialize(2, 12345)
	if not init_result.ok:
		return Result.failure("初始化失败: %s" % init_result.error)
	var setup_result: Result = TestPhaseUtilsClass.complete_setup(engine)
	if not setup_result.ok:
		return Result.failure("Setup 构造失败: %s" % setup_result.error)
	var tmp_path := "user://replay_player_smoke.json"
	var save_result: Result = engine.save_to_file(tmp_path)
	if not save_result.ok:
		return Result.failure("写入临时存档失败: %s" % save_result.error)

	var player: ReplayPlayer = ReplayPlayerScene.instantiate()
	if player == null or not is_instance_valid(player):
		return Result.failure("无法实例化 ReplayPlayer")

	# 由于本测试不是通过场景树驱动 `_ready()`，这里直接调用内部初始化逻辑。
	player._setup_ui()
	player._connect_signals()

	var load_result: Result = player.load_from_file(tmp_path)
	if not load_result.ok:
		_safe_free(player)
		return Result.failure("ReplayPlayer 载入失败: %s" % load_result.error)

	var loaded_engine: GameEngine = player.get_game_engine()
	if loaded_engine == null:
		_safe_free(player)
		return Result.failure("ReplayPlayer.get_game_engine 为空")

	var command_count := player.get_command_count()
	if command_count <= 0:
		_safe_free(player)
		return Result.failure("命令数量应 > 0，实际: %d" % command_count)

	# 能步进到第一条命令（0），说明 seek/rewind 链路可用。
	var seek_result: Result = player.seek_to(0)
	if not seek_result.ok:
		_safe_free(player)
		return Result.failure("seek_to(0) 失败: %s" % seek_result.error)

	_safe_free(player)
	return Result.success({
		"commands": command_count,
	})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
