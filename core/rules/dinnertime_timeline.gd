class_name DinnertimeTimeline
extends RefCounted

# DinnertimeTimeline：晚餐结算“时间线事件”约定（供 UI 按支付完成顺序展示反馈）。
#
# 目前仅用于里程碑提示（kind="milestone"），但 schema 允许未来扩展更多事件类型。
#
# 存储位置：
#   state.round_state["dinnertime"]["timeline_events"] = Array[Dictionary]
#
# 事件（milestone）建议结构：
#   {
#     "kind": "milestone",
#     "timeline_stage": "sale"|"post_income"|"end",
#     "sale_index": int,                 # stage="sale" 时必填
#     "post_income_kind": String,        # stage="post_income" 时必填（例如 "tips"/"cfo"）
#     "payment_amount": int,             # stage="post_income" 时必填
#     "player_id": int,
#     "milestone_id": String,
#   }

const KEY_DINNERTIME := "dinnertime"
const KEY_TIMELINE_EVENTS := "timeline_events"

const KEY_KIND := "kind"
const KIND_MILESTONE := "milestone"

const KEY_STAGE := "timeline_stage"
const STAGE_SALE := "sale"
const STAGE_POST_INCOME := "post_income"
const STAGE_END := "end"

const KEY_SALE_INDEX := "sale_index"
const KEY_POST_INCOME_KIND := "post_income_kind"
const KEY_PAYMENT_AMOUNT := "payment_amount"

const KEY_PLAYER_ID := "player_id"
const KEY_MILESTONE_ID := "milestone_id"

static func ensure_state_timeline_events(state: GameState) -> Array:
	if state == null:
		return []
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var rs: Dictionary = state.round_state

	var ds: Dictionary = {}
	var ds_val = rs.get(KEY_DINNERTIME, null)
	if ds_val is Dictionary:
		ds = ds_val

	var events_val = ds.get(KEY_TIMELINE_EVENTS, null)
	if events_val is Array:
		return events_val as Array

	ds[KEY_TIMELINE_EVENTS] = []
	rs[KEY_DINNERTIME] = ds
	state.round_state = rs
	return ds[KEY_TIMELINE_EVENTS]

static func append_milestone_event(out_events: Array, player_id: int, milestone_id: String, meta: Dictionary = {}) -> void:
	if out_events == null:
		return
	var mid := str(milestone_id).strip_edges()
	if player_id < 0 or mid.is_empty():
		return

	var evt := {
		KEY_KIND: KIND_MILESTONE,
		KEY_PLAYER_ID: player_id,
		KEY_MILESTONE_ID: mid,
	}
	if meta != null and meta is Dictionary:
		for k in meta.keys():
			if not (k is String):
				continue
			evt[str(k)] = meta[k]
	out_events.append(evt)

static func append_sale_milestone(out_events: Array, sale_index: int, player_id: int, milestone_id: String) -> void:
	append_milestone_event(out_events, player_id, milestone_id, {
		KEY_STAGE: STAGE_SALE,
		KEY_SALE_INDEX: int(sale_index),
	})

static func append_post_income_milestone(out_events: Array, post_income_kind: String, player_id: int, payment_amount: int, milestone_id: String) -> void:
	append_milestone_event(out_events, player_id, milestone_id, {
		KEY_STAGE: STAGE_POST_INCOME,
		KEY_POST_INCOME_KIND: str(post_income_kind).strip_edges(),
		KEY_PAYMENT_AMOUNT: int(payment_amount),
	})

static func append_end_milestone(out_events: Array, player_id: int, milestone_id: String) -> void:
	append_milestone_event(out_events, player_id, milestone_id, {
		KEY_STAGE: STAGE_END,
	})

static func snapshot_milestones_by_player(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.players is Array):
		return out
	for pid in range(state.players.size()):
		out.append(snapshot_player_milestone_set(state, pid))
	return out

static func snapshot_player_milestone_set(state: GameState, player_id: int) -> Dictionary:
	var set := {}
	if state == null or not (state.players is Array):
		return set
	if player_id < 0 or player_id >= state.players.size():
		return set
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return set
	var player: Dictionary = player_val
	var ms_val = player.get("milestones", null)
	if not (ms_val is Array):
		return set
	for mid_val in Array(ms_val):
		if mid_val is String:
			var mid := str(mid_val).strip_edges()
			if not mid.is_empty():
				set[mid] = true
	return set

static func append_new_milestone_events_from_diff(
	out_events: Array,
	before_by_player: Array[Dictionary],
	after_by_player: Array[Dictionary],
	meta: Dictionary
) -> void:
	if out_events == null:
		return
	var count := mini(before_by_player.size(), after_by_player.size())
	for pid in range(count):
		append_new_milestone_events_for_player_from_diff(out_events, pid, before_by_player[pid], after_by_player[pid], meta)

static func append_new_milestone_events_for_player_from_diff(
	out_events: Array,
	player_id: int,
	before_set: Dictionary,
	after_set: Dictionary,
	meta: Dictionary
) -> void:
	if out_events == null:
		return
	if player_id < 0:
		return
	if not (before_set is Dictionary and after_set is Dictionary):
		return

	var claimed: Array[String] = []
	for mid_val in after_set.keys():
		var mid := str(mid_val).strip_edges()
		if mid.is_empty():
			continue
		if before_set.has(mid):
			continue
		claimed.append(mid)
	if claimed.is_empty():
		return
	claimed.sort()

	for mid in claimed:
		append_milestone_event(out_events, player_id, mid, meta)

