# 设计文档审查报告

> 审查日期：2026-01-14
> 对比文档：FCM_Rules_EN_v3.pdf、FCM_ketchup_Regels_English_web_2.pdf

## 一、总体评价

设计文档整体结构清晰，覆盖了游戏的核心机制。架构设计（命令模式+事件溯源、可插拔模块系统）非常合理。但与原版规则书对比后，发现以下问题需要关注。

---

## 二、关键缺漏与错误

### 1. 回合阶段顺序问题 ⚠️ 严重

**规则书原文（第3页）**：
> Turn structure: 1. Restructuring → 2. Order of Business → 3. Working 9-5 → 4. Dinnertime → 5. Payday → 6. Marketing Campaigns → 7. Cleanup

**设计文档（第73-74行）**：
```
4. 晚餐时间（Dinnertime）
5. 发薪日（Payday）
6. 营销活动（Marketing Campaigns 结算持续时间与新增需求）
```

**问题**：设计文档的阶段顺序是正确的，但对"营销活动"阶段的描述有误。

**规则书明确说明**：
- 营销活动阶段是**生成需求**的阶段，不是"结算持续时间"
- 持续时间标记的移除发生在**清理阶段**，不是营销阶段

**建议修正**：
```
6. 营销活动（Marketing Campaigns）：按编号顺序结算，为范围内房屋放置需求标记
7. 清理（Cleanup）：移除营销持续标记、清空库存等
```

---

### 2. 距离计算规则不完整 ⚠️ 重要

**规则书原文（第5页）**：
> Distance is measured by counting the number of tiles you cross to get from one place to another. You do not count the tile you start on, but you do count the tile you end on.

**设计文档（第827行）**：
> 距离定义：从餐厅入口到房屋服务边（相邻道路）在"有效道路"上求最短路；距离的"跨板块计数"...

**缺漏**：
1. 设计文档没有明确说明"不计起始板块，计算终点板块"
2. 没有说明距离0的情况（同一板块内）

**建议补充**：
```
- 距离计算：从餐厅入口所在板块到房屋所在板块
- 起始板块不计入距离，终点板块计入
- 同一板块内距离为0
- 跨越每个板块边界距离+1
```

---

### 3. 员工薪资规则缺漏 ⚠️ 重要

**规则书原文（第4页）**：
> Employees with a $ on their card must be paid $5 each during Payday.

**设计文档（第913行）**：
> 发薪：先可解雇任意数量员工...随后为所有"带薪"员工每人支付 $5

**缺漏**：设计文档没有明确说明以下员工卡的薪资状态：
- Management Trainee（管理培训生）：无薪
- Trainer（培训师）：有薪
- Recruiter（招聘员）：有薪
- 各级厨师/服务员的薪资状态

**建议**：在 EmployeeDef 数据中明确列出所有员工的 `salary: true/false`

---

### 4. 招聘规则细节缺漏 ⚠️ 重要

**规则书原文（第4页）**：
> You can only recruit entry-level employees (those at the bottom of the career tree).
> If the supply is empty, you may still recruit that employee, but you must immediately train them to a higher position.

**设计文档（第911行）**：
> 招聘：CEO 每回合 1 次免费招聘入门级；可"缺货预支"但需紧接培训为上级职位。

**缺漏**：
1. 没有说明"免费"是指不花钱，还是指每回合一次的限制
2. 规则书中招聘本身就是免费的，不需要花钱
3. 缺少对"缺货预支"的详细校验逻辑

**建议补充**：
```
- 招聘本身免费（不花钱）
- CEO每回合可招聘1名入门级员工
- 若供应池为空，可"预支"招聘，但必须在同一工作阶段立即培训到更高职位
- 培训目标职位必须在供应池中有卡
```

---

### 5. 培训规则细节缺漏 ⚠️ 重要

**规则书原文（第4页）**：
> Training costs $5 per step on the career tree.
> You can train an employee multiple steps in one turn.

