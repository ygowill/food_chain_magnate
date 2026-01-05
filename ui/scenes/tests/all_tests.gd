# 全部测试聚合场景（Headless / Autorun）
extends Control

const ReplayDeterminismTestClass = preload("res://core/tests/replay_determinism_test.gd")
const EmployeeActionTestClass = preload("res://core/tests/employee_action_test.gd")
const RecruitOnCreditRulesTestClass = preload("res://core/tests/recruit_on_credit_rules_test.gd")
const PaydaySalaryTestClass = preload("res://core/tests/payday_salary_test.gd")
const InitialCompanyTestClass = preload("res://core/tests/initial_company_test.gd")
const MandatoryActionsTestClass = preload("res://core/tests/mandatory_actions_test.gd")
const ProduceFoodTestClass = preload("res://core/tests/produce_food_test.gd")
const ProcureDrinksTestClass = preload("res://core/tests/procure_drinks_test.gd")
const ProcureDrinksRouteRulesTestClass = preload("res://core/tests/procure_drinks_route_rules_test.gd")
const PlaceHouseRulesTestClass = preload("res://core/tests/place_house_rules_test.gd")
const AddGardenRulesTestClass = preload("res://core/tests/add_garden_rules_test.gd")
const PlaceRestaurantRulesTestClass = preload("res://core/tests/place_restaurant_rules_test.gd")
const MoveRestaurantRulesTestClass = preload("res://core/tests/move_restaurant_rules_test.gd")
const FailFastParsingTestClass = preload("res://core/tests/fail_fast_parsing_test.gd")
const ArchiveFailFastTestClass = preload("res://core/tests/archive_fail_fast_test.gd")
const InvariantsFailFastTestClass = preload("res://core/tests/invariants_fail_fast_test.gd")
const RoundStateFailFastTestClass = preload("res://core/tests/round_state_fail_fast_test.gd")
const CleanupInventoryTestClass = preload("res://core/tests/cleanup_inventory_test.gd")
const FireActionTestClass = preload("res://core/tests/fire_action_test.gd")
const CompanyStructureTestClass = preload("res://core/tests/company_structure_test.gd")
const OrderOfBusinessTestClass = preload("res://core/tests/order_of_business_test.gd")
const MilestoneSystemTestClass = preload("res://core/tests/milestone_system_test.gd")
const ModulePackageLoaderV2TestClass = preload("res://core/tests/module_package_loader_v2_test.gd")
const ContentCatalogV2TestClass = preload("res://core/tests/content_catalog_v2_test.gd")
const VisualCatalogLoaderV2TestClass = preload("res://core/tests/visual_catalog_loader_v2_test.gd")
const ModulePlanBuilderV2TestClass = preload("res://core/tests/module_plan_builder_v2_test.gd")
const ModuleSystemV2BootstrapTestClass = preload("res://core/tests/module_system_v2_bootstrap_test.gd")
const SettlementRegistryV2TestClass = preload("res://core/tests/settlement_registry_v2_test.gd")
const DinnertimeRoutePurchaseRegistryV2TestClass = preload("res://core/tests/dinnertime_route_purchase_registry_v2_test.gd")
const EffectRegistryV2TestClass = preload("res://core/tests/effect_registry_v2_test.gd")
const PoolBuilderV2TestClass = preload("res://core/tests/pool_builder_v2_test.gd")
const MarketingCampaignsTestClass = preload("res://core/tests/marketing_campaigns_test.gd")
const MassMarketeersV2TestClass = preload("res://core/tests/mass_marketeers_v2_test.gd")
const KetchupMechanismV2TestClass = preload("res://core/tests/ketchup_mechanism_v2_test.gd")
const KimchiV2TestClass = preload("res://core/tests/kimchi_v2_test.gd")
const CoffeeV2TestClass = preload("res://core/tests/coffee_v2_test.gd")
const MovieStarsV2TestClass = preload("res://core/tests/movie_stars_v2_test.gd")
const NightShiftManagersV2TestClass = preload("res://core/tests/night_shift_managers_v2_test.gd")
const NewDistrictsV2TestClass = preload("res://core/tests/new_districts_v2_test.gd")
const FryChefsV2TestClass = preload("res://core/tests/fry_chefs_v2_test.gd")
const RuralMarketeersV2TestClass = preload("res://core/tests/rural_marketeers_v2_test.gd")
const GourmetFoodCriticsV2TestClass = preload("res://core/tests/gourmet_food_critics_v2_test.gd")
const ReservePricesV2TestClass = preload("res://core/tests/reserve_prices_v2_test.gd")
const HardChoicesV2TestClass = preload("res://core/tests/hard_choices_v2_test.gd")
const PhaseOrderOverrideV2TestClass = preload("res://core/tests/phase_order_override_v2_test.gd")
const WorkingSubPhaseOrderOverrideV2TestClass = preload("res://core/tests/working_sub_phase_order_override_v2_test.gd")
const SettlementTriggerOverrideV2TestClass = preload("res://core/tests/settlement_trigger_override_v2_test.gd")
const SettlementTriggerOverrideExtraV2TestClass = preload("res://core/tests/settlement_trigger_override_extra_v2_test.gd")
const PaydaySubPhaseV2TestClass = preload("res://core/tests/payday_sub_phase_v2_test.gd")
const ActionAvailabilityOverrideV2TestClass = preload("res://core/tests/action_availability_override_v2_test.gd")
const NewMilestonesV2TestClass = preload("res://core/tests/new_milestones_v2_test.gd")
const NewMilestonesNewRestaurantV2TestClass = preload("res://core/tests/new_milestones_new_restaurant_v2_test.gd")
const NewMilestonesMarketingTraineeV2TestClass = preload("res://core/tests/new_milestones_marketing_trainee_v2_test.gd")
const NewMilestonesCampaignManagerV2TestClass = preload("res://core/tests/new_milestones_campaign_manager_v2_test.gd")
const NewMilestonesBrandManagerV2TestClass = preload("res://core/tests/new_milestones_brand_manager_v2_test.gd")
const NewMilestonesBrandDirectorV2TestClass = preload("res://core/tests/new_milestones_brand_director_v2_test.gd")
const NewMilestonesBurgerSoldV2TestClass = preload("res://core/tests/new_milestones_burger_sold_v2_test.gd")
const NewMilestonesCokeSoldV2TestClass = preload("res://core/tests/new_milestones_coke_sold_v2_test.gd")
const NewMilestonesPizzaSoldV2TestClass = preload("res://core/tests/new_milestones_pizza_sold_v2_test.gd")
const NewMilestonesLemonadeSoldV2TestClass = preload("res://core/tests/new_milestones_lemonade_sold_v2_test.gd")
const NewMilestonesBeerTrainerPaydayV2TestClass = preload("res://core/tests/new_milestones_beer_trainer_payday_v2_test.gd")
const NewMilestonesRecruiterWaitressV2TestClass = preload("res://core/tests/new_milestones_recruiter_waitress_v2_test.gd")
const NewMilestonesDiscountManagerBankBurnV2TestClass = preload("res://core/tests/new_milestones_discount_manager_bank_burn_v2_test.gd")
const LobbyistsV2TestClass = preload("res://core/tests/lobbyists_v2_test.gd")
const NoodlesSushiV2TestClass = preload("res://core/tests/noodles_sushi_v2_test.gd")
const MarketingSettlementFailFastTestClass = preload("res://core/tests/marketing_settlement_fail_fast_test.gd")
const MarketingDinnertimeGoldenReplayTestClass = preload("res://core/tests/marketing_dinnertime_golden_replay_test.gd")
const MilestoneEffectValuesTestClass = preload("res://core/tests/milestone_effect_values_test.gd")
const RandomMapGenerationTestClass = preload("res://core/tests/random_map_generation_test.gd")
const DinnertimeSettlementTestClass = preload("res://core/tests/dinnertime_settlement_test.gd")
const BankruptcyTestClass = preload("res://core/tests/bankruptcy_test.gd")

