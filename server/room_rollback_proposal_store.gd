extends RefCounted

var _pending: Dictionary = {}

func has_pending() -> bool:
	return not _pending.is_empty()

func create(
	proposal_id: String,
	proposer_peer_id: int,
	proposer_player_id: int,
	target_index: int,
	before_index: int,
	history_size: int,
	required_player_ids: Array[int],
	reason: String
) -> Result:
	if has_pending():
		return Result.failure("Rollback proposal already pending")

	var votes := {}
	votes[int(proposer_player_id)] = true
	var rid := str(proposal_id).strip_edges()
	if rid.is_empty():
		rid = "rollback_%d" % int(Time.get_ticks_msec())
	var required := required_player_ids.duplicate()
	required.sort()
	_pending = {
		"proposal_id": rid,
		"proposer_peer_id": int(proposer_peer_id),
		"proposer_player_id": int(proposer_player_id),
		"target_index": int(target_index),
		"before_index": int(before_index),
		"history_size_at_proposal": int(history_size),
		"reason": str(reason).strip_edges(),
		"created_at_ms": int(Time.get_ticks_msec()),
		"required_player_ids": required,
		"votes": votes,
	}
	return Result.success(public_payload())

func vote(proposal_id: String, voter_player_id: int, approve: bool) -> Result:
	if _pending.is_empty():
		return Result.failure("No rollback proposal pending")
	var pid := int(voter_player_id)
	var current_id := str(_pending.get("proposal_id", "")).strip_edges()
	if current_id != str(proposal_id).strip_edges():
		return Result.failure("Rollback proposal id mismatch")
	if pid == int(_pending.get("proposer_player_id", -1)):
		return Result.failure("Proposer vote is already recorded")
	var required: Array = Array(_pending.get("required_player_ids", []))
	if not required.has(pid):
		return Result.failure("Player is not required to vote")
	if not bool(approve):
		var rejected := public_payload()
		rejected["status"] = "rejected"
		rejected["rejected_by_player_id"] = pid
		_pending = {}
		return Result.success(rejected)

	var votes: Dictionary = Dictionary(_pending.get("votes", {})).duplicate(true)
	votes[pid] = true
	_pending["votes"] = votes
	var approved := true
	for required_pid in required:
		if not bool(votes.get(int(required_pid), false)):
			approved = false
			break
	var out := public_payload()
	out["status"] = "approved" if approved else "pending"
	return Result.success(out)

func consume() -> Dictionary:
	var out := _pending.duplicate(true)
	_pending = {}
	return out

func clear() -> bool:
	if _pending.is_empty():
		return false
	_pending = {}
	return true

func public_payload() -> Dictionary:
	if _pending.is_empty():
		return {}
	return {
		"proposal_id": str(_pending.get("proposal_id", "")).strip_edges(),
		"proposer_player_id": int(_pending.get("proposer_player_id", -1)),
		"target_index": int(_pending.get("target_index", -1)),
		"before_index": int(_pending.get("before_index", -1)),
		"history_size_at_proposal": int(_pending.get("history_size_at_proposal", -1)),
		"reason": str(_pending.get("reason", "")).strip_edges(),
		"created_at_ms": int(_pending.get("created_at_ms", 0)),
		"required_player_ids": Array(_pending.get("required_player_ids", [])).duplicate(),
		"votes": Dictionary(_pending.get("votes", {})).duplicate(true),
		"status": "pending",
	}
