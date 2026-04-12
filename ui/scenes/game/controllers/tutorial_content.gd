# Game scene：教学文案与步骤定义
# 负责：
# - 主界面导览步骤文案
# - 重组导览步骤文案
# - 首局流程提示文案
class_name GameTutorialContent
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const TUTORIAL_RESTRUCTURING_TOUR_ID := "restructuring_modal_ui"
const TUTORIAL_TURN_ORDER_TOUR_ID := "turn_order_modal_ui"
const TUTORIAL_RESTAURANT_PLACEMENT_TOUR_ID := "restaurant_placement_ui"
const TUTORIAL_EMPLOYEE_TREE_TOUR_ID := "employee_tree_ui"
const REQUIRED_FLOW_HINT_IDS := [
	"setup_place_restaurant",
	"round1_restructuring",
	"round1_order_of_business",
	"round1_working",
	"round1_dinnertime",
	"round1_payday",
	"round1_marketing_phase",
	"round1_cleanup",
]

static func get_required_flow_hint_ids() -> Array[String]:
	return _duplicate_string_array(REQUIRED_FLOW_HINT_IDS)

static func get_restructuring_tour_id() -> String:
	return TUTORIAL_RESTRUCTURING_TOUR_ID

static func get_turn_order_tour_id() -> String:
	return TUTORIAL_TURN_ORDER_TOUR_ID

static func get_restaurant_placement_tour_id() -> String:
	return TUTORIAL_RESTAURANT_PLACEMENT_TOUR_ID

static func get_employee_tree_tour_id() -> String:
	return TUTORIAL_EMPLOYEE_TREE_TOUR_ID

static func build_game_ui_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"status_bar",
		"先看顶部状态栏",
		"这里会告诉你当前回合、阶段，以及银行何时会破产结算。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_player_overview",
		"左上角是玩家概览",
		"这里会同时展示所有玩家的现金、员工、餐厅和里程碑。现金始终是公开信息；点击任意玩家卡片，可以切换左侧信息面板正在查看的对象。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_inventory_section",
		"这里才是当前玩家的库存",
		"原料、饮料和成品都会在这里汇总显示，并由你的所有餐厅共享。你能不能满足需求，很多时候就看这里有没有货；没有冰箱时，清理阶段通常会清空剩余库存。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_employee_scroll",
		"左侧中部是员工与结构清单",
		"这里会汇总当前查看玩家的公司结构、手牌和忙碌中的营销人员，方便你快速盘点人手。真正调整公司结构，会在重组阶段打开专门界面。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_milestones_section",
		"里程碑也会显示在左侧",
		"这里会列出已经拿到和仍在竞争中的里程碑。里程碑一旦达成立即生效，而且同一回合内可以有多名玩家同时获得同一个。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"left_activity_feed",
		"底部活动流会滚动显示最近事件",
		"这里会保留最近几条关键日志，方便你快速回忆刚刚发生了什么。想看完整记录时，再去打开右侧日志按钮。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"map_view",
		"地图是你的主战场",
		"选地、送货、营销和员工部署，都会围绕这块地图展开。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"action_panel",
		"右侧是动作面板",
		"轮到你时先看这里。它会按当前阶段列出可执行动作和下一步提示；如果只剩“确认结束”，表示当前阶段已经没有更多可执行动作。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"turn_order_track",
		"顺位轨会显示本轮行动先后",
		"商业秩序阶段结束后，这里会显示谁先行动。抢位置、抢采购时，要经常回来看。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_log_button",
		"日志按钮可以展开完整过程",
		"如果你想确认某一步到底发生了什么，优先打开这里。它比左侧的简短活动流更完整，也更适合回看结算细节。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_milestones_button",
		"里程碑按钮会打开详细说明",
		"左侧只适合快速浏览。如果你想认真查看里程碑效果、剩余机会和模块里程碑，打开这里会更清楚。常见关键例子包括首次培训、首次放广告牌、首次雇佣三人，以及首次丢弃食物饮料获得冰箱。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_employee_tree_button",
		"升级路线按钮用来看员工树",
		"不确定某张员工卡从哪里来、还能升级成什么，以及还剩多少张时，就打开这里。它是规划招聘和培训路线最常用的查询入口。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_reserve_area_button",
		"供应堆按钮用来查公共组件余量",
		"这里查看的是房屋、花园、营销板块、地图板块和玩家 token 等公共组件，不是员工卡。纸板组件数量有限；员工还能否招聘或培训，请到升级路线里看对应岗位右上角数字。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_reserve_cards_button",
		"储备卡按钮用来回看已公开信息",
		"它用于回看已公开的储备卡信息。开局每位玩家都要秘密选择 1 张；不同模式或模块下，储备卡效果可能不同，拿不准时请以当前卡面说明为准。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar_distance_button",
		"距离工具专门拿来量顾客到餐厅的路程",
		"当你不确定顾客会去哪家餐厅时，可以打开它比较从餐厅入口出发、沿道路统计的服务距离。这里的距离看的是跨过多少个地图板块边界，不是直线；若员工写明飞艇范围，则按对应图标理解。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"toolbar",
		"右侧这一排是常用辅助入口",
		"除了日志、升级路线和里程碑外，这里还能打开供应堆、储备卡，以及距离工具。遇到想查一下的问题，通常先看这里。"
	)
	return steps

