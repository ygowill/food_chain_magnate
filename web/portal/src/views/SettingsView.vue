<template>
  <AppLayout>
    <div class="page-header">
      <h2 class="page-title">
        <svg class="page-title__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.241-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.991l1.004.827c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.991l-1.004-.827a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"/><path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
        账号设置
      </h2>
      <div class="page-title-line" />
    </div>

    <div class="settings-layout">
      <nav class="settings-nav">
        <button
          v-for="tab in tabs"
          :key="tab.key"
          class="settings-nav__item"
          :class="{ 'settings-nav__item--active': activeTab === tab.key }"
          @click="activeTab = tab.key"
        >
          {{ tab.label }}
        </button>
      </nav>

      <div class="settings-content">
        <!-- Account Info -->
        <div v-if="activeTab === 'info'" class="settings-card">
          <h3 class="settings-card__title">账号信息</h3>
          <el-descriptions :column="1" border v-if="auth.user">
            <el-descriptions-item label="昵称">{{ auth.user.display_name || '-' }}</el-descriptions-item>
            <el-descriptions-item label="用户 ID">
              <code class="mono-text">{{ auth.user.user_id }}</code>
            </el-descriptions-item>
            <el-descriptions-item label="邮箱">{{ auth.user.email || '未绑定' }}</el-descriptions-item>
            <el-descriptions-item label="邮箱状态">{{ emailStatusText }}</el-descriptions-item>
            <el-descriptions-item label="账号类型">
              <span class="account-type" :class="auth.user.is_guest ? 'account-type--guest' : 'account-type--full'">
                {{ auth.user.is_guest ? '游客' : '正式' }}
              </span>
            </el-descriptions-item>
            <el-descriptions-item label="注册时间">
              {{ new Date(auth.user.created_at).toLocaleString('zh-CN') }}
            </el-descriptions-item>
          </el-descriptions>
        </div>

        <!-- Display Name -->
        <div v-if="activeTab === 'display_name' && auth.user && !auth.user.is_guest" class="settings-card">
          <h3 class="settings-card__title">昵称设置</h3>
          <p class="settings-card__hint">联机昵称与账号绑定。修改后，游戏客户端将自动使用该昵称。</p>
          <el-form @submit.prevent="handleUpdateDisplayName" :disabled="displayNameLoading" class="settings-form">
            <el-form-item label="昵称">
              <el-input v-model="displayNameInput" maxlength="24" show-word-limit placeholder="请输入昵称（最多24字）" size="large" />
            </el-form-item>
            <el-alert v-if="displayNameError" :title="displayNameError" type="error" :closable="false" style="margin-bottom: 16px" />
            <el-alert v-if="displayNameSuccess" title="昵称修改成功" type="success" :closable="false" style="margin-bottom: 16px" />
            <el-form-item>
              <el-button type="primary" native-type="submit" :loading="displayNameLoading">保存昵称</el-button>
            </el-form-item>
          </el-form>
        </div>

        <!-- Bind Email (Guest) -->
        <div v-if="activeTab === 'bind_email' && auth.user && auth.user.is_guest" class="settings-card">
          <h3 class="settings-card__title">绑定邮箱</h3>
          <p class="settings-card__hint">绑定邮箱后可使用邮箱登录，游戏数据将保留。</p>
          <el-form @submit.prevent="handleBind" :disabled="bindLoading" class="settings-form">
            <el-form-item label="邮箱">
              <el-input v-model="bindEmail" placeholder="请输入邮箱" size="large" />
            </el-form-item>
            <el-form-item label="设置密码">
              <el-input v-model="bindPassword" type="password" placeholder="请输入密码" show-password size="large" />
            </el-form-item>
            <el-form-item label="确认密码">
              <el-input v-model="bindConfirm" type="password" placeholder="请再次输入密码" show-password size="large" />
            </el-form-item>
            <el-alert v-if="bindError" :title="bindError" type="error" :closable="false" style="margin-bottom: 16px" />
            <el-alert v-if="bindSuccess" title="绑定成功，账号已升级" type="success" :closable="false" style="margin-bottom: 16px" />
            <el-form-item>
              <el-button type="primary" native-type="submit" :loading="bindLoading">绑定邮箱</el-button>
            </el-form-item>
          </el-form>
        </div>

        <!-- Update Email -->
        <div v-if="activeTab === 'email' && auth.user && !auth.user.is_guest" class="settings-card">
          <h3 class="settings-card__title">修改邮箱</h3>
          <p class="settings-card__hint">修改后，后续请使用新邮箱登录。</p>
          <el-form @submit.prevent="handleUpdateEmail" :disabled="emailLoading" class="settings-form">
            <el-form-item label="新邮箱">
              <el-input v-model="emailInput" placeholder="请输入新邮箱" size="large" />
            </el-form-item>
            <el-form-item label="当前密码">
              <el-input v-model="emailPassword" type="password" show-password placeholder="请输入当前密码" size="large" />
            </el-form-item>
            <el-alert v-if="emailError" :title="emailError" type="error" :closable="false" style="margin-bottom: 16px" />
            <el-alert v-if="emailSuccess" title="邮箱修改成功" type="success" :closable="false" style="margin-bottom: 16px" />
            <el-form-item>
              <el-button type="primary" native-type="submit" :loading="emailLoading">保存邮箱</el-button>
            </el-form-item>
          </el-form>
        </div>

        <!-- Change Password -->
        <div v-if="activeTab === 'password' && auth.user && !auth.user.is_guest" class="settings-card">
          <h3 class="settings-card__title">修改密码</h3>
          <el-form @submit.prevent="handleChangePassword" :disabled="loading" class="settings-form">
            <el-form-item label="旧密码">
              <el-input v-model="oldPassword" type="password" show-password size="large" />
            </el-form-item>
            <el-form-item label="新密码">
              <el-input v-model="newPassword" type="password" show-password size="large" />
            </el-form-item>
            <el-form-item label="确认新密码">
              <el-input v-model="confirmPassword" type="password" show-password size="large" />
            </el-form-item>
            <el-alert v-if="error" :title="error" type="error" :closable="false" style="margin-bottom: 16px" />
            <el-alert v-if="success" title="密码修改成功" type="success" :closable="false" style="margin-bottom: 16px" />
            <el-form-item>
              <el-button type="primary" native-type="submit" :loading="loading">修改密码</el-button>
            </el-form-item>
          </el-form>
        </div>
      </div>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useAuthStore } from '../stores/auth'
