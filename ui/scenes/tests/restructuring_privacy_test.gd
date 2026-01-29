# Restructuring 隐私：Online 禁止查看他人；Hotseat 已提交锁定
extends RefCounted

const RestructuringModalClass = preload("res://ui/components/modal_panel/restructuring_modal.gd")

static func run() -> Result:
	var r1 := _case_hotseat_submitted_locked()
	if not r1.ok:
		return r1
	var r2 := _case_online_only_local_selectable()
	if not r2.ok:
		return r2
	var r3 := _case_online_spectator_all_disabled()
	if not r3.ok:
		return r3
	return Result.success()

static func _case_hotseat_submitted_locked() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()

	var modal = RestructuringModalClass.new()
	var host := HBoxContainer.new()
	modal.add_child(host)
	modal.set("player_buttons_host", host)

	modal.set_player_switcher(3, 0, {0: false, 1: true, 2: false})

	if host.get_child_count() != 3:
		_safe_free(modal)
		return Result.failure("Hotseat: player_buttons 数量错误: %d" % host.get_child_count())

	var b0: Button = host.get_child(0)
	var b1: Button = host.get_child(1)
	var b2: Button = host.get_child(2)
	if b0.disabled:
		_safe_free(modal)
		return Result.failure("Hotseat: 未提交玩家(0)不应禁用")
	if not b1.disabled:
		_safe_free(modal)
		return Result.failure("Hotseat: 已提交玩家(1)应禁用")
	if b2.disabled:
		_safe_free(modal)
		return Result.failure("Hotseat: 未提交玩家(2)不应禁用")

	_safe_free(modal)
	return Result.success()

static func _case_online_only_local_selectable() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	if NetContext != null:
		NetContext.mode = NetContext.Mode.ONLINE_CLIENT
		NetContext.local_player_id = 1

	var modal = RestructuringModalClass.new()
	var host := HBoxContainer.new()
	modal.add_child(host)
	modal.set("player_buttons_host", host)

	modal.set_player_switcher(3, 1, {0: false, 1: false, 2: true})

	var b0: Button = host.get_child(0)
	var b1: Button = host.get_child(1)
	var b2: Button = host.get_child(2)
	if not b0.disabled:
		_safe_free(modal)
		return Result.failure("Online: 非本地玩家(0)应禁用")
	if b1.disabled:
		_safe_free(modal)
		return Result.failure("Online: 本地玩家(1)不应禁用")
	if not b2.disabled:
		_safe_free(modal)
		return Result.failure("Online: 非本地玩家(2)应禁用（即便未提交也不可查看）")

	_safe_free(modal)
	return Result.success()

static func _case_online_spectator_all_disabled() -> Result:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
	if NetContext != null:
		NetContext.mode = NetContext.Mode.ONLINE_CLIENT
		NetContext.local_player_id = -1

	var modal = RestructuringModalClass.new()
	var host := HBoxContainer.new()
	modal.add_child(host)
	modal.set("player_buttons_host", host)

	modal.set_player_switcher(2, -1, {0: false, 1: false})

	for ch in host.get_children():
		if ch is Button and not (ch as Button).disabled:
			_safe_free(modal)
			return Result.failure("Online spectator: 所有玩家按钮都应禁用")

	_safe_free(modal)
	return Result.success()

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
