# Runtime UI, log, replay, rewind, and step timeline tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
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
						"name": "PiecePreviewLayoutTest",
						"fn": func() -> Result: return TestRefs.PiecePreviewLayoutTestClass.run(),
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
				"fn": func() -> Result: return await TestRefs.GameTimelineZeroCommandSnapshotTestClass.run(),
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
	]
	return tests