import {
  changePassword,
  bindEmail as apiBindEmail,
  updateEmail,
  updateDisplayName,
} from '../api/auth'
import AppLayout from '../components/AppLayout.vue'

const auth = useAuthStore()
const activeTab = ref('info')

const tabs = computed(() => {
  const list = [{ key: 'info', label: '账号信息' }]
  if (auth.user && !auth.user.is_guest) {
    list.push({ key: 'display_name', label: '昵称设置' })
    list.push({ key: 'email', label: '修改邮箱' })
    list.push({ key: 'password', label: '修改密码' })
  } else if (auth.user?.is_guest) {
    list.push({ key: 'bind_email', label: '绑定邮箱' })
  }
  return list
})

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
const emailInput = ref('')
const emailPassword = ref('')
const emailError = ref('')
const emailSuccess = ref(false)
const emailLoading = ref(false)
const displayNameInput = ref('')
const displayNameError = ref('')
const displayNameSuccess = ref(false)
const displayNameLoading = ref(false)
const emailStatusText = computed(() => {
  const currentUser = auth.user
  if (!currentUser) return '-'
  if (!currentUser.email) return '未绑定'
  return '已绑定'
})

onMounted(async () => {
  await auth.fetchUser()
  displayNameInput.value = auth.user?.display_name || ''
  bindEmail.value = auth.user?.email || ''
  emailInput.value = auth.user?.email || ''
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
    await apiBindEmail(auth.sessionId, bindEmail.value, bindPassword.value)
    bindSuccess.value = true
    await auth.fetchUser()
    bindEmail.value = auth.user?.email || ''
    displayNameInput.value = auth.user?.display_name || ''
  } catch (e: any) {
    bindError.value = e.response?.data?.detail || '绑定失败'
  } finally {
    bindLoading.value = false
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

async function handleUpdateEmail() {
  emailError.value = ''
  emailSuccess.value = false
  if (!emailInput.value.trim()) {
    emailError.value = '邮箱不能为空'
    return
  }
  if (!emailPassword.value) {
    emailError.value = '请输入当前密码'
    return
  }
  emailLoading.value = true
  try {
    await updateEmail(auth.sessionId, emailInput.value, emailPassword.value)
    emailSuccess.value = true
    emailPassword.value = ''
    await auth.fetchUser()
    emailInput.value = auth.user?.email || emailInput.value
  } catch (e: any) {
    emailError.value = e.response?.data?.detail || '邮箱修改失败'
  } finally {
    emailLoading.value = false
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
  margin-bottom: 24px;
}

.page-title {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 0 8px;
  font-size: 22px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.page-title__icon {
  width: 24px;
  height: 24px;
  color: var(--fcm-gold);
}

.page-title-line {
  height: 2px;
  background: linear-gradient(90deg, var(--fcm-gold), transparent);
  max-width: 200px;
}

.settings-layout {
  display: grid;
  grid-template-columns: 200px 1fr;
  gap: 24px;
  max-width: 800px;
}

.settings-nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
  position: sticky;
  top: 96px;
  align-self: start;
}

.settings-nav__item {
  display: block;
  width: 100%;
  padding: 10px 16px;
  font-size: 14px;
  font-weight: 500;
  font-family: var(--fcm-font-body);
  color: var(--fcm-text-muted);
  text-align: left;
  background: none;
  border: none;
  border-radius: var(--fcm-radius);
  cursor: pointer;
  transition: all 0.15s;
  border-left: 3px solid transparent;
}

.settings-nav__item:hover {
  color: var(--fcm-text-primary);
  background: var(--fcm-primary-light);
}

.settings-nav__item--active {
  color: var(--fcm-text-primary);
  background: var(--fcm-surface);
  border-left-color: var(--fcm-gold);
  font-weight: 600;
  box-shadow: var(--fcm-shadow-card);
}

.settings-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius-lg);
  padding: 24px 28px;
  box-shadow: var(--fcm-shadow-card);
}

.settings-card__title {
  margin: 0 0 16px;
  font-size: 17px;
  font-weight: 600;
  color: var(--fcm-text-primary);
  padding-bottom: 12px;
  border-bottom: 1px solid var(--fcm-gold-line);
}

.settings-card__hint {
  font-size: 13px;
  color: var(--fcm-text-muted);
  margin: 0 0 20px;
  line-height: 1.6;
}

.settings-form {
  max-width: 400px;
}

.mono-text {
  font-family: monospace;
  font-size: 12px;
  background: rgba(43, 33, 23, 0.06);
  padding: 2px 6px;
  border-radius: 3px;
}

.account-type {
  font-size: 13px;
  font-weight: 500;
  padding: 2px 10px;
  border-radius: 999px;
}

.account-type--guest {
  color: var(--fcm-gold);
  background: var(--fcm-gold-light);
}

.account-type--full {
  color: var(--fcm-text-success);
  background: rgba(71, 140, 56, 0.1);
}
</style>
