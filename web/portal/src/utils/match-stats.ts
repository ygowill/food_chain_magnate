import type { PlayerScore, ProductStatMap } from '../api/matches'

type UnknownRecord = Record<string, unknown>

const MODULE_EMPLOYEES: Record<string, string[]> = {
  base_employees: [
    'brand_director', 'brand_manager', 'burger_chef', 'burger_cook', 'campaign_manager', 'cart_operator',
    'ceo', 'cfo', 'coach', 'discount_manager', 'errand_boy', 'executive_vice_president', 'guru',
    'hr_director', 'junior_vice_president', 'kitchen_trainee', 'local_manager', 'luxury_manager',
    'management_trainee', 'marketing_trainee', 'new_business_developer', 'pizza_chef', 'pizza_cook',
    'pricing_manager', 'recruiting_girl', 'recruiting_manager', 'regional_manager', 'senior_vice_president',
    'trainer', 'truck_driver', 'vice_president', 'waitress', 'zeppelin_pilot',
  ],
  coffee: ['barista', 'barista_trainee', 'lead_barista'],
  fry_chefs: ['fry_chef'],
  gourmet_food_critics: ['gourmet_food_critic'],
  kimchi: ['kimchi_master'],
  lobbyists: ['lobbyist'],
  mass_marketeers: ['mass_marketeer'],
  movie_stars: ['movie_star_b', 'movie_star_c', 'movie_star_d'],
  night_shift_managers: ['night_shift_manager'],
  noodles: ['noodle_chef', 'noodle_cook'],
  rural_marketeers: ['rural_marketeer'],
  sushi: ['sushi_chef', 'sushi_cook'],
}

const MODULE_PRODUCTS: Record<string, string[]> = {
  base_products: ['burger', 'pizza', 'lemonade', 'soda', 'beer'],
  coffee: ['coffee'],
  kimchi: ['kimchi'],
  noodles: ['noodles'],
  sushi: ['sushi'],
}

const PRODUCT_KEY_ALIASES: Record<string, string> = {
  coke: 'soda',
  cola: 'soda',
}

const EMPLOYEE_USAGE_TAGS: Record<string, string[]> = {
  barista: ['use:produce:coffee'],
  barista_trainee: ['use:produce:coffee'],
  brand_director: ['use:marketing:airplane', 'use:marketing:billboard', 'use:marketing:mailbox', 'use:marketing:radio'],
  brand_manager: ['use:marketing:airplane', 'use:marketing:billboard', 'use:marketing:mailbox'],
  burger_chef: ['use:produce:burger'],
  burger_cook: ['use:produce:burger'],
  campaign_manager: ['use:marketing:billboard', 'use:marketing:mailbox'],
  cart_operator: ['use:procure:road'],
  ceo: ['use:recruit'],
  coach: ['use:train'],
  errand_boy: ['use:procure:errand_boy'],
  gourmet_food_critic: ['use:marketing:gourmet_guide'],
  guru: ['use:train'],
  hr_director: ['use:recruit'],
  kitchen_trainee: ['use:produce:burger', 'use:produce:pizza'],
  lead_barista: ['use:produce:coffee'],
  lobbyist: ['use:lobbyists'],
  local_manager: ['use:place_restaurant'],
  marketing_trainee: ['use:marketing:billboard'],
  new_business_developer: ['use:add_garden', 'use:place_house'],
  noodle_chef: ['use:produce:noodles'],
  noodle_cook: ['use:produce:noodles'],
  pizza_chef: ['use:produce:pizza'],
  pizza_cook: ['use:produce:pizza'],
  recruiting_girl: ['use:recruit'],
  recruiting_manager: ['use:recruit'],
  regional_manager: ['use:move_restaurant', 'use:place_restaurant'],
  sushi_chef: ['use:produce:sushi'],
  sushi_cook: ['use:produce:sushi'],
  trainer: ['use:train'],
  truck_driver: ['use:procure:road'],
  zeppelin_pilot: ['use:procure:air'],
}

