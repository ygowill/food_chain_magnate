# Core, setup, tutorial, and architecture contract tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
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
			"name": "TutorialRuntimeScopeTest",
			"fn": func() -> Result: return TestRefs.TutorialRuntimeScopeTestClass.run(),
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
	]
	return tests
