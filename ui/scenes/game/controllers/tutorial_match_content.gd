# Game scene：教学局专用文案
# 负责：
# - 教学局模式下更清晰、更偏说明书风格的主界面导览
# - 教学局模式下按流程推进的分阶段提示
# - 教学局模式下的关键交互面板导览
class_name GameTutorialMatchContent
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const TUTORIAL_MATCH_RECRUIT_TOUR_ID := "match_recruit_panel_ui"
const TUTORIAL_MATCH_TRAIN_TOUR_ID := "match_train_panel_ui"
const TUTORIAL_MATCH_MARKETING_TOUR_ID := "match_marketing_panel_ui"
const TUTORIAL_MATCH_FOOD_TOUR_ID := "match_food_panel_ui"
const TUTORIAL_MATCH_DRINKS_TOUR_ID := "match_drinks_panel_ui"
const TUTORIAL_MATCH_EMPLOYEE_TREE_TOUR_ID := "match_employee_tree_ui"

const REQUIRED_FLOW_HINT_IDS := [
	"match_setup_place_restaurant",
	"match_round1_restructuring",
	"match_round1_order_of_business",
	"match_round1_working_recruit",
	"match_round1_working_train",
	"match_round1_working_marketing",
	"match_round1_working_get_food",
	"match_round1_working_get_drinks",
	"match_round1_working_place_houses",
	"match_round1_working_place_restaurants",
	"match_round1_dinnertime",
	"match_round1_payday",
	"match_round1_marketing_phase",
	"match_round1_cleanup",
	"match_round2_ready_summary",
]

static func get_required_flow_hint_ids() -> Array[String]:
	return _duplicate_string_array(REQUIRED_FLOW_HINT_IDS)

static func get_recruit_tour_id() -> String:
	return TUTORIAL_MATCH_RECRUIT_TOUR_ID

static func get_train_tour_id() -> String:
	return TUTORIAL_MATCH_TRAIN_TOUR_ID

static func get_marketing_tour_id() -> String:
	return TUTORIAL_MATCH_MARKETING_TOUR_ID

static func get_food_tour_id() -> String:
	return TUTORIAL_MATCH_FOOD_TOUR_ID

static func get_drinks_tour_id() -> String:
	return TUTORIAL_MATCH_DRINKS_TOUR_ID

static func get_employee_tree_tour_id() -> String:
	return TUTORIAL_MATCH_EMPLOYEE_TREE_TOUR_ID

static func build_game_ui_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"status_bar",
		"顶部状态栏",
		"这里显示当前回合、阶段和当前玩家。每次不确定流程进行到哪里，先看这里。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_player_overview",
		"玩家概览",
		"这里汇总各玩家的现金、员工、餐厅和经营状态。现金始终是公开信息；结算后先看这里，通常就能判断自己当前最缺钱、人还是位置。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_inventory_section",
		"库存区",
		"食材、饮料和成品都显示在这里，而且由你的所有餐厅共享。生产、采购和晚餐结算前，建议先检查库存缺口；正式对局里，没有冰箱时清理阶段会清空剩余库存。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_employee_scroll",
		"员工列表和公司结构摘要",
		"这里用于查看你拥有哪些员工、哪些已经上岗、哪些仍在待命，以及哪些营销员仍在忙碌。招聘、培训和发薪前，先在这里确认当前的人手结构。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_milestones_section",
		"里程碑区域",
		"正式对局中，里程碑一旦达成立即生效，而且同一回合内可以有多名玩家同时获得同一个里程碑。教学局关闭了里程碑，但你仍应记住它的位置和作用。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_activity_feed",
		"最近事件会显示在这里",
		"这里保留最近几条关键记录，方便你快速回忆刚刚发生了什么。若要追完整的结算链，请再打开右侧日志。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"map_view",
		"地图区域",
		"房屋、道路、餐厅和广告都会在地图上共同作用。只要你在判断需求、距离、扩张或竞争关系，都需要回到地图查看。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"action_panel",
		"动作面板",
		"右侧动作面板会显示当前阶段可执行的动作，以及下一步应打开的操作面板。不知道该点哪里时，先看这里；如果面板只剩“确认结束”，表示当前阶段已经没有更多可执行动作。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_employee_tree_button",
		"员工树按钮",
		"当你不清楚某个员工可以培训成什么岗位，或想确认关键岗位还剩多少张时，可以打开这里查看完整升级路线。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_milestones_button",
		"里程碑按钮",
		"正式对局里，建议在这里查看里程碑效果和剩余争夺机会。常见关键例子包括：一回合雇佣 3 人、首次培训、首次放广告牌，以及首次丢弃食物饮料获得冰箱。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_reserve_area_button",
		"供应堆按钮",
		"这里用于查看房屋、花园、营销板块、地图板块和玩家 token 等公共组件的剩余情况。纸板组件数量有限；食物和饮料 token 不在这里统计。员工卡的剩余数量，应从升级路线中查看。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_reserve_cards_button",
		"储备卡按钮",
		"开局每位玩家都要秘密选择 1 张储备卡，确认后不可更改。开局选择完成后，可以在这里回看已公开信息；若本模式与纸质规则或其他模块不同，请以当前卡面说明为准。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_distance_button",
		"距离工具按钮",
		"判断房屋会去哪家餐厅，或放置新餐厅前比较两个候选位置时，可以用它比较从入口出发、沿道路统计的服务距离。距离看的是跨过的板块边界数，不是直线；若员工写明飞艇距离，则按对应图标解释。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_log_button",
		"日志按钮",
		"看不懂为什么有销量、为什么丢单、或者某次结算为何发生变化时，建议先打开日志。日志最适合核对晚餐比较链、广告结算、破产和发薪等完整过程。"
	)
	return steps

