import client from './client'

export interface ProductStatMap {
  [productId: string]: number
}

export interface PlayerActionStats {
  marketing_actions?: number
  marketing_count?: number
  billboard_placements?: number
  billboard_count?: number
  hired_employees?: number
  recruit_count?: number
  trained_employees?: number
  train_count?: number
  produced?: ProductStatMap
  production_counts?: ProductStatMap
  sold?: ProductStatMap
  sales_counts?: ProductStatMap
  marketing_by_type?: ProductStatMap
  metrics?: ProductStatMap
  [key: string]: unknown
}

export interface PlayerScore {
  cash: number
  forfeited: boolean
  restaurants: number
  employees: string[]
  milestones: string[]
  inventory: Record<string, number>
  marketing_campaigns: number
  stats?: PlayerActionStats | null
}

export interface GameSummary {
  modules: string[]
  round_number: number
  bank_total: number
  bank_broke_count: number
  bank_reserve_added: number
  marketing_count: number
}

export interface ParticipantInfo {
  user_id: string
  role: string
  seat_index: number | null
  result: string | null
  display_name?: string | null
  restaurant_logo_id?: number | null
  restaurant_logo_key?: string | null
  score: PlayerScore | null
}

export interface MatchSummary {
  match_id: string
  room_code: string | null
  status: string
  player_count: number
  started_at: string | null
  ended_at: string | null
  duration_sec: number | null
  participants: ParticipantInfo[]
  latest_save_round?: number | null
  map_snapshot_count?: number
}

export interface MatchDetail extends MatchSummary {
  seed: string | null
  game_version: string | null
  schema_version: string | null
  final_hash: string | null
  summary: GameSummary | null
  has_replay: boolean
  latest_save: MatchArtifactInfo | null
  map_snapshots: MatchArtifactInfo[]
}

export interface ReplayInfo {
  match_id: string
  storage_uri: string
  checksum: string | null
  size_bytes: number | null
}

export interface MatchArtifactInfo {
  id: string
  artifact_type: string
  snapshot_kind: string | null
  round_number: number
  state_hash: string | null
  storage_uri: string
  download_url: string
  mime_type: string
  checksum: string | null
  size_bytes: number | null
  created_at: string
  updated_at: string | null
}

function requireSessionId(sessionId: string): string {
  const normalized = String(sessionId || '').trim()
  if (!normalized) {
    throw new Error('login required')
  }
  return normalized
}

export function listMatches(sessionId: string) {
  return client.get<MatchSummary[]>('/matches', { params: { session_id: requireSessionId(sessionId) } })
}

export function getMatch(matchId: string, sessionId: string) {
  return client.get<MatchDetail>(`/matches/${matchId}`, { params: { session_id: requireSessionId(sessionId) } })
}

export function getReplay(matchId: string, sessionId: string) {
  return client.get<ReplayInfo>(`/matches/${matchId}/replay`, { params: { session_id: requireSessionId(sessionId) } })
}
