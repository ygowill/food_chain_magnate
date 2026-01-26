# Timeline event formatting helpers (replay/log derived view)
# - Centralizes event envelope fields: sequence/timestamp/command_index
# - Provides StepTimelineBuild helpers to inject step_index/phase_segment consistently
extends RefCounted

static func append_timeline_event(
	out: Array[Dictionary],
	event_type: String,
	data: Dictionary,
	seq_in: int,
	command_index: int
) -> int:
	var t := str(event_type).strip_edges()
	if t.is_empty():
		return int(seq_in)
	var d: Dictionary = data if (data is Dictionary) else {}
	var seq := int(seq_in) + 1
	out.append({
		"type": t,
		"data": d,
		"sequence": seq,
		"timestamp": seq,
		"command_index": int(command_index),
	})
	return seq

static func append_step_event(
	out: Array[Dictionary],
	event_type: String,
	data: Dictionary,
	seq_in: int,
	command_index: int,
	step_index: int,
	phase_segment: String
) -> int:
	var t := str(event_type).strip_edges()
	if t.is_empty():
		return int(seq_in)

	var d: Dictionary = data.duplicate(true) if (data is Dictionary) else {}
	d["command_index"] = int(command_index)
	d["step_index"] = int(step_index)

	var seq := int(seq_in) + 1
	out.append({
		"type": t,
		"data": d,
		"sequence": seq,
		"timestamp": seq,
		"command_index": int(command_index),
		"step_index": int(step_index),
		"phase_segment": str(phase_segment),
	})
	return seq

static func append_step_events(
	out: Array[Dictionary],
	events: Array[Dictionary],
	seq_in: int,
	command_index: int,
	step_index: int,
	phase_segment: String
) -> int:
	var seq := int(seq_in)
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t: String = str(ev.get("type", "")).strip_edges()
		if t.is_empty():
			continue
		var d_val = ev.get("data", {})
		var d: Dictionary = d_val if (d_val is Dictionary) else {}
		seq = append_step_event(out, t, d, seq, command_index, step_index, phase_segment)
	return seq
