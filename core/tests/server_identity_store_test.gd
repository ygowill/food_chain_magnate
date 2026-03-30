# Dedicated Server：game_server_id 持久化
class_name ServerIdentityStoreTest
extends RefCounted

const StoreClass = preload("res://server/server_identity_store.gd")

static func run() -> Result:
	var store := StoreClass.new("user://server_identity_store_test.cfg")
	var first_r: Result = store.load_or_create(7000)
	if not first_r.ok:
		return Result.failure("load_or_create(first) 失败: %s" % first_r.error)
	var first: Dictionary = Dictionary(first_r.value)
	var first_id := str(first.get("game_server_id", "")).strip_edges()
	if first_id.is_empty():
		return Result.failure("first game_server_id 为空")

	var second_r: Result = store.load_or_create(7000)
	if not second_r.ok:
		return Result.failure("load_or_create(second) 失败: %s" % second_r.error)
	var second: Dictionary = Dictionary(second_r.value)
	var second_id := str(second.get("game_server_id", "")).strip_edges()
	if second_id != first_id:
		return Result.failure("持久化 identity 不稳定: %s vs %s" % [first_id, second_id])

	return Result.success({
		"game_server_id": first_id,
	})
