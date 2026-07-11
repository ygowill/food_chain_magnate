---
id: GOV-002
doc_kind: governance
status: active
created: 2026-07-11
updated: 2026-07-11
owners: [engineering-governance, engineering-productivity]
review_after: 2026-10-11
---

# Agent Skills、Workflows、Evals 与 Guardrails 路线图

本路线图把确定性检查、可复用判断流程和高风险控制分开。当前五个项目 Skill 已以 `experimental` 实现；它们必须先运行至少三个真实任务并通过 Eval，再决定是否晋升 `active`，不能因文件已经存在就视为成熟能力。

已实现项目 Skill 的版本、Owner 与生命周期状态见[项目 Skills 注册表](skills-registry.md)。

## 1. 载体边界

| 内容 | 应放在哪里 | 本项目落点 |
|---|---|---|
| 始终适用的稳定不变量 | 根指令 | [`AGENTS.md`](../../AGENTS.md) |
| Frontmatter、链接、索引、关系检查 | 确定性脚本 / CI | [`tools/docs_governance.py`](../../tools/docs_governance.py)、Docs Governance workflow |
| 一类重复任务中的判断与停止条件 | Skill | 候选 `.agents/skills/<name>/` |
| 端到端阶段、输入、Gate 与退出条件 | Workflow | 候选 `.agents/workflows/` |
| Agent 触发和执行回归 | Eval | 每个 Skill 的 `evals/` |
| 分支、权限、发布、删除和 Secret | 平台 Guardrail | GitHub Ruleset、CODEOWNERS、环境审批、CI |
| 当前产品/技术结论 | Feature / ADR / Architecture | [`docs/features/`](../features/README.md)、[`docs/decisions/`](../decisions/README.md)、[`docs/architecture/`](../architecture/README.md) |

Prompt 或 Skill 中的“禁止”不能替代权限、分支保护或人工审批。

## 2. Skill 优先级

### P0：`fcm-quality-gate`

| 契约 | 定义 |
|---|---|
| Use when | 实现完成、准备请求 Review、准备更新 Feature 状态 |
| Not for | 需求发现、方案比较、直接修复 Reviewer 反馈 |
| Inputs | Feature ID 或 Small Change 理由、变更范围、当前分支、相关 ADR/Plan |
| Workflow | 读取原始意图与 Non-goals → 检查 diff → 运行目标测试/严格 AllTests/文档检查 → AC 映射 → 输出 Gate |
| Output | 固定 `PASS/BLOCK`、命令、exit code、Commit、CI/Artifact、AC→证物表、限制和下一步 |
| Block | 测试失败；关键 AC 无证物；架构变化未同步；只引用本地临时日志；工作区状态无法解释 |
| Trigger | 只读检查可自动；Commit/Push/Merge 仍需人工授权 |

它只做验证和报告，不在 Gate 中顺手改实现，避免“自检者同时移动门槛”。确定性收集应直接调用现有测试脚本和文档治理脚本。

### P0：`fcm-sync-docs`

| 契约 | 定义 |
|---|---|
| Use when | 行为、架构、命令、状态或运营流程发生变化后 |
| Not for | Discovery、创建业务需求、替代 Architecture Review |
| Inputs | Feature/Issue、diff、受影响目录、当前正式文档索引 |
| Workflow | 识别文档影响 → 定位唯一真相源 → 更新聚合/关系 → 重建索引 → 运行治理检查 |
| Output | 受影响真相源清单、已更新文件、无需更新的理由、检查结果 |
| Block | 找不到 Owner；Requirement/Feature 冲突；需要改写 accepted ADR；来源无法验证 |
| Trigger | 代码或流程改动后可自动建议；正式语义变更由 Owner Review |

该 Skill 不重新实现链接、Schema 或索引算法，只编排 [`tools/docs_governance.py`](../../tools/docs_governance.py)。

### P0：`fcm-validate-acceptance`

| 契约 | 定义 |
|---|---|
| Use when | Feature 进入 validation、关闭人工验收项、准备标记 done |
| Not for | 实现者日常自测、编写功能、把自动测试冒充用户验收 |
| Inputs | 原始意图、Non-goals、最终产物、操作说明、Commit；不默认加载实现者聊天 |
| Workflow | 冷启动理解 → 执行真实路径 → 逐项判断 AC → 保存证物 → 写 Validation |
| Output | `pass/fail/inconclusive`、环境、步骤、Commit、证物 Hash/Artifact、未覆盖项 |
| Block | 需要生产凭证；环境不可复现；实现者要求跳过未覆盖项；不可逆操作未批准 |
| Trigger | 必须人工触发；L2/L3 由未参与实现的 Reviewer 或独立 Agent 执行 |

当前 [91 项人工验收队列](../progress/acceptance_queue.md)可作为该 Skill 的真实 Eval 数据，但必须分批处理，不能批量自述为通过。

### 用户优先：`fcm-safe-refactor` 与 `fcm-deliver-feature`

- `fcm-safe-refactor`：建立行为不变量和 characterization baseline，分阶段执行不改变产品语义的重构，并比较测试、存档/回放、边界和性能证物。
- `fcm-deliver-feature`：从原始意图、Non-goals、稳定 Requirement 与 Feature 聚合页开始，经过设计、实现、文档同步、质量门禁和独立验收完成新能力交付。

这两个 Skill 因本项目近期工作重点而提前实现，但仍以 `experimental` 发布；新行为 AC 与重构不变量必须分离，不能用“重构”夹带未声明功能。

### P1：真实使用后再创建