static func build_recruit_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"recruit_panel_items_container",
		"招聘面板",
		"这里列出当前可以招聘的基础员工。卡片右上角数字表示该员工当前还能拿到多少张；新招来的员工会先进入待命区，本轮不能直接上岗。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_employee_scroll",
		"先查看当前人手缺口",
		"招聘前建议先回看左侧员工列表，确认自己当前更缺生产、营销还是扩张能力。招聘是为下一轮重组准备人手，不是立刻补本轮动作。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_employee_tree_button",
		"先查看升级路线",
		"招聘前建议先打开升级路线，确认这张基础员工后续能培训到哪些岗位，同时看看关键岗位还剩多少张。若入门员工堆已空，只有在紧接培训阶段能立刻升到仍有库存的更高职位时，才值得先招。"
	)
	return steps

static func build_employee_tree_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_viewport",
		"这里用于规划员工路线",
		"员工树是招聘和培训时最重要的参考视图。下面会先按一张员工卡从上到下说明，再补充特殊标记与连线。",
		"",
		"below"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_header",
		"先看卡片顶部色条和名称",
		"顶部色条用于区分岗位类别，名称用于确认具体员工。阅读路线时，先看自己缺的是哪类能力，再找对应颜色的一条线继续追。",
		"employee_tree_sample_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_remaining_badge",
		"右上角数字表示剩余数量",
		"右上角数字表示这个岗位当前还能拿到多少张。招聘和培训前，都建议先看这里，避免把行动花在已经接近拿空的路线节点上。",
		"employee_tree_sample_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_description",
		"正文说明岗位能力",
		"正文会概括员工作用。读卡时，建议把岗位能力和你当前的经营目标一起看，而不是只看职位名称。",
		"employee_tree_sample_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_entry_marker",
		"左下角图标表示取得方式",
		"左下角像播放键一样的三角形图标表示入门级员工，这类员工可以直接通过招聘取得。查看升级路线时，先确认自己拿到的是不是一条能力链的入口。",
		"employee_tree_entry_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_one_x_marker",
		"1x 表示每位玩家通常只能拥有 1 张",
		"如果左下角显示 1x，则表示这种职位对每位玩家通常只能拥有 1 张。它不是入门级标记，而是数量限制，决定是否投入这条路线前要先看清。",
		"employee_tree_one_x_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_range_marker",
		"底部中间是距离图标",
		"底部中间的图标表示该岗位使用的是公路距离还是飞艇距离，以及对应范围。规则中的距离通常按跨过的地图板块边界数计算；若是飞艇图标，则按卡牌能力处理。",
		"employee_tree_range_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_salary_marker",
		"右下角是薪水标志",
		"右下角的 $ 标志表示正式对局发薪时通常要为这张员工支付薪水。教学局关闭了薪水成本，但正式对局里它会直接影响本轮净收入。",
		"employee_tree_salary_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_manager_header",
		"最后看经理卡的黑色标题条",
		"经理卡顶部是黑色标题条。经理在公司结构里只能向 CEO 汇报，并提供管理名额；如果没有足够的管理名额，就无法安置更多下属。",
		"employee_tree_manager_card",
		"right"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_viewport",
		"连线表示培训方向",
		"连线表示该员工可以进一步培训到哪里。招聘基础员工时，不只是在拿一张卡，而是在为后面的整条能力链预留入口。",
		"",
		"below"
	)
	return steps

