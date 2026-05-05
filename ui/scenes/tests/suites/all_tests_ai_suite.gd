# AI boundary tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	return [
		{
			"name": "ObservationAdapterTest",
			"fn": func() -> Result: return TestRefs.ObservationAdapterTestClass.run(2, 12345),
		},
		{
			"name": "BoardAnalyzerTest",
			"fn": func() -> Result: return TestRefs.BoardAnalyzerTestClass.run(2, 12345),
		},
		{
			"name": "LegalActionServiceTest",
			"fn": func() -> Result: return TestRefs.LegalActionServiceTestClass.run(2, 12345),
		},
		{
			"name": "RandomLegalBotSmokeTest",
			"fn": func() -> Result: return TestRefs.RandomLegalBotSmokeTestClass.run(2, 12345),
		},
		{
			"name": "AiEngineForkTest",
			"fn": func() -> Result: return TestRefs.AiEngineForkTestClass.run(2, 12345),
		},
		{
			"name": "ForwardSimulatorTest",
			"fn": func() -> Result: return TestRefs.ForwardSimulatorTestClass.run(2, 12345),
		},
		{
			"name": "DinnerPreviewGoldenTest",
			"fn": func() -> Result: return TestRefs.DinnerPreviewGoldenTestClass.run(2, 12345),
		},
	]
