# ActionIds：集中管理 core/ 中使用的 action_id 字符串常量（避免散落硬编码）
extends RefCounted

# 通用/系统动作
const SKIP := "skip"
const SKIP_SUB_PHASE := "skip_sub_phase"
const END_TURN := "end_turn"
const ADVANCE_PHASE := "advance_phase"

# Working 自动补完的无参强制动作
const SET_PRICE := "set_price"
const SET_DISCOUNT := "set_discount"
const SET_LUXURY_PRICE := "set_luxury_price"
