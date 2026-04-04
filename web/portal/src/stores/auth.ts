import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import {
  login as apiLogin,
  register as apiRegister,
  guestLogin as apiGuestLogin,
  getMe,
  logout as apiLogout,
  type AuthResponse,
  type MeResponse,
} from '../api/auth'

const SESSION_KEY = 'fcm_session_id'
const USER_ID_KEY = 'fcm_user_id'
const IS_GUEST_KEY = 'fcm_is_guest'
const DISPLAY_NAME_KEY = 'fcm_display_name'
const DEVICE_ID_KEY = 'fcm_device_id'
const EMAIL_KEY = 'fcm_email'
const EMAIL_VERIFIED_KEY = 'fcm_email_verified'
const EMAIL_VERIFICATION_PENDING_KEY = 'fcm_email_verification_pending'
const IS_ADMIN_KEY = 'fcm_is_admin'
const CREATED_AT_KEY = 'fcm_created_at'

const SHARED_AUTH_KEYS = new Set([
  SESSION_KEY,
  USER_ID_KEY,
  IS_GUEST_KEY,
  DISPLAY_NAME_KEY,
  EMAIL_KEY,
  EMAIL_VERIFIED_KEY,
  EMAIL_VERIFICATION_PENDING_KEY,
  IS_ADMIN_KEY,
  CREATED_AT_KEY,
])

let browserSyncInstalled = false

export const useAuthStore = defineStore('auth', () => {
  const sessionId = ref(localStorage.getItem(SESSION_KEY) || '')
  const user = ref<MeResponse | null>(null)

  const isLoggedIn = computed(() => !!sessionId.value)
  const isAdmin = computed(() => !!user.value?.is_admin)

  function applySession(nextSessionId: string) {
    sessionId.value = nextSessionId
    if (nextSessionId) {
      localStorage.setItem(SESSION_KEY, nextSessionId)
      return
    }
    localStorage.removeItem(SESSION_KEY)
  }

  function syncStoredIdentity(data: Pick<MeResponse, 'user_id' | 'display_name' | 'is_guest'>) {
    localStorage.setItem(USER_ID_KEY, data.user_id)
    localStorage.setItem(IS_GUEST_KEY, String(data.is_guest))
    localStorage.setItem(DISPLAY_NAME_KEY, data.display_name || '')
  }

  function syncStoredAccountDetails(data: Pick<MeResponse, 'email' | 'email_verified' | 'email_verification_pending' | 'is_admin' | 'created_at'>) {
    localStorage.setItem(EMAIL_KEY, data.email || '')
    localStorage.setItem(EMAIL_VERIFIED_KEY, String(!!data.email_verified))
    localStorage.setItem(EMAIL_VERIFICATION_PENDING_KEY, String(!!data.email_verification_pending))
    localStorage.setItem(IS_ADMIN_KEY, String(!!data.is_admin))
    localStorage.setItem(CREATED_AT_KEY, data.created_at || '')
  }

  function clearStoredIdentity() {
    localStorage.removeItem(USER_ID_KEY)
    localStorage.removeItem(IS_GUEST_KEY)
    localStorage.removeItem(DISPLAY_NAME_KEY)
    localStorage.removeItem(EMAIL_KEY)
    localStorage.removeItem(EMAIL_VERIFIED_KEY)
    localStorage.removeItem(EMAIL_VERIFICATION_PENDING_KEY)
    localStorage.removeItem(IS_ADMIN_KEY)
    localStorage.removeItem(CREATED_AT_KEY)
  }

  function clearAuthState() {
    applySession('')
    user.value = null
    clearStoredIdentity()
  }

  function ensureDeviceId() {
    const cached = localStorage.getItem(DEVICE_ID_KEY) || ''
    if (cached) {
      return cached
    }
    const created = crypto.randomUUID()
    localStorage.setItem(DEVICE_ID_KEY, created)
    return created
  }

  function applyAuthPayload(data: AuthResponse) {
    applySession(data.session_id)
    syncStoredIdentity(data)
    syncStoredAccountDetails({
      email: null,
      email_verified: null,
      email_verification_pending: false,
      is_admin: false,
      created_at: '',
    })
  }

  async function syncFromSharedStorage() {
    const nextSessionId = localStorage.getItem(SESSION_KEY) || ''
    if (!nextSessionId) {
      clearAuthState()
      return
    }
    if (nextSessionId !== sessionId.value) {
      applySession(nextSessionId)
    }
    await fetchUser()
  }

  function installBrowserSync() {
    if (browserSyncInstalled || typeof window === 'undefined') {
      return
    }
    browserSyncInstalled = true

    window.addEventListener('storage', (event) => {
      if (event.storageArea !== localStorage) {
        return
      }
      if (event.key && !SHARED_AUTH_KEYS.has(event.key)) {
        return
      }
      void syncFromSharedStorage()
    })

    window.addEventListener('focus', () => {
      void syncFromSharedStorage()
    })

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        void syncFromSharedStorage()
      }
    })
  }

  async function login(email: string, password: string) {
    const { data } = await apiLogin(email, password)
    applyAuthPayload(data)
    await fetchUser()
  }

  async function register(email: string, password: string, displayName?: string) {
    const { data } = await apiRegister(email, password, displayName)
    applyAuthPayload(data)
    await fetchUser()
    return data
  }

  async function guestLogin() {
    const deviceId = ensureDeviceId()
    const { data } = await apiGuestLogin(deviceId)
    applyAuthPayload(data)
    await fetchUser()
  }

  async function fetchUser() {
    if (!sessionId.value) {
      user.value = null
      clearStoredIdentity()
      return
    }
    try {
      const { data } = await getMe(sessionId.value)
      user.value = data
      syncStoredIdentity(data)
      syncStoredAccountDetails(data)
    } catch {
      clearAuthState()
    }
  }

  async function logout() {
    const currentSessionId = sessionId.value
    if (currentSessionId) {
      try {
        await apiLogout(currentSessionId)
      } catch {
      }
    }
    clearAuthState()
  }

  installBrowserSync()

  return {
    sessionId,
    user,
    isLoggedIn,
    isAdmin,
    login,
    register,
    guestLogin,
    fetchUser,
    logout,
  }
})
