import client from './client'

export interface AuthResponse {
  user_id: string
  session_id: string
  display_name: string
  is_guest: boolean
}

export interface MeResponse {
  user_id: string
  display_name: string
  email: string | null
  is_guest: boolean
  is_admin: boolean
  created_at: string
}

export function login(email: string, password: string) {
  return client.post<AuthResponse>('/auth/login', { email, password })
}

export function register(email: string, password: string, displayName?: string) {
  const payload: Record<string, string> = { email, password }
  if (displayName && String(displayName).trim()) {
    payload.display_name = String(displayName).trim()
  }
  return client.post<AuthResponse>('/auth/register', payload)
}

export function getMe(sessionId: string) {
  return client.get<MeResponse>('/auth/me', { params: { session_id: sessionId } })
}

export function changePassword(sessionId: string, oldPassword: string, newPassword: string) {
  return client.put('/auth/password', {
    session_id: sessionId,
    old_password: oldPassword,
    new_password: newPassword,
  })
}

export function guestLogin(deviceId: string) {
  return client.post<AuthResponse>('/auth/guest', { device_id: deviceId })
}

export function bindEmail(sessionId: string, email: string, password: string) {
  return client.post<AuthResponse>('/auth/bind', {
    session_id: sessionId,
    provider: 'email',
    email,
    password,
  })
}

export interface UpdateProfileResponse {
  user_id: string
  display_name: string
  is_guest: boolean
}

export function updateDisplayName(sessionId: string, displayName: string) {
  return client.put<UpdateProfileResponse>('/auth/profile', {
    session_id: sessionId,
    display_name: displayName,
  })
}

export function authorizeDevice(userCode: string, sessionId: string) {
  return client.post('/auth/device/authorize', {
    user_code: userCode,
    session_id: sessionId,
  })
}
