# 员工卡/升级路线图对齐：修复方案与数据对照（待确认）

> 目的：你先审阅这份“修复方案 + 数据对照表”，点头后我再开始改代码/改数据（避免误改导致存档/玩法受影响）。

---

## A. 缩略员工卡顶部名字偶发为空（UI Bug）

### 现象

- 升级路线树里，缩略版员工卡顶部看不到名字（只剩空白区域/背景）。

### 根因（当前实现）

- `ui/components/employee_tree/employee_tree_graph.gd` 在 `add_child(card)` 之前调用 `card.setup(def.to_dict())`。
- `ui/components/employee_card/employee_card.gd` 的 `setup()` 会立刻调用 `_update_display()`。
- 但此时节点尚未进入 scene tree，`_ready()` 尚未执行，`_build_ui()` 尚未创建 `_name_label`。
- `_update_display()` 看到 `_name_label == null` 会直接 `return`，因此名字不会被写入；后续 `_ready()` 也不会再次触发一次 `_update_display()`。

### 拟修复方案（需你确认后实施）

**目标：保证无论 `setup()` 在 `_ready()` 前/后调用，最终都会渲染到正确的 name/颜色/描述。**

两种等价实现（二选一，我倾向选 1，改动最小）：

1) 在 `EmployeeCard._build_ui()` 或 `_ready()` 末尾补一次：若 `_employee_def` 已设置，则 `_update_display()`。
2) 在 `EmployeeCard.setup()` 中：若尚未 `is_inside_tree()`，则 `call_deferred("_update_display")`（或 deferred 重建/刷新）。

---

## B. 员工定义与参考图不一致：修复范围说明

### 参考资料

- 英文路线图/规则参考：`demo_image/FCM_All_Career_Paths_+_Round_Reference_v1.3.pdf`
- 中文名参考：`demo_image/road_map.png`

### 我建议的落地策略（需你点头）

- **默认只改 `name` + `train_to` +（如确有误）`id`**，以匹配参考图，尽量不改动玩法。
- **关于 `pool`（供应张数）**：`road_map.png` 每个员工名后括号数字看起来像“张数”，但当前项目的 `pool` 设计（`fixed/one_x` + `rules.one_x_employee_copies_by_player_count`）与之差异很大；这会影响玩法与测试。
	- 我先把所有差异都列出来（见表格的 `pool?`）。
	- **是否要把括号数字严格同步到 `pool`**，需要你确认后我才会动。

---

## C. 明确可直接修改的 name 对齐清单（来自 `road_map.png`）

以下 7 项是“当前 JSON 的 name”与 `road_map.png` 明确不一致的地方：

- `cfo`: `cfo` -> `首席财务官`
- `guru`: `培训导师` -> `培训专家`
- `junior_vice_president`: `初级副总裁` -> `总经理助理`
- `local_manager`: `本地经理` -> `区域经理`
- `recruiter`: `招聘专员` -> `人力资源专员`
- `truck_driver`: `卡车司机` -> `货车驾驶员`
- `waitress`: `女服务员` -> `服务员`

> 备注：以上都只影响 UI 展示文本；不改 `id` 的情况下，存档与规则引用不会受影响。

---

## D. `train_to`（升级路线）核对结论（来自 PDF）

在当前仓库的 50 个员工定义里，我对照 `FCM_All_Career_Paths_+_Round_Reference_v1.3.pdf` 检查了所有“有升级箭头”的员工：

- `train_to` 路线 **未发现与 PDF 冲突的条目**（见下方全表，`差异` 列若包含 `train_to` 我会标出来）。

---

## E. 数据对照表（当前 vs 参考）

字段说明：

- `road_map期望name`：仅对 base 员工提供（来自 `road_map.png`）；模块员工暂留空
- `PDF期望train_to`：来自 PDF（仅对有升级箭头的员工）
- `road_map(括号)`：我按 `road_map.png` 的括号数字录入（仅 base）；**是否对齐到 `pool` 需你确认**
- `差异`：
	- `name`：name 与 road_map 不一致
	- `train_to`：train_to 与 PDF 不一致
	- `pool?`：pool 与 road_map(括号) 不一致（可选项，需你确认）

