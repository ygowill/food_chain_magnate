import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { login as apiLogin, register as apiRegister, guestLogin as apiGuestLogin, getMe, type MeResponse } from '../api/auth'

const SESSION_KEY = 'fcm_session_id'
const USER_ID_KEY = 'fcm_user_id'
const IS_GUEST_KEY = 'fcm_is_guest'

export const useAuthStore = defineStore('auth', () => {
  const sessionId = ref(localStorage.getItem(SESSION_KEY) || '')
  const user = ref<MeResponse | null>(null)

  const isLoggedIn = computed(() => !!sessionId.value)
  const isAdmin = computed(() => !!user.value?.is_admin)

  async function login(email: string, password: string) {
    const { data } = await apiLogin(email, password)
    sessionId.value = data.session_id
    localStorage.setItem(SESSION_KEY, data.session_id)
    await fetchUser()
  }

  async function register(email: string, password: string, displayName?: string) {
    const { data } = await apiRegister(email, password, displayName)
    sessionId.value = data.session_id
    localStorage.setItem(SESSION_KEY, data.session_id)
    await fetchUser()
  }

  async function guestLogin() {
    const deviceId = crypto.randomUUID()
    const { data } = await apiGuestLogin(deviceId)
    sessionId.value = data.session_id
    localStorage.setItem(SESSION_KEY, data.session_id)
    await fetchUser()
  }

  async function fetchUser() {
    if (!sessionId.value) return
    try {
      const { data } = await getMe(sessionId.value)
      user.value = data
      localStorage.setItem(USER_ID_KEY, data.user_id)
      localStorage.setItem(IS_GUEST_KEY, String(data.is_guest))
    } catch {
      logout()
    }
  }

  function logout() {
    sessionId.value = ''
    user.value = null
    localStorage.removeItem(SESSION_KEY)
    localStorage.removeItem(USER_ID_KEY)
    localStorage.removeItem(IS_GUEST_KEY)
  }

  return { sessionId, user, isLoggedIn, isAdmin, login, register, guestLogin, fetchUser, logout }
})
