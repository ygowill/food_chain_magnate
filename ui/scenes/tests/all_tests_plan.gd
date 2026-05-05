# 全部测试计划（由 all_tests.gd 运行器消费）
extends RefCounted

const BootstrapSuite = preload("res://ui/scenes/tests/suites/all_tests_bootstrap_suite.gd")
const CoreArchitectureSuite = preload("res://ui/scenes/tests/suites/all_tests_core_architecture_suite.gd")
const OnlineSuite = preload("res://ui/scenes/tests/suites/all_tests_online_suite.gd")
const UiSuite = preload("res://ui/scenes/tests/suites/all_tests_ui_suite.gd")
const CoreRulesSuite = preload("res://ui/scenes/tests/suites/all_tests_core_rules_suite.gd")
const AiSuite = preload("res://ui/scenes/tests/suites/all_tests_ai_suite.gd")
const RuntimeTimelineSuite = preload("res://ui/scenes/tests/suites/all_tests_runtime_timeline_suite.gd")
const ModulesSuite = preload("res://ui/scenes/tests/suites/all_tests_modules_suite.gd")
const SettlementSuite = preload("res://ui/scenes/tests/suites/all_tests_settlement_suite.gd")

static func build_tests(host) -> Array[Dictionary]:
	var tests: Array[Dictionary] = []
	_append_suite(tests, BootstrapSuite.build_tests(host))
	_append_suite(tests, CoreArchitectureSuite.build_tests(host))
	_append_suite(tests, OnlineSuite.build_tests(host))
	_append_suite(tests, UiSuite.build_tests(host))
	_append_suite(tests, CoreRulesSuite.build_tests(host))
	_append_suite(tests, AiSuite.build_tests(host))
	_append_suite(tests, RuntimeTimelineSuite.build_tests(host))
	_append_suite(tests, ModulesSuite.build_tests(host))
	_append_suite(tests, SettlementSuite.build_tests(host))
	return tests

static func _append_suite(target: Array[Dictionary], suite_tests: Array[Dictionary]) -> void:
	for test_def in suite_tests:
		target.append(test_def)
