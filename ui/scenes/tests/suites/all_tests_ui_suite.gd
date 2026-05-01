# UI privacy, modal, action panel, and left panel tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
		{
			"name": "GameOverWinnerRulesTest",
			"fn": func() -> Result: return TestRefs.GameOverWinnerRulesTestClass.run(),
		},
		{
			"name": "CommandPrivacyTest",
			"fn": func() -> Result: return TestRefs.CommandPrivacyTestClass.run(),
		},
			{
				"name": "ReserveCardSelectionModalPrivacyTest",
				"fn": func() -> Result: return TestRefs.ReserveCardSelectionModalPrivacyTestClass.run(),
			},
			{
				"name": "ReserveCardSelectionModalPresentationTest",
				"fn": func() -> Result: return TestRefs.ReserveCardSelectionModalPresentationTestClass.run(),
			},
			{
				"name": "ModalOverlayOpacityContractTest",
				"fn": func() -> Result: return await TestRefs.ModalOverlayOpacityContractTestClass.run(),
			},
			{
				"name": "EntityTabReserveCardPrivacyTest",
				"fn": func() -> Result: return TestRefs.EntityTabReserveCardPrivacyTestClass.run(),
			},
			{
				"name": "ReserveCardsOverviewAccessTest",
				"fn": func() -> Result: return TestRefs.ReserveCardsOverviewAccessTestClass.run(),
			},
			{
				"name": "ReserveCardsFullScreenViewPrivacyTest",
				"fn": func() -> Result: return await TestRefs.ReserveCardsFullScreenViewPrivacyTestClass.run(),
			},
			{
				"name": "GameOverlayFirstHave20PopupTest",
				"fn": func() -> Result: return await TestRefs.GameOverlayFirstHave20PopupTestClass.run(),
			},
			{
				"name": "UiSyncFirstHave20PopupTest",
				"fn": func() -> Result: return TestRefs.UiSyncFirstHave20PopupTestClass.run(),
			},
			{
				"name": "TimelineUiStateSupportBatchUpdateTest",
				"fn": func() -> Result: return TestRefs.TimelineUiStateSupportBatchUpdateTestClass.run(),
			},
			{
				"name": "UiComponentsBinderBatchContextTest",
				"fn": func() -> Result: return TestRefs.UiComponentsBinderBatchContextTestClass.run(),
			},
			{
				"name": "ReplayBarSupportNoopTest",
				"fn": func() -> Result: return TestRefs.ReplayBarSupportNoopTestClass.run(),
			},
			{
				"name": "TurnOrderSelectionModalOnlineVisibilityTest",
				"fn": func() -> Result: return TestRefs.TurnOrderSelectionModalOnlineVisibilityTestClass.run(),
			},
			{
				"name": "RoomConfigEditorEditableSignalTest",
				"fn": func() -> Result: return TestRefs.RoomConfigEditorEditableSignalTestClass.run(),
			},
			{
				"name": "ActionPanelOnlineLocalPlayerTest",
				"fn": func() -> Result: return TestRefs.ActionPanelOnlineLocalPlayerTestClass.run(),
			},
			{
				"name": "ActionPanelGlobalDisabledRestoreTest",
				"fn": func() -> Result: return TestRefs.ActionPanelGlobalDisabledRestoreTestClass.run(),
			},
			{
				"name": "ActionPanelRefreshSingleRebuildTest",
				"fn": func() -> Result: return await TestRefs.ActionPanelRefreshSingleRebuildTestClass.run(),
			},
			{
				"name": "ActionFlowControlsNoopTest",
				"fn": func() -> Result: return await TestRefs.ActionFlowControlsNoopTestClass.run(),
			},
			{
				"name": "DinnertimeAnimationCompletionTest",
				"fn": func() -> Result: return TestRefs.DinnertimeAnimationCompletionTestClass.run(),
			},
			{
				"name": "ActionPanelExternalBlockReasonTest",
				"fn": func() -> Result: return await TestRefs.ActionPanelExternalBlockReasonTestClass.run(),
			},
			{
				"name": "ActionPanelExecutorMetadataTest",
				"fn": func() -> Result: return TestRefs.ActionPanelExecutorMetadataTestClass.run(),
			},
			{
				"name": "ActionPanelHideNonInitiatableSpecialActionsTest",
				"fn": func() -> Result: return TestRefs.ActionPanelHideNonInitiatableSpecialActionsTestClass.run(),
			},
			{
				"name": "ActionPanelRestaurantDualActionsTest",
				"fn": func() -> Result: return await TestRefs.ActionPanelRestaurantDualActionsTestClass.run(),
			},
			{
				"name": "LeftPanelSelectionIsolationTest",
				"fn": func() -> Result: return TestRefs.LeftPanelSelectionIsolationTestClass.run(),
			},
			{
				"name": "LeftPanelViewSelectionPersistenceTest",
				"fn": func() -> Result: return await TestRefs.LeftPanelViewSelectionPersistenceTestClass.run(),
			},
			{
				"name": "LeftPanelBusyMarketersGroupTest",
				"fn": func() -> Result: return TestRefs.LeftPanelBusyMarketersGroupTestClass.run(),
			},
			{
				"name": "LeftPanelOnlineStatusBadgeTest",
				"fn": func() -> Result: return await TestRefs.LeftPanelOnlineStatusBadgeTestClass.run(),
			},
	]
	return tests
