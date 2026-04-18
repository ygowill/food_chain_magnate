# CommandRunner：事件构建（日志/展示语义）
# 该文件位于 gameplay 层：用于 UI/回放/日志从 state 差异推导事件，不属于 core 执行内核。
extends RefCounted

const DinnertimeEventsClass = preload("res://gameplay/replay/command_runner_event_build/dinnertime_events.gd")
const MarketingEventsClass = preload("res://gameplay/replay/command_runner_event_build/marketing_events.gd")
const CleanupEventsClass = preload("res://gameplay/replay/command_runner_event_build/cleanup_events.gd")
const OrderOfBusinessEventsClass = preload("res://gameplay/replay/command_runner_event_build/order_of_business_events.gd")
const PaydayEventsClass = preload("res://gameplay/replay/command_runner_event_build/payday_events.gd")
const RoundEventsClass = preload("res://gameplay/replay/command_runner_event_build/round_events.gd")
const PhaseEventsClass = preload("res://gameplay/replay/command_runner_event_build/phase_events.gd")
const MilestoneEventsClass = preload("res://gameplay/replay/command_runner_event_build/milestone_events.gd")
const CashEventsClass = preload("res://gameplay/replay/command_runner_event_build/cash_events.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func build_milestone_achieved_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	return MilestoneEventsClass.build_milestone_achieved_events(old_state, new_state, command)

static func build_phase_change_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events

	# 阶段变化事件
	if old_state.phase != new_state.phase:
		# 最终行动顺序落地事件（首轮 OrderOfBusiness auto finalize 依赖此事件用于日志显示/回放恢复）。
		events.append_array(OrderOfBusinessEventsClass.build_turn_order_finalized_events(old_state, new_state))

		# Payday 结算报告：在离开 Payday 时发射（PaydaySettlement 在 exit hook 运行，报告写入 new_state.round_state.payday）。
		events.append_array(PaydayEventsClass.build_payday_report_events(old_state, new_state))

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == DefsClass.PHASE_MARKETING:
			events.append_array(MarketingEventsClass.build_marketing_demand_generated_events(old_state))
			events.append_array(MarketingEventsClass.build_marketing_expired_events(old_state))

		events.append_array(PhaseEventsClass.build_phase_changed_events(old_state, new_state))

		# Dinnertime 结算报告：在进入 Dinnertime 时发射（结算在 enter hook 运行，报告写入 new_state.round_state.dinnertime）。
		events.append_array(DinnertimeEventsClass.build_dinnertime_report_events(old_state, new_state))

		# Cleanup 库存丢弃：在进入 Cleanup 时发射（清理结算在 Cleanup:enter 运行）。
		if str(new_state.phase) == DefsClass.PHASE_CLEANUP:
			events.append_array(CleanupEventsClass.build_cleanup_inventory_discarded_events(new_state))

		# 回合开始/结束事件
		events.append_array(RoundEventsClass.build_round_boundary_events(old_state, new_state))

	# 子阶段变化事件
	events.append_array(PhaseEventsClass.build_sub_phase_changed_events(old_state, new_state))

	return events

static func build_payday_report_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	return PaydayEventsClass.build_payday_report_events(old_state, new_state)

static func build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	return DinnertimeEventsClass.build_food_sold_events_from_dinnertime_report(dinnertime_state, report)

static func build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	return MarketingEventsClass.build_marketing_demand_generated_events(marketing_state)

static func build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	return MarketingEventsClass.build_marketing_expired_events(marketing_state)

static func build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	return CleanupEventsClass.build_cleanup_inventory_discarded_events(cleanup_state)

static func build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	return CashEventsClass.build_player_cash_changed_events(old_state, new_state, command)
