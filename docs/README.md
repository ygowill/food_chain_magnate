# 文档总入口

本仓库把长期知识保存在可审查、可链接、可重建索引的 Markdown 中。聊天记录、本地 `.godot/*.log`、过程草稿和归档快照都不是当前事实源。

## 先从这里开始

| 要回答的问题 | 当前真相源 |
|---|---|
| 项目为什么存在、明确不做什么 | [VISION](VISION.md) |
| 稳定 Requirement ID 与规范定义 | [REQUIREMENTS](REQUIREMENTS.md) |
| 哪些工作当前正在推进 | [BACKLOG](BACKLOG.md) |
| 某项能力的范围、状态、AC 与证物 | [Feature 索引](features/README.md) |
| 当前系统如何工作 | [Architecture](architecture/README.md) |
| 为什么采用某个高影响方案 | [ADR 索引](decisions/README.md) |
| 某个提交验证了什么 | [Validation 索引](validation/README.md) |
| 当前状态导航与待人工验收 | [Progress](progress/README.md) |
| 文档如何创建、更新与归档 | [文档治理规范](governance/documentation-governance.md) |

更细的角色/任务阅读路线见 [DOC MAP](DOC_MAP.md)。所有正式文档的机器可读清单由脚本生成在 [document-index.json](_generated/document-index.json)。

## 真相优先级

遇到冲突时按以下顺序处理：

1. Git 中可定位的代码、配置和测试行为；
2. 已接受的 [ADR](decisions/README.md) 与当前 [Architecture](architecture/README.md)；
3. [Feature](features/README.md) 的范围、状态、AC 判定与限制；
4. [Requirements](REQUIREMENTS.md) 的稳定定义；
5. Design、Plan、Report 与历史材料。

这不是让代码永远“压过”需求；发现高层意图与实现冲突时，应停止复制旧结论，基于证物修正错误的真相源并保留决策历史。

## 目录职责

- [architecture/](architecture/README.md)：当前实现事实；
- [features/](features/README.md)：每个正式能力唯一的聚合入口；
- [decisions/](decisions/README.md)：长期架构决策与替代关系；
- [validation/](validation/README.md)：提交级验证范围、结果和限制；
- [plans/](plans/README.md)：仍在执行的计划；完成或放弃后移入归档；
- [design/](design/)：目标方案与交互设计，不承担实现状态；
- [online/](online/README.md)：联机专题导航与 runbook；
- [progress/](progress/README.md)：当前状态导航和人工验收队列；
- [reports/](reports/)：一次性审计、评估与复盘；
- [reference/](reference/)：规则、OCR 和资源参考；
- 各目录的 `archive/`：只读历史，不得覆盖当前结论。

## 三跳规则

正式 Feature 必须能沿以下路径在三次链接内找到意图、决策、代码和验证：

`本页 → Feature 索引 → Feature 页 → ADR / Architecture / Code / Validation`

三个试点入口：

- [F-001 Modules V2](features/F-001-modules-v2.md)
- [F-002 Online Resume / Bootstrap](features/F-002-online-resume-bootstrap.md)
- [F-003 Tutorial Campaign](features/F-003-tutorial-campaign.md)

## 修改前后

新增正式文档应从 [templates/](templates/) 实例化，使用稳定 ID、Owner、状态和复核日期。提交前运行：

```bash
python3 tools/docs_governance.py --self-test
python3 tools/docs_governance.py --write-index
python3 tools/docs_governance.py
```

链接、Frontmatter、Requirement/Feature/ADR/Validation 关系、过期日期和生成索引由 PR 门禁检查。只改文档但改变 API、策略、权限或流程语义时，仍需要主题 Owner Review。
