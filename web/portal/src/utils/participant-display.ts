import type { ParticipantInfo } from '../api/matches'

const RESTAURANT_LOGO_KEYS = [
  'restaurant_logo_fried_geese_donkey',
  'restaurant_logo_gluttony_inc_burgers',
  'restaurant_logo_golden_duck_diner',
  'restaurant_logo_santa_maria_pizza',
  'restaurant_logo_xango_blues_bar',
  'restaurant_logo_sixth_chain',
] as const

type RestaurantLogoKey = (typeof RESTAURANT_LOGO_KEYS)[number]

const RESTAURANT_LOGO_LABELS: Record<RestaurantLogoKey, string> = {
  restaurant_logo_fried_geese_donkey: '驴肉&烧鹅',
  restaurant_logo_gluttony_inc_burgers: '饕餮汉堡',
  restaurant_logo_golden_duck_diner: '金鸭小馆',
  restaurant_logo_santa_maria_pizza: '圣玛丽亚披萨',
  restaurant_logo_xango_blues_bar: '尚戈蓝调酒吧',
  restaurant_logo_sixth_chain: '好味来',
}

const RESTAURANT_LOGO_FILES: Record<RestaurantLogoKey, string> = {
  restaurant_logo_fried_geese_donkey: '/restaurant-logos/fried_geese_donkey.png',
  restaurant_logo_gluttony_inc_burgers: '/restaurant-logos/gluttony_inc_burgers.png',
  restaurant_logo_golden_duck_diner: '/restaurant-logos/golden_duck_diner.png',
  restaurant_logo_santa_maria_pizza: '/restaurant-logos/santa_maria_pizza.png',
  restaurant_logo_xango_blues_bar: '/restaurant-logos/xango_blues_bar.png',
  restaurant_logo_sixth_chain: '/restaurant-logos/siap_faji.png',
}

function asLogoKey(value: string | null | undefined): RestaurantLogoKey | null {
  if (!value) return null
  return (RESTAURANT_LOGO_KEYS as readonly string[]).includes(value)
    ? (value as RestaurantLogoKey)
    : null
}

function logoKeyFromId(logoId: number | null | undefined): RestaurantLogoKey | null {
  if (logoId == null) return null
  if (logoId < 0 || logoId >= RESTAURANT_LOGO_KEYS.length) return null
  return RESTAURANT_LOGO_KEYS[logoId]
}

export interface ParticipantLogoInfo {
  key: string | null
  label: string | null
  url: string | null
}

export function resolveParticipantLogoInfo(participant: ParticipantInfo): ParticipantLogoInfo {
  const key = asLogoKey(participant.restaurant_logo_key) ?? logoKeyFromId(participant.restaurant_logo_id)
  if (!key) {
    return {
      key: null,
      label: null,
      url: null,
    }
  }
  return {
    key,
    label: RESTAURANT_LOGO_LABELS[key],
    url: RESTAURANT_LOGO_FILES[key],
  }
}

export function participantDisplayName(participant: ParticipantInfo): string {
  const name = String(participant.display_name ?? '').trim()
  if (name) return name
  if (participant.seat_index != null && participant.seat_index >= 0) {
    return `玩家${participant.seat_index + 1}`
  }
  return participant.user_id.slice(0, 8)
}
