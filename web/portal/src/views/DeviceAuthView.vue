<template>
  <AuthCard title="设备授权" width="480px">
    <div v-if="!authorized" style="text-align: center">
      <p class="device-hint">请确认以下设备码与客户端显示一致：</p>
      <div class="user-code">{{ userCode }}</div>
      <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin: 16px 0" />
      <el-button type="primary" :loading="loading" @click="handleAuthorize" size="large" style="width: 100%; font-weight: 600">
        授权此设备
      </el-button>
    </div>
    <el-result v-else icon="success" title="授权成功" sub-title="你可以关闭此页面，客户端将自动登录" />
  </AuthCard>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { authorizeDevice } from '../api/auth'
import AuthCard from '../components/AuthCard.vue'

const route = useRoute()
const auth = useAuthStore()

const userCode = ref('')
const loading = ref(false)
const error = ref('')
const authorized = ref(false)

onMounted(() => {
  userCode.value = (route.query.code as string) || ''
})

async function handleAuthorize() {
  if (!userCode.value) {
    error.value = '缺少设备码'
    return
  }
  error.value = ''
  loading.value = true
  try {
    await authorizeDevice(userCode.value, auth.sessionId)
    authorized.value = true
  } catch (e: any) {
    error.value = e.response?.data?.detail || '授权失败'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.device-hint {
  color: var(--fcm-text-muted);
  margin: 0 0 8px;
  font-size: 14px;
}
.user-code {
  font-size: 36px;
  font-weight: 700;
  letter-spacing: 6px;
  margin: 20px 0 28px;
  font-family: 'Playfair Display', monospace;
  color: var(--fcm-text-primary);
  background: var(--fcm-field-bg);
  border: 2px solid var(--fcm-gold-border);
  border-radius: var(--fcm-radius);
  display: inline-block;
  padding: 12px 32px;
}
</style>
