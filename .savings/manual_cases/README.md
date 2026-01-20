# 手工复核用存档索引（employees / milestones）

本目录包含用于**手工复核**的存档（archive JSON）与同名说明文件（Markdown）。

- 生成脚本：`res://tools/generate_manual_test_saves.gd`
- 场景清单：`res://tools/generate_manual_test_saves_manifest.gd`
- 每个条目：`<id>.json` + `<id>.md`

## 如何载入

主菜单 → 载入游戏 → “文件”页签 → 选择本目录下的 `.json`。

## 如何重新生成（可选）

```bash
godot --headless --path . --script res://tools/generate_manual_test_saves.gd
```

可选过滤：

```bash
godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --kind employee
godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --kind milestone
godot --headless --path . --script res://tools/generate_manual_test_saves.gd -- --id kitchen_trainee
```

说明：

- `new_milestones` 与 `base_milestones` 冲突，因此对应里程碑存档会在生成时自动 `exclude_modules=["base_milestones"]`（见 manifest）。

## 员工（50）

- `barista_trainee`: `employees/barista_trainee.json` + `employees/barista_trainee.md`
- `barista`: `employees/barista.json` + `employees/barista.md`
- `brand_director`: `employees/brand_director.json` + `employees/brand_director.md`
- `brand_manager`: `employees/brand_manager.json` + `employees/brand_manager.md`
- `burger_chef`: `employees/burger_chef.json` + `employees/burger_chef.md`
- `burger_cook`: `employees/burger_cook.json` + `employees/burger_cook.md`
- `campaign_manager`: `employees/campaign_manager.json` + `employees/campaign_manager.md`
- `cart_operator`: `employees/cart_operator.json` + `employees/cart_operator.md`
- `ceo`: `employees/ceo.json` + `employees/ceo.md`
- `cfo`: `employees/cfo.json` + `employees/cfo.md`
- `coach`: `employees/coach.json` + `employees/coach.md`
- `discount_manager`: `employees/discount_manager.json` + `employees/discount_manager.md`
- `errand_boy`: `employees/errand_boy.json` + `employees/errand_boy.md`
- `executive_vice_president`: `employees/executive_vice_president.json` + `employees/executive_vice_president.md`
- `fry_chef`: `employees/fry_chef.json` + `employees/fry_chef.md`
- `gourmet_food_critic`: `employees/gourmet_food_critic.json` + `employees/gourmet_food_critic.md`
- `guru`: `employees/guru.json` + `employees/guru.md`
- `hr_director`: `employees/hr_director.json` + `employees/hr_director.md`
- `junior_vice_president`: `employees/junior_vice_president.json` + `employees/junior_vice_president.md`
- `kimchi_master`: `employees/kimchi_master.json` + `employees/kimchi_master.md`
- `kitchen_trainee`: `employees/kitchen_trainee.json` + `employees/kitchen_trainee.md`
- `lead_barista`: `employees/lead_barista.json` + `employees/lead_barista.md`
- `lobbyist`: `employees/lobbyist.json` + `employees/lobbyist.md`
- `local_manager`: `employees/local_manager.json` + `employees/local_manager.md`
- `luxury_manager`: `employees/luxury_manager.json` + `employees/luxury_manager.md`
- `management_trainee`: `employees/management_trainee.json` + `employees/management_trainee.md`
- `marketing_trainee`: `employees/marketing_trainee.json` + `employees/marketing_trainee.md`
- `mass_marketeer`: `employees/mass_marketeer.json` + `employees/mass_marketeer.md`
- `movie_star_b`: `employees/movie_star_b.json` + `employees/movie_star_b.md`
- `movie_star_c`: `employees/movie_star_c.json` + `employees/movie_star_c.md`
- `movie_star_d`: `employees/movie_star_d.json` + `employees/movie_star_d.md`
- `new_business_developer`: `employees/new_business_developer.json` + `employees/new_business_developer.md`
- `night_shift_manager`: `employees/night_shift_manager.json` + `employees/night_shift_manager.md`
- `noodle_chef`: `employees/noodle_chef.json` + `employees/noodle_chef.md`
- `noodle_cook`: `employees/noodle_cook.json` + `employees/noodle_cook.md`
- `pizza_chef`: `employees/pizza_chef.json` + `employees/pizza_chef.md`
- `pizza_cook`: `employees/pizza_cook.json` + `employees/pizza_cook.md`
- `pricing_manager`: `employees/pricing_manager.json` + `employees/pricing_manager.md`
- `recruiting_girl`: `employees/recruiting_girl.json` + `employees/recruiting_girl.md`
- `recruiting_manager`: `employees/recruiting_manager.json` + `employees/recruiting_manager.md`
- `regional_manager`: `employees/regional_manager.json` + `employees/regional_manager.md`
- `rural_marketeer`: `employees/rural_marketeer.json` + `employees/rural_marketeer.md`
- `senior_vice_president`: `employees/senior_vice_president.json` + `employees/senior_vice_president.md`
- `sushi_chef`: `employees/sushi_chef.json` + `employees/sushi_chef.md`
- `sushi_cook`: `employees/sushi_cook.json` + `employees/sushi_cook.md`
- `trainer`: `employees/trainer.json` + `employees/trainer.md`
- `truck_driver`: `employees/truck_driver.json` + `employees/truck_driver.md`
- `vice_president`: `employees/vice_president.json` + `employees/vice_president.md`
- `waitress`: `employees/waitress.json` + `employees/waitress.md`
- `zeppelin_pilot`: `employees/zeppelin_pilot.json` + `employees/zeppelin_pilot.md`