@onready var output: RichTextLabel = $Root/Output
@onready var run_button: Button = $Root/TopBar/RunButton

var _exit_code: int = 0

func _ready() -> void:
	output.clear()
	output.append_text("全部测试聚合：按既定顺序依次运行所有 headless 测试。\n")
	output.append_text("提示：CLI 可用 `-- --autorun` 自动执行并退出。\n")
	if _should_autorun():
		_exit_code = _run_all()
		get_tree().quit(_exit_code)

func _on_back_pressed() -> void:
	SceneManager.go_back()

func _on_run_pressed() -> void:
	if is_instance_valid(run_button):
		run_button.disabled = true
	_exit_code = _run_all()
	if is_instance_valid(run_button):
		run_button.disabled = false

func _run_all() -> int:
	output.append_text("\n--- 开始运行全部测试 ---\n")
	print("[AllTests] START args=%s" % str(OS.get_cmdline_user_args()))

	var tests: Array[Dictionary] = [
		{
			"name": "ReplayTest",
			"fn": func() -> Result: return ReplayDeterminismTestClass.run(2, 12345, 20),
		},
		{
			"name": "EmployeeTest",
			"fn": func() -> Result: return EmployeeActionTestClass.run(2, 12345),
		},
		{
			"name": "RecruitOnCreditRulesTest",
			"fn": func() -> Result: return RecruitOnCreditRulesTestClass.run(2, 12345),
		},
		{
			"name": "PaydaySalaryTest",
			"fn": func() -> Result: return PaydaySalaryTestClass.run(2, 12345),
		},
		{
			"name": "InitialCompanyTest",
			"fn": func() -> Result: return InitialCompanyTestClass.run(2, 12345),
		},
		{
			"name": "MandatoryActionsTest",
			"fn": func() -> Result: return MandatoryActionsTestClass.run(2, 12345),
		},
		{
			"name": "ProduceFoodTest",
			"fn": func() -> Result: return ProduceFoodTestClass.run(2, 12345),
		},
		{
			"name": "ProcureDrinksTest",
			"fn": func() -> Result: return ProcureDrinksTestClass.run(2, 12345),
		},
		{
			"name": "ProcureDrinksRouteRulesTest",
			"fn": func() -> Result: return ProcureDrinksRouteRulesTestClass.run(2, 12345),
		},
		{
			"name": "PlaceHouseRulesTest",
			"fn": func() -> Result: return PlaceHouseRulesTestClass.run(2, 12345),
		},
		{
			"name": "AddGardenRulesTest",
			"fn": func() -> Result: return AddGardenRulesTestClass.run(2, 12345),
		},
		{
			"name": "PlaceRestaurantRulesTest",
			"fn": func() -> Result: return PlaceRestaurantRulesTestClass.run(2, 12345),
		},
		{
			"name": "MoveRestaurantRulesTest",
			"fn": func() -> Result: return MoveRestaurantRulesTestClass.run(2, 12345),
		},
		{
			"name": "FailFastParsingTest",
			"fn": func() -> Result: return FailFastParsingTestClass.run(2, 12345),
		},
		{
			"name": "ArchiveFailFastTest",
			"fn": func() -> Result: return ArchiveFailFastTestClass.run(2, 12345),
		},
		{
			"name": "InvariantsFailFastTest",
			"fn": func() -> Result: return InvariantsFailFastTestClass.run(2, 12345),
		},
		{
			"name": "RoundStateFailFastTest",
			"fn": func() -> Result: return RoundStateFailFastTestClass.run(2, 12345),
		},
		{
			"name": "CleanupInventoryTest",
			"fn": func() -> Result: return CleanupInventoryTestClass.run(2, 12345),
		},
		{
			"name": "FireActionTest",
			"fn": func() -> Result: return FireActionTestClass.run(2, 12345),
		},
		{
			"name": "CompanyStructureTest",
			"fn": func() -> Result: return CompanyStructureTestClass.run(2, 12345),
		},
		{
			"name": "OrderOfBusinessTest",
			"fn": func() -> Result: return OrderOfBusinessTestClass.run(3, 12345),
		},
			{
				"name": "MilestoneSystemTest",
				"fn": func() -> Result: return MilestoneSystemTestClass.run(2, 12345),
			},
			{
				"name": "ModulePackageLoaderV2Test",
				"fn": func() -> Result: return ModulePackageLoaderV2TestClass.run(2, 12345),
			},
			{
				"name": "ContentCatalogV2Test",
				"fn": func() -> Result: return ContentCatalogV2TestClass.run(2, 12345),
			},
			{
				"name": "VisualCatalogLoaderV2Test",
				"fn": func() -> Result: return VisualCatalogLoaderV2TestClass.run(2, 12345),
			},
			{
				"name": "ModulePlanBuilderV2Test",
				"fn": func() -> Result: return ModulePlanBuilderV2TestClass.run(2, 12345),
			},
			{
				"name": "ModuleSystemV2BootstrapTest",
				"fn": func() -> Result: return ModuleSystemV2BootstrapTestClass.run(2, 12345),
			},
				{
					"name": "SettlementRegistryV2Test",
					"fn": func() -> Result: return SettlementRegistryV2TestClass.run(2, 12345),
				},
				{
					"name": "DinnertimeRoutePurchaseRegistryV2Test",
					"fn": func() -> Result: return DinnertimeRoutePurchaseRegistryV2TestClass.run(2, 12345),
				},
				{
					"name": "EffectRegistryV2Test",
					"fn": func() -> Result: return EffectRegistryV2TestClass.run(2, 12345),
				},
			{
				"name": "PoolBuilderV2Test",
				"fn": func() -> Result: return PoolBuilderV2TestClass.run(2, 12345),
			},
					{
						"name": "MarketingCampaignsTest",
						"fn": func() -> Result: return MarketingCampaignsTestClass.run(2, 12345),
					},
					{
						"name": "MassMarketeersV2Test",
						"fn": func() -> Result: return MassMarketeersV2TestClass.run(2, 12345),
					},
					{
						"name": "KetchupMechanismV2Test",
						"fn": func() -> Result: return KetchupMechanismV2TestClass.run(2, 12345),
					},
					{
						"name": "KimchiV2Test",
						"fn": func() -> Result: return KimchiV2TestClass.run(2, 12345),
					},
					{
						"name": "CoffeeV2Test",
						"fn": func() -> Result: return CoffeeV2TestClass.run(12345),
					},
					{
						"name": "MovieStarsV2Test",
						"fn": func() -> Result: return MovieStarsV2TestClass.run(3, 12345),
					},
					{
						"name": "NightShiftManagersV2Test",
						"fn": func() -> Result: return NightShiftManagersV2TestClass.run(2, 12345),
					},
					{
						"name": "NewDistrictsV2Test",
						"fn": func() -> Result: return NewDistrictsV2TestClass.run(2, 12345),
					},
		{
			"name": "FryChefsV2Test",
			"fn": func() -> Result: return FryChefsV2TestClass.run(2, 12345),
		},
		{
			"name": "RuralMarketeersV2Test",
			"fn": func() -> Result: return RuralMarketeersV2TestClass.run(2, 12345),
		},
		{
			"name": "GourmetFoodCriticsV2Test",
			"fn": func() -> Result: return GourmetFoodCriticsV2TestClass.run(2, 12345),
		},
		{
			"name": "ReservePricesV2Test",
			"fn": func() -> Result: return ReservePricesV2TestClass.run(2, 12345),
		},
					{
						"name": "HardChoicesV2Test",
						"fn": func() -> Result: return HardChoicesV2TestClass.run(2, 12345),
					},
					{
						"name": "PhaseOrderOverrideV2Test",
						"fn": func() -> Result: return PhaseOrderOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "WorkingSubPhaseOrderOverrideV2Test",
						"fn": func() -> Result: return WorkingSubPhaseOrderOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "SettlementTriggerOverrideV2Test",
						"fn": func() -> Result: return SettlementTriggerOverrideV2TestClass.run(2, 12345),
					},
					{
						"name": "SettlementTriggerOverrideExtraV2Test",
						"fn": func() -> Result: return SettlementTriggerOverrideExtraV2TestClass.run(2, 12345),
					},
				{
					"name": "PaydaySubPhaseV2Test",
					"fn": func() -> Result: return PaydaySubPhaseV2TestClass.run(2, 12345),
				},
				{
					"name": "ActionAvailabilityOverrideV2Test",
					"fn": func() -> Result: return ActionAvailabilityOverrideV2TestClass.run(2, 12345),
				},
				{
					"name": "NewMilestonesV2Test",
					"fn": func() -> Result: return NewMilestonesV2TestClass.run(2, 12345),
				},
					{
						"name": "NewMilestonesNewRestaurantV2Test",
						"fn": func() -> Result: return NewMilestonesNewRestaurantV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesMarketingTraineeV2Test",
						"fn": func() -> Result: return NewMilestonesMarketingTraineeV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesCampaignManagerV2Test",
						"fn": func() -> Result: return NewMilestonesCampaignManagerV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBrandManagerV2Test",
						"fn": func() -> Result: return NewMilestonesBrandManagerV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBrandDirectorV2Test",
						"fn": func() -> Result: return NewMilestonesBrandDirectorV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBurgerSoldV2Test",
						"fn": func() -> Result: return NewMilestonesBurgerSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesCokeSoldV2Test",
						"fn": func() -> Result: return NewMilestonesCokeSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesPizzaSoldV2Test",
						"fn": func() -> Result: return NewMilestonesPizzaSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesLemonadeSoldV2Test",
						"fn": func() -> Result: return NewMilestonesLemonadeSoldV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesBeerTrainerPaydayV2Test",
						"fn": func() -> Result: return NewMilestonesBeerTrainerPaydayV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesRecruiterWaitressV2Test",
						"fn": func() -> Result: return NewMilestonesRecruiterWaitressV2TestClass.run(2, 12345),
					},
					{
						"name": "NewMilestonesDiscountManagerBankBurnV2Test",
						"fn": func() -> Result: return NewMilestonesDiscountManagerBankBurnV2TestClass.run(2, 12345),
					},
					{
						"name": "LobbyistsV2Test",
						"fn": func() -> Result: return LobbyistsV2TestClass.run(2, 12345),
					},
					{
						"name": "NoodlesSushiV2Test",
						"fn": func() -> Result: return NoodlesSushiV2TestClass.run(2, 12345),
					},
					{
						"name": "MarketingSettlementFailFastTest",
						"fn": func() -> Result: return MarketingSettlementFailFastTestClass.run(2, 12345),
					},
			{
				"name": "MarketingDinnertimeGoldenReplayTest",
				"fn": func() -> Result: return MarketingDinnertimeGoldenReplayTestClass.run(2, 12345),
			},
			{
				"name": "MilestoneEffectValuesTest",
				"fn": func() -> Result: return MilestoneEffectValuesTestClass.run(2, 12345),
			},
			{
				"name": "RandomMapGenerationTest",
				"fn": func() -> Result: return RandomMapGenerationTestClass.run(2, 12345),
			},
			{
				"name": "DinnertimeSettlementTest",
				"fn": func() -> Result: return DinnertimeSettlementTestClass.run(2, 12345),
			},
			{
				"name": "BankruptcyTest",
				"fn": func() -> Result: return BankruptcyTestClass.run(2, 12345),
			},
		]

	var passed := 0
	var failed: Array[String] = []
	var total_start := Time.get_ticks_msec()

	for test_def in tests:
		var name: String = test_def.get("name", "UnknownTest")
		var fn: Callable = test_def.get("fn", Callable())

		output.append_text("\n== %s ==\n" % name)
		print("[AllTests] RUN %s" % name)

		var start := Time.get_ticks_msec()
		var result: Result = fn.call()
		var duration_ms := Time.get_ticks_msec() - start

		if result.ok:
			passed += 1
			output.append_text("PASS (%dms)\n" % duration_ms)
			print("[AllTests] PASS %s (%dms)" % [name, duration_ms])
		else:
			failed.append(name)
			output.append_text("FAIL (%dms): %s\n" % [duration_ms, result.error])
			push_error("[AllTests] FAIL %s: %s" % [name, result.error])
			print("[AllTests] FAIL %s (%dms): %s" % [name, duration_ms, result.error])

	var total_ms := Time.get_ticks_msec() - total_start
	output.append_text("\n--- 汇总 ---\n")
	output.append_text("通过: %d/%d, 总耗时: %dms\n" % [passed, tests.size(), total_ms])
	print("[AllTests] SUMMARY passed=%d/%d failed=%s total_ms=%d" % [passed, tests.size(), str(failed), total_ms])

	return 0 if failed.is_empty() else 1

func _should_autorun() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("autorun") or args.has("--autorun"):
		return true
	return OS.has_feature("headless")
