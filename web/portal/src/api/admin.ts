import client from './client'

export interface AdminUserSummary {
  user_id: string
  display_name: string
  status: string
  created_at: string
  email: string | null
  is_guest: boolean
  active_sessions: number
  room_count: number
  match_count: number
}

export interface AdminRoomSummary {
  room_code: string
  status: string
  owner_user_id: string
  join_policy: string
  game_server_id: string | null
  ws_url: string | null
  player_count: number
  spectator_count: number
  created_at: string
  updated_at: string
}

export interface AdminMatchSummary {
  match_id: string
  room_code: string | null
  status: string
  player_count: number
  participant_count: number
  has_replay: boolean
  started_at: string | null
  ended_at: string | null
  created_at: string
}

export interface BatchActionResult {
  ok: boolean
  requested: number
  affected: number
  missing: string[]
  meta: Record<string, number>
}

export function listAdminUsers(sessionId: string, params: { status?: string; query?: string; limit?: number; offset?: number } = {}) {
  return client.get<AdminUserSummary[]>('/admin/users', { params: { session_id: sessionId, ...params } })
}

export function updateAdminUserStatus(sessionId: string, userId: string, status: string) {
  return client.put<AdminUserSummary>(
    `/admin/users/${userId}/status`,
    { status },
    { params: { session_id: sessionId } },
  )
}

export function batchUpdateAdminUsersStatus(sessionId: string, userIds: string[], status: string) {
  return client.post<BatchActionResult>(
    '/admin/users/batch/status',
    { user_ids: userIds, status },
    { params: { session_id: sessionId } },
  )
}

export function batchDeleteAdminUsers(sessionId: string, userIds: string[]) {
  return client.post<BatchActionResult>(
    '/admin/users/batch/delete',
    { user_ids: userIds },
    { params: { session_id: sessionId } },
  )
}

export function listAdminRooms(sessionId: string, params: { status?: string; room_code?: string; limit?: number; offset?: number } = {}) {
  return client.get<AdminRoomSummary[]>('/admin/rooms', { params: { session_id: sessionId, ...params } })
}

export function endAdminRoom(sessionId: string, roomCode: string) {
  return client.post<AdminRoomSummary>(`/admin/rooms/${roomCode}/end`, {}, { params: { session_id: sessionId } })
}

export function batchEndAdminRooms(sessionId: string, roomCodes: string[]) {
  return client.post<BatchActionResult>(
    '/admin/rooms/batch/end',
    { room_codes: roomCodes },
    { params: { session_id: sessionId } },
  )
}

export function batchDeleteAdminRooms(sessionId: string, roomCodes: string[]) {
  return client.post<BatchActionResult>(
    '/admin/rooms/batch/delete',
    { room_codes: roomCodes },
    { params: { session_id: sessionId } },
  )
}

export function listAdminMatches(sessionId: string, params: { status?: string; room_code?: string; limit?: number; offset?: number } = {}) {
  return client.get<AdminMatchSummary[]>('/admin/matches', { params: { session_id: sessionId, ...params } })
}

export function deleteAdminMatch(sessionId: string, matchId: string) {
  return client.delete<{ ok: boolean }>(`/admin/matches/${matchId}`, { params: { session_id: sessionId } })
}

export function batchDeleteAdminMatches(sessionId: string, matchIds: string[]) {
  return client.post<BatchActionResult>(
    '/admin/matches/batch/delete',
    { match_ids: matchIds },
    { params: { session_id: sessionId } },
  )
}