**设计文档（第912行）**：
> 培训：仅要求最终职位有牌可用，中间职位可缺货。

**缺漏**：
1. 没有明确培训费用：每步$5
2. 没有说明可以一次培训多步
3. 没有说明培训后员工状态（是否立即可用）

**建议补充**：
```
- 培训费用：每步$5（如从Errand Boy到Kitchen Trainee是1步=$5）
- 可一次培训多步（费用累加）
- 培训后员工立即可用（不是"忙碌"状态）
- 只有营销员放置营销后才变为"忙碌"
```

---

### 6. 女服务员小费规则不完整 ⚠️ 重要

**规则书原文（第5页）**：
> Each waitress earns $3 in tips at the end of Dinnertime.
> Milestone "First to have a waitress" increases tips to $5.

**设计文档（第142行）**：
> 女服务员：晚餐结束统一收取（默认3；里程碑可至5）。

**缺漏**：
1. 没有说明是"每位"女服务员$3
2. 没有说明里程碑效果是对所有女服务员生效还是只对一位

**建议补充**：
```
- 每位女服务员在晚餐阶段结束时获得$3小费
- 拥有"首个女服务员"里程碑的玩家，每位女服务员获得$5小费
```

---

### 7. 银行破产规则不完整 ⚠️ 严重

**规则书原文（第6页）**：
> First bankruptcy: Flip reserve cards, add money to bank, set CEO slots.
> Second bankruptcy: Game ends immediately.

**设计文档（第144-147行）**：
> 银行破产：
> - 第一次：翻储备卡→补充资金...
> - 第二次：在晚餐阶段结束后立刻游戏结束

**缺漏**：
1. 储备卡的具体机制没有详细说明
2. 没有说明储备卡数量（每人1张）
3. 没有说明CEO卡槽数的确定规则（出现最多的数字）
4. 没有说明第二次破产时的胜负判定

**建议补充**：
```
储备卡机制：
- 每位玩家开局获得1张储备卡（面朝下）
- 第一次银行破产时：
  1. 所有玩家翻开储备卡
  2. 银行获得所有储备卡上金额的总和
  3. 统计所有储备卡上出现最多的数字，该数字决定CEO之后的卡槽数
  4. 若有平局，取较小的数字
- 第二次银行破产：
  1. 游戏立即结束
  2. 现金最多的玩家获胜
  3. 平局时，员工数量多者胜
```

---

### 8. 营销板件编号与移除规则 ⚠️ 重要

**规则书原文（第7页）**：
> 2 players: Remove tiles 12, 15, 16
> 3 players: Remove tiles 15, 16
> 4 players: Remove tile 16
> 5 players: Remove nothing

**设计文档（第22行）**：
> 营销板编号：与资源编号一致；按玩家人数在设置阶段移除指定编号（2人：#12/#15/#16；3人：#15/#16；4人：#16；5人：不移除）。

**问题**：设计文档正确，但缺少以下细节：
1. 营销板件的总数量
2. 每种类型的数量分布
3. 编号与类型的对应关系

**建议补充完整的营销板件清单**

---

### 9. 里程碑触发条件不完整 ⚠️ 重要

**规则书原文（第6页）列出了所有里程碑**：

| 里程碑 | 触发条件 | 效果 |
|--------|----------|------|
| First billboard | 首个放置广告牌 | 营销员免薪+营销永久 |
| First to train | 首个培训员工 | 薪资-$15 |
| First burger | 首个卖出汉堡 | 每个汉堡+$5 |
| First pizza | 首个卖出披萨 | 每个披萨+$5 |
| First drink | 首个卖出饮品 | 每个饮品+$5 |
| First to have $100 | 首个拥有$100 | CEO获得CFO能力 |
| First waitress | 首个雇佣女服务员 | 小费$3→$5 |
| First to hire 3 | 首个一回合雇3人 | 薪资-$10 |
| First airplane | 首个飞机营销 | 决定顺序+2卡槽 |

