---
id: F-002
doc_kind: feature
status: validation
created: 2026-03-15
updated: 2026-07-11
owners: [online-systems]
requirement_ids: [REQ-003, REQ-004, NFR-002]
decision_refs: [docs/decisions/0004-online-resume-single-full-engine-startup.md]
validation_refs: [docs/validation/VAL-2026-001-all-tests-baseline.md]
review_after: 2027-01-11
---

# F-002：Online Resume / Bootstrap

## 当前结论

平台房间恢复与联机开局 Bootstrap 的仓库内实现及 headless 回归已落地，当前处于 validation。恢复房客户端在进入 Game 场景前加载完整 archive，使用同一个 full-history engine 作为 live 与历史真相，并预构建 timeline/log cache；Bootstrap 负责本地就绪、失败上报和统一 Loading 协调。旧的 runtime/full-history 双引擎 fast-start 不是当前方案。真实平台、多客户端和弱网 E2E 尚未形成持久证物，因此不能标记 done。

## 背景、目标与范围

目标是让断线或冷启动后的玩家恢复到服务器权威对局，同时避免双历史坐标和场景提前切换导致的不一致。范围包括平台恢复上下文、snapshot/archive 传输、本地 engine bootstrap、ready/failure 协议、单引擎历史缓存、resync 与进度反馈。

Non-goals：

- 不以最短进场时间换取短历史 fast-start。
- 不允许客户端从历史点本地分叉继续执行。
- 不把半完成的 Bootstrap session 持久化为可恢复业务状态。
- 不以本地 headless 测试替代真实平台后端、跨进程网络与 Web 性能验收。

## Requirements 与验收标准

这些 Requirement ID 的规范性定义来自[项目级需求](../REQUIREMENTS.md)；本页只维护 F-002 的验收解释、判定与证物映射。

| ID | Requirement / AC | 判定 | 证物 |
|---|---|---|---|
| REQ-003 | 恢复房在进入 Game 前完成 full archive 回放，live 与 full-history 指向同一 engine，并预构建 timeline/log cache | pass | [完整 snapshot bootstrap 测试](../../core/tests/online_resume_full_snapshot_bootstrap_test.gd)、[单引擎 cache 测试](../../core/tests/online_resume_single_full_engine_cache_test.gd) |
| REQ-004 | live、日志、timeline 与 replay 使用同一完整历史坐标；权威命令只推进单 engine，历史查看保持只读 | pass | [单引擎 cache 测试](../../core/tests/online_resume_single_full_engine_cache_test.gd)、[Cache forwarding 测试](../../core/tests/net_client_online_resume_cached_timeline_forwarding_test.gd)、[History view adapter](../../ui/scenes/game/timeline/online_resume_history_view_support.gd) |
| NFR-002 | Bootstrap、snapshot/archive 回放和 cache 构建具有可观察进度；ready gate、过期消息与失败上报显式且失败后进入安全状态 | pass | [Server flow 测试](../../core/tests/online_match_bootstrap_server_flow_test.gd)、[Resume history gate 测试](../../core/tests/online_match_bootstrap_resume_history_gate_test.gd)、[Error policy 测试](../../core/tests/online_resume_error_policy_test.gd)、[基线验证](../validation/VAL-2026-001-all-tests-baseline.md) |

## Related Artifacts

### 原始需求与设计意图

- [项目级 Requirements](../REQUIREMENTS.md) 定义 REQ-003、REQ-004 与 NFR-002。
- [单 full-engine 启动方案](../online/online_resume_single_full_engine_startup_2026-04-17.md) 记录恢复链路的目标、取舍和验证重点。
- [Bootstrap / 统一 Loading 历史方案](../online/archive/online_match_bootstrap_loading_redesign.md) 记录 Starting、ready gate、进度与失败处理的原始需求；它是只读过程材料，当前状态以本页和 Architecture 为准。

### Decisions

- [ADR-0004：恢复房单 full-engine 启动](../decisions/0004-online-resume-single-full-engine-startup.md)

### Architecture

- [Online Multiplayer 当前架构](../architecture/70-online-multiplayer.md)
- [平台后端与账号边界](../architecture/71-online-platform-backend-and-accounts.md)
- [Replay 与 Timeline](../architecture/42-gameplay-replay-timelines.md)

### Plans

- [Online recovery roadmap](../online/online_recovery_roadmap_2026-03-30.md)
- [Resume hot-path rebuild plan](../online/archive/online_resume_hot_path_rebuild_plan_2026-04-16.md)
- [Live command / UI log performance plan](../plans/PLAN-2026-001-online-live-command-ui-log-performance.md)

以上是过程或历史材料；当其 fast-start、双引擎或进度描述与 ADR-0004 冲突时，以 ADR-0004 和当前 Architecture 为准。

### Code

- [OnlineMatchBootstrap](../../autoload/online_match_bootstrap.gd)
- [NetClient resume support](../../autoload/net_client_online_resume_support.gd)
- [OnlineResumeSessionState](../../autoload/online_resume_session_state.gd)
- [Startup resume controller](../../ui/scenes/game/controllers/startup_online_resume_controller.gd)
- [Full-history adapter](../../ui/scenes/game/timeline/online_resume_full_history_adapter.gd)
- [Server room](../../server/room.gd)

### Tests and Validation

- [Full snapshot bootstrap](../../core/tests/online_resume_full_snapshot_bootstrap_test.gd)
- [Single full-engine cache](../../core/tests/online_resume_single_full_engine_cache_test.gd)
- [Bootstrap server flow](../../core/tests/online_match_bootstrap_server_flow_test.gd)
- [Bootstrap resume history gate](../../core/tests/online_match_bootstrap_resume_history_gate_test.gd)
- [Reconnect flow](../../core/tests/game_online_resync_reconnect_flow_test.gd)
- [Error policy](../../core/tests/online_resume_error_policy_test.gd)
- [2026-07-11 AllTests 基线](../validation/VAL-2026-001-all-tests-baseline.md)

## 已知限制与偏差

- 当前持久 Validation 证明本地 headless 套件通过，不证明真实平台 API、WebSocket、多个 Godot 进程和弱网组合已在同一提交上完成 E2E。
- 完整 archive 回放使恢复进场时间更长；这是 ADR-0004 接受的取舍，仍需用真实长局数据持续监测。
- Web 下 descriptor 分帧、Loading 文案和等待态自动打开日志属于用户体验与性能约束，自动功能测试不能替代帧耗时和人工观感证物。
- 本地基线存在 Godot 退出资源泄漏警告，尚未在本 Feature 内归因。

## Next Action

- online-systems：在真实平台环境补充同 commit 的创建、加入、断线、冷恢复与 resync 多客户端 E2E Validation。
- performance-engineering：保存长历史恢复耗时、进场后 command hot path 与 Web 构建的性能基线。
- repository-admin：把 Docs Governance 与 PR Quality Gate 配置为受保护分支的 required checks；工作流文件本身不等于平台门禁已启用。
