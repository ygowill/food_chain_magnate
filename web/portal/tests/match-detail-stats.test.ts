import assert from 'node:assert/strict'
import test from 'node:test'

import { employeeName, milestoneName, productName } from '../src/utils/game-names.ts'
import { buildPlayerStatMatrixRows, buildPlayerStatRows, normalizePlayerStats } from '../src/utils/match-stats.ts'

test('normalizePlayerStats supports multiple stats key styles', () => {
  const score = {
    cash: 210,
    forfeited: false,
    restaurants: 2,
    employees: ['ceo', 'burger_cook'],
    milestones: [],
    inventory: { burger: 2 },
    marketing_campaigns: 2,
    stats: {
      marketing_actions: 7,
      marketing_by_type: { billboard: 3, radio: 1 },
      recruit_count: 5,
      train_count: 2,
      production_counts: { burger: 11, pizza: 3 },
      sales_counts: { lemonade: 4, coke: 3, beer: 2 },
    },
  }

  const normalized = normalizePlayerStats(score)
  assert.equal(normalized.marketingActions, 7)
  assert.equal(normalized.billboardPlacements, 3)
  assert.equal(normalized.hiredEmployees, 5)
  assert.equal(normalized.trainedEmployees, 2)
  assert.deepEqual(normalized.produced, { burger: 11, pizza: 3 })
  assert.deepEqual(normalized.sold, { lemonade: 4, soda: 3, beer: 2 })
})

test('normalizePlayerStats falls back to marketing campaign count', () => {
  const score = {
    cash: 30,
    forfeited: false,
    restaurants: 1,
    employees: ['ceo'],
    milestones: [],
    inventory: {},
    marketing_campaigns: 3,
    stats: {},
  }

  const normalized = normalizePlayerStats(score)
  assert.equal(normalized.marketingActions, 3)
  assert.equal(normalized.billboardPlacements, 0)
})

test('buildPlayerStatRows includes dynamic stats and capability-based zero rows', () => {
  const score = {
    cash: 320,
    forfeited: false,
    restaurants: 3,
    employees: ['ceo', 'burger_cook', 'truck_driver'],
    milestones: ['first_burger_sold'],
    inventory: { burger: 3, lemonade: 1 },
    marketing_campaigns: 1,
    stats: {
      marketing_actions: 9,
      marketing_by_type: { billboard: 4 },
      mailbox_placements: 2,
      hired_employees: 8,
      trained_employees: 5,
      metrics: { place_house_count: 2, restaurant_built: 1 },
      produced: { burger: 21 },
      sold: { lemonade: 13 },
    },
  }

  const items = buildPlayerStatRows(
    score,
    productName,
    {
      modules: ['base_employees', 'base_products', 'new_milestones'],
      milestones: ['first_house_built'],
      employees: score.employees,
    }
  )
  const byKey = Object.fromEntries(items.map(item => [item.key, item]))

  assert.equal(byKey['marketing_actions']?.value, 9)
  assert.equal(byKey['marketing_type:billboard']?.value, 4)
  assert.equal(byKey['marketing_type:mailbox']?.value, 2)
  assert.equal(byKey['marketing_type:radio']?.value, 0)
  assert.equal(byKey['mailbox_placements'], undefined)
  assert.equal(byKey['hired_employees']?.value, 8)
  assert.equal(byKey['trained_employees']?.value, 5)
  assert.equal(byKey['house_built']?.value, 2)
  assert.equal(byKey['house_built']?.label, '建设房子数')
  assert.equal(byKey['restaurant_built']?.value, 1)
  assert.equal(byKey['produced:burger']?.label, '生产汉堡')
  assert.equal(byKey['produced:burger']?.value, 21)
  assert.equal(byKey['sold:lemonade']?.label, '售卖柠檬水')
  assert.equal(byKey['sold:lemonade']?.value, 13)
  assert.equal(byKey['sold:soda']?.value, 0)
  assert.equal(byKey['sold:beer']?.value, 0)
})

