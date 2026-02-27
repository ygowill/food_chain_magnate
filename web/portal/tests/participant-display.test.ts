import assert from 'node:assert/strict'
import test from 'node:test'

import { participantDisplayName, resolveParticipantLogoInfo } from '../src/utils/participant-display.ts'

test('participantDisplayName prefers in-game nickname and falls back to seat label', () => {
  assert.equal(participantDisplayName({
    user_id: 'uid-1',
    role: 'player',
    seat_index: 0,
    result: null,
    score: null,
    display_name: '老王',
  }), '老王')

  assert.equal(participantDisplayName({
    user_id: 'uid-2',
    role: 'player',
    seat_index: 2,
    result: null,
    score: null,
  }), '玩家3')
})

test('resolveParticipantLogoInfo resolves by logo key then by logo id', () => {
  const byKey = resolveParticipantLogoInfo({
    user_id: 'uid-1',
    role: 'player',
    seat_index: 0,
    result: null,
    score: null,
    restaurant_logo_key: 'restaurant_logo_santa_maria_pizza',
  })
  assert.equal(byKey.label, '圣玛丽亚披萨')
  assert.equal(byKey.url, '/restaurant-logos/santa_maria_pizza.png')

  const byId = resolveParticipantLogoInfo({
    user_id: 'uid-2',
    role: 'player',
    seat_index: 1,
    result: null,
    score: null,
    restaurant_logo_id: 5,
  })
  assert.equal(byId.label, '好味来')
  assert.equal(byId.url, '/restaurant-logos/siap_faji.png')
})
