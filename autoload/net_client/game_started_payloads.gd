# NetClient server helper：构造 rpc_game_started payload。
extends RefCounted

const RESUME_BOOTSTRAP_MODE_FULL_ARCHIVE_SNAPSHOT := "full_archive_snapshot"

static func build_for_room_peer(room, peer_id: int) -> Dictionary:
	var payload := {
		"player_id_by_peer_id": room.player_id_by_peer_id.duplicate(true),
		"config": room.config.duplicate(true),
		"local_player_id": room.get_seat_index_for_peer(peer_id) if room.has_method("get_seat_index_for_peer") else -1,
	}
	return mark_resume_archive_bootstrap(payload, room)

static func mark_resume_archive_bootstrap(payload: Dictionary, room) -> Dictionary:
	if room != null and room.has_method("is_resume_archive_room") and room.is_resume_archive_room():
		payload["resume_bootstrap_mode"] = RESUME_BOOTSTRAP_MODE_FULL_ARCHIVE_SNAPSHOT
	return payload
