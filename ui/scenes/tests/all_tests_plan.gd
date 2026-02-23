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
			"name": "PaydaySalaryTokenEligibilityTest",
			"fn": func() -> Result: return TestRefs.PaydaySalaryTokenEligibilityTestClass.run(),
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
			"name": "PlatformApiResponseParseTest",
			"fn": func() -> Result: return TestRefs.PlatformApiResponseParseTestClass.run(),
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
			"name": "OnlineClientHelloConnectTokenTest",
			"fn": func() -> Result: return TestRefs.OnlineClientHelloConnectTokenTestClass.run(),
		},
		{
			"name": "PlatformConnectTokenAutoJoinTest",
			"fn": func() -> Result: return TestRefs.PlatformConnectTokenAutoJoinTestClass.run(),
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
			"name": "OnlineStartGameReplayTest",
			"fn": func() -> Result: return TestRefs.OnlineStartGameReplayTestClass.run(),
		},
		{
			"name": "OnlineResyncArchiveTest",
			"fn": func() -> Result: return TestRefs.OnlineResyncArchiveTestClass.run(),
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
			"name": "OnlineRoomSpectatorTest",
			"fn": func() -> Result: return TestRefs.OnlineRoomSpectatorTestClass.run(),
		},
		{
			"name": "OnlineDisconnectGraceReconnectTest",
			"fn": func() -> Result: return await TestRefs.OnlineDisconnectGraceReconnectTestClass.run(),
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
				"name": "EntityTabReserveCardPrivacyTest",
				"fn": func() -> Result: return TestRefs.EntityTabReserveCardPrivacyTestClass.run(),
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
				"name": "ActionPanelExecutorMetadataTest",
				"fn": func() -> Result: return TestRefs.ActionPanelExecutorMetadataTestClass.run(),
			},
			{
				"name": "LeftPanelSelectionIsolationTest",
				"fn": func() -> Result: return TestRefs.LeftPanelSelectionIsolationTestClass.run(),
			},
			{
				"name": "LeftPanelBusyMarketersGroupTest",
				"fn": func() -> Result: return TestRefs.LeftPanelBusyMarketersGroupTestClass.run(),
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
			"name": "RuralMarketeersAutoAdvanceUnblockedTest",
			"fn": func() -> Result: return TestRefs.RuralMarketeersAutoAdvanceUnblockedTestClass.run(2, 12345),
		},
		{
			"name": "ProduceFoodTest",
			"fn": func() -> Result: return TestRefs.ProduceFoodTestClass.run(2, 12345),
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
				"name": "AirplaneMarketingOutsideSelectionTest",
				"fn": func() -> Result: return TestRefs.AirplaneMarketingOutsideSelectionTestClass.run(),
			},
			{
				"name": "MoveRestaurantDisplayLabelTest",
				"fn": func() -> Result: return TestRefs.MoveRestaurantDisplayLabelTestClass.run(),
			},
			{
				"name": "ActionPanelGuidedActionPlaceholderTest",
				"fn": func() -> Result: return await TestRefs.ActionPanelGuidedActionPlaceholderTestClass.run(),
			},
			{
				"name": "GameLogDockControllerTimelineSyncTest",
				"fn": func() -> Result: return await TestRefs.GameLogDockControllerTimelineSyncTestClass.run(),
			},
				{
					"name": "LogRestoreAfterLoadTest",
					"fn": func() -> Result: return TestRefs.LogRestoreAfterLoadTestClass.run(),
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
					"name": "ProductionPanelUsedCountsSyncTest",
					"fn": func() -> Result: return TestRefs.ProductionPanelUsedCountsSyncTestClass.run(),
				},
					{
						"name": "ManualLogSaveTest",
						"fn": func() -> Result: return TestRefs.ManualLogSaveTestClass.run(),
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
											"name": "EventTimelineBuildTest",
											"fn": func() -> Result: return TestRefs.EventTimelineBuildTestClass.run(2, 12345, 20),
										},
							{
								"name": "StepTimelineBuildTest",
								"fn": func() -> Result: return TestRefs.StepTimelineBuildTestClass.run(),
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
				"name": "MarketingPanelModuleTypesUiTest",
				"fn": func() -> Result: return TestRefs.MarketingPanelModuleTypesUiTestClass.run(),
			},
			{
				"name": "MarketingPanelPostPlaceRefreshTest",
				"fn": func() -> Result: return TestRefs.MarketingPanelPostPlaceRefreshTestClass.run(),
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
				"name": "OnlineDinnertimeConfirmEnforcedTest",
				"fn": func() -> Result: return TestRefs.OnlineDinnertimeConfirmEnforcedTestClass.run(2, 12345),
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
