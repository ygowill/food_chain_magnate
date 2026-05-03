# Module system, catalogs, V2 modules, and marketing domain tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
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
				"name": "MapSkinRawImageFallbackTest",
				"fn": func() -> Result: return TestRefs.MapSkinRawImageFallbackTestClass.run(),
			},
			{
				"name": "MapSnapshotApartmentUiHintsTest",
				"fn": func() -> Result: return TestRefs.MapSnapshotApartmentUiHintsTestClass.run(),
			},
			{
				"name": "HouseLabelRawImageFallbackTest",
				"fn": func() -> Result: return TestRefs.HouseLabelRawImageFallbackTestClass.run(),
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
	]
	return tests
