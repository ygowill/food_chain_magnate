extends RefCounted

func register(registrar) -> Result:
	var r = registrar.register_effect("good_effects:test_effect", Callable(self, "_on_test_effect"))
	if not r.ok:
		return r
	return Result.success()

func _on_test_effect(_state: GameState, _player_id: int, _ctx: Dictionary) -> Result:
	return Result.success()

