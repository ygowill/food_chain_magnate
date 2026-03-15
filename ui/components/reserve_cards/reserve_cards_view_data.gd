class_name ReserveCardsViewData
extends RefCounted

static func resolve_viewer_player_id(state: GameState) -> int:
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		return int(NetContext.get_command_privacy_viewer_player_id())
	if state != null:
		var cur := int(state.get_current_player_id())
		if cur >= 0:
			return cur
	return -1

static func build_player_sections(state: GameState, viewer_player_id: int = -999) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.players is Array):
		return out

	var viewer_id := viewer_player_id
	if viewer_id == -999:
		viewer_id = resolve_viewer_player_id(state)

	for player_id in range(state.players.size()):
		var player_val = state.players[player_id]
		if not (player_val is Dictionary):
			continue
		var player: Dictionary = player_val
		var cards_val = player.get("reserve_cards", [])
		if not (cards_val is Array):
			cards_val = []
		var cards: Array = cards_val

		var selected_index := _read_selected_index(player)
		var revealed_selected := bool(player.get("reserve_card_revealed", false))
		var can_view_all := _can_view_all_reserve_cards(viewer_id, player_id, state)
		var visible_selected := can_view_all or revealed_selected or viewer_id == player_id

		var card_entries: Array[Dictionary] = []
		var selected_card_val = cards[selected_index] if selected_index >= 0 and selected_index < cards.size() else null
		var show_selected_card := can_view_all or viewer_id == player_id or revealed_selected
		card_entries.append(build_card_entry(selected_card_val, selected_index, show_selected_card, visible_selected))

		out.append({
			"player_id": player_id,
			"viewer_player_id": viewer_id,
			"can_view_all": can_view_all,
			"revealed_selected": revealed_selected,
			"selected_index": selected_index if visible_selected else -1,
			"selection_text": _build_selection_text(player_id, viewer_id, can_view_all, revealed_selected, selected_index),
			"cards": card_entries,
		})

	return out

static func build_card_entry(card_val, index: int, visible: bool, selected: bool) -> Dictionary:
	if not visible:
		return {
			"index": index,
			"visible": false,
			"selected": false,
			"title": "未公开",
			"desc": "",
			"summary": "未公开",
		}

	var card: Dictionary = card_val if (card_val is Dictionary) else {}
	var details := describe_card(card, index)
	details["visible"] = true
	details["selected"] = selected
	return details

static func describe_card(card: Dictionary, index: int) -> Dictionary:
	var option_text := "已选储备卡"
	var has_bank_fields := (
		card.has("cash") and (card.get("cash", null) is int)
		and card.has("ceo_slots") and (card.get("ceo_slots", null) is int)
	)

	if has_bank_fields:
		var cash := int(card.get("cash", 0))
		var slots := int(card.get("ceo_slots", 0))
		var title := option_text
		var desc := "起始现金：+$%d\nCEO 卡槽：%d" % [cash, slots]
		var summary_parts: Array[String] = []
		if index >= 0:
			summary_parts.append("选项#%d" % (index + 1))
		summary_parts.append("注资 $%d" % cash)
		summary_parts.append("CEO 槽位 %d" % slots)
		return {
			"index": index,
			"title": title,
			"desc": desc,
			"summary": "，".join(summary_parts),
		}
	var price := _read_int(card.get("type", null), -1)
	var price_text := "$?" if price < 0 else "$%d" % price
	return {
		"index": index,
		"title": option_text,
		"desc": "基础单价候选：%s\n首次破产后按多数决定（平局 20 > 5 > 10）" % price_text,
		"summary": "选项#%d，基础单价候选 %s" % [index + 1, price_text],
	}

static func format_revealed_card_summary(card: Dictionary, selected_index: int) -> String:
	var details := describe_card(card, maxi(selected_index, 0))
	return str(details.get("summary", "")).strip_edges()

static func _build_selection_text(player_id: int, viewer_player_id: int, can_view_all: bool, revealed_selected: bool, selected_index: int) -> String:
	if viewer_player_id == player_id:
		if selected_index >= 0:
			return "你已选择：储备卡 %d" % (selected_index + 1)
		return "你的储备卡"
	if can_view_all:
		if selected_index >= 0:
			return "已选择：储备卡 %d（里程碑能力可查看全部）" % (selected_index + 1)
		return "里程碑能力可查看全部储备卡"
	if revealed_selected:
		if selected_index >= 0:
			return "仅公开已选项：储备卡 %d" % (selected_index + 1)
		return "已公开选中的储备卡"
	return "未公开"

static func _can_view_all_reserve_cards(viewer_player_id: int, player_id: int, state: GameState) -> bool:
	if viewer_player_id < 0:
		return true
	if viewer_player_id == player_id:
		return true
	if state == null or not (state.players is Array):
		return false
	if viewer_player_id >= state.players.size():
		return false
	var viewer_val = state.players[viewer_player_id]
	if not (viewer_val is Dictionary):
		return false
	var viewer: Dictionary = viewer_val
	var v = viewer.get("can_peek_all_reserve_cards", false)
	return (v is bool) and bool(v)

static func _read_selected_index(player: Dictionary) -> int:
	var idx_val = player.get("reserve_card_selected", -1)
	return _read_int(idx_val, -1)

static func _read_int(value, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return fallback
