extends RefCounted

const CommandClass = preload("res://core/types/command.gd")

const ACTION_ROAD := "place_lobbyists_road"
const ACTION_PARK := "place_lobbyists_park"

static func normalize_action(action_id: String) -> String:
	var aid := str(action_id).strip_edges()
	if aid == ACTION_ROAD or aid == ACTION_PARK:
		return aid
	return ""

static func build_command(
	state,
	action_id: String,
	actor_id: int,
	position: Vector2i,
	rotation: int,
	piece_id: String,
	employee_type: String,
	staff_id: int
) -> Result:
	if state == null:
		return Result.failure("LobbyistsPlacementCommandBuilder.build_command: state 为空")
	if actor_id < 0:
		return Result.failure("LobbyistsPlacementCommandBuilder.build_command: actor_id 非法")

	var aid := normalize_action(action_id)
	if aid.is_empty():
		return Result.failure("LobbyistsPlacementCommandBuilder.build_command: 未支持的 action_id=%s" % action_id)

	var params_read := build_params(position, rotation, piece_id, employee_type, staff_id)
	if not params_read.ok:
		return params_read

	var command = CommandClass.new()
	command.action_id = aid
	command.actor = int(actor_id)
	command.params = Dictionary(params_read.value).duplicate(true)
	command.phase = str(state.phase)
	command.sub_phase = str(state.sub_phase)
	return Result.success(command)

static func build_params(
	position: Vector2i,
	rotation: int,
	piece_id: String,
	employee_type: String,
	staff_id: int
) -> Result:
	var pid := str(piece_id).strip_edges()
	if pid.is_empty():
		return Result.failure("LobbyistsPlacementCommandBuilder.build_params: piece_id 不能为空")
	if position == Vector2i(-1, -1):
		return Result.failure("LobbyistsPlacementCommandBuilder.build_params: position 未选择")

	var out := {
		"piece_id": pid,
		"anchor_pos": [position.x, position.y],
		"rotation": int(rotation),
	}
	var emp_type := str(employee_type).strip_edges()
	if not emp_type.is_empty():
		out["employee_type"] = emp_type
		if int(staff_id) > 0:
			out["staff_id"] = int(staff_id)
	return Result.success(out)
