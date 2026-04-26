<template>
  <div class="app-layout">
    <header class="app-nav">
      <div class="app-nav__inner">
        <router-link to="/game" class="app-nav__brand">
          <span class="app-nav__title">Food Chain Magnate</span>
        </router-link>

        <nav class="app-nav__links">
          <router-link to="/game" class="app-nav__link">
            <svg class="app-nav__icon" viewBox="0 0 20 20" fill="currentColor"><path d="M10 2a.75.75 0 01.6.3l7 9.5A.75.75 0 0117 13H3a.75.75 0 01-.6-1.2l7-9.5A.75.75 0 0110 2zm-4.47 14h8.94a.75.75 0 010 1.5H5.53a.75.75 0 010-1.5z"/></svg>
            游戏
          </router-link>
          <router-link to="/matches" class="app-nav__link">
            <svg class="app-nav__icon" viewBox="0 0 20 20" fill="currentColor"><path d="M2 4.5A2.5 2.5 0 014.5 2h11A2.5 2.5 0 0118 4.5v11a2.5 2.5 0 01-2.5 2.5h-11A2.5 2.5 0 012 15.5v-11zm2.5-1a1 1 0 00-1 1v11a1 1 0 001 1h11a1 1 0 001-1v-11a1 1 0 00-1-1h-11zM6 7h8v1.5H6V7zm0 3h8v1.5H6V10zm0 3h5v1.5H6V13z"/></svg>
            对局历史
          </router-link>
          <router-link v-if="auth.isAdmin" to="/admin" class="app-nav__link">
            <svg class="app-nav__icon" viewBox="0 0 20 20" fill="currentColor"><path d="M10 1a2 2 0 00-2 2v1.07A7.003 7.003 0 003.07 9H2a2 2 0 100 2h1.07A7.003 7.003 0 008 15.93V17a2 2 0 104 0v-1.07A7.003 7.003 0 0016.93 11H18a2 2 0 100-2h-1.07A7.003 7.003 0 0012 4.07V3a2 2 0 00-2-2zm0 6a3 3 0 100 6 3 3 0 000-6z"/></svg>
            管理后台
          </router-link>
        </nav>

        <div class="app-nav__spacer" />

        <router-link v-if="!auth.isLoggedIn" to="/login" class="app-nav__login">
          登录
        </router-link>

        <div v-else class="app-nav__user" @click="showUserMenu = !showUserMenu" ref="userMenuRef">
          <div class="app-nav__avatar">{{ avatarLetter }}</div>
          <span class="app-nav__username">{{ displayName }}</span>
          <svg class="app-nav__chevron" :class="{ 'app-nav__chevron--open': showUserMenu }" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/></svg>

          <Transition name="dropdown">
            <div v-if="showUserMenu" class="app-nav__dropdown">
              <router-link to="/settings" class="app-nav__dropdown-item" @click="showUserMenu = false">
                <svg class="app-nav__dropdown-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"/></svg>
                账号设置
              </router-link>
              <button class="app-nav__dropdown-item app-nav__dropdown-item--danger" @click="handleLogout">
                <svg class="app-nav__dropdown-icon" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M3 3a1 1 0 00-1 1v12a1 1 0 001 1h5a1 1 0 100-2H4V5h4a1 1 0 100-2H3zm11.293 3.293a1 1 0 011.414 0l3 3a1 1 0 010 1.414l-3 3a1 1 0 01-1.414-1.414L15.586 11H8a1 1 0 110-2h7.586l-1.293-1.293a1 1 0 010-1.414z" clip-rule="evenodd"/></svg>
                退出登录
              </button>
            </div>
          </Transition>
        </div>
      </div>
      <div class="app-nav__accent" />
    </header>

    <main class="app-main">
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useAuthStore } from '../stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()
const showUserMenu = ref(false)
const userMenuRef = ref<HTMLElement | null>(null)

const displayName = computed(() => {
  return auth.user?.display_name || auth.user?.email?.split('@')[0] || '用户'
})

const avatarLetter = computed(() => {
  const name = displayName.value
  return name.charAt(0).toUpperCase()
})

onMounted(() => {
  if (auth.isLoggedIn && auth.user == null) {
    void auth.fetchUser()
  }
  document.addEventListener('click', handleClickOutside)
})

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside)
})

function handleClickOutside(e: MouseEvent) {
  if (userMenuRef.value && !userMenuRef.value.contains(e.target as Node)) {
    showUserMenu.value = false
  }
}

async function handleLogout() {
  showUserMenu.value = false
  await auth.logout()
  router.push('/login')
}
</script>

