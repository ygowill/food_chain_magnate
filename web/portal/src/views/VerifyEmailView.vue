<template>
  <AuthCard title="验证邮箱" width="460px">
    <el-result
      v-if="loading"
      icon="info"
      title="正在验证邮箱"
      sub-title="请稍候，验证成功后会自动登录。"
    />
    <el-result
      v-else-if="success"
      icon="success"
      title="邮箱验证成功"
      sub-title="账号已自动登录，正在跳转。"
    />
    <el-result
      v-else
      icon="error"
      title="邮箱验证失败"
      :sub-title="error || '验证链接无效或已过期。'"
    >
      <template #extra>
        <router-link to="/login">
          <el-button type="primary">前往登录</el-button>
        </router-link>
      </template>
    </el-result>
  </AuthCard>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import AuthCard from '../components/AuthCard.vue'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()

const loading = ref(true)
const success = ref(false)
const error = ref('')

onMounted(async () => {
  const token = String(route.query.token || '').trim()
  if (!token) {
    loading.value = false
    error.value = '缺少验证 token'
    return
  }

  try {
    await auth.completeEmailVerification(token)
    success.value = true
    await router.replace('/matches')
  } catch (e: any) {
    error.value = e.response?.data?.detail || '验证失败'
  } finally {
    loading.value = false
  }
})
</script>
