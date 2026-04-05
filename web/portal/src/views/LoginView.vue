<template>
  <AuthCard title="登录" width="460px">
    <el-form @submit.prevent="handleLogin" :disabled="loading">
      <el-form-item label="邮箱">
        <el-input v-model="email" placeholder="请输入邮箱" />
      </el-form-item>
      <el-form-item label="密码">
        <el-input v-model="password" type="password" placeholder="请输入密码" show-password />
      </el-form-item>
      <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-bottom: 16px" />
      <el-form-item>
        <el-button type="primary" native-type="submit" :loading="loading" style="width: 100%">
          登录
        </el-button>
      </el-form-item>
    </el-form>
    <div class="divider"><span>或</span></div>
    <el-button :loading="guestLoading" style="width: 100%" @click="handleGuestLogin">
      游客试玩
    </el-button>
    <template #footer>
      还没有账号？<router-link to="/register">注册</router-link>
    </template>
  </AuthCard>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import AuthCard from '../components/AuthCard.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)
const guestLoading = ref(false)

async function handleGuestLogin() {
  error.value = ''
  guestLoading.value = true
  try {
    await auth.guestLogin()
    const redirect = (route.query.redirect as string) || '/game'
    router.push(redirect)
  } catch (e: any) {
    error.value = e.response?.data?.detail || '游客登录失败'
  } finally {
    guestLoading.value = false
  }
}

async function handleLogin() {
  error.value = ''
  loading.value = true
  try {
    await auth.login(email.value, password.value)
    const redirect = (route.query.redirect as string) || '/game'
    router.push(redirect)
  } catch (e: any) {
    error.value = e.response?.data?.detail || '登录失败'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.divider {
  display: flex;
  align-items: center;
  margin: 16px 0;
  color: var(--fcm-text-muted);
  font-size: 13px;
}
.divider::before,
.divider::after {
  content: '';
  flex: 1;
  height: 1px;
  background: var(--fcm-field-border);
}
.divider span {
  padding: 0 12px;
}
</style>