const MILESTONE_METRIC_HINTS: Record<string, string[]> = {
  first_airplane: ['marketing_type:airplane', 'marketing_actions'],
  first_billboard: ['marketing_type:billboard', 'marketing_actions'],
  first_burger_marketed: ['marketing_actions'],
  first_burger_produced: ['produced:burger'],
  first_drink_marketed: ['marketing_actions'],
  first_hire_3: ['hired_employees'],
  first_pizza_marketed: ['marketing_actions'],
  first_pizza_produced: ['produced:pizza'],
  first_radio: ['marketing_type:radio', 'marketing_actions'],
  first_train: ['trained_employees'],
  first_coffee_sold: ['sold:coffee'],
  first_burger_sold: ['sold:burger'],
  first_pizza_sold: ['sold:pizza'],
  first_lemonade_sold: ['sold:lemonade'],
  first_beer_sold: ['sold:beer'],
  first_coke_sold: ['sold:soda'],
  first_house_built: ['house_built'],
  first_new_restaurant: ['restaurant_built'],
  first_marketeer_used: ['marketing_actions'],
  first_marketing_trainee_used: ['marketing_actions', 'marketing_type:billboard'],
  first_campaign_manager_used: ['marketing_actions', 'marketing_type:mailbox', 'marketing_type:billboard'],
  first_brand_manager_used: ['marketing_actions', 'marketing_type:airplane', 'marketing_type:mailbox', 'marketing_type:billboard'],
  first_brand_director_used: ['marketing_actions', 'marketing_type:airplane', 'marketing_type:radio'],
  first_recruiting_girl_used: ['hired_employees'],
  first_waitress_used: ['sold:burger', 'sold:pizza', 'sold:lemonade', 'sold:soda', 'sold:coffee'],
  first_cart_operator_used: ['procurement_actions'],
  first_discount_manager_used: ['sold:burger', 'sold:pizza', 'sold:lemonade', 'sold:soda', 'sold:coffee'],
  first_trainer_used: ['trained_employees'],
  first_rural_marketeer_used: ['marketing_actions', 'marketing_type:giant_billboard'],
}

const MODULE_METRIC_HINTS: Record<string, string[]> = {
  mass_marketeers: ['marketing_actions'],
  rural_marketeers: ['marketing_actions', 'marketing_type:giant_billboard'],
}

const DIRECT_LABELS: Record<string, string> = {
  marketing_actions: '营销次数',
  hired_employees: '雇佣员工数',
  trained_employees: '培训员工数',
  house_built: '建设房子数',
  garden_built: '建设花园数',
  restaurant_built: '建设餐厅数',
  restaurant_moved: '搬迁餐厅数',
  procurement_actions: '采购次数',
  lobbyists_actions: '游说行动次数',
}

const MARKETING_TYPE_LABELS: Record<string, string> = {
  billboard: '放置广告牌',
  mailbox: '放置邮箱',
  radio: '放置电波广告',
  airplane: '放置飞机广告',
  gourmet_guide: '放置美食指南',
  giant_billboard: '放置巨型广告牌',
}

const ENTITY_LABELS: Record<string, string> = {
  airplane: '飞机广告',
  beer: '啤酒',
  billboard: '广告牌',
  coke: '可乐',
  cola: '可乐',
  coffee: '咖啡',
  demand: '需求',
  drink: '饮料',
  drinks: '饮料',
  food: '食物',
  garden: '花园',
  giant_billboard: '巨型广告牌',
  gourmet_guide: '美食指南',
  house: '房子',
  employee: '员工',
  employees: '员工',
  hire: '雇佣',
  hired: '雇佣',
  lemonade: '柠檬水',
  lobbyist: '游说',
  lobbyists: '游说',
  mailbox: '邮箱',
  marketing: '营销',
  pizza: '披萨',
  procure: '采购',
  procurement: '采购',
  radio: '电波广告',
  recruit: '雇佣',
  restaurant: '餐厅',
  sale: '售卖',
  sales: '售卖',
  soda: '可乐',
  sold: '售卖',
  train: '培训',
  trained: '培训',
}

const NUMBER_ALIAS_KEYS: Record<string, string[]> = {
  marketing_actions: ['marketing_actions', 'marketingActions', 'marketing_count', 'marketingCount'],
  hired_employees: ['hired_employees', 'hiredEmployees', 'recruit_count', 'recruitCount'],
  trained_employees: ['trained_employees', 'trainedEmployees', 'train_count', 'trainCount'],
  house_built: ['house_built', 'houses_built', 'house_build_count', 'build_house_count', 'place_house_count', 'house_placement_count'],
  garden_built: ['garden_built', 'gardens_built', 'build_garden_count', 'place_garden_count'],
  restaurant_built: ['restaurant_built', 'restaurants_built', 'place_restaurant_count', 'new_restaurant_count'],
  restaurant_moved: ['restaurant_moved', 'restaurants_moved', 'move_restaurant_count'],
  procurement_actions: ['procurement_actions', 'procurement_count', 'procure_count'],
  lobbyists_actions: ['lobbyists_actions', 'lobbyists_count', 'lobbyist_actions'],
}

