# 生成文档

本目录是可重建访问层，不是状态真相源。

- `document-index.json` 由正式文档 Frontmatter 编译生成；
- 禁止手工编辑生成文件；
- 修改正式文档后运行 `python3 tools/docs_governance.py --write-index`；
- CI 会运行普通检查并阻止缺失或过期索引合入。

生成器、字段校验和关系检查的实现位于 [`tools/docs_governance.py`](../../tools/docs_governance.py)，规则说明见[文档治理规范](../governance/documentation-governance.md)。
