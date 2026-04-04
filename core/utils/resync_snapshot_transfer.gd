extends RefCounted

const TRANSFER_VERSION := 1

static func build_snapshot_transfer(
	archive: Dictionary,
	transfer_id: String,
	chunk_size_bytes: int,
	max_chunks: int
) -> Result:
	var normalized_transfer_id := str(transfer_id).strip_edges()
	if normalized_transfer_id.is_empty():
		return Result.failure("snapshot transfer_id missing")
	if chunk_size_bytes <= 0:
		return Result.failure("snapshot chunk_size invalid")
	if max_chunks <= 0:
		return Result.failure("snapshot max_chunks invalid")

	var archive_bytes: PackedByteArray = var_to_bytes(Dictionary(archive).duplicate(true))
	var total_bytes := archive_bytes.size()
	var chunk_count := maxi(1, int(ceili(float(total_bytes) / float(chunk_size_bytes))))
	if chunk_count > max_chunks:
		return Result.failure("snapshot chunk_count exceeded: %d > %d" % [chunk_count, max_chunks])

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(archive_bytes)
	var archive_hash := ctx.finish().hex_encode()

	var chunks: Array[Dictionary] = []
	for chunk_index in range(chunk_count):
		var start := chunk_index * chunk_size_bytes
		var end := mini(start + chunk_size_bytes, total_bytes)
		var chunk_bytes := PackedByteArray()
		for byte_index in range(start, end):
			chunk_bytes.append(archive_bytes[byte_index])
		chunks.append({
			"transfer_id": normalized_transfer_id,
			"chunk_index": chunk_index,
			"bytes": chunk_bytes,
		})

	return Result.success({
		"manifest": {
			"transfer_id": normalized_transfer_id,
			"transfer_version": TRANSFER_VERSION,
			"chunk_size_bytes": chunk_size_bytes,
			"chunk_count": chunk_count,
			"total_bytes": total_bytes,
			"archive_hash": archive_hash,
		},
		"chunks": chunks,
		"chunk_count": chunk_count,
		"total_bytes": total_bytes,
		"archive_hash": archive_hash,
	})

static func assemble_snapshot(manifest: Dictionary, chunks_by_index: Dictionary) -> Result:
	var transfer_id := str(manifest.get("transfer_id", "")).strip_edges()
	if transfer_id.is_empty():
		return Result.failure("snapshot transfer_id missing")
	var chunk_count := int(manifest.get("chunk_count", 0))
	if chunk_count <= 0:
		return Result.failure("snapshot chunk_count invalid")
	var total_bytes := int(manifest.get("total_bytes", -1))
	if total_bytes < 0:
		return Result.failure("snapshot total_bytes invalid")
	var expected_hash := str(manifest.get("archive_hash", "")).strip_edges()
	if expected_hash.is_empty():
		return Result.failure("snapshot archive_hash missing")

	var archive_bytes := PackedByteArray()
	for chunk_index in range(chunk_count):
		if not chunks_by_index.has(chunk_index):
			return Result.failure("snapshot missing chunk: %d" % chunk_index)
		var chunk_val = chunks_by_index.get(chunk_index, null)
		if not (chunk_val is PackedByteArray):
			return Result.failure("snapshot chunk bytes invalid: %d" % chunk_index)
		var chunk_bytes: PackedByteArray = chunk_val
		archive_bytes.append_array(chunk_bytes)

	if archive_bytes.size() != total_bytes:
		return Result.failure(
			"snapshot total_bytes mismatch: %d != %d" % [archive_bytes.size(), total_bytes]
		)

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(archive_bytes)
	var actual_hash := ctx.finish().hex_encode()
	if actual_hash != expected_hash:
		return Result.failure("snapshot archive_hash mismatch")

	var archive_val = bytes_to_var(archive_bytes)
	if not (archive_val is Dictionary):
		return Result.failure("snapshot bytes decode failed")
	return Result.success(Dictionary(archive_val).duplicate(true))
