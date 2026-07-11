---
id: GOV-001
doc_kind: governance
status: active
created: 2026-07-11
updated: 2026-07-11
owners: [engineering-governance]
review_after: 2027-01-11
---

# 文档治理规范

本规范定义仓库内长期文档的最小契约。它约束正式文档的身份、状态、所有权、生命周期、追溯关系与证物；它不要求把历史材料一次性改写为新格式。正式热层由治理脚本按明确路径纳管；其他存量材料在重新分类为正式文档时迁移，不能仅靠一条不可检查的“以后补元数据”承诺。

## 1. 基本原则

1. 文档是可审查的知识源，索引和导航页只引用，不复制易变状态。
2. 每个正式 Feature 只有一个稳定聚合页；Feature 页负责当前结论与导航，不复制设计、计划或测试正文。
3. 一种状态只有一个真相源。发现冲突时，先核对代码和证物，再修正对应真相源，不能在另一份文档中增加第二套“当前状态”。
4. 完成必须有证物。只有“已完成”“测试通过”等文字，不构成验证。
5. Owners 必须是团队或职责角色，不能写 Agent 名、会话名或临时个人工作区。
6. 历史文档保留历史原貌；被替代时增加明确替代关系，不能静默重写为“从未存在”。

## 2. Frontmatter 最小契约

正式文档至少包含以下字段：

    ---
    id: F-001
    doc_kind: feature
    status: in-progress
    created: 2026-07-11
    updated: 2026-07-11
    owners: [gameplay-engineering]
    ---

字段规则：

| 字段 | 规则 |
|---|---|
| id | 全仓唯一、创建后不可复用，文件改名或移动时保持不变 |
| doc_kind | 只能使用本规范定义的枚举 |
| status | 必须使用对应 doc_kind 的状态枚举 |
| created / updated | ISO 日期 YYYY-MM-DD；正文或关系发生实质变化时更新 updated |
| owners | 非空 YAML 列表；使用稳定团队或职责角色 |
| feature_ids | ADR、Plan、Validation 等与 Feature 的稳定关联；无关联时使用空列表 |
| requirement_ids | 需求稳定 ID；不得因改写标题而改变 |
| decision_refs / validation_refs | Feature 指向正式 ADR / Validation 的仓库相对路径；`*_ids` 表示稳定身份，`*_refs` 表示文件位置 |
| source_refs | 原始来源或迁移来源的仓库相对路径；不能指向个人工作区 |
| supersedes / superseded_by | 使用稳定文档 ID；无关联时使用空列表 |
| review_after | 需要复核的当前规范、Architecture、Feature 或 ADR 使用 ISO 日期 |
| commit | Validation 必填，使用被验证提交的完整或足以唯一定位的 SHA |
| verdict | Validation 必填；最终报告只能为 pass、fail 或 inconclusive |

模板中的占位值必须在创建正式文档时全部替换。README 导航页和历史原始材料可以不补 Frontmatter，但不能承担 Feature 当前状态、ADR 有效性或测试结论。

## 3. 合法 doc_kind 与状态

合法 doc_kind：

- vision
- governance
- requirement
- architecture
- feature
- decision
- research
- plan
- review
- validation
- release
- incident
- lesson
- runbook
- reference
- backlog
- acceptance-queue
- progress

状态枚举：

| doc_kind | 合法 status |
|---|---|
| vision | draft, active, superseded, retired |
| governance | draft, active, superseded, retired |
| requirement | draft, accepted, superseded, retired |
| architecture | draft, active, superseded, archived |
| feature | idea, discovery, planned, in-progress, validation, done, cancelled |
| decision | proposed, accepted, rejected, superseded |
| research | draft, active, completed, archived |
| plan | draft, active, completed, abandoned, archived |
| review | draft, completed, archived |
| validation | draft, completed, superseded |
| release | draft, released, withdrawn |
| incident | open, mitigated, resolved, archived |
| lesson | draft, validated, institutionalized, archived |
| runbook | draft, active, superseded, retired |
| reference | draft, active, superseded, archived |
| backlog | active, archived |
| acceptance-queue | active, archived |
| progress | current, historical, archived |

Validation 的 status 表示报告生命周期，verdict 表示验证结论。draft 报告可用 verdict: pending；completed 报告必须使用 pass、fail 或 inconclusive。

## 4. 单一真相源

