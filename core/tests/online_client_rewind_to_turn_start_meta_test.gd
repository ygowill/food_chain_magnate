# Online client：回退元数据应走独立通道，不再混入 resync archive
class_name OnlineClientRewindToTurnStartMetaTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode := NetContext.mode
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "RWMD01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}

	var payload := {
		"request_id": "req_rewind_meta",
		"room_code": "RWMD01",
		"target_index": 3,
		"before_index": 7,
		"history_size": 4,
		"state_hash": "hash_after_rewind",
		"noop": false,
	}
	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)
	client.handle_rpc_rewind_to_turn_start_meta(payload)

	if mock_net.rewind_meta_payloads.size() != 1:
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta 应发出一次独立信号: %s" % str(mock_net.rewind_meta_payloads))
	var received: Dictionary = Dictionary(mock_net.rewind_meta_payloads[0]).duplicate(true)
	if str(received.get("request_id", "")) != "req_rewind_meta":
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta request_id 错误: %s" % str(received))
	if int(received.get("target_index", -1)) != 3:
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta target_index 错误: %s" % str(received))
	if int(received.get("history_size", -1)) != 4:
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta history_size 错误: %s" % str(received))
	if mock_net._pending_resync_archive.has("_rewind_to_turn_start"):
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta 不应再落到 pending archive: %s" % str(mock_net._pending_resync_archive))
	if str(mock_net._pending_rewind_to_turn_start_meta.get("request_id", "")) != "req_rewind_meta":
		_restore(prev_mode, prev_room_state)
		return Result.failure("rewind meta 应缓存在独立 pending 区: %s" % str(mock_net._pending_rewind_to_turn_start_meta))

	_restore(prev_mode, prev_room_state)
	return Result.success()

static func _restore(prev_mode, prev_room_state: Dictionary) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)

class _MockNet:
	extends RefCounted

	signal rewind_to_turn_start_meta_received(payload: Dictionary)

	var _pending_resync_archive: Dictionary = {}
	var _pending_rewind_to_turn_start_meta: Dictionary = {}
	var rewind_meta_payloads: Array[Dictionary] = []

	func _init() -> void:
		rewind_to_turn_start_meta_received.connect(func(payload: Dictionary) -> void:
			rewind_meta_payloads.append(Dictionary(payload).duplicate(true))
		)
