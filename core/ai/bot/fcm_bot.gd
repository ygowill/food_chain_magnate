class_name FcmBot
extends RefCounted

func choose_command(
	_observation: ObservationState,
	_context: AiDecisionContext,
	_legal_action_ids: Array[String],
	_validate_command: Callable = Callable(),
	_budget: TimeBudget = null
) -> BotDecision:
	return BotDecision.failure("FcmBot.choose_command is not implemented")
