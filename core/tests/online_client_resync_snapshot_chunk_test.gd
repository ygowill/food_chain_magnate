# Online client：chunked snapshot 组装后再发出一次性 archive 恢复信号
class_name OnlineClientResyncSnapshotChunkTest
extends RefCounted

const ClientLogicClass = preload("res://autoload/net_client/client.gd")
const ResyncSnapshotTransferClass = preload("res://core/utils/resync_snapshot_transfer.gd")

static func run() -> Result:
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	var prev_mode := NetContext.mode
	var prev_room_state := Dictionary(NetContext.room_state).duplicate(true)

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.room_state = {
		"room_code": "SNAP01",
		"status": "InGame",
		"players": [],
		"spectators": [],
	}

	var archive := {
		"blob": "snapshot_chunk_test_payload_".repeat(64),
		"meta": {
			"room_code": "SNAP01",
			"history_size": 9,
		},
		"numbers": [1, 2, 3, 5, 8, 13],
	}
	var transfer_r: Result = ResyncSnapshotTransferClass.build_snapshot_transfer(archive, "snapshot_transfer_test", 96, 64)
	if not transfer_r.ok:
		_restore(prev_mode, prev_room_state)
		return Result.failure("build_snapshot_transfer 失败: %s" % transfer_r.error)
	var transfer: Dictionary = Dictionary(transfer_r.value)
	var manifest: Dictionary = Dictionary(transfer.get("manifest", {})).duplicate(true)
	manifest["room_code"] = "SNAP01"
	var chunks: Array = Array(transfer.get("chunks", [])).duplicate(true)
	if chunks.size() < 2:
		_restore(prev_mode, prev_room_state)
		return Result.failure("测试需要多 chunk snapshot，实际=%d" % chunks.size())

	var mock_net := _MockNet.new()
	var client = ClientLogicClass.new()
	client.setup(mock_net)

	client.handle_rpc_resync_snapshot_chunk(Dictionary(chunks[0]))
	if not mock_net.archive_payloads.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("manifest 之前收到 chunk 不应直接完成恢复")

	client.handle_rpc_resync_snapshot_manifest(manifest)
	for i in range(chunks.size() - 1, -1, -1):
		client.handle_rpc_resync_snapshot_chunk(Dictionary(chunks[i]))

	if mock_net.archive_payloads.size() != 1:
		_restore(prev_mode, prev_room_state)
		return Result.failure("chunk 组装完成后应发出一次 archive_received: %s" % str(mock_net.archive_payloads))
	var received: Dictionary = Dictionary(mock_net.archive_payloads[0]).duplicate(true)
	if str(received.get("blob", "")) != str(archive.get("blob", "")):
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装后的 blob 不一致")
	var received_meta: Dictionary = Dictionary(received.get("meta", {}))
	if str(received_meta.get("room_code", "")) != "SNAP01":
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装后的 meta.room_code 不一致: %s" % str(received_meta))
	if Array(received.get("numbers", [])).size() != 6:
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装后的 numbers 不一致: %s" % str(received.get("numbers", null)))
	if not mock_net._pending_resync_snapshot_manifest.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装完成后应清理 pending manifest")
	if not mock_net._pending_resync_snapshot_chunks.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装完成后应清理 pending chunks")
	if str(mock_net._pending_resync_archive.get("blob", "")) != str(archive.get("blob", "")):
		_restore(prev_mode, prev_room_state)
		return Result.failure("组装完成后应缓存 pending archive")

	_restore(prev_mode, prev_room_state)
	return Result.success()

static func _restore(prev_mode, prev_room_state: Dictionary) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)

class _MockNet:
	extends RefCounted

	signal resync_archive_received(archive: Dictionary)

	var _pending_resync_archive: Dictionary = {}
	var _pending_resync_snapshot_manifest: Dictionary = {}
	var _pending_resync_snapshot_chunks: Dictionary = {}
	var archive_payloads: Array[Dictionary] = []

	func _init() -> void:
		resync_archive_received.connect(func(archive: Dictionary) -> void:
			archive_payloads.append(Dictionary(archive).duplicate(true))
		)
