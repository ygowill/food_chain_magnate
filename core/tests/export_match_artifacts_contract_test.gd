class_name ExportMatchArtifactsContractTest
extends RefCounted

const ExporterClass = preload("res://tools/export_match_artifacts_from_replay.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	var round_end_r: Result = ExporterClass._final_snapshot_event_for_latest_autosave(
		_FakeCommand.new(DefsClass.PHASE_CLEANUP),
		_FakeState.new(DefsClass.PHASE_RESTRUCTURING, 3)
	)
	if not round_end_r.ok:
		return Result.failure("round_end snapshot event 应可导出: %s" % round_end_r.error)
	var round_end_event: Dictionary = Dictionary(round_end_r.value)
	if int(round_end_event.get("round_number", -1)) != 2 or str(round_end_event.get("snapshot_kind", "")) != "round_end":
		return Result.failure("round_end snapshot event 内容错误: %s" % str(round_end_event))

	var game_over_r: Result = ExporterClass._final_snapshot_event_for_latest_autosave(
		_FakeCommand.new(DefsClass.PHASE_CLEANUP),
		_FakeState.new(DefsClass.PHASE_GAME_OVER, 4)
	)
	if not game_over_r.ok:
		return Result.failure("game_over snapshot event 应可导出: %s" % game_over_r.error)
	var game_over_event: Dictionary = Dictionary(game_over_r.value)
	if int(game_over_event.get("round_number", -1)) != 3 or str(game_over_event.get("snapshot_kind", "")) != "game_over":
		return Result.failure("game_over snapshot event 内容错误: %s" % str(game_over_event))

	var ambiguous_r: Result = ExporterClass._final_snapshot_event_for_latest_autosave(
		_FakeCommand.new(DefsClass.PHASE_WORKING),
		_FakeState.new(DefsClass.PHASE_WORKING, 2)
	)
	if ambiguous_r.ok:
		return Result.failure("非 round snapshot 最终状态不应被 latest autosave 猜测为成功")
	if str(ambiguous_r.error).find("不是明确的 round snapshot event") < 0:
		return Result.failure("非 snapshot 失败原因应说明缺少明确事件: %s" % ambiguous_r.error)

	return Result.success()

class _FakeCommand:
	extends RefCounted

	var phase: String = ""

	func _init(p_phase: String) -> void:
		phase = p_phase

class _FakeState:
	extends RefCounted

	var phase: String = ""
	var round_number: int = 0

	func _init(p_phase: String, p_round_number: int) -> void:
		phase = p_phase
		round_number = int(p_round_number)