| id | file | 当前name | road_map期望name | 当前train_to | PDF期望train_to | 当前pool(type:count) | road_map(括号) | 差异 |
|---|---|---|---|---|---|---|---|---|
| brand_director | modules/base_employees/content/employees/brand_director.json | 品牌总监 | 品牌总监 |  |  | one_x: | 1 | pool? |
| brand_manager | modules/base_employees/content/employees/brand_manager.json | 品牌经理 | 品牌经理 | brand_director | brand_director | fixed:8 | 6 | pool? |
| burger_chef | modules/base_employees/content/employees/burger_chef.json | 汉堡主厨 | 汉堡主厨 |  |  | one_x: | 1 | pool? |
| burger_cook | modules/base_employees/content/employees/burger_cook.json | 汉堡厨师 | 汉堡厨师 | burger_chef | burger_chef | fixed:12 | 6 | pool? |
| campaign_manager | modules/base_employees/content/employees/campaign_manager.json | 营销经理 | 营销经理 | brand_manager | brand_manager | fixed:8 | 6 | pool? |
| cart_operator | modules/base_employees/content/employees/cart_operator.json | 手推车操作员 | 手推车操作员 | truck_driver | truck_driver | fixed:12 | 6 | pool? |
| ceo | modules/base_employees/content/employees/ceo.json | CEO |  |  |  | (missing): |  |  |
| cfo | modules/base_employees/content/employees/cfo.json | cfo | 首席财务官 |  |  | one_x: | 1 | name, pool? |
| coach | modules/base_employees/content/employees/coach.json | 培训指导员 | 培训指导员 |  |  | fixed:4 | 6 | pool? |
| discount_manager | modules/base_employees/content/employees/discount_manager.json | 折扣经理 | 折扣经理 |  |  | one_x: | 6 | pool? |
| errand_boy | modules/base_employees/content/employees/errand_boy.json | 跑腿伙计 | 跑腿伙计 | cart_operator | cart_operator | fixed:12 | 12 |  |
| executive_vp | modules/base_employees/content/employees/executive_vp.json | 执行副总裁 | 执行副总裁 |  |  | one_x: | 1 | pool? |
| guru | modules/base_employees/content/employees/guru.json | 培训导师 | 培训专家 |  |  | fixed:4 | 1 | name, pool? |
| hr_director | modules/base_employees/content/employees/hr_director.json | 人力资源总监 | 人力资源总监 |  |  | one_x: | 1 | pool? |
| junior_vice_president | modules/base_employees/content/employees/junior_vice_president.json | 初级副总裁 | 总经理助理 | local_manager, vice_president, discount_manager, recruiting_manager | local_manager, vice_president, discount_manager, recruiting_manager | one_x: | 12 | name, pool? |
| kitchen_trainee | modules/base_employees/content/employees/kitchen_trainee.json | 见习厨师 | 见习厨师 | burger_cook, pizza_cook | burger_cook, pizza_cook | fixed:12 | 12 |  |
| local_manager | modules/base_employees/content/employees/local_manager.json | 本地经理 | 区域经理 |  |  | fixed:12 | 6 | name, pool? |
| luxury_manager | modules/base_employees/content/employees/luxury_manager.json | 奢侈品经理 | 奢侈品经理 |  |  | one_x: | 1 | pool? |
| management_trainee | modules/base_employees/content/employees/management_trainee.json | 管理培训生 | 管理培训生 | new_business_dev, junior_vice_president, luxury_manager | new_business_dev, junior_vice_president, luxury_manager | fixed:8 | 18 | pool? |
| marketer | modules/base_employees/content/employees/marketer.json | 营销实习生 | 营销实习生 | campaign_manager | campaign_manager | fixed:12 | 11 | pool? |
| new_business_dev | modules/base_employees/content/employees/new_business_dev.json | 新业务拓展经理 | 新业务拓展经理 |  |  | fixed:12 | 6 | pool? |
| pizza_chef | modules/base_employees/content/employees/pizza_chef.json | 披萨主厨 | 披萨主厨 |  |  | one_x: | 1 | pool? |
| pizza_cook | modules/base_employees/content/employees/pizza_cook.json | 披萨厨师 | 披萨厨师 | pizza_chef | pizza_chef | fixed:12 | 6 | pool? |
| pricing_manager | modules/base_employees/content/employees/pricing_manager.json | 定价经理 | 定价经理 |  |  | one_x: | 12 | pool? |
| recruiter | modules/base_employees/content/employees/recruiter.json | 招聘专员 | 人力资源专员 |  |  | fixed:12 | 12 | name |
| recruiting_manager | modules/base_employees/content/employees/recruiting_manager.json | 人力资源经理 | 人力资源经理 |  |  | (missing): | 6 | pool? |
| regional_manager | modules/base_employees/content/employees/regional_manager.json | 大区经理 | 大区经理 |  |  | fixed:4 | 1 | pool? |
| senior_vice_president | modules/base_employees/content/employees/senior_vice_president.json | 高级副总裁 | 高级副总裁 | cfo, executive_vp, hr_director | cfo, executive_vp, hr_director | (missing): | 6 | pool? |
| trainer | modules/base_employees/content/employees/trainer.json | 培训讲师 | 培训讲师 |  |  | fixed:12 | 11 | pool? |
| truck_driver | modules/base_employees/content/employees/truck_driver.json | 卡车司机 | 货车驾驶员 | zeppelin_pilot | zeppelin_pilot | fixed:4 | 6 | name, pool? |
| vice_president | modules/base_employees/content/employees/vice_president.json | 副总裁 | 副总裁 | regional_manager, senior_vice_president, guru | regional_manager, senior_vice_president, guru | one_x: | 6 | pool? |
| waitress | modules/base_employees/content/employees/waitress.json | 女服务员 | 服务员 |  |  | fixed:12 | 12 | name |
| zeppelin_pilot | modules/base_employees/content/employees/zeppelin_pilot.json | 飞艇驾驶员 | 飞艇驾驶员 |  |  | one_x: | 1 | pool? |
| barista | modules/coffee/content/employees/barista.json | 咖啡师 |  | lead_barista | lead_barista | fixed:6 |  |  |
| barista_trainee | modules/coffee/content/employees/barista_trainee.json | 咖啡学徒 |  | barista | barista | fixed:12 |  |  |
| lead_barista | modules/coffee/content/employees/lead_barista.json | 首席咖啡师 |  |  |  | one_x: |  |  |
| fry_chef | modules/fry_chefs/content/employees/fry_chef.json | 薯条厨师 |  |  |  | fixed:8 |  |  |
| gourmet_food_critic | modules/gourmet_food_critics/content/employees/gourmet_food_critic.json | 美食评论家 |  |  |  | fixed:6 |  |  |
| kimchi_master | modules/kimchi/content/employees/kimchi_master.json | 泡菜大师 |  |  |  | one_x: |  |  |
| lobbyist | modules/lobbyists/content/employees/lobbyist.json | 说客 |  |  |  | fixed:6 |  |  |
| mass_marketeer | modules/mass_marketeers/content/employees/mass_marketeer.json | 大众营销员 |  |  |  | fixed:12 |  |  |
| movie_star_b | modules/movie_stars/content/employees/movie_star_b.json | 电影明星B |  |  |  | fixed:1 |  |  |
| movie_star_c | modules/movie_stars/content/employees/movie_star_c.json | 电影明星C |  |  |  | fixed:1 |  |  |
| movie_star_d | modules/movie_stars/content/employees/movie_star_d.json | 电影明星D |  |  |  | fixed:1 |  |  |
| night_shift_manager | modules/night_shift_managers/content/employees/night_shift_manager.json | 夜班经理 |  |  |  | fixed:6 |  |  |
| noodles_chef | modules/noodles/content/employees/noodles_chef.json | 面条主厨 |  |  |  | one_x: |  |  |
| noodles_cook | modules/noodles/content/employees/noodles_cook.json | 面条厨师 |  | noodles_chef | noodles_chef | fixed:12 |  |  |
| rural_marketeer | modules/rural_marketeers/content/employees/rural_marketeer.json | 乡村营销员 |  |  |  | fixed:6 |  |  |
| sushi_chef | modules/sushi/content/employees/sushi_chef.json | 寿司主厨 |  |  |  | one_x: |  |  |
| sushi_cook | modules/sushi/content/employees/sushi_cook.json | 寿司厨师 |  | sushi_chef | sushi_chef | fixed:12 |  |  |

