class_name OnlineResumeDeltaStoreContractTest
extends RefCounted

const RoomClass = preload("res://server/room.gd")

class _HashState:
	extends RefCounted

	var _hash: String = "hash_after"

	func compute_hash() -> String:
		return _hash

class _FakeEngine:
	extends RefCounted

	var command_history: Array = []
	var fail_create_archive: bool = false
	var state := _HashState.new()

	func create_archive() -> Result:
		if fail_create_archive:
			return Result.failure("archive boom")
		return Result.success({
			"version": 1,
			"commands": [],
			"final_hash": state.compute_hash(),
		})

	func get_state():
		return state

static func run() -> Result:
	var init_failure_r := _case_checkpoint_init_failure_is_returned()
	if not init_failure_r.ok:
		return init_failure_r

	var success_r := _case_success_records_delta()
	if not success_r.ok:
		return success_r

	var rotate_failure_r := _case_checkpoint_rotate_failure_is_returned()
	if not rotate_failure_r.ok:
		return rotate_failure_r

	return Result.success({
		"init_failure": init_failure_r.value,
		"success": success_r.value,
		"rotate_failure": rotate_failure_r.value,
	})

static func _case_checkpoint_init_failure_is_returned() -> Result:
	var room := RoomClass.new("DR01", 1, "public", "", {"desired_player_count": 2})
	var engine := _FakeEngine.new()
	engine.command_history = [Command.create_system("noop")]
	engine.fail_create_archive = true
	room.status = RoomClass.STATUS_IN_GAME
	room.game_engine = engine

	var record_r: Result = room.record_resume_delta(Command.create_system("noop"), "hash_after")
	if record_r.ok:
		return Result.failure("checkpoint init failure should be returned")
	if not str(record_r.error).contains("checkpoint init failed"):
		return Result.failure("unexpected init failure error: %s" % record_r.error)
	if room._resume_delta_store.get_delta_count() != 0:
		return Result.failure("checkpoint init failure should not append delta")
	return Result.success(record_r.error)

static func _case_success_records_delta() -> Result:
	var room := RoomClass.new("DR02", 1, "public", "", {"desired_player_count": 2})
	var engine := _FakeEngine.new()
	engine.command_history = [Command.create_system("noop")]
	engine.state._hash = "hash_before"
	room.status = RoomClass.STATUS_IN_GAME
	room.game_engine = engine
	var checkpoint_r: Result = room._reset_recovery_store_from_current_engine("manual")
	if not checkpoint_r.ok:
		return Result.failure("checkpoint setup should succeed: %s" % checkpoint_r.error)
	engine.state._hash = "hash_after"

	var record_r: Result = room.record_resume_delta(Command.create_system("noop"), "")
	if not record_r.ok:
		return Result.failure("record_resume_delta should succeed: %s" % record_r.error)
	var delta_log := room._resume_delta_store.get_delta_log_snapshot()
	if delta_log.size() != 1:
		return Result.failure("expected one delta entry, got %d" % delta_log.size())
	var entry: Dictionary = delta_log[0]
	if int(entry.get("sequence", -1)) != 1:
		return Result.failure("unexpected delta sequence: %s" % str(entry.get("sequence", null)))
	if str(entry.get("post_state_hash", "")) != "hash_after":
		return Result.failure("post_state_hash should use current state hash when omitted")
	return Result.success(record_r.value)

static func _case_checkpoint_rotate_failure_is_returned() -> Result:
	var room := RoomClass.new("DR03", 1, "public", "", {"desired_player_count": 2})
	var engine := _FakeEngine.new()
	engine.state._hash = "hash_before"
	room.status = RoomClass.STATUS_IN_GAME
	room.game_engine = engine
	var checkpoint_r: Result = room._reset_recovery_store_from_current_engine("manual")
	if not checkpoint_r.ok:
		return Result.failure("checkpoint setup should succeed: %s" % checkpoint_r.error)
	for i in range(RoomClass.RESUME_DELTA_ROTATE_COMMAND_THRESHOLD):
		engine.command_history.append(Command.create_system("noop"))
	engine.state._hash = "hash_after"
	engine.fail_create_archive = true

	var record_r: Result = room.record_resume_delta(Command.create_system("noop"), "hash_after")
	if record_r.ok:
		return Result.failure("checkpoint rotate failure should be returned")
	if not str(record_r.error).contains("checkpoint rotate failed"):
		return Result.failure("unexpected rotate failure error: %s" % record_r.error)
	if room._resume_delta_store.get_delta_count() != 1:
		return Result.failure("rotate failure should keep the just recorded delta for diagnostics")
	return Result.success(record_r.error)