<style scoped>
.app-layout {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.app-nav {
  position: sticky;
  top: 0;
  z-index: 100;
  background: linear-gradient(135deg, var(--fcm-dark) 0%, var(--fcm-dark-lighter) 100%);
  box-shadow: var(--fcm-shadow-nav);
}

.app-nav__inner {
  display: flex;
  align-items: center;
  height: 64px;
  padding: 0 28px;
  max-width: var(--fcm-max-width);
  margin: 0 auto;
  width: 100%;
}

.app-nav__accent {
  height: 2px;
  background: linear-gradient(90deg, var(--fcm-gold) 0%, rgba(201, 160, 32, 0.3) 50%, var(--fcm-gold) 100%);
}

.app-nav__brand {
  display: flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
  margin-right: 32px;
  flex-shrink: 0;
}

.app-nav__title {
  font-family: var(--fcm-font-display);
  font-size: 18px;
  font-weight: 600;
  color: var(--fcm-text-light);
  letter-spacing: 0.02em;
  white-space: nowrap;
}

.app-nav__links {
  display: flex;
  gap: 2px;
  height: 100%;
  align-items: stretch;
}

.app-nav__link {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 0 16px;
  font-size: 14px;
  font-weight: 500;
  color: rgba(247, 237, 209, 0.6);
  text-decoration: none;
  border: none;
  background: none;
  cursor: pointer;
  position: relative;
  transition: color 0.2s, background 0.2s;
  border-radius: var(--fcm-radius) var(--fcm-radius) 0 0;
}

.app-nav__link:hover {
  color: var(--fcm-text-light);
  background: rgba(247, 237, 209, 0.08);
}

.app-nav__link.router-link-active {
  color: var(--fcm-text-light);
  background: rgba(247, 237, 209, 0.06);
}

.app-nav__link.router-link-active::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 12px;
  right: 12px;
  height: 3px;
  background: var(--fcm-gold);
  border-radius: 2px 2px 0 0;
}

.app-nav__icon {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  opacity: 0.7;
}

.app-nav__link.router-link-active .app-nav__icon {
  opacity: 1;
}

.app-nav__spacer {
  flex: 1;
}

.app-nav__user {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  border-radius: var(--fcm-radius);
  cursor: pointer;
  transition: background 0.2s;
  position: relative;
  user-select: none;
}

.app-nav__login {
  display: inline-flex;
  align-items: center;
  min-height: 40px;
  padding: 0 16px;
  border: 1px solid rgba(201, 160, 32, 0.34);
  border-radius: var(--fcm-radius);
  color: var(--fcm-text-light);
  background: rgba(247, 237, 209, 0.08);
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  transition: background 0.2s, border-color 0.2s;
}

.app-nav__login:hover {
  background: rgba(247, 237, 209, 0.14);
  border-color: rgba(201, 160, 32, 0.55);
  text-decoration: none;
}

.app-nav__user:hover {
  background: rgba(247, 237, 209, 0.08);
}

.app-nav__avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--fcm-primary), var(--fcm-primary-hover));
  color: var(--fcm-text-light);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  font-weight: 700;
  flex-shrink: 0;
  border: 2px solid rgba(201, 160, 32, 0.3);
}

.app-nav__username {
  font-size: 14px;
  font-weight: 500;
  color: var(--fcm-text-light);
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.app-nav__chevron {
  width: 14px;
  height: 14px;
  color: rgba(247, 237, 209, 0.5);
  transition: transform 0.2s;
}

.app-nav__chevron--open {
  transform: rotate(180deg);
}

.app-nav__dropdown {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  min-width: 180px;
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
  box-shadow: var(--fcm-shadow-elevated);
  padding: 6px;
  z-index: 200;
}

.app-nav__dropdown-item {
  display: flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 10px 14px;
  font-size: 14px;
  font-family: var(--fcm-font-body);
  font-weight: 500;
  color: var(--fcm-text-primary);
  text-decoration: none;
  border: none;
  background: none;
  cursor: pointer;
  border-radius: 4px;
  transition: background 0.15s;
}

.app-nav__dropdown-item:hover {
  background: var(--fcm-primary-light);
}

.app-nav__dropdown-item--danger {
  color: var(--fcm-primary);
}

.app-nav__dropdown-icon {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  opacity: 0.6;
}

.dropdown-enter-active {
  transition: opacity 0.15s, transform 0.15s;
}
.dropdown-leave-active {
  transition: opacity 0.1s, transform 0.1s;
}
.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateY(-6px);
}

.app-main {
  flex: 1;
  padding: 32px 28px;
  max-width: var(--fcm-max-width);
  margin: 0 auto;
  width: 100%;
}
</style>
