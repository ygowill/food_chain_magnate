# Base rules, state access, archive, and invariants tests.
extends RefCounted

const TestRefs = preload("res://ui/scenes/tests/all_tests_refs.gd")

static func build_tests(_host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = [
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
	]
	return tests
