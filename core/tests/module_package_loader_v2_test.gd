# 模块系统 V2：module.json 严格解析 + 模块包加载器
class_name ModulePackageLoaderV2Test
extends RefCounted

const ModuleManifestClass = preload("res://core/modules/v2/module_manifest.gd")
const ModulePackageLoaderClass = preload("res://core/modules/v2/module_package_loader.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var ok_manifest := {
		"schema_version": 1,
		"id": "hello_module",
		"name": "",
		"version": "1.2.3",
		"priority": 50,
		"dependencies": ["dep_a", "dep_b"],
		"conflicts": [],
		"entry_script": "res://modules/hello_module/rules/entry.gd",
		"provides": {"effects": ["effect:x"]}
	}
	var parsed_ok := ModuleManifestClass.from_dict(ok_manifest)
	if not parsed_ok.ok:
		return Result.failure("ModuleManifest.from_dict 应成功，实际失败: %s" % parsed_ok.error)
	var mm = parsed_ok.value
	if mm.id != "hello_module":
		return Result.failure("manifest.id 解析错误: %s" % mm.id)
	if mm.name != "hello_module":
		return Result.failure("manifest.name 为空时应回退到 id，实际: %s" % mm.name)
	if mm.version != "1.2.3":
		return Result.failure("manifest.version 解析错误: %s" % mm.version)
	if mm.priority != 50:
		return Result.failure("manifest.priority 解析错误: %d" % mm.priority)
	if mm.dependencies != ["dep_a", "dep_b"]:
		return Result.failure("manifest.dependencies 解析错误: %s" % str(mm.dependencies))
	if not (mm.provides is Dictionary):
		return Result.failure("manifest.provides 类型错误（期望 Dictionary）")

	var bad_schema := {
		"schema_version": 999,
		"id": "x",
		"version": "0.0.1"
	}
	var parsed_bad_schema := ModuleManifestClass.from_dict(bad_schema)
	if parsed_bad_schema.ok:
		return Result.failure("schema_version 不支持时应失败")

	var valid_dir := "res://core/tests/fixtures/modules_v2_valid"
	var loaded_valid := ModulePackageLoaderClass.load_all(valid_dir)
	if not loaded_valid.ok:
		return Result.failure("ModulePackageLoader.load_all(valid) 失败: %s" % loaded_valid.error)
	var registry: Dictionary = loaded_valid.value
	if not (registry is Dictionary):
		return Result.failure("load_all 返回类型错误（期望 Dictionary）")
	if not registry.has("alpha") or not registry.has("beta"):
		return Result.failure("valid fixtures 应包含 alpha/beta，实际: %s" % str(registry.keys()))
	var alpha = registry.get("alpha", null)
	if alpha == null or alpha.version != "1.0.0":
		return Result.failure("alpha manifest 解析错误")
	var beta = registry.get("beta", null)
	if beta == null or beta.name != "beta":
		return Result.failure("beta name 缺失时应回退到 id，实际: %s" % (beta.name if beta != null else "<null>"))

	var mismatch_dir := "res://core/tests/fixtures/modules_v2_invalid_mismatch_id"
	var loaded_mismatch := ModulePackageLoaderClass.load_all(mismatch_dir)
	if loaded_mismatch.ok:
		return Result.failure("目录名与 manifest.id 不一致时应失败")

	var missing_manifest_dir := "res://core/tests/fixtures/modules_v2_invalid_missing_manifest"
	var loaded_missing := ModulePackageLoaderClass.load_all(missing_manifest_dir)
	if loaded_missing.ok:
		return Result.failure("存在缺少 module.json 的目录时应失败")

	return Result.success()
