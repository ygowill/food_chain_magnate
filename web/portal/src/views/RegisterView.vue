<template>
  <AuthCard title="注册" width="460px">
    <el-form @submit.prevent="handleRegister" :disabled="loading">
      <el-form-item label="邮箱">
        <el-input v-model="email" placeholder="请输入邮箱" />
      </el-form-item>
      <el-form-item label="密码">
        <el-input v-model="password" type="password" placeholder="请输入密码" show-password />
      </el-form-item>
      <el-form-item label="确认密码">
        <el-input v-model="confirmPassword" type="password" placeholder="请再次输入密码" show-password />
      </el-form-item>
      <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-bottom: 16px" />
      <el-form-item>
        <el-button type="primary" native-type="submit" :loading="loading" style="width: 100%">
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
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import AuthCard from '../components/AuthCard.vue'

const auth = useAuthStore()
const router = useRouter()

const email = ref('')
const password = ref('')
const confirmPassword = ref('')
const error = ref('')
const loading = ref(false)

async function handleRegister() {
  error.value = ''
  if (password.value !== confirmPassword.value) {
    error.value = '两次输入的密码不一致'
    return
  }
  loading.value = true
  try {
    await auth.register(email.value, password.value)
    router.push('/matches')
  } catch (e: any) {
    error.value = e.response?.data?.detail || '注册失败'
  } finally {
    loading.value = false
  }
}
</script>