const MAP_ALIAS_KEYS: Record<string, string[]> = {
  produced: ['produced', 'produced_products', 'producedProducts', 'production_counts', 'productionCounts'],
  sold: ['sold', 'sold_products', 'soldProducts', 'sales_counts', 'salesCounts'],
  marketing_by_type: ['marketing_by_type', 'marketingByType', 'marketing_type_counts', 'marketingTypeCounts'],
  metrics: ['metrics', 'counters', 'extra_metrics', 'extraMetrics'],
}

const RESERVED_STATS_KEYS = new Set<string>([
  ...Object.values(NUMBER_ALIAS_KEYS).flat(),
  ...Object.values(MAP_ALIAS_KEYS).flat(),
])

export interface PlayerStatDisplayItem {
  key: string
  label: string
  value: number
}

export interface PlayerStatMatrixParticipant {
  userId: string
  score: PlayerScore | null | undefined
  context?: PlayerStatContext
}

export interface PlayerStatMatrixRow {
  key: string
  label: string
  values: Record<string, number>
}

export interface PlayerStatContext {
  modules?: string[]
  milestones?: string[]
  employees?: string[]
}

export interface NormalizedPlayerStats {
  marketingActions: number
  billboardPlacements: number
  hiredEmployees: number
  trainedEmployees: number
  produced: ProductStatMap
  sold: ProductStatMap
}

function asRecord(value: unknown): UnknownRecord | null {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    return null
  }
  return value as UnknownRecord
}

function toNonNegativeInt(value: unknown): number {
  const n = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(n)) return 0
  return Math.max(0, Math.floor(n))
}

function canonicalizeProductKey(key: string): string {
  const normalized = key.trim().toLowerCase()
  return PRODUCT_KEY_ALIASES[normalized] ?? normalized
}

function canonicalizeMarketingTypeKey(key: string): string {
  const normalized = key.trim().toLowerCase()
  const aliases: Record<string, string> = {
    'giant-billboard': 'giant_billboard',
    giantbillboard: 'giant_billboard',
    'gourmet-guide': 'gourmet_guide',
    gourmetguide: 'gourmet_guide',
  }
  return aliases[normalized] ?? normalized
}

function parseCountMap(value: unknown, normalizeKey: (key: string) => string = (key: string) => key): ProductStatMap {
  const record = asRecord(value)
  if (!record) return {}
  const out: ProductStatMap = {}
  for (const [key, raw] of Object.entries(record)) {
    const count = toNonNegativeInt(raw)
    if (count <= 0) continue
    const normalizedKey = normalizeKey(String(key))
    if (!normalizedKey) continue
    out[normalizedKey] = (out[normalizedKey] ?? 0) + count
  }
  return out
}

function pickNumber(records: Array<UnknownRecord | null>, aliases: string[]): number {
  for (const record of records) {
    if (!record) continue
    for (const key of aliases) {
      if (!Object.prototype.hasOwnProperty.call(record, key)) continue
      return toNonNegativeInt(record[key])
    }
  }
  return 0
}

function pickCountMap(
  records: Array<UnknownRecord | null>,
  aliases: string[],
  normalizeKey: (key: string) => string = (key: string) => key,
): ProductStatMap {
  for (const record of records) {
    if (!record) continue
    for (const key of aliases) {
      if (!Object.prototype.hasOwnProperty.call(record, key)) continue
      return parseCountMap(record[key], normalizeKey)
    }
  }
  return {}
}

function metricKeysFromUsageTag(tag: string): string[] {
  if (tag === 'use:recruit') return ['hired_employees']
  if (tag === 'use:train') return ['trained_employees']
  if (tag === 'use:place_house') return ['house_built']
  if (tag === 'use:add_garden') return ['garden_built']
  if (tag === 'use:place_restaurant') return ['restaurant_built']
  if (tag === 'use:move_restaurant') return ['restaurant_moved']
  if (tag === 'use:lobbyists') return ['lobbyists_actions']
  if (tag.startsWith('use:procure:')) return ['procurement_actions']
  if (tag.startsWith('use:produce:')) {
    const product = tag.split(':')[2]
    if (!product) return []
    return [`produced:${canonicalizeProductKey(product)}`]
  }
  if (tag.startsWith('use:marketing:')) {
    const kind = tag.split(':')[2]
    if (!kind) return ['marketing_actions']
    return ['marketing_actions', `marketing_type:${kind}`]
  }
  return []
}

