<template>
  <AuthCard title="注册" width="480px">
    <el-form @submit.prevent="handleRegister" :disabled="loading">
      <el-form-item label="昵称">
        <el-input v-model="displayName" placeholder="可选，不填则自动生成" size="large" />
      </el-form-item>
      <el-form-item label="邮箱">
        <el-input v-model="email" placeholder="请输入邮箱" size="large" />
      </el-form-item>
      <el-form-item label="密码">
        <el-input v-model="password" type="password" placeholder="请输入密码" show-password size="large" />
      </el-form-item>
      <el-form-item label="确认密码">
        <el-input v-model="confirmPassword" type="password" placeholder="请再次输入密码" show-password size="large" />
      </el-form-item>
      <el-form-item label="验证码">
        <div class="captcha-row">
          <div class="captcha-code">{{ captchaCode }}</div>
          <el-input v-model="captchaInput" placeholder="请输入验证码" size="large" />
          <el-button @click="refreshCaptcha" size="large">换一张</el-button>
        </div>
      </el-form-item>
      <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-bottom: 16px" />
      <el-form-item>
        <el-button type="primary" native-type="submit" :loading="loading" size="large" class="auth-btn">
          注册
        </el-button>
      </el-form-item>
    </el-form>
    <template #footer>
      已有账号？<router-link to="/login">登录</router-link>
    </template>
  </AuthCard>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import AuthCard from '../components/AuthCard.vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const displayName = ref('')
const captchaInput = ref('')
const error = ref('')
const loading = ref(false)
const captchaCode = ref('')

function refreshCaptcha() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let next = ''
  for (let i = 0; i < 5; i += 1) {
    next += chars[Math.floor(Math.random() * chars.length)]
  }
  captchaCode.value = next
  captchaInput.value = ''
}

refreshCaptcha()

async function handleRegister() {
  error.value = ''
  if (!email.value.trim()) {
    error.value = '邮箱不能为空'
    return
  }
  if (password.value !== confirmPassword.value) {
    error.value = '两次输入的密码不一致'
    return
  }
  if (captchaInput.value.trim().toUpperCase() !== captchaCode.value) {
    error.value = '验证码错误'
    refreshCaptcha()
    return
  }
  loading.value = true
  try {
    await auth.register(email.value, password.value, displayName.value)
    const redirect = (route.query.redirect as string) || '/game'
    router.push(redirect)
  } catch (e: any) {
    error.value = e.response?.data?.detail || '注册失败'
    refreshCaptcha()
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.auth-btn {
  width: 100%;
  font-weight: 600;
}

.captcha-row {
  display: grid;
  grid-template-columns: 108px 1fr auto;
  gap: 12px;
  width: 100%;
  align-items: center;
}

.captcha-code {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 40px;
  border: 1px solid var(--fcm-gold-border);
  border-radius: var(--fcm-radius);
  background:
    linear-gradient(135deg, rgba(201, 160, 32, 0.08), rgba(201, 160, 32, 0.15)),
    repeating-linear-gradient(-45deg, rgba(43, 33, 23, 0.04), rgba(43, 33, 23, 0.04) 6px, transparent 6px, transparent 12px);
  color: var(--fcm-text-primary);
  font-size: 18px;
  font-weight: 700;
  letter-spacing: 0.22em;
  user-select: none;
}
</style>
