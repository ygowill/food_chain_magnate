<template>
  <AppLayout>
    <div class="page-header">
      <h2 class="page-title">账号设置</h2>
      <div class="page-title-line" />
    </div>
    <div class="poster-card" style="max-width: 500px">
      <h3 class="poster-card__title">账号信息</h3>
      <el-descriptions :column="1" border v-if="auth.user">
        <el-descriptions-item label="昵称">{{ auth.user.display_name || '-' }}</el-descriptions-item>
        <el-descriptions-item label="用户 ID">{{ auth.user.user_id }}</el-descriptions-item>
        <el-descriptions-item label="邮箱">{{ auth.user.email || '未绑定' }}</el-descriptions-item>
        <el-descriptions-item label="邮箱状态">
          {{
            auth.user.email == null
              ? '未绑定'
              : auth.user.email_verified
                ? '已验证'
                : '待验证'
          }}
        </el-descriptions-item>
        <el-descriptions-item label="账号类型">{{ auth.user.is_guest ? '游客' : '正式' }}</el-descriptions-item>
        <el-descriptions-item label="注册时间">
          {{ new Date(auth.user.created_at).toLocaleString('zh-CN') }}
        </el-descriptions-item>
      </el-descriptions>
    </div>

    <div class="poster-card" style="max-width: 500px; margin-top: 20px" v-if="auth.user && !auth.user.is_guest">
      <h3 class="poster-card__title">昵称设置</h3>
      <p class="poster-card__hint">联机昵称与账号绑定。修改后，游戏客户端将自动使用该昵称。</p>
      <el-form @submit.prevent="handleUpdateDisplayName" :disabled="displayNameLoading">
        <el-form-item label="昵称">
          <el-input v-model="displayNameInput" maxlength="24" show-word-limit placeholder="请输入昵称（最多24字）" />
        </el-form-item>
        <el-alert v-if="displayNameError" :title="displayNameError" type="error" :closable="false" style="margin-bottom: 16px" />
        <el-alert v-if="displayNameSuccess" title="昵称修改成功" type="success" :closable="false" style="margin-bottom: 16px" />
        <el-form-item>
          <el-button type="primary" native-type="submit" :loading="displayNameLoading">保存昵称</el-button>
        </el-form-item>
      </el-form>
    </div>

    <div class="poster-card" style="max-width: 500px; margin-top: 20px" v-if="auth.user && auth.user.is_guest">
      <h3 class="poster-card__title">绑定邮箱</h3>
      <p class="poster-card__hint">
        绑定邮箱后可使用邮箱登录，游戏数据将保留。
        <span v-if="auth.user.email_verification_pending">当前邮箱待验证：{{ auth.user.email }}</span>
      </p>
      <el-form @submit.prevent="handleBind" :disabled="bindLoading">
        <el-form-item label="邮箱">
          <el-input v-model="bindEmail" placeholder="请输入邮箱" />
        </el-form-item>
        <el-form-item label="设置密码">
          <el-input v-model="bindPassword" type="password" placeholder="请输入密码" show-password />
        </el-form-item>
        <el-form-item label="确认密码">
          <el-input v-model="bindConfirm" type="password" placeholder="请再次输入密码" show-password />
        </el-form-item>
        <el-alert v-if="bindError" :title="bindError" type="error" :closable="false" style="margin-bottom: 16px" />
        <el-alert
          v-if="bindSuccess"
          title="验证邮件已发送，请打开邮箱中的链接完成绑定"
          type="success"
          :closable="false"
          style="margin-bottom: 16px"
        />
        <el-form-item>
          <el-button type="primary" native-type="submit" :loading="bindLoading">
            {{ auth.user.email_verification_pending ? '更新并重发验证邮件' : '绑定邮箱' }}
          </el-button>
          <el-button
            v-if="auth.user.email_verification_pending"
            :loading="bindResendLoading"
            @click="handleResendBindVerification"
          >
            重新发送
          </el-button>
        </el-form-item>
      </el-form>
    </div>

    <div class="poster-card" style="max-width: 500px; margin-top: 20px" v-if="auth.user && !auth.user.is_guest">
      <h3 class="poster-card__title">修改密码</h3>
      <el-form @submit.prevent="handleChangePassword" :disabled="loading">
        <el-form-item label="旧密码">
          <el-input v-model="oldPassword" type="password" show-password />
        </el-form-item>
        <el-form-item label="新密码">
          <el-input v-model="newPassword" type="password" show-password />
        </el-form-item>
        <el-form-item label="确认新密码">
          <el-input v-model="confirmPassword" type="password" show-password />
        </el-form-item>
        <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-bottom: 16px" />
        <el-alert v-if="success" title="密码修改成功" type="success" :closable="false" style="margin-bottom: 16px" />
        <el-form-item>
          <el-button type="primary" native-type="submit" :loading="loading">修改密码</el-button>
        </el-form-item>
      </el-form>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useAuthStore } from '../stores/auth'
