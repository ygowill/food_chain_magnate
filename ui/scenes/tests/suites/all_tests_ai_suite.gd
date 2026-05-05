# AI boundary tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	return [
		{
			"name": "ObservationAdapterTest",
			"fn": func() -> Result: return TestRefs.ObservationAdapterTestClass.run(2, 12345),
		},
	]