static func build_train_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"train_panel_sources_section",
		"培训来源员工",
		"先从这里选择要升级的员工。基础规则下，培训来源通常来自待命区；培训的重点是把现有人手转成之后能发挥作用的专业岗位。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"train_panel_targets_section",
		"培训目标岗位",
		"这里显示当前可以到达的岗位。被培训的来源卡会放回供应区，只拿目标岗位的新卡；只要最终岗位还有卡，中间路径职位缺货也不影响这次培训。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_employee_tree_button",
		"先查路线再培训",
		"如果不确定后续还能继续升级到什么岗位，或关键岗位是否还有余量，可以先打开员工树，再决定本次培训目标。招聘和培训是两个独立动作，不要把它们当成同一步。"
	)
	return steps

static func build_marketing_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"marketing_panel_type_section",
		"广告类型",
		"先确定要使用哪种广告。每名在岗营销员一次只能发起一项营销，而且每项营销只宣传一种产品；广告的作用是把需求放到地图上，而不是直接产生收入。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"marketing_panel_board_section",
		"广告板件和范围",
		"这里决定广告的形状、覆盖范围和持续时间。广告牌、邮箱、飞机和收音机影响范围不同；板件上的持续时间 token 会决定广告还能持续几轮。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"marketing_panel_target_section",
		"广告落点",
		"最后在地图上选择落点。广告牌、邮箱和收音机通常要靠路放置，飞机则放在边缘；距离从你任意一家餐厅的入口开始计算。广告发起后，该营销员会一直忙碌到活动结束。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_log_button",
		"结算后查看日志",
		"如果广告投放后没有形成销量，可以通过日志检查问题是距离不够、库存不足，还是被对手抢走需求。"
	)
	return steps

static func build_food_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"production_panel_products_container",
		"生产商品列表",
		"这里决定本轮要生产哪些食物。所有食物和饮料都会进入玩家共享库存，供所有餐厅共同使用；建议优先补足最可能卖出的商品，而不是平均生产所有选项。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_inventory_section",
		"先对照库存",
		"如果库存里已经有足够成品，就不必重复生产。真正重要的是补齐晚餐最容易短缺的部分，并记住这批货会被所有餐厅共享使用。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"production_panel_summary_label",
		"产量和成本汇总",
		"确认前建议查看这里的产量和成本，避免在本轮投入过多，却形成卖不掉的库存。正式对局里，没有冰箱时清理阶段会丢弃全部剩余库存。"
	)
	return steps

static func build_drinks_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"production_panel_products_container",
		"采购列表",
		"这里显示本轮可以采购的饮料。采购员会从餐厅出发沿路线拿货，不需要返回；饮料往往决定订单能否完整成交，因此建议优先补最关键的缺口。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"map_view",
		"先判断要补给哪家餐厅",
		"采购前先看地图，确认哪家餐厅最有机会在晚餐阶段接单，以及这次补货是否能及时发挥作用。同一采购员本回合不能 U 型折返，也不能对同一饮料图标拿两次。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"production_panel_summary_label",
		"最后检查补货是否合适",
		"饮料太少会丢单，太多则会压库存。若你有多个采购员，他们可以分别使用同一个饮料图标；确认前建议再看一次本轮补货量是否合理。"
	)
	return steps

static func build_restaurant_placement_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_distance_button",
		"先理解距离计算规则",
		"距离通常沿道路计算，并统计跨过多少个地图板块边界；从餐厅出发时，要从入口开始算。顾客只会在能满足全部需求的餐厅中比较这个距离；若距离相同，再按回合顺序判断。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"map_view",
		"先确认哪些格子允许放置",
		"地图上发亮的格子，就是当前这一步合法的落点。起始放置时，餐厅必须完整落在空方格上，入口紧邻公路，而且同一地图板块不能出现两个起始入口。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"action_panel_context_panel",
		"右侧会记录当前选中的位置",
		"点击地图后，这里会显示本次选点和确认按钮。工作阶段里，本地经理和区域经理既可以放新餐厅，也可以移动已有餐厅；只要还没提交，你就可以继续改点。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"action_panel_rotation_row",
		"旋转会改变入口方向",
		"餐厅入口会随着旋转一起变化。带门的角就是入口；顾客和多数范围判断都从这里出发，所以入口方向会直接影响竞争力。若本回合使用了本地经理或区域经理，你的所有餐厅还会临时获得 drive-thru，每个角都视为入口。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"map_view",
		"位置优劣要看入口服务距离",
		"真正比较的不是直线远近，而是从房屋到餐厅入口、沿道路跨过的板块边界数。看起来靠得近，如果入口绕路，实际也可能并不占优。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_distance_button",
		"拿不准时用距离工具验证",
		"如果你不确定两家餐厅谁更近，就打开这个按钮，在地图上直接比较从入口出发的服务距离，再决定是否确认。工作阶段放餐厅时，不再受“同一地图板块只能有一个入口”的起始限制。"
	)
	return steps

