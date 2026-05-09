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
			"name": "CandidateGeneratorTest",
			"fn": func() -> Result: return TestRefs.CandidateGeneratorTestClass.run(2, 12345),
		},
		{
			"name": "GreedySearchTest",
			"fn": func() -> Result: return TestRefs.GreedySearchTestClass.run(2, 12345),
		},
		{
			"name": "OSLASearchTest",
			"fn": func() -> Result: return TestRefs.OSLASearchTestClass.run(2, 12345),
		},
		{
			"name": "BeamSearchTest",
			"fn": func() -> Result: return TestRefs.BeamSearchTestClass.run(2, 12345),
		},
		{
			"name": "MCTSSearchTest",
			"fn": func() -> Result: return TestRefs.MCTSSearchTestClass.run(2, 12345),
		},
		{
			"name": "BotSelfplaySummaryTest",
			"fn": func() -> Result: return TestRefs.BotSelfplaySummaryTestClass.run(2, 12345),
		},
		{
			"name": "BotSelfplayToolTest",
			"fn": func() -> Result: return TestRefs.BotSelfplayToolTestClass.run(2, 12345),
		},
		{
			"name": "BotSelfplayMatrixTest",
			"fn": func() -> Result: return TestRefs.BotSelfplayMatrixTestClass.run(2, 12345),
		},
		{
			"name": "GreedyBotSmokeTest",
			"fn": func() -> Result: return TestRefs.GreedyBotSmokeTestClass.run(2, 12345),
		},
		{
			"name": "StrategyBotTest",
			"fn": func() -> Result: return TestRefs.StrategyBotTestClass.run(2, 12345),
		},
		{
			"name": "StrategyBotScenarioBenchmarkTest",
			"fn": func() -> Result: return TestRefs.StrategyBotScenarioBenchmarkTestClass.run(2, 12345),
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
		{
			"name": "MarketingPreviewGoldenTest",
			"fn": func() -> Result: return TestRefs.MarketingPreviewGoldenTestClass.run(2, 12345),
		},
		{
			"name": "PaydayPreviewGoldenTest",
			"fn": func() -> Result: return TestRefs.PaydayPreviewGoldenTestClass.run(2, 12345),
		},
		{
			"name": "CleanupPreviewGoldenTest",
			"fn": func() -> Result: return TestRefs.CleanupPreviewGoldenTestClass.run(2, 12345),
		},
	]