static func build_restructuring_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"restructuring_player_buttons",
		"先确认当前在给哪位玩家排班",
		"教学局里，每位玩家都会依次在这里调整结构。先切对玩家，再开始拖拽，避免把关键岗位排错人。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"restructuring_hand_host",
		"左侧是待命区，也是本轮的人手池",
		"这里的员工还没有正式上岗。把他们拖到右侧岗位，才算进入本轮行动序列；拖回来则表示本轮不启用。CEO 始终在岗。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"restructuring_company_host",
		"右侧才是会真正生效的公司结构",
		"CEO 直属槽、经理下属槽都在这里安排。经理只能向 CEO 汇报，而经理下方只能放普通员工；如果结构超出容量，除了 CEO 外其余员工都会回待命区。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"restructuring_button_row",
		"确认前，做最后一次班表检查",
		"提交后，这轮上岗名单就锁定了。你可以先用一键填充快速铺开，再回头微调关键岗位，并检查经理层级是否合法。"
	)
	return steps

static func build_turn_order_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"turn_order_modal_display",
		"先从这里挑一个顺位空位",
		"每个空位都代表一个本轮先后手。系统会先按空余卡槽决定谁先挑位置；顺位 1 最先行动，越往后越晚出手。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"turn_order_modal_selection_label",
		"这行文字会提示你当前选中的位置",
		"如果你想先抢扩张位、先做采购，或者先完成关键动作，就要争更靠前的顺位。空余卡槽平手时，会按上一轮顺位决定先选。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"turn_order_track",
		"选完后记得看右侧顺位轨",
		"后面的 Working 每个子阶段都会按这里轮流行动。正式对局里，首个飞机广告里程碑还会让空余卡槽计算额外加 2。"
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
		"点击地图后，这里会显示本次选点和确认按钮。工作阶段里，本地经理和区域经理既可以放新餐厅，也可以移动已有餐厅；只要还没有提交，你就可以继续改点。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"action_panel_rotation_row",
		"旋转会改变入口方向",
		"点击左右旋转，或直接按 R，可以切换入口方向。带门的角就是餐厅入口；若本回合使用了本地经理或区域经理，你的所有餐厅还会临时获得 drive-thru，每个角都视为入口。"
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
		"如果你不确定两家餐厅谁更近，就打开这个按钮，在地图上直接比较从入口出发的服务距离，再决定是否确认。工作阶段放餐厅时，不再受起始入口板块限制。"
	)
	return steps

