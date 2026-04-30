# 全部测试计划（由 all_tests.gd 运行器消费）
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
		{
			"name": "ReplayTest",
			"fn": func() -> Result: return TestRefs.ReplayDeterminismTestClass.run(2, 12345, 20),
		},
		{
			"name": "EmployeeTest",
			"fn": func() -> Result: return TestRefs.EmployeeActionTestClass.run(2, 12345),
		},
		{
			"name": "RestructuringOverflowPenaltyTest",
			"fn": func() -> Result: return TestRefs.RestructuringOverflowPenaltyTestClass.run(2, 12345),
		},
		{
			"name": "RestructuringBusyDuplicateEmployeeRegressionTest",
			"fn": func() -> Result: return TestRefs.RestructuringBusyDuplicateEmployeeRegressionTestClass.run(2, 12345),
		},
		{
			"name": "RecruitOnCreditRulesTest",
			"fn": func() -> Result: return TestRefs.RecruitOnCreditRulesTestClass.run(2, 12345),
		},
		{
			"name": "PaydaySalaryTest",
			"fn": func() -> Result: return TestRefs.PaydaySalaryTestClass.run(2, 12345),
		},
		{
			"name": "PaydayReportEventTest",
			"fn": func() -> Result: return TestRefs.PaydayReportEventTestClass.run(2, 12345),
		},
		{
			"name": "GameStateFactoryStartingInventoryTest",
			"fn": func() -> Result: return TestRefs.GameStateFactoryStartingInventoryTestClass.run(),
		},
		{
			"name": "RestaurantLogoAssignmentTest",
			"fn": func() -> Result: return TestRefs.RestaurantLogoAssignmentTestClass.run(6, 12345),
		},
		{
			"name": "RestaurantLogoTexturesLoadedTest",
			"fn": func() -> Result: return TestRefs.RestaurantLogoTexturesLoadedTestClass.run(),
		},
		{
			"name": "SixPlayersSetupTest",
			"fn": func() -> Result: return TestRefs.SixPlayersSetupTestClass.run(12345),
		},
		{
			"name": "ModuleSelectorSetupConstraintsTest",
			"fn": func() -> Result: return TestRefs.ModuleSelectorSetupConstraintsTestClass.run(12345),
		},
		{
			"name": "SetupTutorialTargetsContractTest",
			"fn": func() -> Result: return await TestRefs.SetupTutorialTargetsContractTestClass.run(),
		},
		{
			"name": "GameTutorialTargetsContractTest",
			"fn": func() -> Result: return await TestRefs.GameTutorialTargetsContractTestClass.run(),
		},
		{
			"name": "TutorialSceneBoundaryContractTest",
			"fn": func() -> Result: return TestRefs.TutorialSceneBoundaryContractTestClass.run(),
		},
		{
			"name": "TutorialMatchRuntimeTest",
			"fn": func() -> Result: return TestRefs.TutorialMatchRuntimeTestClass.run(),
		},
		{
			"name": "TutorialSpotlightOverlayStartTest",
			"fn": func() -> Result: return await TestRefs.TutorialSpotlightOverlayStartTestClass.run(),
		},
		{
			"name": "TutorialSpotlightOverlayLayoutTest",
			"fn": func() -> Result: return await TestRefs.TutorialSpotlightOverlayLayoutTestClass.run(),
		},
		{
			"name": "EmployeeTreeTutorialTargetsTest",
			"fn": func() -> Result: return await TestRefs.EmployeeTreeTutorialTargetsTestClass.run(),
		},
		{
			"name": "PaydaySalaryTokenEligibilityTest",
			"fn": func() -> Result: return TestRefs.PaydaySalaryTokenEligibilityTestClass.run(),
		},
		{
			"name": "PaydaySettlementStateAccessTest",
			"fn": func() -> Result: return TestRefs.PaydaySettlementStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "EffectUiTextRegistryTest",
			"fn": func() -> Result: return TestRefs.EffectUiTextRegistryTestClass.run(),
		},
		{
			"name": "MapOverlayProviderRegistryTest",
			"fn": func() -> Result: return TestRefs.MapOverlayProviderRegistryTestClass.run(),
		},
		{
			"name": "CallbackResultContractTest",
			"fn": func() -> Result: return TestRefs.CallbackResultContractTestClass.run(),
		},
		{
			"name": "ModuleBoundaryContractTest",
			"fn": func() -> Result: return TestRefs.ModuleBoundaryContractTestClass.run(),
		},
		{
			"name": "CoreArchitectureBoundaryContractTest",
			"fn": func() -> Result: return TestRefs.CoreArchitectureBoundaryContractTestClass.run(),
		},
		{
			"name": "RulesetUiExtensionsFacadeTest",
			"fn": func() -> Result: return TestRefs.RulesetUiExtensionsFacadeTestClass.run(),
		},
		{
			"name": "CatalogRegistryBundleIsolationTest",
			"fn": func() -> Result: return TestRefs.CatalogRegistryBundleIsolationTestClass.run(),
		},
		{
			"name": "EngineDependenciesInjectionTest",
			"fn": func() -> Result: return TestRefs.EngineDependenciesInjectionTestClass.run(),
		},
		{
			"name": "PlatformApiResponseParseTest",
			"fn": func() -> Result: return TestRefs.PlatformApiResponseParseTestClass.run(),
		},
		{
			"name": "PlatformSessionProfileDeviceIdTest",
			"fn": func() -> Result: return TestRefs.PlatformSessionProfileDeviceIdTestClass.run(),
		},
		{
			"name": "NetContextOnlineResumeTest",
			"fn": func() -> Result: return TestRefs.NetContextOnlineResumeTestClass.run(),
		},
		{
			"name": "NetContextOnlineResumePersistenceTest",
			"fn": func() -> Result: return TestRefs.NetContextOnlineResumePersistenceTestClass.run(),
		},
		{
			"name": "OnlineResumeTerminalRecordTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeTerminalRecordTestClass.run(),
		},
		{
			"name": "NetClientConnectPreserveContextTest",
			"fn": func() -> Result: return TestRefs.NetClientConnectPreserveContextTestClass.run(),
		},
		{
			"name": "OnlineResumeErrorPolicyTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeErrorPolicyTestClass.run(),
		},
		{
			"name": "UiLobbyistsRoadOverlaysHardRefContractTest",
			"fn": func() -> Result: return TestRefs.UiLobbyistsRoadOverlaysHardRefContractTestClass.run(),
		},
			{
				"name": "UiLobbyistsPiecePrefixContractTest",
				"fn": func() -> Result: return TestRefs.UiLobbyistsPiecePrefixContractTestClass.run(),
			},
		{
			"name": "UiMapOptionalPieceIdsContractTest",
			"fn": func() -> Result: return TestRefs.UiMapOptionalPieceIdsContractTestClass.run(),
		},
		{
			"name": "UiMapOverlayPrivateStateContractTest",
			"fn": func() -> Result: return TestRefs.UiMapOverlayPrivateStateContractTestClass.run(),
		},
		{
			"name": "MilestonePanelEffectTextContractTest",
			"fn": func() -> Result: return TestRefs.MilestonePanelEffectTextContractTestClass.run(),
		},
		{
			"name": "MilestoneFullScreenViewCardStateTest",
			"fn": func() -> Result: return await TestRefs.MilestoneFullScreenViewCardStateTestClass.run(),
		},
		{
			"name": "UiModuleSelectorHardcodedModuleIdsContractTest",
			"fn": func() -> Result: return TestRefs.UiModuleSelectorHardcodedModuleIdsContractTestClass.run(),
		},
		{
			"name": "UiBasePiecesLogoHardRefContractTest",
			"fn": func() -> Result: return TestRefs.UiBasePiecesLogoHardRefContractTestClass.run(),
		},
		{
			"name": "UiModulesBaseDirContractTest",
			"fn": func() -> Result: return TestRefs.UiModulesBaseDirContractTestClass.run(),
		},
		{
			"name": "UiProductNameMappingContractTest",
			"fn": func() -> Result: return TestRefs.UiProductNameMappingContractTestClass.run(),
		},
		{
			"name": "UiFryChefEmployeeIdContractTest",
			"fn": func() -> Result: return TestRefs.UiFryChefEmployeeIdContractTestClass.run(),
		},
		{
			"name": "ModuleUiMetadataBootstrapTest",
			"fn": func() -> Result: return TestRefs.ModuleUiMetadataBootstrapTestClass.run(),
		},
		{
			"name": "EmployeeTreeLayoutBottomTagTest",
			"fn": func() -> Result: return TestRefs.EmployeeTreeLayoutBottomTagTestClass.run(),
		},
		{
			"name": "EmployeeCardDescriptionWrapTest",
			"fn": func() -> Result: return TestRefs.EmployeeCardDescriptionWrapTestClass.run(),
		},
		{
			"name": "GamePanelModalsControllerKindContractTest",
			"fn": func() -> Result: return TestRefs.GamePanelModalsControllerKindContractTestClass.run(),
		},
		{
			"name": "ReserveCardModalPendingStateResetTest",
			"fn": func() -> Result: return await TestRefs.ReserveCardModalPendingStateResetTestClass.run(),
		},
		{
			"name": "PhaseActionUiRegistryCleanupTest",
			"fn": func() -> Result: return TestRefs.PhaseActionUiRegistryCleanupTestClass.run(),
		},
		{
			"name": "PhaseActionUiModalRegistrationTest",
			"fn": func() -> Result: return TestRefs.PhaseActionUiModalRegistrationTestClass.run(),
		},
		{
			"name": "PieceUiHintsRegistryLobbyistsTest",
			"fn": func() -> Result: return TestRefs.PieceUiHintsRegistryLobbyistsTestClass.run(),
		},
		{
			"name": "NetClientParseConnectTokenUrlTest",
			"fn": func() -> Result: return TestRefs.NetClientParseConnectTokenUrlTestClass.run(),
		},
		{
			"name": "OnlineClientHelloConnectTokenTest",
			"fn": func() -> Result: return TestRefs.OnlineClientHelloConnectTokenTestClass.run(),
		},
		{
			"name": "PlatformConnectTokenAutoJoinTest",
			"fn": func() -> Result: return TestRefs.PlatformConnectTokenAutoJoinTestClass.run(),
		},
		{
			"name": "OnlineResumeRoomLobbyTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeRoomLobbyTestClass.run(),
		},
		{
			"name": "OnlineResumeArchiveRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeArchiveRecoveryTestClass.run(),
		},
		{
			"name": "OnlineResumeStartValidationTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeStartValidationTestClass.run(),
		},
		{
			"name": "OnlineResumeFullSnapshotBootstrapTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullSnapshotBootstrapTestClass.run(),
		},
		{
			"name": "OnlineResumeSingleFullEngineCacheTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeSingleFullEngineCacheTestClass.run(),
		},
		{
			"name": "OnlineResumeFullHistoryBaselineSelectionTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullHistoryBaselineSelectionTestClass.run(),
		},
		{
			"name": "NetClientOnlineResumeCachedTimelineForwardingTest",
			"fn": func() -> Result: return TestRefs.NetClientOnlineResumeCachedTimelineForwardingTestClass.run(),
		},
		{
			"name": "OnlineResumeFullArchiveExportTest",
			"fn": func() -> Result: return TestRefs.OnlineResumeFullArchiveExportTestClass.run(),
		},
		{
			"name": "OnlineClientDisconnectPreserveContextTest",
			"fn": func() -> Result: return TestRefs.OnlineClientDisconnectPreserveContextTestClass.run(),
		},
		{
			"name": "OnlineClientGameStartedReconnectTest",
			"fn": func() -> Result: return TestRefs.OnlineClientGameStartedReconnectTestClass.run(),
		},
		{
			"name": "OnlineClientConfigBootstrapOverridesTest",
			"fn": func() -> Result: return TestRefs.OnlineClientConfigBootstrapOverridesTestClass.run(),
		},
		{
			"name": "GameMenuDebugControllerOnlineQuitTest",
			"fn": func() -> Result: return TestRefs.GameMenuDebugControllerOnlineQuitTestClass.run(),
		},
		{
			"name": "GameOverOnlineReturnFlowTest",
			"fn": func() -> Result: return TestRefs.GameOverOnlineReturnFlowTestClass.run(),
		},
		{
			"name": "GameMenuDebugControllerOnlineSurrenderQuitTest",
			"fn": func() -> Result: return await TestRefs.GameMenuDebugControllerOnlineSurrenderQuitTestClass.run(),
		},
		{
			"name": "GameMenuControllerOnlineForfeitConfirmTest",
			"fn": func() -> Result: return await TestRefs.GameMenuControllerOnlineForfeitConfirmTestClass.run(),
		},
		{
			"name": "OnlineRoomManagerTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomManagerTestClass.run(),
		},
		{
			"name": "OnlineRoomListTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomListTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomListControllerTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomListControllerTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomStateRendererTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomStateRendererTestClass.run(),
		},
		{
			"name": "OnlineLobbyRoomConfigSyncControllerTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyRoomConfigSyncControllerTestClass.run(),
		},
		{
			"name": "OnlineMatchBootstrapResumeHistoryGateTest",
			"fn": func() -> Result: return TestRefs.OnlineMatchBootstrapResumeHistoryGateTestClass.run(),
		},
		{
			"name": "OnlineMatchBootstrapServerFlowTest",
			"fn": func() -> Result: return TestRefs.OnlineMatchBootstrapServerFlowTestClass.run(),
		},
		{
			"name": "OnlineStartGameReplayTest",
			"fn": func() -> Result: return TestRefs.OnlineStartGameReplayTestClass.run(),
		},
		{
			"name": "MatchFinalizeParticipantLogoPayloadTest",
			"fn": func() -> Result: return TestRefs.MatchFinalizeParticipantLogoPayloadTestClass.run(),
		},
		{
			"name": "OnlineResyncArchiveTest",
			"fn": func() -> Result: return TestRefs.OnlineResyncArchiveTestClass.run(),
		},
		{
			"name": "ServerResyncGuardTest",
			"fn": func() -> Result: return TestRefs.ServerResyncGuardTestClass.run(),
		},
		{
			"name": "OnlineClientResyncSnapshotChunkTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncSnapshotChunkTestClass.run(),
		},
		{
			"name": "OnlineClientRewindToTurnStartMetaTest",
			"fn": func() -> Result: return TestRefs.OnlineClientRewindToTurnStartMetaTestClass.run(),
		},
		{
			"name": "OnlineClientResyncDeltaApplyTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncDeltaApplyTestClass.run(),
		},
		{
			"name": "OnlineClientResyncRoomIsolationTest",
			"fn": func() -> Result: return TestRefs.OnlineClientResyncRoomIsolationTestClass.run(),
		},
		{
			"name": "OnlineRewindToTurnStartTest",
			"fn": func() -> Result: return TestRefs.OnlineRewindToTurnStartTestClass.run(),
		},
		{
			"name": "ForfeitPlayerActionTest",
			"fn": func() -> Result: return TestRefs.ForfeitPlayerActionTestClass.run(),
		},
		{
			"name": "ForfeitPlayerStateAccessTest",
			"fn": func() -> Result: return TestRefs.ForfeitPlayerStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "OnlineRoomSpectatorTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomSpectatorTestClass.run(),
		},
		{
			"name": "OnlineLobbyDisconnectReclaimTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyDisconnectReclaimTestClass.run(),
		},
		{
			"name": "OnlineLobbyDisconnectGraceReleaseTest",
			"fn": func() -> Result: return await TestRefs.OnlineLobbyDisconnectGraceReleaseTestClass.run(),
		},
		{
			"name": "OnlineDisconnectGraceReconnectTest",
			"fn": func() -> Result: return await TestRefs.OnlineDisconnectGraceReconnectTestClass.run(),
		},
		{
			"name": "OnlineForfeitAndLeaveRoomTest",
			"fn": func() -> Result: return TestRefs.OnlineForfeitAndLeaveRoomTestClass.run(),
		},
		{
			"name": "GameOnlineResyncResumeTicketRetryPolicyTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResyncResumeTicketRetryPolicyTestClass.run(),
		},
		{
			"name": "GameOnlineResyncReconnectFlowTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResyncReconnectFlowTestClass.run(),
		},
		{
			"name": "GameOnlineResumeProgressSyncTest",
			"fn": func() -> Result: return await TestRefs.GameOnlineResumeProgressSyncTestClass.run(),
		},
		{
			"name": "GameOnlineResyncRequestRejectionTest",
			"fn": func() -> Result: return TestRefs.GameOnlineResyncRequestRejectionTestClass.run(),
		},
		{
			"name": "OnlineLobbyResumeControllerTest",
			"fn": func() -> Result: return await TestRefs.OnlineLobbyResumeControllerTestClass.run(),
		},
		{
			"name": "OnlineLobbyInGameEntryFallbackTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyInGameEntryFallbackTestClass.run(),
		},
		{
			"name": "OnlineRoomPersistenceRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomPersistenceRecoveryTestClass.run(),
		},
		{
			"name": "OnlineRoundAutosaveTest",
			"fn": func() -> Result: return TestRefs.OnlineRoundAutosaveTestClass.run(),
		},
		{
			"name": "OnlineLobbyPersistenceRecoveryTest",
			"fn": func() -> Result: return TestRefs.OnlineLobbyPersistenceRecoveryTestClass.run(),
		},
		{
			"name": "ServerIdentityStoreTest",
			"fn": func() -> Result: return TestRefs.ServerIdentityStoreTestClass.run(),
		},
		{
			"name": "GameStartupDirectResumeGuardTest",
			"fn": func() -> Result: return TestRefs.GameStartupDirectResumeGuardTestClass.run(),
		},
		{
			"name": "GameStartupOnlineResumeControllerTest",
			"fn": func() -> Result: return await TestRefs.GameStartupOnlineResumeControllerTestClass.run(),
		},
		{
			"name": "OnlineRoomSeedRandomStableTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomSeedRandomStableTestClass.run(),
		},
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
		{
			"name": "InitialCompanyTest",
			"fn": func() -> Result: return TestRefs.InitialCompanyTestClass.run(2, 12345),
		},
		{
			"name": "MandatoryActionsTest",
			"fn": func() -> Result: return TestRefs.MandatoryActionsTestClass.run(2, 12345),
		},
		{
			"name": "TrainPhaseStartCountsStateAccessTest",
			"fn": func() -> Result: return TestRefs.TrainPhaseStartCountsStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "TrainStateAccessTest",
			"fn": func() -> Result: return TestRefs.TrainStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "PriceModifierStateAccessTest",
			"fn": func() -> Result: return TestRefs.PriceModifierStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "SkipMandatoryActionsStateAccessTest",
			"fn": func() -> Result: return TestRefs.SkipMandatoryActionsStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "SkipCleanupPendingRegressionTest",
			"fn": func() -> Result: return TestRefs.SkipCleanupPendingRegressionTestClass.run(2, 12345),
		},
		{
			"name": "BaseRulesPhaseAndMapStateAccessTest",
			"fn": func() -> Result: return TestRefs.BaseRulesPhaseAndMapStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersAutoAdvanceUnblockedTest",
			"fn": func() -> Result: return TestRefs.RuralMarketeersAutoAdvanceUnblockedTestClass.run(2, 12345),
		},
		{
			"name": "ProduceFoodTest",
			"fn": func() -> Result: return TestRefs.ProduceFoodTestClass.run(2, 12345),
		},
		{
			"name": "ProduceFoodStateAccessTest",
			"fn": func() -> Result: return TestRefs.ProduceFoodStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "ProcureDrinksTest",
			"fn": func() -> Result: return TestRefs.ProcureDrinksTestClass.run(2, 12345),
		},
		{
			"name": "ProcureDrinksRouteRulesTest",
			"fn": func() -> Result: return TestRefs.ProcureDrinksRouteRulesTestClass.run(2, 12345),
		},
		{
			"name": "DrinksProcurementStateAccessTest",
			"fn": func() -> Result: return TestRefs.DrinksProcurementStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "AirProcureStartTileChoiceTest",
			"fn": func() -> Result: return TestRefs.AirProcureStartTileChoiceTestClass.run(),
		},
		{
			"name": "RoadProcureStartRestaurantChoiceTest",
			"fn": func() -> Result: return TestRefs.RoadProcureStartRestaurantChoiceTestClass.run(),
		},
		{
			"name": "ProcureDrinksStartRestaurantSelectTest",
			"fn": func() -> Result: return TestRefs.ProcureDrinksStartRestaurantSelectTestClass.run(),
		},
		{
			"name": "PlaceHouseRulesTest",
			"fn": func() -> Result: return TestRefs.PlaceHouseRulesTestClass.run(2, 12345),
		},
		{
			"name": "AddGardenRulesTest",
			"fn": func() -> Result: return TestRefs.AddGardenRulesTestClass.run(2, 12345),
		},
			{
				"name": "PlaceRestaurantRulesTest",
				"fn": func() -> Result: return TestRefs.PlaceRestaurantRulesTestClass.run(2, 12345),
			},
		{
			"name": "MoveRestaurantRulesTest",
			"fn": func() -> Result: return TestRefs.MoveRestaurantRulesTestClass.run(2, 12345),
		},
			{
				"name": "PlacementStaffPickerUiTest",
				"fn": func() -> Result: return await TestRefs.PlacementStaffPickerUiTestClass.run(),
			},
			{
				"name": "WorkingActionFeedbackTest",
				"fn": func() -> Result: return await TestRefs.WorkingActionFeedbackTestClass.run(),
			},
			{
				"name": "EmployeePickerRebuildCleanupTest",
				"fn": func() -> Result: return await TestRefs.EmployeePickerRebuildCleanupTestClass.run(),
			},
		{
			"name": "FailFastParsingTest",
			"fn": func() -> Result: return TestRefs.FailFastParsingTestClass.run(2, 12345),
		},
		{
			"name": "ArchiveFailFastTest",
			"fn": func() -> Result: return TestRefs.ArchiveFailFastTestClass.run(2, 12345),
		},
		{
			"name": "ArchiveFileRoundtripTest",
			"fn": func() -> Result: return TestRefs.ArchiveFileRoundtripTestClass.run(2, 12345),
		},
		{
			"name": "StateSchemaArchiveLoadTest",
			"fn": func() -> Result: return TestRefs.StateSchemaArchiveLoadTestClass.run(2, 12345),
		},
		{
			"name": "StateSchemaUnregisteredModuleKeyWarningTest",
			"fn": func() -> Result: return TestRefs.StateSchemaUnregisteredModuleKeyWarningTestClass.run(2, 12345),
		},
		{
			"name": "InvariantsFailFastTest",
			"fn": func() -> Result: return TestRefs.InvariantsFailFastTestClass.run(2, 12345),
		},
		{
			"name": "RoundStateFailFastTest",
			"fn": func() -> Result: return TestRefs.RoundStateFailFastTestClass.run(2, 12345),
		},
		{
			"name": "RoundStatePlayerBoolFlagsTest",
			"fn": func() -> Result: return TestRefs.RoundStatePlayerBoolFlagsTestClass.run(2, 12345),
		},
		{
			"name": "RoundStateOrderOfBusinessTest",
			"fn": func() -> Result: return TestRefs.RoundStateOrderOfBusinessTestClass.run(2, 12345),
		},
		{
			"name": "RoundStateSubPhasePassedTest",
			"fn": func() -> Result: return TestRefs.RoundStateSubPhasePassedTestClass.run(2, 12345),
		},
		{
			"name": "StaffStateTest",
			"fn": func() -> Result: return TestRefs.StaffStateTestClass.run(2, 12345),
		},
		{
			"name": "PlayerStateAccessTest",
			"fn": func() -> Result: return TestRefs.PlayerStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "MapStateAccessTest",
			"fn": func() -> Result: return TestRefs.MapStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "BankStateAccessTest",
			"fn": func() -> Result: return TestRefs.BankStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeRouteStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeRouteStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeCleanupStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeCleanupStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeRangeOriginsStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeRangeOriginsStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeShopPlacementStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeShopPlacementStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeBonusShopPlacementStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeBonusShopPlacementStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CoffeeFirstCoffeeSoldStateAccessTest",
			"fn": func() -> Result: return TestRefs.CoffeeFirstCoffeeSoldStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "ChooseFridgeKeepStateAccessTest",
			"fn": func() -> Result: return TestRefs.ChooseFridgeKeepStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "KimchiCleanupStateAccessTest",
			"fn": func() -> Result: return TestRefs.KimchiCleanupStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "ChooseKimchiStorageStateAccessTest",
			"fn": func() -> Result: return TestRefs.ChooseKimchiStorageStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "InitiateMarketingActionStateAccessTest",
			"fn": func() -> Result: return TestRefs.InitiateMarketingActionStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "InitiateMarketingOverlapStateAccessTest",
			"fn": func() -> Result: return TestRefs.InitiateMarketingOverlapStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "InitiateMarketingAirplaneOverlapStateAccessTest",
			"fn": func() -> Result: return TestRefs.InitiateMarketingAirplaneOverlapStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "MapContextBuilderStateAccessTest",
			"fn": func() -> Result: return TestRefs.MapContextBuilderStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "BaseMarketingStateAccessTest",
			"fn": func() -> Result: return TestRefs.BaseMarketingStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "StateUpdaterInventoryStateAccessTest",
			"fn": func() -> Result: return TestRefs.StateUpdaterInventoryStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "StateUpdaterCashStateAccessTest",
			"fn": func() -> Result: return TestRefs.StateUpdaterCashStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "TrainActionStateAccessTest",
			"fn": func() -> Result: return TestRefs.TrainActionStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "EmployeeUsageHelperStateAccessTest",
			"fn": func() -> Result: return TestRefs.EmployeeUsageHelperStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "MandatoryActionsRulesStateAccessTest",
			"fn": func() -> Result: return TestRefs.MandatoryActionsRulesStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "FireActionStateAccessTest",
			"fn": func() -> Result: return TestRefs.FireActionStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "MassMarketeersStateAccessTest",
			"fn": func() -> Result: return TestRefs.MassMarketeersStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "NightShiftManagersStateAccessTest",
			"fn": func() -> Result: return TestRefs.NightShiftManagersStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CleanupSettlementOpeningSoonStateAccessTest",
			"fn": func() -> Result: return TestRefs.CleanupSettlementOpeningSoonStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "PlaceRestaurantOpeningSoonStateAccessTest",
			"fn": func() -> Result: return TestRefs.PlaceRestaurantOpeningSoonStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "PlaceRestaurantStateAccessTest",
			"fn": func() -> Result: return TestRefs.PlaceRestaurantStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RestaurantActionCountStateAccessTest",
			"fn": func() -> Result: return TestRefs.RestaurantActionCountStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "MoveRestaurantStateAccessTest",
			"fn": func() -> Result: return TestRefs.MoveRestaurantStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "AddGardenStateAccessTest",
			"fn": func() -> Result: return TestRefs.AddGardenStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "PlaceHouseStateAccessTest",
			"fn": func() -> Result: return TestRefs.PlaceHouseStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "LobbyistsRoadStateAccessTest",
			"fn": func() -> Result: return TestRefs.LobbyistsRoadStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "LobbyistsExtraTileStateAccessTest",
			"fn": func() -> Result: return TestRefs.LobbyistsExtraTileStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "LobbyistsParkStateAccessTest",
			"fn": func() -> Result: return TestRefs.LobbyistsParkStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "LobbyistsParkBonusStateAccessTest",
			"fn": func() -> Result: return TestRefs.LobbyistsParkBonusStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "LobbyistsSupplyStateAccessTest",
			"fn": func() -> Result: return TestRefs.LobbyistsSupplyStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "GourmetFoodCriticsStateAccessTest",
			"fn": func() -> Result: return TestRefs.GourmetFoodCriticsStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralMarketeersStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersMarketingStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralMarketeersMarketingStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersDinnertimeStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralMarketeersDinnertimeStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralGiantBillboardStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralGiantBillboardStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralOfframpAirplaneOverlapStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralOfframpAirplaneOverlapStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RuralOfframpStateAccessTest",
			"fn": func() -> Result: return TestRefs.RuralOfframpStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "DebugAddHouseDemandStateAccessTest",
			"fn": func() -> Result: return TestRefs.DebugAddHouseDemandStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "NewRestaurantMailboxStateAccessTest",
			"fn": func() -> Result: return TestRefs.NewRestaurantMailboxStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "PizzaRadioStateAccessTest",
			"fn": func() -> Result: return TestRefs.PizzaRadioStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "BrandManagerAirplaneSecondGoodStateAccessTest",
			"fn": func() -> Result: return TestRefs.BrandManagerAirplaneSecondGoodStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CampaignManagerSecondTileStateAccessTest",
			"fn": func() -> Result: return TestRefs.CampaignManagerSecondTileStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "NewMilestonesBrandDirectorStateAccessTest",
			"fn": func() -> Result: return TestRefs.NewMilestonesBrandDirectorStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "NewMilestonesPizzaPendingStateAccessTest",
			"fn": func() -> Result: return TestRefs.NewMilestonesPizzaPendingStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "NewMilestonesMarketingInitiationStateAccessTest",
			"fn": func() -> Result: return TestRefs.NewMilestonesMarketingInitiationStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "SubmitRestructuringStateAccessTest",
			"fn": func() -> Result: return TestRefs.SubmitRestructuringStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CompanyStructureStateAccessTest",
			"fn": func() -> Result: return TestRefs.CompanyStructureStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "RestructureEmployeeStateAccessTest",
			"fn": func() -> Result: return TestRefs.RestructureEmployeeStateAccessTestClass.run(2, 12345),
		},
		{
			"name": "CleanupInventoryTest",
			"fn": func() -> Result: return TestRefs.CleanupInventoryTestClass.run(2, 12345),
		},
		{
			"name": "FireActionTest",
			"fn": func() -> Result: return TestRefs.FireActionTestClass.run(2, 12345),
		},
		{
			"name": "CompanyStructureTest",
			"fn": func() -> Result: return TestRefs.CompanyStructureTestClass.run(2, 12345),
		},
		{
			"name": "ActionPanelEndButtonsOrderTest",
			"fn": func() -> Result: return TestRefs.ActionPanelEndButtonsOrderTestClass.run(),
		},
		{
			"name": "GameOverOnlineReturnContractTest",
			"fn": func() -> Result: return TestRefs.GameOverOnlineReturnContractTestClass.run(),
		},
		{
			"name": "GameOverPanelReturnButtonTextTest",
			"fn": func() -> Result: return await TestRefs.GameOverPanelReturnButtonTextTestClass.run(),
		},
		{
			"name": "HandAreaViewSwitchTest",
			"fn": func() -> Result: return TestRefs.HandAreaViewSwitchTestClass.run(),
		},
		{
			"name": "DragPreviewVisualTest",
			"fn": func() -> Result: return TestRefs.DragPreviewVisualTestClass.run(),
		},
		{
			"name": "EmployeePickerMinSizeTest",
			"fn": func() -> Result: return TestRefs.EmployeePickerMinSizeTestClass.run(),
		},
		{
			"name": "CompanyStructureDeferredRebuildTest",
			"fn": func() -> Result: return TestRefs.CompanyStructureDeferredRebuildTestClass.run(),
		},
		{
			"name": "RestructuringLayoutTest",
			"fn": func() -> Result: return TestRefs.RestructuringLayoutTestClass.run(),
		},
		{
			"name": "RestructuringReserveDropTargetTest",
			"fn": func() -> Result: return TestRefs.RestructuringReserveDropTargetTestClass.run(),
		},
		{
			"name": "RestructuringPrivacyTest",
			"fn": func() -> Result: return TestRefs.RestructuringPrivacyTestClass.run(),
		},
		{
			"name": "UiRegressionPropertyTest",
			"fn": func() -> Result: return TestRefs.UiRegressionPropertyTestClass.run(),
		},
			{
				"name": "MapZoomPropertyTest",
				"fn": func() -> Result: return TestRefs.MapZoomPropertyTestClass.run(),
			},
			{
				"name": "RuralAreaMapPanelBoundsTest",
				"fn": func() -> Result: return TestRefs.RuralAreaMapPanelBoundsTestClass.run(),
			},
					{
						"name": "TileInternalGridLinesTest",
						"fn": func() -> Result: return TestRefs.TileInternalGridLinesTestClass.run(),
					},
					{
						"name": "ExternalTileInternalGridLinesTest",
						"fn": func() -> Result: return TestRefs.ExternalTileInternalGridLinesTestClass.run(),
					},
						{
							"name": "MapGroundSkipsOutsideRingTest",
							"fn": func() -> Result: return TestRefs.MapGroundSkipsOutsideRingTestClass.run(),
						},
					{
						"name": "MapBlockedOverlaySkipsVoidCellsTest",
						"fn": func() -> Result: return TestRefs.MapBlockedOverlaySkipsVoidCellsTestClass.run(),
					},
					{
						"name": "MapIndexerStructuresRespectsMapOriginTest",
						"fn": func() -> Result: return TestRefs.MapIndexerStructuresRespectsMapOriginTestClass.run(),
					},
			{
				"name": "AirplaneMarketingOutsideRenderTest",
				"fn": func() -> Result: return TestRefs.AirplaneMarketingOutsideRenderTestClass.run(),
			},
		{
			"name": "AirplaneMarketingIconRotationTest",
			"fn": func() -> Result: return TestRefs.AirplaneMarketingIconRotationTestClass.run(),
		},
		{
			"name": "MarketingRangeFullFootprintTest",
			"fn": func() -> Result: return TestRefs.MarketingRangeFullFootprintTestClass.run(),
		},
			{
				"name": "MarketingHighlightsNoDrinkSourceTest",
				"fn": func() -> Result: return TestRefs.MarketingHighlightsNoDrinkSourceTestClass.run(),
			},
			{
				"name": "MarketingBoardNumberBadgeTest",
				"fn": func() -> Result: return TestRefs.MarketingBoardNumberBadgeTestClass.run(),
			},
			{
				"name": "MarketingRemainingDurationLabelTest",
				"fn": func() -> Result: return TestRefs.MarketingRemainingDurationLabelTestClass.run(),
			},
			{
				"name": "MarketingSelectionFreezeTest",
				"fn": func() -> Result: return TestRefs.MarketingSelectionFreezeTestClass.run(),
			},
		{
			"name": "MapHoverHelpTooltipTest",
			"fn": func() -> Result: return TestRefs.MapHoverHelpTooltipTestClass.run(),
		},
		{
			"name": "MapTouchSelectionTest",
			"fn": func() -> Result: return TestRefs.MapTouchSelectionTestClass.run(),
		},
		{
			"name": "AirplaneMarketingOutsideSelectionTest",
			"fn": func() -> Result: return TestRefs.AirplaneMarketingOutsideSelectionTestClass.run(),
		},
		{
			"name": "SoundManagerLocalInputGateTest",
			"fn": func() -> Result: return TestRefs.SoundManagerLocalInputGateTestClass.run(),
		},
		{
			"name": "MoveRestaurantDisplayLabelTest",
			"fn": func() -> Result: return TestRefs.MoveRestaurantDisplayLabelTestClass.run(),
		},
		{
			"name": "RestaurantPlacementDistanceToolToggleTest",
			"fn": func() -> Result: return TestRefs.RestaurantPlacementDistanceToolToggleTestClass.run(),
		},
		{
			"name": "ConfirmDinnertimeAvailabilityTest",
			"fn": func() -> Result: return TestRefs.ConfirmDinnertimeAvailabilityTestClass.run(),
		},
		{
			"name": "ConfirmMarketingAvailabilityTest",
			"fn": func() -> Result: return TestRefs.ConfirmMarketingAvailabilityTestClass.run(),
		},
		{
			"name": "ActionPanelGuidedActionPlaceholderTest",
			"fn": func() -> Result: return await TestRefs.ActionPanelGuidedActionPlaceholderTestClass.run(),
		},
			{
				"name": "ActionPanelNoAvailableActionsHintTest",
				"fn": func() -> Result: return await TestRefs.ActionPanelNoAvailableActionsHintTestClass.run(),
			},
			{
				"name": "GameLogDockControllerTimelineSyncTest",
				"fn": func() -> Result: return await TestRefs.GameLogDockControllerTimelineSyncTestClass.run(),
			},
			{
				"name": "RightPanelDockControllerReplaceVisiblePanelTest",
				"fn": func() -> Result: return TestRefs.RightPanelDockControllerReplaceVisiblePanelTestClass.run(),
			},
			{
				"name": "GamePanelControllerAutoOpenOverLogTest",
				"fn": func() -> Result: return TestRefs.GamePanelControllerAutoOpenOverLogTestClass.run(),
			},
			{
				"name": "GameTimelineZeroCommandSnapshotTest",
				"fn": func() -> Result: return TestRefs.GameTimelineZeroCommandSnapshotTestClass.run(),
			},
			{
				"name": "LogRestoreAfterLoadTest",
				"fn": func() -> Result: return TestRefs.LogRestoreAfterLoadTestClass.run(),
			},
			{
				"name": "GameLogPanelReplayToggleAvailabilityTest",
				"fn": func() -> Result: return await TestRefs.GameLogPanelReplayToggleAvailabilityTestClass.run(),
			},
			{
				"name": "GameLogPanelStepTimelineAppendTest",
				"fn": func() -> Result: return await TestRefs.GameLogPanelStepTimelineAppendTestClass.run(),
			},
			{
				"name": "GameLogAutoScrollBehaviorTest",
				"fn": func() -> Result: return await TestRefs.GameLogAutoScrollBehaviorTestClass.run(),
			},
			{
				"name": "GameLogDescriptorCommitChunkingTest",
				"fn": func() -> Result: return await TestRefs.GameLogDescriptorCommitChunkingTestClass.run(),
			},
			{
				"name": "GameLogHiddenTimelineStateSkipTest",
				"fn": func() -> Result: return await TestRefs.GameLogHiddenTimelineStateSkipTestClass.run(),
			},
			{
				"name": "LiveLogRefreshDebounceTest",
				"fn": func() -> Result: return await TestRefs.LiveLogRefreshDebounceTestClass.run(),
			},
			{
				"name": "GameLogTimelineLocalStateDeltaTest",
				"fn": func() -> Result: return await TestRefs.GameLogTimelineLocalStateDeltaTestClass.run(),
			},
			{
				"name": "GameLogTimelineRuntimeEventSourceTest",
				"fn": func() -> Result: return await TestRefs.GameLogTimelineRuntimeEventSourceTestClass.run(),
			},
			{
				"name": "OnlineResumeReplayEntryStateNoopTest",
				"fn": func() -> Result: return TestRefs.OnlineResumeReplayEntryStateNoopTestClass.run(),
			},
			{
				"name": "GameTimelineSeekRoutingManualReplayTest",
				"fn": func() -> Result: return TestRefs.GameTimelineSeekRoutingManualReplayTestClass.run(),
			},
			{
				"name": "CreateRoomResumeLogHistoryBuilderTest",
				"fn": func() -> Result: return TestRefs.CreateRoomResumeLogHistoryBuilderTestClass.run(),
			},
			{
				"name": "GameOverPanelReadOnlyTest",
				"fn": func() -> Result: return TestRefs.GameOverPanelReadOnlyTestClass.run(),
			},
				{
					"name": "GameOverFreezeFullGameTest",
					"fn": func() -> Result: return await TestRefs.GameOverFreezeFullGameTestClass.run(),
				},
				{
					"name": "GameOverLastPlayerStandingTest",
					"fn": func() -> Result: return await TestRefs.GameOverLastPlayerStandingTestClass.run(),
				},
				{
					"name": "GameOverForfeitBadgeTest",
					"fn": func() -> Result: return await TestRefs.GameOverForfeitBadgeTestClass.run(),
				},
				{
					"name": "ProductionPanelUsedCountsSyncTest",
					"fn": func() -> Result: return await TestRefs.ProductionPanelUsedCountsSyncTestClass.run(),
				},
				{
					"name": "ProductionProcureStaffPickerUiTest",
					"fn": func() -> Result: return await TestRefs.ProductionProcureStaffPickerUiTestClass.run(),
				},
					{
						"name": "ManualLogSaveTest",
						"fn": func() -> Result: return TestRefs.ManualLogSaveTestClass.run(),
					},
					{
						"name": "ManualMultiTrainersSaveTest",
						"fn": func() -> Result: return TestRefs.ManualMultiTrainersSaveTestClass.run(),
					},
					{
						"name": "ManualLogSavesCoverageTest",
						"fn": func() -> Result: return TestRefs.ManualLogSavesCoverageTestClass.run(),
					},
							{
								"name": "EventHistoryRewindTest",
								"fn": func() -> Result: return TestRefs.EventHistoryRewindTestClass.run(2, 12345),
							},
								{
									"name": "RewindTurnStartFallbackTest",
									"fn": func() -> Result: return TestRefs.RewindTurnStartFallbackTestClass.run(2, 12345),
								},
									{
										"name": "RewindTurnStartPhaseChangeTest",
										"fn": func() -> Result: return TestRefs.RewindTurnStartPhaseChangeTestClass.run(2, 12345),
									},
										{
											"name": "RewindTurnStartReenterTest",
											"fn": func() -> Result: return TestRefs.RewindTurnStartReenterTestClass.run(2, 12345),
										},
										{
											"name": "RewindTurnStartSetupTurnSwitchTest",
											"fn": func() -> Result: return TestRefs.RewindTurnStartSetupTurnSwitchTestClass.run(12345),
										},
										{
											"name": "RewindTurnStartActorIdTest",
											"fn": func() -> Result: return TestRefs.RewindTurnStartActorIdTestClass.run(2, 12345),
										},
										{
											"name": "EventTimelineBuildTest",
											"fn": func() -> Result: return TestRefs.EventTimelineBuildTestClass.run(2, 12345, 20),
										},
							{
								"name": "StepTimelineBuildTest",
								"fn": func() -> Result: return TestRefs.StepTimelineBuildTestClass.run(),
							},
							{
								"name": "StepTimelineCleanupPendingStateAccessTest",
								"fn": func() -> Result: return TestRefs.StepTimelineCleanupPendingStateAccessTestClass.run(2, 12345),
							},
							{
								"name": "StepTimelineForceExecuteActorMismatchTest",
								"fn": func() -> Result: return TestRefs.StepTimelineForceExecuteActorMismatchTestClass.run(12345),
							},
								{
									"name": "StepTimelineMarketingMilestoneOrderTest",
									"fn": func() -> Result: return TestRefs.StepTimelineMarketingMilestoneOrderTestClass.run(12345),
								},
								{
									"name": "StepTimelinePhaseBoundaryOrderTest",
									"fn": func() -> Result: return TestRefs.StepTimelinePhaseBoundaryOrderTestClass.run(12345),
								},
								{
									"name": "StepTimelineIncrementalAppendTest",
									"fn": func() -> Result: return TestRefs.StepTimelineIncrementalAppendTestClass.run(12345),
								},
								{
									"name": "StepTimelineCleanupDiscardOrderTest",
									"fn": func() -> Result: return TestRefs.StepTimelineCleanupDiscardOrderTestClass.run(12345),
								},
								{
									"name": "StepTimelineKetchupMilestoneOrderTest",
									"fn": func() -> Result: return TestRefs.StepTimelineKetchupMilestoneOrderTestClass.run(12345),
								},
								{
									"name": "ReplayLogFutureVisibilityTest",
									"fn": func() -> Result: return TestRefs.ReplayLogFutureVisibilityTestClass.run(2, 12345, 12),
								},
			{
				"name": "ReplayPlayerSmokeTest",
				"fn": func() -> Result: return TestRefs.ReplayPlayerSmokeTestClass.run(),
			},
			{
				"name": "OrderOfBusinessTest",
				"fn": func() -> Result: return TestRefs.OrderOfBusinessTestClass.run(3, 12345),
			},
			{
				"name": "MilestoneSystemTest",
				"fn": func() -> Result: return TestRefs.MilestoneSystemTestClass.run(2, 12345),
			},
			{
				"name": "ModulePackageLoaderV2Test",
				"fn": func() -> Result: return TestRefs.ModulePackageLoaderV2TestClass.run(2, 12345),
			},
			{
				"name": "ContentCatalogV2Test",
				"fn": func() -> Result: return TestRefs.ContentCatalogV2TestClass.run(2, 12345),
			},
			{
				"name": "VisualCatalogLoaderV2Test",
				"fn": func() -> Result: return TestRefs.VisualCatalogLoaderV2TestClass.run(2, 12345),
			},
			{
				"name": "ModuleProductIconsLoadedTest",
				"fn": func() -> Result: return TestRefs.ModuleProductIconsLoadedTestClass.run(),
			},
			{
				"name": "ReserveAreaSupplyVisualsTest",
				"fn": func() -> Result: return TestRefs.ReserveAreaSupplyVisualsTestClass.run(),
			},
			{
				"name": "ModulePlanBuilderV2Test",
				"fn": func() -> Result: return TestRefs.ModulePlanBuilderV2TestClass.run(2, 12345),
			},
			{
				"name": "ModuleSystemV2BootstrapTest",
				"fn": func() -> Result: return TestRefs.ModuleSystemV2BootstrapTestClass.run(2, 12345),
			},
				{
					"name": "SettlementRegistryV2Test",
					"fn": func() -> Result: return TestRefs.SettlementRegistryV2TestClass.run(2, 12345),
				},
				{
					"name": "DinnertimeDemandRegistryV2Test",
					"fn": func() -> Result: return TestRefs.DinnertimeDemandRegistryV2TestClass.run(2, 12345),
				},
				{
					"name": "DinnertimeRoutePurchaseRegistryV2Test",
					"fn": func() -> Result: return TestRefs.DinnertimeRoutePurchaseRegistryV2TestClass.run(2, 12345),
				},
				{
					"name": "DinnertimeRulesDomainTest",
					"fn": func() -> Result: return TestRefs.DinnertimeRulesDomainTestClass.run(2, 12345),
				},
				{
					"name": "EffectRegistryV2Test",
					"fn": func() -> Result: return TestRefs.EffectRegistryV2TestClass.run(2, 12345),
				},
			{
				"name": "PoolBuilderV2Test",
				"fn": func() -> Result: return TestRefs.PoolBuilderV2TestClass.run(2, 12345),
			},
			{
				"name": "MarketingBoardDataTest",
				"fn": func() -> Result: return TestRefs.MarketingBoardDataTestClass.run(2, 12345),
			},
			{
				"name": "MarketingRulesDomainTest",
				"fn": func() -> Result: return TestRefs.MarketingRulesDomainTestClass.run(2, 12345),
			},
			{
				"name": "MarketingPanelModuleTypesUiTest",
				"fn": func() -> Result: return TestRefs.MarketingPanelModuleTypesUiTestClass.run(),
			},
			{
				"name": "MarketingPanelPostPlaceRefreshTest",
				"fn": func() -> Result: return TestRefs.MarketingPanelPostPlaceRefreshTestClass.run(),
			},
			{
				"name": "MarketingRotationPreviewUiTest",
				"fn": func() -> Result: return TestRefs.MarketingRotationPreviewUiTestClass.run(),
			},
						{
							"name": "MarketingCampaignsTest",
							"fn": func() -> Result: return TestRefs.MarketingCampaignsTestClass.run(2, 12345),
						},
					{
						"name": "MassMarketeersV2Test",
						"fn": func() -> Result: return TestRefs.MassMarketeersV2TestClass.run(2, 12345),
					},
					{
						"name": "KetchupMechanismV2Test",
						"fn": func() -> Result: return TestRefs.KetchupMechanismV2TestClass.run(2, 12345),
					},
						{
							"name": "KimchiStorageModalUiTest",
							"fn": func() -> Result: return await TestRefs.KimchiStorageModalUiTestClass.run(12345),
						},
						{
							"name": "FridgeKeepModalUiTest",
							"fn": func() -> Result: return await TestRefs.FridgeKeepModalUiTestClass.run(12345),
						},
						{
							"name": "MilestoneControllerVisibleSyncTest",
							"fn": func() -> Result: return TestRefs.MilestoneControllerVisibleSyncTestClass.run(12345),
						},
						{
							"name": "TrainControllerSourceFilterTest",
							"fn": func() -> Result: return TestRefs.TrainControllerSourceFilterTestClass.run(12345),
						},
						{
							"name": "RecruitTrainStaffPickerUiTest",
							"fn": func() -> Result: return await TestRefs.RecruitTrainStaffPickerUiTestClass.run(),
						},
						{
							"name": "WorkingPanelsVisibleSyncTest",
							"fn": func() -> Result: return TestRefs.WorkingPanelsVisibleSyncTestClass.run(12345),
						},
						{
							"name": "KimchiV2Test",
							"fn": func() -> Result: return TestRefs.KimchiV2TestClass.run(2, 12345),
						},
					{
						"name": "CoffeeV2Test",
						"fn": func() -> Result: return TestRefs.CoffeeV2TestClass.run(12345),
					},
					{
						"name": "MovieStarsV2Test",
						"fn": func() -> Result: return TestRefs.MovieStarsV2TestClass.run(3, 12345),
					},
					{
						"name": "NightShiftManagersV2Test",
						"fn": func() -> Result: return TestRefs.NightShiftManagersV2TestClass.run(2, 12345),
					},
					{
						"name": "NewDistrictsV2Test",
						"fn": func() -> Result: return TestRefs.NewDistrictsV2TestClass.run(2, 12345),
					},
		{
			"name": "FryChefsV2Test",
			"fn": func() -> Result: return TestRefs.FryChefsV2TestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersV2Test",
			"fn": func() -> Result: return TestRefs.RuralMarketeersV2TestClass.run(2, 12345),
		},
		{
			"name": "GourmetFoodCriticsV2Test",
			"fn": func() -> Result: return TestRefs.GourmetFoodCriticsV2TestClass.run(2, 12345),
		},
		{
			"name": "ReservePricesV2Test",
			"fn": func() -> Result: return TestRefs.ReservePricesV2TestClass.run(2, 12345),
		},
					{
						"name": "HardChoicesV2Test",
						"fn": func() -> Result: return TestRefs.HardChoicesV2TestClass.run(2, 12345),
					},
					{
						"name": "PhaseOrderOverrideV2Test",
						"fn": func() -> Result: return TestRefs.PhaseOrderOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "WorkingSubPhaseOrderOverrideV2Test",
						"fn": func() -> Result: return TestRefs.WorkingSubPhaseOrderOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "SettlementTriggerOverrideV2Test",
						"fn": func() -> Result: return TestRefs.SettlementTriggerOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "SettlementTriggerOverrideExtraV2Test",
						"fn": func() -> Result: return TestRefs.SettlementTriggerOverrideExtraV2TestClass.run(2, 12345),
					},
				{
					"name": "PaydaySubPhaseV2Test",
					"fn": func() -> Result: return TestRefs.PaydaySubPhaseV2TestClass.run(2, 12345),
				},
				{
					"name": "ActionAvailabilityOverrideV2Test",
					"fn": func() -> Result: return TestRefs.ActionAvailabilityOverrideV2TestClass.run(2, 12345),
				},
				{
					"name": "NewMilestonesV2Test",
					"fn": func() -> Result: return TestRefs.NewMilestonesV2TestClass.run(2, 12345),
				},
					{
						"name": "NewMilestonesNewRestaurantV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesNewRestaurantV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesMarketingTraineeV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesMarketingTraineeV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesCampaignManagerV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesCampaignManagerV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBrandManagerV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesBrandManagerV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBrandDirectorV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesBrandDirectorV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBurgerSoldV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesBurgerSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesCokeSoldV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesCokeSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesPizzaSoldV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesPizzaSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesLemonadeSoldV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesLemonadeSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBeerTrainerPaydayV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesBeerTrainerPaydayV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesRecruiterWaitressV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesRecruiterWaitressV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesDiscountManagerBankBurnV2Test",
						"fn": func() -> Result: return TestRefs.NewMilestonesDiscountManagerBankBurnV2TestClass.run(2, 12345),
					},
						{
							"name": "LobbyistsV2Test",
							"fn": func() -> Result: return TestRefs.LobbyistsV2TestClass.run(2, 12345),
						},
						{
							"name": "LobbyistsExtraTileMultiPlayerSameRoundUiTest",
							"fn": func() -> Result: return await TestRefs.LobbyistsExtraTileMultiPlayerSameRoundUiTestClass.run(),
						},
						{
							"name": "LobbyistsExtraTilePickerLayoutUiTest",
							"fn": func() -> Result: return await TestRefs.LobbyistsExtraTilePickerLayoutUiTestClass.run(),
						},
						{
							"name": "NoodlesSushiV2Test",
							"fn": func() -> Result: return TestRefs.NoodlesSushiV2TestClass.run(2, 12345),
						},
					{
						"name": "MarketingSettlementFailFastTest",
						"fn": func() -> Result: return TestRefs.MarketingSettlementFailFastTestClass.run(2, 12345),
					},
					{
						"name": "MarketingDemandGeneratedEventTest",
						"fn": func() -> Result: return TestRefs.MarketingDemandGeneratedEventTestClass.run(),
					},
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