function canonicalizeMetricKey(key: string): string {
  const normalized = key.toLowerCase()

  const soldMatch = normalized.match(/^sold:(.+)$/)
  if (soldMatch) return `sold:${canonicalizeProductKey(soldMatch[1])}`
  const producedMatch = normalized.match(/^produced:(.+)$/)
  if (producedMatch) return `produced:${canonicalizeProductKey(producedMatch[1])}`

  for (const [canonical, aliases] of Object.entries(NUMBER_ALIAS_KEYS)) {
    if (aliases.map(item => item.toLowerCase()).includes(normalized)) {
      return canonical
    }
  }
  const marketingAlias: Record<string, string> = {
    billboard_placements: 'marketing_type:billboard',
    billboard_count: 'marketing_type:billboard',
    billboard_actions: 'marketing_type:billboard',
    place_billboard_count: 'marketing_type:billboard',
    mailbox_placements: 'marketing_type:mailbox',
    mailbox_count: 'marketing_type:mailbox',
    mailbox_actions: 'marketing_type:mailbox',
    place_mailbox_count: 'marketing_type:mailbox',
    radio_placements: 'marketing_type:radio',
    radio_count: 'marketing_type:radio',
    place_radio_count: 'marketing_type:radio',
    airplane_placements: 'marketing_type:airplane',
    airplane_count: 'marketing_type:airplane',
    place_airplane_count: 'marketing_type:airplane',
    gourmet_guide_placements: 'marketing_type:gourmet_guide',
    gourmet_guide_count: 'marketing_type:gourmet_guide',
    giant_billboard_placements: 'marketing_type:giant_billboard',
    giant_billboard_count: 'marketing_type:giant_billboard',
    place_giant_billboard_count: 'marketing_type:giant_billboard',
  }
  if (marketingAlias[normalized]) return marketingAlias[normalized]
  return normalized
}

function buildExpectedMetricKeys(context: PlayerStatContext): Set<string> {
  const expected = new Set<string>()
  const employeeSet = new Set<string>(context.employees ?? [])
  const moduleSet = new Set<string>(context.modules ?? [])
  moduleSet.add('base_products')

  for (const moduleId of moduleSet) {
    for (const empId of MODULE_EMPLOYEES[moduleId] ?? []) {
      employeeSet.add(empId)
    }
    for (const productId of MODULE_PRODUCTS[moduleId] ?? []) {
      const normalizedProductId = canonicalizeProductKey(productId)
      expected.add(`produced:${normalizedProductId}`)
      expected.add(`sold:${normalizedProductId}`)
    }
    for (const metricKey of MODULE_METRIC_HINTS[moduleId] ?? []) {
      expected.add(metricKey)
    }
  }
  for (const empId of employeeSet) {
    for (const tag of EMPLOYEE_USAGE_TAGS[empId] ?? []) {
      for (const metricKey of metricKeysFromUsageTag(tag)) {
        expected.add(metricKey)
      }
    }
  }
  for (const milestoneId of context.milestones ?? []) {
    for (const metricKey of MILESTONE_METRIC_HINTS[milestoneId] ?? []) {
      expected.add(metricKey)
    }
  }
  return expected
}

function collectDynamicStatsFromRecord(record: UnknownRecord | null): Map<string, number> {
  const out = new Map<string, number>()
  if (!record) return out
  for (const [key, value] of Object.entries(record)) {
    if (RESERVED_STATS_KEYS.has(key)) continue
    const n = toNonNegativeInt(value)
    if (n > 0) {
      out.set(canonicalizeMetricKey(key), n)
      continue
    }
    const dict = asRecord(value)
    if (!dict) continue
    for (const [subKey, subValue] of Object.entries(dict)) {
      const subN = toNonNegativeInt(subValue)
      if (subN <= 0) continue
      out.set(canonicalizeMetricKey(`${key}:${subKey}`), subN)
    }
  }
  return out
}

