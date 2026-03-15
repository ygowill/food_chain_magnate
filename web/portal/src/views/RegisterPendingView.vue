<template>
  <AuthCard title="验证邮箱" width="460px">
    <el-result
      icon="success"
      title="验证邮件已发送"
      :sub-title="subtitle"
    >
      <template #extra>
        <el-button type="primary" :loading="resendLoading" @click="handleResend" :disabled="!email">
          重新发送
        </el-button>
        <router-link to="/login">
          <el-button>返回登录</el-button>
        </router-link>
      </template>
    </el-result>
    <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-top: 16px" />
    <el-alert
      v-if="success"
      :title="success"
      type="success"
      :closable="false"
      style="margin-top: 16px"
    />
  </AuthCard>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute } from 'vue-router'
import { resendEmailVerification } from '../api/auth'
import AuthCard from '../components/AuthCard.vue'

const route = useRoute()
const email = computed(() => String(route.query.email || '').trim())
const subtitle = computed(() => email.value
  ? `验证链接已发送到 ${email.value}，请打开邮件中的链接完成激活。`
  : '请打开邮件中的验证链接完成激活。')
const resendLoading = ref(false)
const error = ref('')
const success = ref('')

async function handleResend() {
  if (!email.value) return
  error.value = ''
  success.value = ''
  resendLoading.value = true
  try {
    const { data } = await resendEmailVerification({ email: email.value })
    success.value = `验证邮件已重新发送到 ${data.email}`
  } catch (e: any) {
    error.value = e.response?.data?.detail || '重新发送失败'
  } finally {
    resendLoading.value = false
  }
}
</script>