static func build_employee_tree_tour_steps(targets: Dictionary) -> Array:
	var steps: Array = []
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_viewport",
		"这里是员工升级路线总览",
		"员工树用于查看员工如何取得、如何继续培训，以及整条能力链是否还走得通。教学开始前，这个视图会先自动按宽度调整，方便你看清卡片和连线。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_header",
		"先读卡片顶部",
		"卡片顶部色条和名称用于区分岗位类别与员工身份。不同颜色通常对应不同职能，便于你快速判断这条路线偏向招聘、培训、营销、生产还是扩张。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_remaining_badge",
		"右上角数字表示剩余数量",
		"右上角数字表示该岗位当前还能拿到多少张。规划招聘和培训时，这个数字能帮助你判断一条路线是否还值得继续投入。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_entry_marker",
		"左下角图标说明取得方式",
		"左下角的 1 表示入门级员工，可以直接招聘；1x 表示该职位对每位玩家通常只能拥有 1 张。读路线时，要先分清它是招聘入口，还是唯一高位岗位。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_viewport",
		"黑底卡通常是经理岗位",
		"黑底表示经理。重组时，经理只能向 CEO 汇报，而经理下方只能放普通员工，所以看路线时也要考虑未来的结构容量。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_range_marker",
		"底部中间是距离图标",
		"底部中间的图标表示该岗位使用的是公路距离还是飞艇距离，以及对应范围。规则中的距离通常按跨过的地图板块边界数计算；若是飞艇图标，则按卡牌能力处理。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_salary_marker",
		"右下角是薪水标志",
		"右下角的 $ 标志表示正式对局发薪时通常要为这张员工支付薪水。它不是行动次数，而是经营成本的一部分。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_sample_card_description",
		"卡片正文说明岗位能力",
		"正文会概括员工作用。规划路线时，不只要看能否升级过去，还要看关键岗位剩余数量和这条路线是否值得投入。"
	)
	_append_step_if_target_available(
		steps,
		targets,
		"employee_tree_viewport",
		"连线表示培训方向",
		"从左往右的连线表示该员工可以培训到哪些后续岗位。规划时要同时看起点、终点和中间节点，避免只盯着终点，却忽略前置员工已经被拿空。"
	)
	return steps