import {
  changePassword,
  bindEmail as apiBindEmail,
  resendEmailVerification,
  updateDisplayName,
} from '../api/auth'
import AppLayout from '../components/AppLayout.vue'

const auth = useAuthStore()
const oldPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const error = ref('')
const success = ref(false)
const loading = ref(false)

const bindEmail = ref('')
const bindPassword = ref('')
const bindConfirm = ref('')
const bindError = ref('')
const bindSuccess = ref(false)
const bindLoading = ref(false)
const bindResendLoading = ref(false)
const displayNameInput = ref('')
const displayNameError = ref('')
const displayNameSuccess = ref(false)
const displayNameLoading = ref(false)

onMounted(async () => {
  await auth.fetchUser()
  displayNameInput.value = auth.user?.display_name || ''
  bindEmail.value = auth.user?.email || ''
})

async function handleBind() {
  bindError.value = ''
  bindSuccess.value = false
  if (bindPassword.value !== bindConfirm.value) {
    bindError.value = '两次输入的密码不一致'
    return
  }
  if (!bindEmail.value || !bindPassword.value) {
    bindError.value = '邮箱和密码不能为空'
    return
  }
  bindLoading.value = true
  try {
    const { data } = await apiBindEmail(auth.sessionId, bindEmail.value, bindPassword.value)
    bindSuccess.value = true
    await auth.fetchUser()
    bindEmail.value = data.email
    displayNameInput.value = auth.user?.display_name || ''
  } catch (e: any) {
    bindError.value = e.response?.data?.detail || '绑定失败'
  } finally {
    bindLoading.value = false
  }
}

async function handleResendBindVerification() {
  bindError.value = ''
  bindSuccess.value = false
  bindResendLoading.value = true
  try {
    const { data } = await resendEmailVerification({ sessionId: auth.sessionId })
    bindSuccess.value = true
    bindEmail.value = data.email
    await auth.fetchUser()
  } catch (e: any) {
    bindError.value = e.response?.data?.detail || '重新发送失败'
  } finally {
    bindResendLoading.value = false
  }
}

async function handleUpdateDisplayName() {
  displayNameError.value = ''
  displayNameSuccess.value = false
  const target = String(displayNameInput.value || '').trim()
  if (!target) {
    displayNameError.value = '昵称不能为空'
    return
  }
  displayNameLoading.value = true
  try {
    await updateDisplayName(auth.sessionId, target)
    displayNameSuccess.value = true
    await auth.fetchUser()
    displayNameInput.value = auth.user?.display_name || target
  } catch (e: any) {
    displayNameError.value = e.response?.data?.detail || '修改昵称失败'
  } finally {
    displayNameLoading.value = false
  }
}

async function handleChangePassword() {
  error.value = ''
  success.value = false
  if (newPassword.value !== confirmPassword.value) {
    error.value = '两次输入的新密码不一致'
    return
  }
  if (!newPassword.value) {
    error.value = '新密码不能为空'
    return
  }
  loading.value = true
  try {
    await changePassword(auth.sessionId, oldPassword.value, newPassword.value)
    success.value = true
    oldPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
  } catch (e: any) {
    error.value = e.response?.data?.detail || '修改失败'
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.page-header {
  margin-bottom: 20px;
}
.page-title {
  margin: 0 0 8px;
  font-size: 20px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}
.page-title-line {
  height: 2px;
  background: var(--fcm-accent-line);
  max-width: 120px;
}
.poster-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
  padding: 20px 24px;
  box-shadow: var(--fcm-shadow-card);
}
.poster-card__title {
  margin: 0 0 16px;
  font-size: 16px;
  font-weight: 500;
  color: var(--fcm-text-primary);
  padding-bottom: 8px;
  border-bottom: 1px solid var(--fcm-accent-line);
}
.poster-card__hint {
  font-size: 13px;
  color: var(--fcm-text-muted);
  margin: 0 0 16px;
}
</style>