| 易变事实 | 唯一真相源 |
|---|---|
| Feature 当前状态、范围、Non-goals、开放事项 | 对应 docs/features/F-*.md |
| Requirement ID 与规范性定义 | docs/REQUIREMENTS.md；Feature 只维护范围、Non-goals、验收解释、判定和证物映射 |
| ADR 是否有效、替代关系 | 对应 docs/decisions/*.md Frontmatter |
| 当前系统如何工作 | docs/architecture/ 当前文档与代码；冲突时必须基于代码和测试修正文档 |
| Plan 当前执行状态 | 对应活跃 Plan；完成后归档，不在 Feature 页复制逐项进度 |
| 某次提交的测试结论 | 对应 Validation 报告与其 CI/日志证物 |
| PR、Commit 是否存在或已合入 | Git 历史或托管平台 |
| 活跃工作项列表 | 项目 Backlog，不使用历史 Issue 日志替代 |

Feature 页可以摘要其他材料的当前结论，但必须链接原始材料，并明确冲突时以哪个真相源为准。

## 5. 三跳可达规则

从文档入口或 Feature 索引开始，最多三次链接跳转必须能找到：

- 为什么做、原始需求和 Non-goals；
- 当前 status 与 owners；
- 关键 ADR；
- 当前 Architecture；
- 实施 Plan 或历史 Plan；
- 主要代码入口；
- 测试与 Validation；
- 已知限制和后续事项。

为满足这一规则，每个 Feature 聚合页必须直接列出以上内容。导航链推荐为：文档入口 → Feature 索引 → Feature 页 → 具体证物。禁止依赖仓库外个人绝对路径完成三跳链。

## 6. 生命周期

### Feature

1. 正式立项时由产品或工程 Owner 创建，分配 F-NNN。
2. discovery/planned 阶段补齐目标、范围、Non-goals、Requirement IDs 和验收标准。
3. in-progress 阶段链接批准的 ADR、Plan、代码入口和已知偏差。
4. 进入 validation 前，验收标准必须逐项有证物计划。
5. 只有验收标准已判定、关键 Validation 已链接、限制已披露，且至少一个 `completed + pass` Validation 反向关联该 Feature 并覆盖其 Requirement IDs 时才能标记 done。
6. Feature 页永久保留；后续能力改变时更新同一聚合页，新的独立能力使用新 ID。

### ADR / Decision

1. 高影响、跨模块、难以逆转或存在重要取舍的决策先以 proposed 创建。
2. 人类责任 Owner 批准后改为 accepted；rejected 保留原因。
3. accepted 后不改写原决策结论。新结论以新 ADR 替代，并在两侧填写 supersedes / superseded_by。
4. 到达 review_after 或关联架构发生实质变化时复核；仍有效可只更新复核日期和 updated。
5. ADR 永久保留，不因被替代删除。

### Plan

1. 中等以上改动在实施前由工程 Owner 创建，分配 PLAN-YYYY-NNN，并链接 Feature/ADR。
2. active 只表示正在执行；步骤完成以 Git 和 Validation 为证，不由聊天记录证明。
3. 完成后改为 completed，记录实际偏差和验证入口，再移入按年月组织的归档目录。
4. 不再执行的计划改为 abandoned 并说明原因；不能继续显示为 active。

### Validation

1. 在 Feature 进入 validation 前创建，分配 VAL-YYYY-NNN，绑定 feature_ids 与 commit。
2. 报告必须记录命令、环境、退出码、结果摘要、原始证物位置和已知警告。
3. 自动测试不能替代未覆盖的手工、跨进程、平台或用户验收；未覆盖项必须显式写入限制。
4. completed + pass 只证明报告列出的范围，不自动证明整个 Feature 已完成。
5. 同一提交与范围的重复运行应更新或链接同一报告；不同提交、环境或验证范围创建新报告。
6. 关键摘要长期保留；大型原始日志可存 CI Artifact 或外部对象存储，并记录稳定链接与 Hash。

## 7. 完成证物门槛

Feature 标记 done 前至少满足：

- 每个 Requirement/AC 有 pass、fail、deferred 或 not-covered 的明确判定；
- 关键自动化命令、commit、exit code 和摘要进入 Validation；
- 需要手工或跨环境验收的内容有证物，或在限制中明确未覆盖并由 Owner 接受；
- 相关 ADR 和当前 Architecture 可从 Feature 页直达；
- 没有引用个人 Downloads、旧 worktree 或本地临时日志作为唯一证物。

## 8. 模板

- [Feature 模板](../templates/feature.md)
- [Validation 模板](../templates/validation.md)
- [Decision 模板](../templates/decision.md)

## 9. 当前纳管范围与生成索引

治理脚本强制纳管：

- `docs/VISION.md`、`docs/REQUIREMENTS.md`、`docs/BACKLOG.md`；
- `docs/features/*.md`、`docs/decisions/*.md`、`docs/validation/*.md`、`docs/governance/*.md`（各目录 README 除外）；
- `docs/plans/PLAN-*.md`；
- 当前 Progress、Issue 入口和 Acceptance Queue；
- 任何主动添加合法 Frontmatter 的其他 Markdown。

`docs/_generated/document-index.json` 是由正式 Frontmatter 编译出的访问层，不是状态修改入口。新增或修改正式文档后运行：

```bash
python3 tools/docs_governance.py --self-test
python3 tools/docs_governance.py --write-index
python3 tools/docs_governance.py
```

普通检查会在索引缺失或过期时失败。模板、链接、ID 唯一性、Requirement 引用、Feature/ADR/Validation 反向关系、ADR 替代关系、复核日期、个人绝对路径与 done 证物门槛也由同一脚本检查。

## 10. 迁移边界

历史 Design、Report、旧 Plan 和归档快照允许暂时没有 Frontmatter，但必须满足：

- 不承担当前 Feature 状态、Requirement 定义、ADR 有效性或测试结论；
- 从热层入口不可被误读为当前事实，必要时加只读/被替代横幅；
- 一旦重新成为活跃计划或正式结论，移动到纳管命名/目录并补齐元数据；
- 迁移豁免不能绕过断链、个人路径和安全检查。