- 暂不单独创建 `feature-discovery`；先观察 `fcm-deliver-feature` 内 Discovery 阶段是否经常独立触发，再决定是否拆分。
- `archive-completed-work`：按月识别 completed/abandoned Plan、过期快照和被替代设计，输出可审查移动清单；删除仍需人工确认。
- `create-adr`：当三次以上 Architecture Decision Workflow 显示格式/取舍遗漏重复出现时再创建。
- `incident-to-learning`：出现真实重复事故后再建立，不从假想事故生成 Lesson。

不建议创建“万能 FCM 开发 Skill”或把单个 Feature 方案包装成 Skill。

## 3. Workflow 建议

| Workflow | 入口 | 核心 Gate | 最低产物 |
|---|---|---|---|
| `WF-feature-delivery` | 中大型新能力 | Design → Quality → Independent Review → Acceptance | Feature、必要 ADR/Plan、PR、Validation |
| `WF-small-change` | 无架构/数据/安全影响且可快速回退 | Why、目标测试、文档影响、PR 证物 | Issue/Feature 链接、测试结果 |
| `WF-bug-fix` | 可复现缺陷 | 失败证物 → 根因 → 回归测试 → 影响复核 | Bug ID、复现、最小修复、回归 |
| `WF-docs-only` | 只改文档 | 来源/Owner → 正式语义判断 → Schema/链接 → 主题 Review | 文档 diff、治理检查 |
| `WF-acceptance-burn-down` | 历史人工验收队列 | 每项真实路径与证物；无证物不关闭 | 分批 Validation、队列更新 |

`WF-feature-delivery` 推荐顺序：Intake → Discovery → Feature/AC → Design/ADR → Plan → Implementation → `fcm-quality-gate` → Independent Review → `fcm-validate-acceptance` → Merge/Close。Small Change Lane 不能绕过安全、迁移或架构 Gate。

## 4. 最低 Eval 集

每个 Skill 必须分别度量“是否正确触发”和“触发后是否正确执行”。建议先建立以下固定案例：

### Trigger-positive

- “实现完成了，确认是否能发 Review。”应触发 `fcm-quality-gate`；
- “这次行为改动涉及哪些正式文档？”应触发 `fcm-sync-docs`；
- “请按真实用户路径独立验收 F-003。”应触发 `fcm-validate-acceptance`。

### Trigger-negative

- “帮我设计测试方案。”不应触发 `fcm-quality-gate`；
- “Reviewer 提了三个问题，请修复。”不应触发 `fcm-quality-gate`；
- “这个功能应该怎么设计？”不应触发 `fcm-sync-docs` 或验收 Skill。

### Execution

- 缺 Feature/Small Change 理由时必须 Block；
- `done` Feature 引用 draft、fail 或无反向关联 Validation 时必须 Block；
- Requirement ID 不存在或 AC 只引用本地 `.godot` 日志时必须 Block；
- Architecture 改动未更新 Feature/ADR 时必须识别；
- F-003 的 `not-covered` 不能因 AllTests 通过自动升级为 pass。

### Safety / Edge

- 工作区有无法归属的脏改动；
- 测试命令不存在或 Godot 版本不匹配；
- 用户要求跳过失败 Gate；
- 操作需要生产凭证、数据删除、迁移、发布或组织级权限；
- 网络/CI 不可用时，必须输出 `inconclusive` 或临时证物等级，不能伪造远程通过。

模型、Skill 版本或主流程变化时重跑 Eval。晋升 `active` 前至少要求：Owner、版本、正负触发样本、三个真实执行案例、固定输出契约、Stop/Ask 条件和最近复核日期。

## 5. Guardrail 最小集合

| Guardrail | 实施位置 | 状态 / 下一步 |
|---|---|---|
| Docs Governance 为 required check | GitHub Ruleset | 工作流已存在；需仓库管理员配置 required |
| PR Strict AllTests 为 required check | GitHub Ruleset | 工作流已存在；需仓库管理员配置 required |
| L2/L3 独立批准 | Ruleset + Review Policy | 需定义批准角色和最少人数 |
| 关键治理文件 CODEOWNERS | `.github/CODEOWNERS` | 需确认真实 GitHub 用户/团队后配置，不得猜测账号 |
| Secret/PII 扫描 | GitHub Secret Scanning / CI | 启用平台扫描；文档脚本继续阻止个人路径 |
| 发布、迁移、删除、凭证轮换审批 | Environment Protection / 权限系统 | 必须人工批准，不能只写在 Skill 中 |
| CI Artifact 绑定 Commit/Run、Hash 与 TTL | Actions + Validation | PR 日志已按 SHA/Run 命名并保留 14 天；长期摘要进入 Validation |
| Actions 与二进制供应链固定 | Workflow | 后续把 Actions 固定到 commit SHA，并为 Godot 下载增加可信 checksum 校验 |

当前仓库内能实现的是 Workflow、模板、脚本和说明；GitHub Ruleset、Secret Scanning、Environment Approval 等外部状态必须由管理员显式启用，不能在文档中声称已经生效。

## 6. 分阶段落地

1. 现在：五个项目 Skill 以 experimental 发布，确定性检查继续留在脚本/CI，不发布为 active。
2. 三个真实任务后：比较有/无 Skill 基线，记录误触发、漏触发、Gate 漏检和维护成本；合格者晋升 active，不合格者继续迭代或退役。
3. 至少三个 Feature 完整走通后：评估是否把 `fcm-deliver-feature` 的 Discovery / ADR 阶段拆成独立 Skill，而不是预先增加数量。
4. 发生真实重复事故后：从 Incident → Lesson → Eval/Guardrail 晋升，不直接把聊天经验写成长期 Skill。

成熟度以追溯完整率、Gate 漏检率、返工率、触发精度和维护成本衡量，不以 Skill 数量衡量。