## 里程碑（38）

- `first_airplane`: `milestones/first_airplane.json` + `milestones/first_airplane.md`
- `first_beer_sold`: `milestones/first_beer_sold.json` + `milestones/first_beer_sold.md`
- `first_billboard`: `milestones/first_billboard.json` + `milestones/first_billboard.md`
- `first_brand_director_used`: `milestones/first_brand_director_used.json` + `milestones/first_brand_director_used.md`
- `first_brand_manager_used`: `milestones/first_brand_manager_used.json` + `milestones/first_brand_manager_used.md`
- `first_burger_marketed`: `milestones/first_burger_marketed.json` + `milestones/first_burger_marketed.md`
- `first_burger_produced`: `milestones/first_burger_produced.json` + `milestones/first_burger_produced.md`
- `first_burger_sold`: `milestones/first_burger_sold.json` + `milestones/first_burger_sold.md`
- `first_campaign_manager_used`: `milestones/first_campaign_manager_used.json` + `milestones/first_campaign_manager_used.md`
- `first_cart_operator_used`: `milestones/first_cart_operator_used.json` + `milestones/first_cart_operator_used.md`
- `first_cart_operator`: `milestones/first_cart_operator.json` + `milestones/first_cart_operator.md`
- `first_coke_sold`: `milestones/first_coke_sold.json` + `milestones/first_coke_sold.md`
- `first_discount_manager_used`: `milestones/first_discount_manager_used.json` + `milestones/first_discount_manager_used.md`
- `first_drink_marketed`: `milestones/first_drink_marketed.json` + `milestones/first_drink_marketed.md`
- `first_errand_boy`: `milestones/first_errand_boy.json` + `milestones/first_errand_boy.md`
- `first_have_100`: `milestones/first_have_100.json` + `milestones/first_have_100.md`
- `first_have_20`: `milestones/first_have_20.json` + `milestones/first_have_20.md`
- `first_hire_3`: `milestones/first_hire_3.json` + `milestones/first_hire_3.md`
- `first_house_built`: `milestones/first_house_built.json` + `milestones/first_house_built.md`
- `first_lemonade_sold`: `milestones/first_lemonade_sold.json` + `milestones/first_lemonade_sold.md`
- `first_lobbyist_used`: `milestones/first_lobbyist_used.json` + `milestones/first_lobbyist_used.md`
- `first_lower_prices`: `milestones/first_lower_prices.json` + `milestones/first_lower_prices.md`
- `first_marketeer_used`: `milestones/first_marketeer_used.json` + `milestones/first_marketeer_used.md`
- `first_marketing_trainee_used`: `milestones/first_marketing_trainee_used.json` + `milestones/first_marketing_trainee_used.md`
- `first_new_restaurant`: `milestones/first_new_restaurant.json` + `milestones/first_new_restaurant.md`
- `first_pay_20_salaries`: `milestones/first_pay_20_salaries.json` + `milestones/first_pay_20_salaries.md`
- `first_pizza_marketed`: `milestones/first_pizza_marketed.json` + `milestones/first_pizza_marketed.md`
- `first_pizza_produced`: `milestones/first_pizza_produced.json` + `milestones/first_pizza_produced.md`
- `first_pizza_sold`: `milestones/first_pizza_sold.json` + `milestones/first_pizza_sold.md`
- `first_radio`: `milestones/first_radio.json` + `milestones/first_radio.md`
- `first_recruiting_girl_used`: `milestones/first_recruiting_girl_used.json` + `milestones/first_recruiting_girl_used.md`
- `first_rural_marketeer_used`: `milestones/first_rural_marketeer_used.json` + `milestones/first_rural_marketeer_used.md`
- `first_throw_away`: `milestones/first_throw_away.json` + `milestones/first_throw_away.md`
- `first_train`: `milestones/first_train.json` + `milestones/first_train.md`
- `first_trainer_used`: `milestones/first_trainer_used.json` + `milestones/first_trainer_used.md`
- `first_waitress_used`: `milestones/first_waitress_used.json` + `milestones/first_waitress_used.md`
- `first_waitress`: `milestones/first_waitress.json` + `milestones/first_waitress.md`
- `ketchup_sold_your_demand`: `milestones/ketchup_sold_your_demand.json` + `milestones/ketchup_sold_your_demand.md`

