# Dinnertime, settlement, confirmation, and end-condition tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
			{
				"name": "MarketingDinnertimeGoldenReplayTest",
				"fn": func() -> Result: return TestRefs.MarketingDinnertimeGoldenReplayTestClass.run(2, 12345),
			},
			{
				"name": "MilestoneEffectValuesTest",
				"fn": func() -> Result: return TestRefs.MilestoneEffectValuesTestClass.run(2, 12345),
			},
			{
				"name": "RandomMapGenerationTest",
				"fn": func() -> Result: return TestRefs.RandomMapGenerationTestClass.run(2, 12345),
			},
			{
				"name": "DinnertimeSettlementTest",
				"fn": func() -> Result: return TestRefs.DinnertimeSettlementTestClass.run(2, 12345),
			},
			{
				"name": "DinnertimeSkippedRequiredTest",
				"fn": func() -> Result: return TestRefs.DinnertimeSkippedRequiredTestClass.run(2, 12345),
			},
			{
				"name": "DinnertimeDistanceEntryBoundaryTest",
				"fn": func() -> Result: return TestRefs.DinnertimeDistanceEntryBoundaryTestClass.run(2, 12345),
			},
			{
				"name": "ConfirmDinnertimePendingPhaseActionsKeyTest",
				"fn": func() -> Result: return TestRefs.ConfirmDinnertimePendingPhaseActionsKeyTestClass.run(2, 12345),
			},
			{
				"name": "ConfirmMarketingPendingPhaseActionsKeyTest",
				"fn": func() -> Result: return TestRefs.ConfirmMarketingPendingPhaseActionsKeyTestClass.run(2, 12345),
			},
			{
				"name": "MarketingAnimationOrdersBuilderTest",
				"fn": func() -> Result: return TestRefs.MarketingAnimationOrdersBuilderTestClass.run(),
			},
			{
				"name": "ManualMarketingReviewSaveTest",
				"fn": func() -> Result: return TestRefs.ManualMarketingReviewSaveTestClass.run(),
			},
			{
				"name": "ConfirmDinnertimeStateAccessTest",
				"fn": func() -> Result: return TestRefs.ConfirmDinnertimeStateAccessTestClass.run(2, 12345),
			},
			{
				"name": "OnlineDinnertimeConfirmEnforcedTest",
				"fn": func() -> Result: return TestRefs.OnlineDinnertimeConfirmEnforcedTestClass.run(2, 12345),
			},
			{
				"name": "OnlinePhaseInteractionDinnertimeTest",
				"fn": func() -> Result: return TestRefs.OnlinePhaseInteractionDinnertimeTestClass.run(),
			},
			{
				"name": "BankruptcyTest",
				"fn": func() -> Result: return TestRefs.BankruptcyTestClass.run(2, 12345),
			},
		{
			"name": "DistanceOverlayRoadworksPenaltyTest",
			"fn": func() -> Result: return TestRefs.DistanceOverlayRoadworksPenaltyTestClass.run(),
		},
	]
	return tests