test('buildPlayerStatMatrixRows aligns metrics by player columns and fills missing values with zero', () => {
  const modules = ['base_products', 'base_employees', 'coffee', 'new_milestones']
  const playerA = {
    cash: 320,
    forfeited: false,
    restaurants: 3,
    employees: ['ceo', 'burger_cook', 'truck_driver'],
    milestones: ['first_house_built'],
    inventory: { burger: 2 },
    marketing_campaigns: 2,
    stats: {
      marketing_actions: 9,
      marketing_by_type: { billboard: 4, mailbox: 2 },
      hired_employees: 8,
      trained_employees: 5,
      metrics: { place_house_count: 2, place_restaurant_count: 1 },
      produced: { burger: 21, coffee: 3 },
      sold: { burger: 16, coffee: 2 },
    },
  }
  const playerB = {
    cash: 180,
    forfeited: false,
    restaurants: 2,
    employees: ['ceo', 'pizza_cook'],
    milestones: ['first_lemonade_sold'],
    inventory: { lemonade: 3 },
    marketing_campaigns: 1,
    stats: {
      marketing_actions: 6,
      marketing_by_type: { billboard: 1 },
      hired_employees: 4,
      metrics: { place_mailbox_count: 3 },
      produced: { lemonade: 10 },
      sales_counts: { lemonade: 7, coke: 3, beer: 2 },
    },
  }

  const rows = buildPlayerStatMatrixRows(
    [
      {
        userId: 'player-a',
        score: playerA,
        context: { modules, milestones: playerA.milestones, employees: playerA.employees },
      },
      {
        userId: 'player-b',
        score: playerB,
        context: { modules, milestones: playerB.milestones, employees: playerB.employees },
      },
    ],
    productName,
  )
  const byKey = Object.fromEntries(rows.map(row => [row.key, row]))

  assert.equal(byKey['marketing_actions']?.values['player-a'], 9)
  assert.equal(byKey['marketing_actions']?.values['player-b'], 6)
  assert.equal(byKey['marketing_type:mailbox']?.label, '放置邮箱')
  assert.equal(byKey['marketing_type:mailbox']?.values['player-a'], 2)
  assert.equal(byKey['marketing_type:mailbox']?.values['player-b'], 3)
  assert.equal(byKey['house_built']?.label, '建设房子数')
  assert.equal(byKey['house_built']?.values['player-a'], 2)
  assert.equal(byKey['house_built']?.values['player-b'], 0)
  assert.equal(byKey['restaurant_built']?.values['player-a'], 1)
  assert.equal(byKey['restaurant_built']?.values['player-b'], 0)
  assert.equal(byKey['produced:coffee']?.values['player-a'], 3)
  assert.equal(byKey['produced:coffee']?.values['player-b'], 0)
  assert.equal(byKey['sold:lemonade']?.values['player-a'], 0)
  assert.equal(byKey['sold:lemonade']?.values['player-b'], 7)
  assert.equal(byKey['sold:soda']?.label, '售卖可乐')
  assert.equal(byKey['sold:soda']?.values['player-a'], 0)
  assert.equal(byKey['sold:soda']?.values['player-b'], 3)
  assert.equal(byKey['sold:beer']?.values['player-a'], 0)
  assert.equal(byKey['sold:beer']?.values['player-b'], 2)
})

test('employeeName follows in-game employee display names', () => {
  assert.equal(employeeName('burger_cook'), '汉堡厨师')
  assert.equal(employeeName('truck_driver'), '货车驾驶员')
  assert.equal(employeeName('unknown_employee'), 'unknown_employee')
})

test('milestoneName follows in-game milestone display names', () => {
  assert.equal(milestoneName('first_house_built'), '首个建造房屋')
  assert.equal(milestoneName('first_lemonade_sold'), '首个卖出柠檬水')
  assert.equal(milestoneName('unknown_milestone'), 'unknown_milestone')
})

test('productName follows in-game product display names for drink aliases', () => {
  assert.equal(productName('soda'), '可乐')
  assert.equal(productName('coke'), '可乐')
  assert.equal(productName('cola'), '可乐')
})
