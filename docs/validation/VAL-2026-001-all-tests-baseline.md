---
id: VAL-2026-001
doc_kind: validation
status: completed
created: 2026-07-11
updated: 2026-07-11
owners: [quality-engineering]
feature_ids: [F-001, F-002, F-003]
requirement_ids: [REQ-001, REQ-002, NFR-001, REQ-003, REQ-004, NFR-002, REQ-005, REQ-006, REQ-007, REQ-008, NFR-005]
commit: 604e27d6
verdict: pass
---

# VAL-2026-001：2026-07-11 AllTests headless 基线

## 结论

提交 604e27d6 的 AllTests 严格模式运行完成，405/405 个测试通过，脚本退出码为 0。verdict: pass 只表示这次本地 headless 测试运行通过；资源泄漏警告、真实平台联机 E2E、Web 性能和 Tutorial Campaign 尚未交付的关卡不在 pass 结论内。

## 验证范围

- Godot 项目主场景 smoke、core 逻辑、架构边界和 UI headless 聚合测试。
- F-001 的模块装配、依赖计划、Strict Mode 和边界守卫。
- F-002 的 full snapshot bootstrap、单 full-engine cache 和 Bootstrap ready gate。
- F-003 已落地部分的教学资产、运行时隔离和场景边界。

明确不覆盖：

- 真实平台后端、WebSocket 网络、多个独立 Godot 进程或弱网组合 E2E。
- Web 导出和浏览器帧性能。
- Tutorial Campaign 设计中尚未落地的完整逐关流程与用户可用性验收。
- Godot 退出资源泄漏的根因或修复。

## 环境

| 项目 | 值 |
|---|---|
| Commit | 604e27d6 |
| Engine | Godot 4.5.1.stable.official.f62fdbde1 |
| Runner | 本地 macOS headless，Asia/Shanghai |
| 开始时间 | 2026-07-11 20:21:30 +08:00 |
| 套件耗时 | 76,973 ms |

## 命令与结果

    tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit

| 项目 | 结果 |
|---|---|
| Script exit code | 0 |
| Test summary | passed=405/405, failed=[] |
| Suite verdict | pass |

## Feature / Requirement 对照

| Feature / ID | 本次证物 | 判定 |
|---|---|---|
| F-001 / REQ-001 | ModulePackageLoaderV2Test、ModulePlanBuilderV2Test | pass |
| F-001 / REQ-002 | ModuleSystemV2BootstrapTest | pass |
| F-001 / NFR-001 | ModuleBoundaryContractTest、CoreArchitectureBoundaryContractTest | pass |
| F-002 / REQ-003 | OnlineResumeFullSnapshotBootstrapTest、OnlineResumeSingleFullEngineCacheTest | pass |
| F-002 / REQ-004 | OnlineResumeSingleFullEngineCacheTest、timeline forwarding 与只读 history adapter 相关聚合测试 | pass |
| F-002 / NFR-002 | OnlineMatchBootstrapServerFlowTest、OnlineMatchBootstrapResumeHistoryGateTest、OnlineResumeErrorPolicyTest | pass |
| F-003 / REQ-005 | 仅证明参考资产存在；未覆盖完整基础规则教学链 | not-covered |
| F-003 / REQ-006 | Setup/Game target contract 证明目标节点存在；未覆盖全部动作触发时机与可完成性 | not-covered |
| F-003 / REQ-007 | 未进行基础/扩展规则分层的用户路径验收 | not-covered |
| F-003 / REQ-008 | 本套件没有完整关卡流程 | not-covered |
| F-003 / NFR-005 | TutorialRuntimeScopeTest、TutorialMatchRuntimeTest、TutorialSceneBoundaryContractTest | pass |

Feature 的最终状态和完整限制以对应聚合页为准：

- [F-001 Modules V2](../features/F-001-modules-v2.md)
- [F-002 Online Resume / Bootstrap](../features/F-002-online-resume-bootstrap.md)
- [F-003 Tutorial Campaign](../features/F-003-tutorial-campaign.md)

## 原始证物与保留性

本次原始日志位于本地 .godot/AllTests.log：

- 文件大小：2,190,228 bytes
- SHA-256：00f216dcfc6d540a11be21911c84faa2d853b04fab90e5350b2746ad49ea4821
- Git 状态：被 .gitignore 忽略，不随提交保留
- 证物等级：local evidence；本报告是持久摘要，不能替代可下载的原始日志

因此，后续 PR Gate 应上传原始日志或结构化测试摘要为 commit 绑定的 CI Artifact。本报告不得被描述为已有远程 CI 证物。

## 已知警告

测试摘要之后出现以下 Godot 退出警告：

- 102 个 CanvasItem RID 泄漏；
- 26 个 DummyTexture、2 个 DummyShader、122 个 ShapedText、5 个 Font RID allocation 泄漏；
- ObjectDB instances leaked at exit；
- 194 resources still in use at exit。

套件严格模式仍返回 0，说明当前 runner 将这些退出期资源警告与测试断言失败区分处理。该 pass 不表示泄漏已解决，也不应在未来 CI 中静默丢弃这些警告。

## 后续证物要求

- quality-engineering：在 pull_request CI 保存 AllTests 日志、SHA 与结构化摘要。
- online-systems：为 F-002 增加真实多客户端平台 E2E Validation。
- player-experience：REQ-007 每完成一组关卡，新增交互 E2E 与人工可用性证物。
