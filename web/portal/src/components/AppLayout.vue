<template>
  <div class="app-layout">
    <header class="app-nav">
      <div class="app-nav__brand">FCM Portal</div>
      <nav class="app-nav__links">
        <router-link to="/game" class="app-nav__link">游戏</router-link>
        <router-link to="/matches" class="app-nav__link">对局历史</router-link>
        <router-link to="/settings" class="app-nav__link">账号设置</router-link>
      </nav>
      <div class="app-nav__spacer" />
      <button class="app-nav__link app-nav__logout" @click="handleLogout">退出登录</button>
    </header>
    <main class="app-main">
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
import { useAuthStore } from '../stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

async function handleLogout() {
  auth.logout()
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
  display: flex;
  align-items: center;
  height: 52px;
  padding: 0 20px;
  background: var(--fcm-surface);
  border-bottom: 2px solid var(--fcm-accent-line);
  gap: 4px;
}

.app-nav__brand {
  font-size: 18px;
  font-weight: 700;
  color: var(--fcm-primary);
  margin-right: 24px;
  user-select: none;
}

.app-nav__links {
  display: flex;
  gap: 4px;
  height: 100%;
  align-items: stretch;
}

.app-nav__link {
  display: flex;
  align-items: center;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 500;
  color: var(--fcm-text-muted);
  text-decoration: none;
  border: none;
  background: none;
  cursor: pointer;
  position: relative;
  transition: color 0.15s, background 0.15s;
  border-radius: var(--fcm-radius-sm) var(--fcm-radius-sm) 0 0;
}

.app-nav__link:hover {
  color: var(--fcm-text-primary);
  background: var(--fcm-field-bg);
}

.app-nav__link.router-link-active {
  color: var(--fcm-text-primary);
}

.app-nav__link.router-link-active::after {
  content: '';
  position: absolute;
  bottom: -2px;
  left: 8px;
  right: 8px;
  height: 3px;
  background: var(--fcm-primary);
  border-radius: 2px 2px 0 0;
}

.app-nav__spacer {
  flex: 1;
}

.app-nav__logout {
  font-family: inherit;
  border-radius: var(--fcm-radius-sm);
}

.app-main {
  flex: 1;
  padding: 24px 28px;
}
</style>