static func get_flow_tutorial_hint_for_state(state: GameState) -> Dictionary:
	if state == null:
		return {}
	if str(state.phase) == DefsClass.PHASE_SETUP and str(state.sub_phase).is_empty():
		return {
			"id": "setup_place_restaurant",
			"eyebrow": "第一局流程引导",
			"title": "先放下你的第一家餐厅",
			"body": "现在每位玩家都要在地图上放置起始餐厅。开局位置会同时决定附近房屋是否更容易到店、入口与道路如何衔接，以及后续还能往哪里扩张。",
			"where": "中央地图 + 右侧动作面板",
			"checklist": [
				"发亮的格子代表当前允许放置的位置，起始餐厅必须完整落在空方格上。",
				"入口必须与公路相邻；初始设置时，同一地图板块上不能出现两个餐厅入口。",
				"旋转餐厅时，等于同时改变入口方向；顾客距离会从入口开始，沿道路按跨过的板块边界数量计算。",
				"拿不准时可以先用距离工具比较入口服务距离，再提交。",
			],
		}
	if int(state.round_number) != 1:
		return {}
	match str(state.phase):
		DefsClass.PHASE_RESTRUCTURING:
			return {
				"id": "round1_restructuring",
				"eyebrow": "第一轮关键阶段",
				"title": "先安排今天上岗的员工",
				"body": "重组阶段决定本回合谁在岗。员工没被安排到位，对应动作和产能就不会生效；CEO 始终在岗，经理结构也必须合法。",
				"where": "重组弹窗左侧待命区 + 右侧公司结构",
				"checklist": [
					"先把今天一定要用到的员工拖到公司结构里，暂时不想启用的员工留在待命区。",
					"经理只能向 CEO 汇报，而经理下方只能放普通员工。",
					"如果结构超出容量，除了 CEO 外其余员工都会回待命区。",
					"排好后再点击确认重组，避免过早锁定。",
				],
			}
		DefsClass.PHASE_ORDER_OF_BUSINESS:
			return {
				"id": "round1_order_of_business",
				"eyebrow": "第一轮关键阶段",
				"title": "接下来决定行动顺位",
				"body": "商业秩序阶段会先按空余卡槽决定谁先选顺位，再由玩家自己挑一个空位。先后手会影响抢位置、采购与扩张节奏。",
				"where": "顺位选择弹窗 + 右侧顺位轨",
				"checklist": [
					"空余卡槽越多，越早获得挑选顺位的位置。",
					"若空余卡槽相同，则按上一轮顺位决定先选；正式对局里，首个飞机广告里程碑会让该计算额外加 2。",
					"顺位 1 最早行动，数字越大越靠后。",
					"选完后看右侧顺位轨，确认本轮先后手。",
				],
			}
		DefsClass.PHASE_WORKING:
			return {
				"id": "round1_working",
				"eyebrow": "第一轮关键阶段",
				"title": "工作阶段是整轮核心",
				"body": "这一阶段通常会依次经历招聘、培训、营销、生产食物、采购饮料、放房子和放餐厅。右侧动作面板会告诉你当前子阶段能做什么。",
				"where": "右侧动作面板 + 左侧库存和员工信息",
				"checklist": [
					"招聘拿入门级员工到待命区，培训再把待命员工升成更专业的岗位。",
					"营销制造需求，生产和采购补共享库存，放房屋和餐厅则改变地图格局。",
					"每进入一个子阶段，都先看动作面板有哪些动作可用；如果只剩“确认结束”，不是 bug，而是当前阶段已经没有更多动作。",
					"如果想规划员工发展，再去点右侧升级路线按钮。",
				],
			}
		DefsClass.PHASE_DINNERTIME:
			return {
				"id": "round1_dinnertime",
				"eyebrow": "第一轮关键阶段",
				"title": "现在开始晚餐结算",
				"body": "顾客会根据距离、价格、营销与供货情况选择餐厅。晚餐会按房屋编号依次结算，只有能满足全部需求的餐厅才有资格参与比较。",
				"where": "日志按钮 + 左侧库存 + 中央地图",
				"checklist": [
					"比较链是：单价加距离最低，其次比在岗女服务员数量，再平手才看本轮顺位。",
					"花园只会让单价部分翻倍；所有房屋处理完后，再结算女服务员收入和 CFO 加成。",
					"对照左侧库存，确认是不是因为缺货错失销售。",
					"若银行资金不够，会在这里触发破产；正式规则通常到第二次破产才会结束游戏。",
				],
			}
		DefsClass.PHASE_PAYDAY:
			return {
				"id": "round1_payday",
				"eyebrow": "第一轮关键阶段",
				"title": "回合尾声主要看现金流",
				"body": "后面会依次处理发薪、营销衰减与清理。这里最值得关注的是钱为什么涨跌，以及哪些员工和库存会带到下一轮。",
				"where": "左上角玩家概览 + 日志",
				"checklist": [
					"可以先解雇任意数量的员工，再支付薪水。",
					"所有带 $ 标志的员工通常每人支付 $5；忙碌营销员通常也要支付。",
					"在岗招聘经理和人力资源总监未使用的招聘次数，会被强制当作薪水折扣，最低支付额为 0。",
					"准备进入下一轮前，再想想下回合最缺的是钱、人还是货。",
				],
			}
		DefsClass.PHASE_MARKETING:
			return {
				"id": "round1_marketing_phase",
				"eyebrow": "第一轮关键阶段",
				"title": "现在结算广告持续效果",
				"body": "这里处理营销板块本身：按照编号放需求、减少持续时间，并决定营销员是否结束忙碌。",
				"where": "日志按钮 + 地图上的营销板块",
				"checklist": [
					"普通房屋最多 3 个需求，带花园的房屋最多 5 个需求。",
					"广告牌影响相邻房屋，邮箱影响同一街区，飞机影响一行或一列，收音机影响所在板块及周围 8 个板块。",
					"每次结算后移除 1 个持续时间 token；token 清空时收回营销板块并解除营销员忙碌。",
					"正式对局里，部分里程碑会改变营销规则，例如永久广告或双需求广播。",
				],
			}
		DefsClass.PHASE_CLEANUP:
			return {
				"id": "round1_cleanup",
				"eyebrow": "第一轮关键阶段",
				"title": "清理阶段会重置临时状态",
				"body": "清理阶段负责把本回合的临时状态收尾，并为下一轮重组做准备。",
				"where": "左侧库存 + 左侧员工区 + 中央地图",
				"checklist": [
					"没有冰箱的玩家要丢弃全部剩余食物和饮料。",
					"所有在岗和待命员工都会回到手牌，等待下一轮重新排班。",
					"所有即将开业的餐厅都会翻到营业面。",
					"本回合被任何玩家获得的里程碑类型，会从供应区全部移除。",
				],
			}
	return {}

static func _append_step_if_target_available(
	steps: Array,
	targets: Dictionary,
	target_key: String,
	title: String,
	body: String
) -> void:
	if not _is_tutorial_target_available(targets.get(target_key, null)):
		return
	steps.append({
		"target_key": target_key,
		"title": title,
		"body": body,
	})

static func _duplicate_string_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(str(value))
	return out

static func _is_tutorial_target_available(target) -> bool:
	if not (target is Control):
		return false
	var control: Control = target
	return is_instance_valid(control) and control.is_visible_in_tree()