static func get_flow_tutorial_hint_for_state(state: GameState) -> Dictionary:
	if state == null:
		return {}
	if str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase).is_empty():
		return {
			"id": "match_setup_place_restaurant",
			"eyebrow": "教学说明 1/15",
			"title": "放置起始餐厅",
			"body": "本步骤用于决定第一家餐厅的位置。起始餐厅必须完整放在空方格上，入口紧邻公路；除此之外，你还要比较入口服务距离和后续扩张空间。",
			"where": "中央地图，右侧放置面板",
			"checklist": [
				"发亮的格子表示本次允许放置的位置，起始餐厅必须完整放在空方格上。",
				"入口必须与有公路的方格相邻；初始设置时，同一地图板块上不能出现两个餐厅入口。",
				"餐厅入口由旋转决定，顾客距离从入口开始，沿道路按跨过的板块边界数量计算。",
				"如果一时拿不准，可以先用距离工具比较，再提交。",
			],
		}
	if int(state.round_number) == 2 and str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
		return {
			"id": "match_round2_ready_summary",
			"eyebrow": "教学说明 15/15",
			"title": "基础流程已完成",
			"body": "到这里，你已经完成教学局中最重要的基础内容，包括排班、顺位、招聘、培训、营销、备货、扩张和结算。教学局使用的是教学预设；接下来可以继续完成本局，或重新开一局正常模式。",
			"where": "继续完成本局，或重新开一局正常模式",
			"checklist": [
				"员工上岗决定本轮能执行哪些动作，顺位决定每个子阶段谁先行动。",
				"营销先制造需求，库存和距离再决定能否成交，晚餐再按比较链结算。",
				"正式对局会恢复薪水、里程碑和第二次银行破产规则；储备卡也请以当前模式和卡面说明为准。",
			],
		}
	if int(state.round_number) != 1:
		return {}
	match str(state.phase):
		DefsClass.PHASE_RESTRUCTURING:
			return {
				"id": "match_round1_restructuring",
				"eyebrow": "教学说明 2/15",
				"title": "安排本轮上岗员工",
				"body": "只有放入公司结构的员工才会在本轮生效。CEO 始终在岗；经理只能向 CEO 汇报，而经理下方只能放普通员工。",
				"where": "重组弹窗",
				"checklist": [
					"把本轮一定要使用的员工放进结构，暂时用不到的员工留在待命区。",
					"忙碌营销员不放进公司结构，也不占卡槽。",
					"如果结构超出容量，除了 CEO 外，其余员工都会回到待命区。",
					"确认前再检查一次关键岗位是否已经覆盖。",
				],
			}
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			return {
				"id": "match_round1_order_of_business",
				"eyebrow": "教学说明 3/15",
				"title": "选择本轮行动顺位",
				"body": "选择顺位前，系统会先按空余卡槽多少决定谁先挑位置。空余越多，越先选择；顺位越靠前，越容易抢到关键时机。",
				"where": "顺位选择弹窗，右侧顺位轨",
				"checklist": [
					"计算时先看公司结构里还剩多少空余卡槽。",
					"若空余卡槽相同，则按上一轮顺位决定先选；正式对局里，首个飞机广告里程碑会让该计算额外加 2。",
					"顺位 1 最先行动，数字越大越靠后。",
					"选完后查看顺位轨，后续每个 Working 子阶段都按这里轮流行动。",
				],
			}
		DefsClass.PHASE_WORKING:
			match str(state.sub_phase):
					DefsClass.SUB_PHASE_RECRUIT:
						return {
							"id": "match_round1_working_recruit",
							"eyebrow": "教学说明 4/15",
							"title": "招聘基础员工",
							"body": "招聘只拿入门级员工。新招来的人会进入待命区，本轮不能直接上岗，所以这一步主要是在为下一轮结构准备人手。",
							"where": "右侧招聘面板，左侧员工摘要",
							"checklist": [
								"升级路线中左下角带 1 的员工才可直接招聘。",
								"新员工会进入待命区，而不是立即进入公司结构。",
								"若某个入门员工已空，只有在紧接培训阶段能立刻升到仍有库存的更高职位时，才值得先招。",
								"招聘前先看升级路线，确认后续岗位和关键节点都还有库存。",
							],
						}
					DefsClass.SUB_PHASE_TRAIN:
						return {
							"id": "match_round1_working_train",
							"eyebrow": "教学说明 5/15",
							"title": "培训员工",
							"body": "培训会把待命员工转成更专业的岗位。来源卡会放回供应区，然后拿取目标职位的新卡。",
							"where": "右侧培训面板，升级路线按钮",
							"checklist": [
								"培训来源通常来自待命区，招聘和培训是两个独立动作。",
								"只要最终岗位还有卡，就可以完成培训；中间路径职位缺货也不影响这次培训。",
								"确认目标岗位是否符合你下一轮真的要上岗的能力链。",
								"不确定时先打开员工树查看完整路线。",
							],
						}
					DefsClass.SUB_PHASE_MARKETING:
						return {
							"id": "match_round1_working_marketing",
							"eyebrow": "教学说明 6/15",
							"title": "投放广告",
							"body": "每名在岗营销员一次只能发起一项营销，而且每项营销只宣传一种产品。广告不会直接带来收入，顾客最终是否会来，还取决于距离、价格和库存。",
							"where": "右侧营销面板，中央地图",
							"checklist": [
								"广告牌、邮箱、飞机和收音机的覆盖范围不同，选择前先看它影响哪些房屋。",
								"距离从你任意一家餐厅的入口开始判断；广告能制造需求，但不能保证成交。",
								"持续时间 token 会决定广告还能持续几轮。",
								"发起后，该营销员会一直忙碌到活动结束。",
							],
						}
					DefsClass.SUB_PHASE_GET_FOOD:
						return {
							"id": "match_round1_working_get_food",
							"eyebrow": "教学说明 7/15",
							"title": "生产食物",
							"body": "厨房员工生产食物；所有得到的食物和饮料都会进入玩家共享库存，供所有餐厅共同使用。",
							"where": "右侧生产面板，左侧库存",
							"checklist": [
								"先查看库存，找出真正短缺的成品。",
								"共享库存意味着你要按整家公司今晚可能的订单准备货，而不是只看单店。",
								"食物和饮料 token 本身无限，但正式对局里没有冰箱就无法把剩余库存留到下一轮。",
								"重点是补足最可能成交的商品，不是平均生产每一种。",
							],
						}
					DefsClass.SUB_PHASE_GET_DRINKS:
						return {
							"id": "match_round1_working_get_drinks",
							"eyebrow": "教学说明 8/15",
							"title": "采购饮料",
							"body": "采购员从餐厅出发沿路线拿饮料，不需要返回，但路线限制比生产更严格。",
							"where": "右侧采购面板，中央地图，左侧库存",
							"checklist": [
								"同一采购员本回合不能 U 型折返。",
								"同一采购员对同一个饮料图标本回合只能拿一次。",
								"如果你有多个采购员，他们可以分别从同一个图标处拿货。",
								"采购完成后的饮料同样进入全公司共享库存。",
							],
						}
					DefsClass.SUB_PHASE_PLACE_HOUSES:
						return {
							"id": "match_round1_working_place_houses",
							"eyebrow": "教学说明 9/15",
							"title": "放置房屋",
							"body": "这个阶段既可能放一栋新房屋，也可能给已有房屋加花园。它们都会改变未来的需求和晚餐价值。",
							"where": "中央地图",
							"checklist": [
								"普通房屋最多 3 个需求；带花园的房屋最多 5 个需求。",
								"花园会让该房屋结算时的单价部分翻倍，但额外奖励不翻倍。",
								"放房屋前先看哪家餐厅更近，别把需求白送给对手。",
								"如果是在加花园，也要确认这笔高价值订单更可能由谁拿到。",
							],
						}
					DefsClass.SUB_PHASE_PLACE_RESTAURANTS:
						return {
							"id": "match_round1_working_place_restaurants",
							"eyebrow": "教学说明 10/15",
							"title": "放置新餐厅",
							"body": "本地经理和区域经理既可以放新餐厅，也可以移动已有餐厅。这个阶段不再沿用起始放置时的入口板块限制。",
							"where": "中央地图，右侧放置面板",
							"checklist": [
								"Working 阶段放餐厅或移动餐厅时，不受“同一地图板块只能有一个入口”的起始限制。",
								"只要本回合使用了本地经理或区域经理，你的所有餐厅本回合都视为 drive-thru，每个角都可当入口。",
								"比较位置时仍要看房屋到入口的服务距离，而不是直线。",
								"选点后记得旋转，确认入口或 drive-thru 的实际覆盖优势。",
							],
						}
		DefsClass.PHASE_DINNERTIME:
			return {
				"id": "match_round1_dinnertime",
				"eyebrow": "教学说明 11/15",
				"title": "查看晚餐结算",
				"body": "晚餐阶段按房屋编号依次结算。只有能满足该房屋全部需求的餐厅，才有资格进入比较。",
				"where": "日志按钮，中央地图，左侧库存",
				"checklist": [
					"比较链是：单价加距离最低，其次比在岗女服务员数量，再平手才看本轮顺位。",
					"房屋带花园时，只把单价部分翻倍；额外营销奖励不翻倍。",
					"所有房屋处理完后，再结算女服务员收入；之后有在岗 CFO 的玩家把本回合收入提高 50% 并向上取整。",
					"若银行资金不够，会在这里触发破产。正式规则通常到第二次破产才结束；教学局把破产上限改成 1 以缩短流程。",
				],
			}
		DefsClass.PHASE_PAYDAY:
			return {
				"id": "match_round1_payday",
				"eyebrow": "教学说明 12/15",
				"title": "查看本轮经营结果",
				"body": "正式规则里，这里要先决定要不要解雇，再支付薪水。教学局已关闭薪水成本，所以本轮更适合把它当成正式规则预告。",
				"where": "左上角玩家总览，日志",
				"checklist": [
					"可以先解雇任意数量的员工，再发薪。",
					"所有带 $ 标志的员工通常每人支付 $5；忙碌营销员通常也要支付。",
					"在岗招聘经理和人力资源总监未使用的招聘次数，会被强制当作薪水折扣，最低支付额为 0。",
					"结算后回看现金变化，再决定下一轮是补人、补货还是调位置。",
				],
			}
		DefsClass.PHASE_MARKETING:
			return {
				"id": "match_round1_marketing_phase",
				"eyebrow": "教学说明 13/15",
				"title": "检查广告持续状态",
				"body": "这里结算广告板块本身：按照板块编号依次放需求、减少持续时间，并决定营销员是否解放。",
				"where": "日志按钮",
				"checklist": [
					"普通房屋最多 3 个需求，带花园的房屋最多 5 个需求。",
					"广告牌影响相邻房屋，邮箱影响同一街区，飞机影响一行或一列，收音机影响所在板块及周围 8 个板块。",
					"每次结算后移除 1 个持续时间 token；token 清空时收回营销板块并解除营销员忙碌。",
					"正式对局里，里程碑会改变部分广告规则，例如永久广告或双需求广播。",
				],
			}
		DefsClass.PHASE_CLEANUP:
			return {
				"id": "match_round1_cleanup",
				"eyebrow": "教学说明 14/15",
				"title": "进入清理阶段",
				"body": "清理阶段会把本回合的临时状态全部收尾，并为下一轮重组做准备。",
				"where": "左侧库存，左侧员工列表，中央地图",
				"checklist": [
					"没有冰箱的玩家要丢弃全部剩余食物和饮料；有冰箱时才能保留一定数量。",
					"所有在岗和待命员工都会回到手牌，等待下一轮重新排班。",
					"所有即将开业的餐厅都会翻到营业面。",
					"正式对局里，本回合被任何玩家获得的里程碑类型都会从供应区移除；教学局关闭了里程碑，所以你在这一局不会看到这一步。",
				],
			}
	return {}

static func _append_step_if_target_available(
	steps: Array,
	targets: Dictionary,
	target_key: String,
	title: String,
	body: String,
	layout_target_key: String = "",
	preferred_card_side: String = ""
) -> void:
	if not _is_target_available(targets.get(target_key, null)):
		return
	var step := {
		"target_key": target_key,
		"title": title,
		"body": body,
	}
	if not layout_target_key.is_empty():
		step["layout_target_key"] = layout_target_key
	if not preferred_card_side.is_empty():
		step["preferred_card_side"] = preferred_card_side
	steps.append(step)

static func _duplicate_string_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out

static func _is_target_available(target) -> bool:
	if not (target is Control):
		return false
	var control: Control = target
	return is_instance_valid(control) and control.is_visible_in_tree()
