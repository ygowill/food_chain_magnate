# 语义步进时间线构建（step_index）
# 该文件位于 gameplay 层：属于 UI/回放/日志派生视图构建，不是 core 执行内核。
# 目标：
# - 在“命令（Command）”之外，引入可停留的阶段切分点（phase step），避免 auto-advance 把多个大阶段合并成一个位置。
# - Working 内的小阶段（sub_phase）尽可能打包：sub_phase 变化不额外生成 step，仅更新当前 step 的状态快照与事件归属。
#
# 约定（与 docs/design/archive/replay_log_timeline_refactor_plan.md#M4.2 对齐）：
# - step=-1 表示初始状态（checkpoint[0]），不计入 steps 数组。
# - “阶段 step”的状态快照以“进入该阶段后的状态（含 enter settlement/enter hooks）”为准；
#   但若该阶段内部发生 sub_phase 自动推进（不跨 phase），会被打包到同一个 step，并更新该 step 的快照。
# - `*_REPORT` 等“离开阶段时发射”的事件归属到离开前阶段（phase_segment=old_phase）。
extends RefCounted

const BuildFullImplClass = preload("res://gameplay/replay/step_timeline_build/build_full_impl.gd")

static func build_full(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("StepTimelineBuild: engine 为空")

	var pm = engine.phase_manager
	var trace_was_enabled := false
	if pm != null:
		trace_was_enabled = pm.is_timeline_trace_enabled()
		pm.set_timeline_trace_enabled(true)

	var r := _build_full_impl(engine)

	if pm != null:
		pm.set_timeline_trace_enabled(trace_was_enabled)

	return r

static func _build_full_impl(engine: GameEngine) -> Result:
	return BuildFullImplClass.build_full_impl(engine)

