# 全部测试聚合场景（Headless / Autorun）
extends Control

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")
const CheckCompileScript = preload("res://tools/check_compile.gd")
const UiSkinCacheClass = preload("res://ui/visual/ui_skin_cache.gd")
const EmployeeCardClass = preload("res://ui/components/employee_card/employee_card.gd")
const StructuresPassClass = preload("res://ui/scenes/game/map_canvas_drawer_structures_pass.gd")
const TilePreviewFactoryClass = preload("res://ui/components/reserve_area/tile_preview_factory.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0
var _write_ui_log: bool = true

func _ready() -> void:
	_write_ui_log = not OS.has_feature("headless")
	_clear_output()
	_append_output("全部测试聚合：按既定顺序依次运行所有 headless 测试。\n")
	_append_output("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")
	if _should_autorun():
		_exit_code = await _run_all()
		await _prepare_runtime_cleanup_before_quit()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = await _run_all()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_all() -> int:
	_append_output("\n--- 开始运行全部测试 ---\n")
	print("[AllTests] START args=%s" % str(OS.get_cmdline_user_args()))

	var tests: Array[Dictionary] = [
		{
			"name": "GameSmokeTest",
			"fn": func() -> Result: return await _run_game_smoke_test(),
		},
		{
			"name": "CheckCompileTest",
			"fn": func() -> Result: return _run_check_compile_test(),
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
				"name": "PlacementOverlayCancelResetsTest",
				"fn": func() -> Result: return TestRefs.PlacementOverlayCancelResetsTestClass.run(),
			},
				{
					"name": "LogRestoreAfterLoadTest",
					"fn": func() -> Result: return TestRefs.LogRestoreAfterLoadTestClass.run(),
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
				"name": "DinnertimeDistanceEntryBoundaryTest",
				"fn": func() -> Result: return TestRefs.DinnertimeDistanceEntryBoundaryTestClass.run(2, 12345),
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

	var passed := 0
	var failed: Array[String] = []
	var total_start := Time.get_ticks_msec()

	for test_def in tests:
		var name: String = test_def.get("name", "UnknownTest")
		var fn: Callable = test_def.get("fn", Callable())

		_append_output("\n== %s ==\n" % name)
		print("[AllTests] RUN %s" % name)

		var start := Time.get_ticks_msec()
		var call_result = await fn.call()
		var result: Result = call_result if (call_result is Result) else Result.failure("测试返回值类型错误（期望 Result）")
		var duration_ms := Time.get_ticks_msec() - start

		if result.ok:
			passed += 1
			_append_output("PASS (%dms)\n" % duration_ms)
			print("[AllTests] PASS %s (%dms)" % [name, duration_ms])
		else:
			failed.append(name)
			_append_output("FAIL (%dms): %s\n" % [duration_ms, result.error])
			push_error("[AllTests] FAIL %s: %s" % [name, result.error])
			print("[AllTests] FAIL %s (%dms): %s" % [name, duration_ms, result.error])
			if name == "GameSmokeTest":
				var total_ms := Time.get_ticks_msec() - total_start
				var skipped := tests.size() - passed - failed.size()
				_append_output("\n--- 汇总 ---\n")
				_append_output("通过: %d/%d, 总耗时: %dms\n" % [passed, tests.size(), total_ms])
				_append_output("Smoke test 失败：已跳过后续 %d 个测试。\n" % skipped)
				print("[AllTests] FAIL_FAST skipped=%d" % skipped)
				print("[AllTests] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [passed, tests.size(), str(failed), total_ms])
				await _cleanup_runtime_between_tests()
				return 1

		await _cleanup_runtime_between_tests()

	var total_ms := Time.get_ticks_msec() - total_start
	_append_output("\n--- 汇总 ---\n")
	_append_output("通过: %d/%d, 总耗时: %dms\n" % [passed, tests.size(), total_ms])
	print("[AllTests] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [passed, tests.size(), str(failed), total_ms])

	return 0 if failed.is_empty() else 1

func _run_game_smoke_test() -> Result:
	var smoke = get_node_or_null("GameSmokeTest")
	if smoke == null and TestRefs.GameSmokeTestScene != null:
		smoke = TestRefs.GameSmokeTestScene.instantiate()
		add_child(smoke)
		if smoke is CanvasItem:
			(smoke as CanvasItem).visible = false
		await get_tree().process_frame

	if smoke == null or not is_instance_valid(smoke):
		return Result.failure("GameSmokeTest 节点缺失")
	if smoke is CanvasItem:
		(smoke as CanvasItem).visible = false
	if not smoke.has_method("_run_test"):
		return Result.failure("GameSmokeTest 缺少 _run_test()")

	var code = await smoke.call("_run_test")
	await _cleanup_test_node(smoke)
	if code is int and int(code) == 0:
		return Result.success({})
	return Result.failure("GameSmokeTest 失败: exit_code=%s" % str(code))

func _cleanup_test_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.queue_free()
	await _drain_frames(4)

func _prepare_runtime_cleanup_before_quit() -> void:
	_clear_output()
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if NetClient != null:
		NetClient.shutdown()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	await _drain_frames(6)

func _cleanup_runtime_between_tests() -> void:
	UiSkinCacheClass.clear_cache()
	EmployeeCardClass.clear_icon_texture_cache()
	StructuresPassClass.clear_drink_source_texture_cache()
	TilePreviewFactoryClass.clear_cached_script()
	if NetClient != null:
		NetClient.shutdown()
	if EventBus != null:
		if EventBus.has_method("clear_all_subscribers"):
			EventBus.clear_all_subscribers()
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		elif EventBus.has_method("clear_history"):
			EventBus.clear_history()
	if SceneManager != null and SceneManager.has_method("clear_stack"):
		SceneManager.clear_stack()
	Globals.reset_game_config()
	await _drain_frames(2)

func _run_check_compile_test() -> Result:
	var scan_result: Result = CheckCompileScript.run_scan()
	if scan_result.ok:
		return scan_result

	var details: Dictionary = scan_result.value if (scan_result.value is Dictionary) else {}
	var preview: Array[String] = Array(details.get("preview", []), TYPE_STRING, "", null)
	if preview.is_empty():
		return scan_result
	return Result.failure("%s; first=%s" % [scan_result.error, preview[0]])

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")

func _drain_frames(count: int) -> void:
	var n := maxi(1, int(count))
	for _i in range(n):
		await get_tree().process_frame

func _append_output(text: String) -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.append_text(text)

func _clear_output() -> void:
	if not _write_ui_log:
		return
	if is_instance_valid(output):
		output.clear()
