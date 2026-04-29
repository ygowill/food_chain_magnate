import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'login',
      component: () => import('../views/LoginView.vue'),
      meta: { guest: true },
    },
    {
      path: '/register',
      name: 'register',
      component: () => import('../views/RegisterView.vue'),
      meta: { guest: true },
    },
    {
      path: '/device',
      name: 'device',
      component: () => import('../views/DeviceAuthView.vue'),
      meta: { auth: true },
    },
    {
      path: '/game',
      name: 'game',
      component: () => import('../views/GameView.vue'),
    },
    {
      path: '/matches',
      name: 'matches',
      component: () => import('../views/MatchesView.vue'),
      meta: { auth: true },
    },
    {
      path: '/matches/:id',
      name: 'match-detail',
      component: () => import('../views/MatchDetailView.vue'),
      meta: { auth: true },
    },
    {
      path: '/settings',
      name: 'settings',
      component: () => import('../views/SettingsView.vue'),
      meta: { auth: true },
    },
    {
      path: '/admin',
      name: 'admin',
      component: () => import('../views/AdminView.vue'),
      meta: { auth: true },
    },
    {
      path: '/',
      redirect: '/game',
    },
  ],
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.isLoggedIn && auth.user == null) {
    await auth.fetchUser()
  }
  if (to.meta.auth && !auth.isLoggedIn) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.name === 'admin' && !auth.isAdmin) {
    return { name: 'game' }
  }
  if (to.meta.guest && auth.isLoggedIn) {
    return { name: 'game' }
  }
})

export default router