function buildMetricMap(score: PlayerScore | null | undefined): Map<string, number> {
  const metrics = new Map<string, number>()
  if (!score) return metrics

  const scoreRecord = asRecord(score)
  const statsRecord = asRecord(score.stats)
  const records = [statsRecord, scoreRecord]

  for (const [metricKey, aliases] of Object.entries(NUMBER_ALIAS_KEYS)) {
    const value = pickNumber(records, aliases)
    if (value > 0) metrics.set(metricKey, value)
  }

  const produced = pickCountMap(records, MAP_ALIAS_KEYS.produced, canonicalizeProductKey)
  for (const [productId, value] of Object.entries(produced)) {
    metrics.set(`produced:${productId}`, value)
  }
  const sold = pickCountMap(records, MAP_ALIAS_KEYS.sold, canonicalizeProductKey)
  for (const [productId, value] of Object.entries(sold)) {
    metrics.set(`sold:${productId}`, value)
  }
  const marketingByType = pickCountMap(records, MAP_ALIAS_KEYS.marketing_by_type, canonicalizeMarketingTypeKey)
  for (const [kind, value] of Object.entries(marketingByType)) {
    metrics.set(`marketing_type:${kind}`, value)
  }

  const marketingTypeNumericAliases: Array<[string, string[]]> = [
    ['billboard', ['billboard_placements', 'billboard_count', 'place_billboard_count']],
    ['mailbox', ['mailbox_placements', 'mailbox_count', 'place_mailbox_count']],
    ['radio', ['radio_placements', 'radio_count', 'place_radio_count']],
    ['airplane', ['airplane_placements', 'airplane_count', 'place_airplane_count']],
    ['gourmet_guide', ['gourmet_guide_placements', 'gourmet_guide_count']],
    ['giant_billboard', ['giant_billboard_placements', 'giant_billboard_count', 'place_giant_billboard_count']],
  ]
  for (const [kind, aliases] of marketingTypeNumericAliases) {
    const n = pickNumber(records, aliases)
    if (n <= 0) continue
    const key = `marketing_type:${kind}`
    if (!metrics.has(key)) metrics.set(key, n)
  }
  const extraMetrics = pickCountMap(records, MAP_ALIAS_KEYS.metrics)
  for (const [key, value] of Object.entries(extraMetrics)) {
    metrics.set(canonicalizeMetricKey(key), value)
  }

  if (!metrics.has('marketing_actions')) {
    const fallbackMarketing = toNonNegativeInt(score.marketing_campaigns)
    if (fallbackMarketing > 0) metrics.set('marketing_actions', fallbackMarketing)
  }
  if (!metrics.has('hired_employees')) {
    const fallbackHire = toNonNegativeInt((statsRecord ?? {})['recruit_used'])
    if (fallbackHire > 0) metrics.set('hired_employees', fallbackHire)
  }
  if (!metrics.has('trained_employees')) {
    const fallbackTrain = toNonNegativeInt((statsRecord ?? {})['train_used'])
    if (fallbackTrain > 0) metrics.set('trained_employees', fallbackTrain)
  }

  for (const [key, value] of collectDynamicStatsFromRecord(statsRecord)) {
    if (!metrics.has(key)) metrics.set(key, value)
  }

  return metrics
}

function entityLabel(raw: string, productLabel: (productId: string) => string): string {
  if (ENTITY_LABELS[raw]) return ENTITY_LABELS[raw]
  const product = productLabel(raw)
  if (product !== raw) return product
  return raw.replace(/_/g, ' ')
}

function metricLabelFromPattern(key: string, productLabel: (productId: string) => string): string | null {
  const place = key.match(/^place_(.+)_count$/)
  if (place) {
    const target = entityLabel(place[1], productLabel)
    if (place[1] === 'house' || place[1] === 'garden' || place[1] === 'restaurant') {
      return `建设${target}数`
    }
    return `放置${target}数`
  }

  const build = key.match(/^build_(.+)_count$/)
  if (build) return `建设${entityLabel(build[1], productLabel)}数`

  const move = key.match(/^move_(.+)_count$/)
  if (move) return `移动${entityLabel(move[1], productLabel)}次数`

  const placements = key.match(/^(.+)_placements?$/)
  if (placements) return `放置${entityLabel(placements[1], productLabel)}数`

  const built = key.match(/^(.+)_built$/)
  if (built) return `建设${entityLabel(built[1], productLabel)}数`

  const actions = key.match(/^(.+)_actions?$/)
  if (actions) return `${entityLabel(actions[1], productLabel)}次数`

  const count = key.match(/^(.+)_count$/)
  if (count) return `${entityLabel(count[1], productLabel)}数`

  return null
}

