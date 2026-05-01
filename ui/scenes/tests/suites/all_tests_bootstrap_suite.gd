# Bootstrap smoke and compile tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(host) -> Array[Dictionary]:
	var h = host
	var tests: Array[Dictionary] = [
		{
			"name": "GameSmokeTest",
			"fn": func() -> Result: return await h._run_game_smoke_test(),
		},
		{
			"name": "CheckCompileTest",
			"fn": func() -> Result: return h._run_check_compile_test(),
		},
	]
	return tests
