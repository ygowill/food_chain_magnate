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

	var bad_mock_net := _MockNet.new()
	var bad_client = ClientLogicClass.new()
	bad_client.setup(bad_mock_net)
	var bad_chunks: Array = []
	for chunk_val in chunks:
		bad_chunks.append(Dictionary(chunk_val).duplicate(true))
	var bad_chunk: Dictionary = Dictionary(bad_chunks[0]).duplicate(true)
	var bad_bytes := PackedByteArray(bad_chunk.get("bytes", PackedByteArray()))
	if bad_bytes.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("测试 chunk bytes 不能为空")
	bad_bytes[0] = int(bad_bytes[0] + 1) % 256
	bad_chunk["bytes"] = bad_bytes
	bad_chunks[0] = bad_chunk
	bad_client.handle_rpc_resync_snapshot_manifest(manifest.duplicate(true))
	for bad_chunk_val in bad_chunks:
		bad_client.handle_rpc_resync_snapshot_chunk(Dictionary(bad_chunk_val))
	if bad_mock_net.archive_payloads.size() != 0:
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot 不应发出 archive_received: %s" % str(bad_mock_net.archive_payloads))
	if bad_mock_net.resync_failures.size() != 1:
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot 应发出一次 resync failure: %s" % str(bad_mock_net.resync_failures))
	if str(bad_mock_net.resync_failures[0]).find("分片组装失败") < 0:
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot failure 应包含组装失败原因: %s" % str(bad_mock_net.resync_failures[0]))
	if not bad_mock_net._pending_resync_snapshot_manifest.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot 失败后应清理 pending manifest")
	if not bad_mock_net._pending_resync_snapshot_chunks.is_empty():
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot 失败后应清理 pending chunks")
	if not bad_mock_net.resume_force_snapshot_requested:
		_restore(prev_mode, prev_room_state)
		return Result.failure("坏 snapshot 失败后应请求下一次 resume 强制 snapshot")

	_restore(prev_mode, prev_room_state)
	return Result.success()

static func _restore(prev_mode, prev_room_state: Dictionary) -> void:
	NetContext.mode = prev_mode
	NetContext.room_state = prev_room_state.duplicate(true)

class _MockNet:
	extends RefCounted

	signal resync_archive_received(archive: Dictionary)
	signal resync_delta_failed(message: String)

	var _pending_resync_archive: Dictionary = {}
	var _pending_resync_snapshot_manifest: Dictionary = {}
	var _pending_resync_snapshot_chunks: Dictionary = {}
	var archive_payloads: Array[Dictionary] = []
	var resync_failures: Array[String] = []
	var resume_force_snapshot_requested: bool = false

	func _init() -> void:
		resync_archive_received.connect(func(archive: Dictionary) -> void:
			archive_payloads.append(Dictionary(archive).duplicate(true))
		)
		resync_delta_failed.connect(func(message: String) -> void:
			resync_failures.append(str(message))
		)

	func request_resume_force_snapshot_once() -> void:
		resume_force_snapshot_requested = true