function metricLabel(key: string, productLabel: (productId: string) => string): string {
  if (DIRECT_LABELS[key]) return DIRECT_LABELS[key]

  if (key.startsWith('produced:')) {
    const productId = key.slice('produced:'.length)
    return `生产${productLabel(productId)}`
  }
  if (key.startsWith('sold:')) {
    const productId = key.slice('sold:'.length)
    return `售卖${productLabel(productId)}`
  }
  if (key.startsWith('marketing_type:')) {
    const kind = key.slice('marketing_type:'.length)
    return MARKETING_TYPE_LABELS[kind] ?? `营销投放(${kind})`
  }

  const [head, tail] = key.split(':')
  if (head === 'metrics' && tail) {
    return metricLabelFromPattern(tail, productLabel) ?? entityLabel(tail, productLabel)
  }
  if (tail) {
    const combined = metricLabelFromPattern(`${head}_${tail}`, productLabel)
    if (combined) return combined
  }
  const fromPattern = metricLabelFromPattern(key, productLabel)
  if (fromPattern) return fromPattern
  return key
}

function metricOrder(key: string): number {
  if (key === 'marketing_actions') return 10
  if (key.startsWith('marketing_type:')) return 20
  if (key === 'hired_employees' || key === 'trained_employees') return 30
  if (key === 'house_built' || key === 'garden_built' || key === 'restaurant_built' || key === 'restaurant_moved') return 40
  if (key.startsWith('produced:')) return 50
  if (key.startsWith('sold:')) return 60
  if (key === 'procurement_actions') return 70
  if (key === 'lobbyists_actions') return 80
  return 99
}

export function buildPlayerStatRows(
  score: PlayerScore | null | undefined,
  productLabel: (productId: string) => string,
  context: PlayerStatContext = {}
): PlayerStatDisplayItem[] {
  const metricMap = buildMetricMap(score)
  const expected = buildExpectedMetricKeys({
    modules: context.modules ?? [],
    milestones: context.milestones ?? [],
    employees: context.employees ?? score?.employees ?? [],
  })

  for (const key of expected) {
    if (!metricMap.has(key)) {
      metricMap.set(key, 0)
    }
  }

  const rows = Array.from(metricMap.entries()).map(([key, value]) => ({
    key,
    label: metricLabel(key, productLabel),
    value,
  }))
  rows.sort((a, b) => {
    const oa = metricOrder(a.key)
    const ob = metricOrder(b.key)
    if (oa !== ob) return oa - ob
    return a.label.localeCompare(b.label, 'zh-CN')
  })
  return rows
}

export function buildPlayerStatMatrixRows(
  participants: PlayerStatMatrixParticipant[],
  productLabel: (productId: string) => string
): PlayerStatMatrixRow[] {
  const matrix = new Map<string, PlayerStatMatrixRow>()

  for (const participant of participants) {
    const rows = buildPlayerStatRows(participant.score, productLabel, participant.context ?? {})
    for (const row of rows) {
      if (!matrix.has(row.key)) {
        matrix.set(row.key, {
          key: row.key,
          label: row.label,
          values: {},
        })
      }
      matrix.get(row.key)!.values[participant.userId] = row.value
    }
  }

  const orderedRows = Array.from(matrix.values())
  for (const row of orderedRows) {
    for (const participant of participants) {
      if (row.values[participant.userId] == null) {
        row.values[participant.userId] = 0
      }
    }
  }
  return orderedRows
}

export function normalizePlayerStats(score: PlayerScore | null | undefined): NormalizedPlayerStats {
  const metricMap = buildMetricMap(score)
  const produced: ProductStatMap = {}
  const sold: ProductStatMap = {}
  const marketingByType: ProductStatMap = {}

  for (const [key, value] of metricMap.entries()) {
    if (key.startsWith('produced:')) {
      produced[key.slice('produced:'.length)] = value
      continue
    }
    if (key.startsWith('sold:')) {
      sold[key.slice('sold:'.length)] = value
      continue
    }
    if (key.startsWith('marketing_type:')) {
      marketingByType[key.slice('marketing_type:'.length)] = value
    }
  }

  return {
    marketingActions: metricMap.get('marketing_actions') ?? 0,
    billboardPlacements: marketingByType.billboard ?? 0,
    hiredEmployees: metricMap.get('hired_employees') ?? 0,
    trainedEmployees: metricMap.get('trained_employees') ?? 0,
    produced,
    sold,
  }
}

export function buildPlayerStatDisplayItems(
  score: PlayerScore | null | undefined,
  productLabel: (productId: string) => string
): PlayerStatDisplayItem[] {
  return buildPlayerStatRows(score, productLabel, {})
}