**设计文档缺漏**：
1. 没有完整列出所有里程碑
2. 没有说明"首个卖出"的具体判定时机
3. 没有说明里程碑的排他性（同回合多人达成时的处理）

---

### 10. 番茄酱扩展规则缺漏 ⚠️ 重要

**Ketchup规则书关键内容**：

1. **番茄酱机制**：
   - 当你的营销产生的需求被其他玩家满足时，你获得里程碑
   - 效果：距离-1

2. **新员工**：
   - Zeppelin（飞艇）：特殊距离计算
   - 其他新职业路线

3. **新里程碑**：
   - 多个新的里程碑卡

**设计文档（第1075-1084行）**：
> 番茄酱（Ketchup）：
> - 订阅 `house_sold` 事件，判断"他人卖出你营销产生的需求"→ 授予里程碑。
> - 在 `PricingPipeline` 中注册距离修饰器，应用 `-1` 距离修正

**缺漏**：
1. 没有详细说明"你的营销产生的需求"的追踪机制
2. 没有说明飞艇的特殊距离计算规则
3. 没有列出番茄酱扩展的完整员工和里程碑清单

---

## 三、设计文档的优点

1. **架构设计优秀**：命令模式+事件溯源的设计非常适合桌游数字化
2. **可插拔性强**：模块系统设计合理，便于扩展
3. **数据驱动**：JSON配置方式便于维护和调整
4. **UI设计参考业界最佳实践**：参考了多款成功游戏的设计理念
5. **存档与复盘系统完善**：校验点机制保证了复盘的可靠性

---

## 四、改进建议汇总

### 高优先级（必须修复）

1. **修正营销阶段描述**：明确需求生成在营销阶段，持续标记移除在清理阶段
2. **完善距离计算规则**：明确"不计起始板块，计算终点板块"
3. **补充银行破产完整规则**：储备卡机制、CEO卡槽确定、胜负判定
4. **补充培训费用规则**：每步$5

### 中优先级（应该修复）

5. **完善员工薪资状态表**：明确每种员工是否需要支付薪资
6. **补充里程碑完整清单**：包括触发条件和效果
7. **补充营销板件完整清单**：编号、类型、数量
8. **完善番茄酱扩展规则**：需求追踪机制、飞艇规则

### 低优先级（建议修复）

9. **补充入门模式的完整规则差异**
10. **补充多人同时达成里程碑的处理规则**

---

## 五、建议新增的数据结构

### 1. 完整员工卡表

```json
{
  "employees": [
    {"id": "errand_boy", "name": "跑腿小弟", "salary": false, "entry_level": true, "train_to": ["kitchen_trainee", "cart_operator"]},
    {"id": "kitchen_trainee", "name": "厨房学徒", "salary": true, "train_to": ["burger_cook", "pizza_cook"]},
    {"id": "burger_cook", "name": "汉堡厨师", "salary": true, "train_to": ["burger_chef"]},
    // ... 完整列表
  ]
}
```

### 2. 完整里程碑表

```json
{
  "milestones": [
    {"id": "first_billboard", "trigger": "place_billboard", "effect": {"marketing_no_salary": true, "marketing_permanent": true}},
    {"id": "first_train", "trigger": "train_employee", "effect": {"salary_discount": 15}},
    // ... 完整列表
  ]
}
```

### 3. 需求追踪结构（番茄酱扩展）

```json
{
  "demand_tracking": {
    "house_id": "7",
    "demands": [
      {"product": "burger", "source_player": 0, "source_marketing": "billboard_12"},
      {"product": "burger", "source_player": 1, "source_marketing": "radio_3"}
    ]
  }
}
```

---

## 六、后续行动项

- [ ] 修正设计文档中的阶段描述
- [ ] 补充完整的员工卡表数据
- [ ] 补充完整的里程碑数据
- [ ] 补充完整的营销板件数据
- [ ] 设计需求追踪机制（番茄酱扩展）
- [ ] 完善银行破产规则描述
