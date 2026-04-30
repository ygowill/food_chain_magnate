<template>
  <AppLayout>
    <div class="page-header">
      <h2 class="page-title">管理后台</h2>
      <div class="page-title-line" />
    </div>

    <el-alert
      v-if="errorMessage"
      :title="errorMessage"
      type="error"
      :closable="false"
      class="error-alert"
    />

    <div class="poster-card">
      <el-tabs v-model="activeTab" @tab-change="handleTabChange">
        <el-tab-pane label="用户管理" name="users">
          <div class="toolbar">
            <el-input
              v-model="userQuery"
              placeholder="按用户ID/昵称/邮箱筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshUsers"
            />
            <el-select v-model="userStatusFilter" placeholder="状态筛选" clearable class="toolbar-select">
              <el-option label="active" value="active" />
              <el-option label="disabled" value="disabled" />
              <el-option label="banned" value="banned" />
            </el-select>
            <el-select v-model="bulkUserStatus" placeholder="批量改状态" class="toolbar-select">
              <el-option label="active" value="active" />
              <el-option label="disabled" value="disabled" />
              <el-option label="banned" value="banned" />
            </el-select>
            <el-button type="primary" @click="refreshUsers">刷新</el-button>
            <el-button :disabled="loadingUsers || users.length === 0" @click="selectUsersOnCurrentPage">当前页全选</el-button>
            <el-button :loading="selectingAllUsers" :disabled="loadingUsers" @click="selectAllFilteredUsers">跨页全选</el-button>
            <el-button text :disabled="selectedUserIds.length === 0" @click="clearUserSelection">清空选择</el-button>
            <span class="selection-count">已选 {{ selectedUserIds.length }}</span>
            <el-button
              :disabled="selectedUserIds.length === 0 || !bulkUserStatus"
              @click="handleBatchUpdateUserStatus"
            >
              批量改状态
            </el-button>
            <el-button
              type="danger"
              plain
              :disabled="selectedUserIds.length === 0"
              @click="handleBatchDeleteUsers"
            >
              批量删除用户
            </el-button>
          </div>
          <el-table
            ref="usersTableRef"
            :data="users"
            v-loading="loadingUsers"
            class="fcm-table"
            @selection-change="onUserSelectionChange"
          >
            <el-table-column type="selection" width="48" />
            <el-table-column prop="user_id" label="用户ID" min-width="240" />
            <el-table-column prop="display_name" label="昵称" min-width="140">
              <template #default="{ row }">{{ row.display_name || '-' }}</template>
            </el-table-column>
            <el-table-column prop="email" label="邮箱" min-width="220">
              <template #default="{ row }">{{ row.email || '-' }}</template>
            </el-table-column>
            <el-table-column label="类型" width="100">
              <template #default="{ row }">{{ row.is_guest ? '游客' : '正式' }}</template>
            </el-table-column>
            <el-table-column prop="active_sessions" label="在线会话" width="100" />
            <el-table-column prop="room_count" label="房间数" width="90" />
            <el-table-column prop="match_count" label="对局数" width="90" />
            <el-table-column label="状态" width="220">
              <template #default="{ row }">
                <div class="inline-row">
                  <el-select v-model="userStatusDraft[row.user_id]" size="small" class="status-select">
                    <el-option label="active" value="active" />
                    <el-option label="disabled" value="disabled" />
                    <el-option label="banned" value="banned" />
                  </el-select>
                  <el-button
                    size="small"
                    @click="saveUserStatus(row)"
                    :disabled="userStatusDraft[row.user_id] === row.status"
                  >
                    保存
                  </el-button>
                </div>
              </template>
            </el-table-column>
            <el-table-column label="创建时间" min-width="180">
              <template #default="{ row }">{{ formatTime(row.created_at) }}</template>
            </el-table-column>
            <el-table-column label="操作" width="90">
              <template #default="{ row }">
                <el-button size="small" @click="openUserDetail(row)">详情</el-button>
              </template>
            </el-table-column>
          </el-table>
          <div class="pager">
            <el-pagination
              background
              layout="total, prev, pager, next, jumper"
              :total="usersTotal"
              :page-size="PAGE_SIZE"
              :current-page="usersPage"
              @current-change="handleUsersPageChange"
            />
          </div>
        </el-tab-pane>

        <el-tab-pane label="房间管理" name="rooms">
          <div class="toolbar">
            <el-input
              v-model="roomCodeFilter"
              placeholder="按房间号筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshRooms"
            />
            <el-select v-model="roomStatusFilter" placeholder="状态筛选" clearable class="toolbar-select">
              <el-option label="Pending" value="Pending" />
              <el-option label="Lobby" value="Lobby" />
              <el-option label="Starting" value="Starting" />
              <el-option label="InGame" value="InGame" />
              <el-option label="Ended" value="Ended" />
            </el-select>
            <el-input
              v-model="roomOwnerFilter"
              placeholder="按房主用户ID筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshRooms"
            />
            <el-input
              v-model="roomGameServerFilter"
              placeholder="按服务器ID筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshRooms"
            />
            <el-button type="primary" @click="refreshRooms">刷新</el-button>
            <el-button :disabled="loadingRooms || rooms.length === 0" @click="selectRoomsOnCurrentPage">当前页全选</el-button>
            <el-button :loading="selectingAllRooms" :disabled="loadingRooms" @click="selectAllFilteredRooms">跨页全选</el-button>
            <el-button text :disabled="selectedRoomCodes.length === 0" @click="clearRoomSelection">清空选择</el-button>
            <span class="selection-count">已选 {{ selectedRoomCodes.length }}</span>
            <el-button
              :disabled="selectedRoomCodes.length === 0"
              @click="handleBatchEndRooms"
            >
              批量结束
            </el-button>
            <el-button
              type="danger"
              plain
              :disabled="selectedRoomCodes.length === 0"
              @click="handleBatchDeleteRooms"
            >
              批量删除房间
            </el-button>
          </div>
          <el-table
            ref="roomsTableRef"
            :data="rooms"
            v-loading="loadingRooms"
            class="fcm-table"
            @selection-change="onRoomSelectionChange"
          >
            <el-table-column type="selection" width="48" />
            <el-table-column prop="room_code" label="房间号" width="120" />
            <el-table-column prop="status" label="状态" width="100" />
            <el-table-column prop="owner_user_id" label="房主用户ID" min-width="220" />
            <el-table-column label="服务器" min-width="220">
              <template #default="{ row }">
                <div class="server-cell">
                  <span>{{ row.game_server_id || '-' }}</span>
                  <el-tag size="small" :type="roomServerTagType(row)">
                    {{ row.game_server_id ? (row.server_online ? '在线' : '离线') : '未分配' }}
                  </el-tag>
                </div>
              </template>
            </el-table-column>
            <el-table-column label="最后心跳" min-width="180">
              <template #default="{ row }">{{ formatTime(row.server_last_heartbeat_at) }}</template>
            </el-table-column>
            <el-table-column prop="join_policy" label="加入策略" width="110" />
            <el-table-column prop="player_count" label="玩家数" width="90" />
            <el-table-column prop="spectator_count" label="观战数" width="90" />
            <el-table-column label="更新时间" min-width="180">
              <template #default="{ row }">{{ formatTime(row.updated_at) }}</template>
            </el-table-column>
            <el-table-column label="操作" width="120">
              <template #default="{ row }">
                <el-button
                  size="small"
                  type="danger"
                  plain
                  :disabled="row.status === 'Ended'"
                  @click="handleEndRoom(row)"
                >
                  结束房间
                </el-button>
              </template>
            </el-table-column>
          </el-table>
          <div class="pager">
            <el-pagination
              background
              layout="total, prev, pager, next, jumper"
              :total="roomsTotal"
              :page-size="PAGE_SIZE"
              :current-page="roomsPage"
              @current-change="handleRoomsPageChange"
            />
          </div>
        </el-tab-pane>

        <el-tab-pane label="对局管理" name="matches">
          <div class="toolbar">
            <el-input
              v-model="matchRoomCodeFilter"
              placeholder="按房间号筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshMatches"
            />
            <el-input
              v-model="matchParticipantFilter"
              placeholder="按参与用户ID筛选"
              clearable
              class="toolbar-input"
              @keyup.enter="refreshMatches"
            />
            <el-select v-model="matchStatusFilter" placeholder="状态筛选" clearable class="toolbar-select">
              <el-option label="completed" value="completed" />
              <el-option label="in_progress" value="in_progress" />
              <el-option label="failed" value="failed" />
            </el-select>
            <el-select v-model="matchReplayFilter" placeholder="回放筛选" clearable class="toolbar-select">
              <el-option label="有回放" value="true" />
              <el-option label="无回放" value="false" />
            </el-select>
            <el-button type="primary" @click="refreshMatches">刷新</el-button>
            <el-button :disabled="loadingMatches || matches.length === 0" @click="selectMatchesOnCurrentPage">当前页全选</el-button>
            <el-button :loading="selectingAllMatches" :disabled="loadingMatches" @click="selectAllFilteredMatches">跨页全选</el-button>
            <el-button text :disabled="selectedMatchIds.length === 0" @click="clearMatchSelection">清空选择</el-button>
            <span class="selection-count">已选 {{ selectedMatchIds.length }}</span>
            <el-button
              type="danger"
              plain
              :disabled="selectedMatchIds.length === 0"
              @click="handleBatchDeleteMatches"
            >
              批量删除对局
            </el-button>
          </div>
          <el-table
            ref="matchesTableRef"
            :data="matches"
            v-loading="loadingMatches"
            class="fcm-table"
            @selection-change="onMatchSelectionChange"
          >
            <el-table-column type="selection" width="48" />
            <el-table-column prop="match_id" label="对局ID" min-width="240" />
            <el-table-column prop="room_code" label="房间号" width="120">
              <template #default="{ row }">{{ row.room_code || '-' }}</template>
            </el-table-column>
            <el-table-column prop="status" label="状态" width="110" />
            <el-table-column prop="player_count" label="玩家数" width="80" />
            <el-table-column prop="participant_count" label="参与人数" width="90" />
            <el-table-column label="回放" width="80">
              <template #default="{ row }">{{ row.has_replay ? '有' : '无' }}</template>
            </el-table-column>
            <el-table-column label="创建时间" min-width="180">
              <template #default="{ row }">{{ formatTime(row.created_at) }}</template>
            </el-table-column>
            <el-table-column label="操作" width="180">
              <template #default="{ row }">
                <div class="inline-row">
                  <el-button size="small" @click="router.push(`/matches/${row.match_id}`)">查看</el-button>
                  <el-button size="small" type="danger" plain @click="handleDeleteMatch(row)">删除</el-button>
                </div>
              </template>
            </el-table-column>
          </el-table>
          <div class="pager">
            <el-pagination
              background
              layout="total, prev, pager, next, jumper"
              :total="matchesTotal"
              :page-size="PAGE_SIZE"
              :current-page="matchesPage"
              @current-change="handleMatchesPageChange"
            />
          </div>
        </el-tab-pane>
      </el-tabs>
    </div>

    <el-drawer
      v-model="userDetailOpen"
      :title="userDetail?.user.display_name || userDetail?.user.user_id || '用户详情'"
      size="620px"
      destroy-on-close
    >
      <div v-loading="loadingUserDetail" class="detail-drawer">
        <template v-if="userDetail">
          <el-descriptions :column="1" border size="small">
            <el-descriptions-item label="用户ID">{{ userDetail.user.user_id }}</el-descriptions-item>
            <el-descriptions-item label="状态">{{ userDetail.user.status }}</el-descriptions-item>
            <el-descriptions-item label="邮箱">{{ userDetail.user.email || '-' }}</el-descriptions-item>
            <el-descriptions-item label="活跃会话">{{ userDetail.user.active_sessions }}</el-descriptions-item>
            <el-descriptions-item label="创建时间">{{ formatTime(userDetail.user.created_at) }}</el-descriptions-item>
          </el-descriptions>

          <h3 class="drawer-section-title">身份</h3>
          <el-table :data="userDetail.identities" size="small" class="fcm-table">
            <el-table-column prop="provider" label="Provider" width="110" />
            <el-table-column prop="provider_user_id" label="标识" min-width="220" />
            <el-table-column label="验证" width="80">
              <template #default="{ row }">{{ row.verified ? '是' : '否' }}</template>
            </el-table-column>
          </el-table>

          <h3 class="drawer-section-title">最近会话</h3>
          <el-table :data="userDetail.sessions" size="small" class="fcm-table">
            <el-table-column prop="session_id" label="Session" min-width="220" />
            <el-table-column label="状态" width="80">
              <template #default="{ row }">
                <el-tag size="small" :type="row.active ? 'success' : 'info'">{{ row.active ? '活跃' : '失效' }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column label="过期时间" min-width="160">
              <template #default="{ row }">{{ formatTime(row.expires_at) }}</template>
            </el-table-column>
          </el-table>

          <h3 class="drawer-section-title">最近房间</h3>
          <el-table :data="userDetail.recent_rooms" size="small" class="fcm-table">
            <el-table-column prop="room_code" label="房间" width="90" />
            <el-table-column prop="status" label="状态" width="90" />
            <el-table-column prop="game_server_id" label="服务器" min-width="140">
              <template #default="{ row }">{{ row.game_server_id || '-' }}</template>
            </el-table-column>
            <el-table-column label="人数" width="90">
              <template #default="{ row }">{{ row.player_count }} / {{ row.spectator_count }}</template>
            </el-table-column>
          </el-table>

          <h3 class="drawer-section-title">最近对局</h3>
          <el-table :data="userDetail.recent_matches" size="small" class="fcm-table">
            <el-table-column prop="match_id" label="对局ID" min-width="220" />
            <el-table-column prop="room_code" label="房间" width="90">
              <template #default="{ row }">{{ row.room_code || '-' }}</template>
            </el-table-column>
            <el-table-column prop="role" label="角色" width="90" />
            <el-table-column prop="result" label="结果" width="90">
              <template #default="{ row }">{{ row.result || '-' }}</template>
            </el-table-column>
          </el-table>
        </template>
      </div>
    </el-drawer>
  </AppLayout>
</template>

<script setup lang="ts">
import { nextTick, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'

import AppLayout from '../components/AppLayout.vue'
import { useAuthStore } from '../stores/auth'
import {
  batchDeleteAdminMatches,
  batchDeleteAdminRooms,
  batchDeleteAdminUsers,
  batchEndAdminRooms,
  batchUpdateAdminUsersStatus,
  deleteAdminMatch,
  endAdminRoom,
  getAdminUserDetail,
  listAdminMatches,
  listAdminRooms,
  listAdminUsers,
  updateAdminUserStatus,
  type BatchActionResult,
  type AdminMatchSummary,
  type AdminRoomSummary,
  type AdminUserDetail,
  type AdminUserSummary,
} from '../api/admin'

type AdminTab = 'users' | 'rooms' | 'matches'
type SelectTableRef = {
  clearSelection: () => void
  toggleRowSelection: (row: unknown, selected?: boolean) => void
}

const PAGE_SIZE = 20
const CROSS_PAGE_SELECT_SIZE = 200

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const activeTab = ref<AdminTab>('users')
const errorMessage = ref('')

const users = ref<AdminUserSummary[]>([])
const loadingUsers = ref(false)
const userQuery = ref('')
const userStatusFilter = ref<string>('')
const bulkUserStatus = ref<string>('disabled')
const userStatusDraft = ref<Record<string, string>>({})
const selectedUserIds = ref<string[]>([])
const usersTableRef = ref<SelectTableRef | null>(null)
const selectingAllUsers = ref(false)
const usersPage = ref(1)
const usersHasNext = ref(false)
const usersTotal = ref(0)
const userDetailOpen = ref(false)
const loadingUserDetail = ref(false)
const userDetail = ref<AdminUserDetail | null>(null)

const rooms = ref<AdminRoomSummary[]>([])
const loadingRooms = ref(false)
const roomCodeFilter = ref('')
const roomStatusFilter = ref<string>('')
const roomOwnerFilter = ref('')
const roomGameServerFilter = ref('')
const selectedRoomCodes = ref<string[]>([])
const roomsTableRef = ref<SelectTableRef | null>(null)
const selectingAllRooms = ref(false)
const roomsPage = ref(1)
const roomsHasNext = ref(false)
const roomsTotal = ref(0)

const matches = ref<AdminMatchSummary[]>([])
const loadingMatches = ref(false)
const matchRoomCodeFilter = ref('')
const matchParticipantFilter = ref('')
const matchStatusFilter = ref<string>('')
const matchReplayFilter = ref<string>('')
const selectedMatchIds = ref<string[]>([])
const matchesTableRef = ref<SelectTableRef | null>(null)
const selectingAllMatches = ref(false)
const matchesPage = ref(1)
const matchesHasNext = ref(false)
const matchesTotal = ref(0)

function resolveErrorMessage(error: any, fallback: string): string {
  const detail = error?.response?.data?.detail
  if (typeof detail === 'string' && detail.trim()) {
    return detail
  }
  return fallback
}

function formatTime(value: string | null | undefined): string {
  if (!value) return '-'
  return new Date(value).toLocaleString('zh-CN')
}

function parseMatchReplayFilter(): boolean | undefined {
  if (matchReplayFilter.value === 'true') return true
  if (matchReplayFilter.value === 'false') return false
  return undefined
}

function roomServerTagType(room: AdminRoomSummary): 'success' | 'warning' | 'info' {
  if (!room.game_server_id) return 'info'
  return room.server_online ? 'success' : 'warning'
}

function summarizeBatchResult(prefix: string, result: BatchActionResult): string {
  const requested = Number(result.requested || 0)
  const affected = Number(result.affected || 0)
  const missing = Array.isArray(result.missing) ? result.missing.length : 0
  if (missing > 0) {
    return `${prefix}：处理 ${affected}/${requested}，缺失 ${missing}`
  }
  return `${prefix}：处理 ${affected}/${requested}`
}

function mergeCurrentPageSelection(allSelected: string[], currentPageIds: string[], checkedIds: string[]): string[] {
  const nextSelected = new Set(allSelected)
  for (const id of currentPageIds) {
    nextSelected.delete(id)
  }
  for (const id of checkedIds) {
    nextSelected.add(id)
  }
  return [...nextSelected]
}

async function applyUserSelectionToTable() {
  await nextTick()
  const table = usersTableRef.value
  if (!table) return
  table.clearSelection()
  const selected = new Set(selectedUserIds.value)
  for (const row of users.value) {
    if (selected.has(row.user_id)) {
      table.toggleRowSelection(row, true)
    }
  }
}

async function applyRoomSelectionToTable() {
  await nextTick()
  const table = roomsTableRef.value
  if (!table) return
  table.clearSelection()
  const selected = new Set(selectedRoomCodes.value)
  for (const row of rooms.value) {
    if (selected.has(row.room_code)) {
      table.toggleRowSelection(row, true)
    }
  }
}

async function applyMatchSelectionToTable() {
  await nextTick()
  const table = matchesTableRef.value
  if (!table) return
  table.clearSelection()
  const selected = new Set(selectedMatchIds.value)
  for (const row of matches.value) {
    if (selected.has(row.match_id)) {
      table.toggleRowSelection(row, true)
    }
  }
}

function clearUserSelection() {
  selectedUserIds.value = []
  usersTableRef.value?.clearSelection()
}

function clearRoomSelection() {
  selectedRoomCodes.value = []
  roomsTableRef.value?.clearSelection()
}

function clearMatchSelection() {
  selectedMatchIds.value = []
  matchesTableRef.value?.clearSelection()
}

function onUserSelectionChange(rows: AdminUserSummary[]) {
  selectedUserIds.value = mergeCurrentPageSelection(
    selectedUserIds.value,
    users.value.map(row => row.user_id),
    rows.map(row => row.user_id),
  )
}

function onRoomSelectionChange(rows: AdminRoomSummary[]) {
  selectedRoomCodes.value = mergeCurrentPageSelection(
    selectedRoomCodes.value,
    rooms.value.map(row => row.room_code),
    rows.map(row => row.room_code),
  )
}

function onMatchSelectionChange(rows: AdminMatchSummary[]) {
  selectedMatchIds.value = mergeCurrentPageSelection(
    selectedMatchIds.value,
    matches.value.map(row => row.match_id),
    rows.map(row => row.match_id),
  )
}

function selectUsersOnCurrentPage() {
  selectedUserIds.value = [...new Set([...selectedUserIds.value, ...users.value.map(row => row.user_id)])]
  void applyUserSelectionToTable()
}

function selectRoomsOnCurrentPage() {
  selectedRoomCodes.value = [...new Set([...selectedRoomCodes.value, ...rooms.value.map(row => row.room_code)])]
  void applyRoomSelectionToTable()
}

function selectMatchesOnCurrentPage() {
  selectedMatchIds.value = [...new Set([...selectedMatchIds.value, ...matches.value.map(row => row.match_id)])]
  void applyMatchSelectionToTable()
}

async function selectAllFilteredUsers() {
  selectingAllUsers.value = true
  try {
    let offset = 0
    const selected = new Set<string>()
    while (true) {
      const { data } = await listAdminUsers(auth.sessionId, {
        query: userQuery.value.trim() || undefined,
        status: userStatusFilter.value.trim() || undefined,
        limit: CROSS_PAGE_SELECT_SIZE,
        offset,
      })
      for (const user of data.items) {
        selected.add(user.user_id)
      }
      if (data.items.length < CROSS_PAGE_SELECT_SIZE) {
        break
      }
      offset += data.items.length
    }
    selectedUserIds.value = [...selected]
    await applyUserSelectionToTable()
    ElMessage.success(`已跨页选中 ${selectedUserIds.value.length} 个用户`)
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '跨页全选用户失败'))
  } finally {
    selectingAllUsers.value = false
  }
}

async function selectAllFilteredRooms() {
  selectingAllRooms.value = true
  try {
    let offset = 0
    const selected = new Set<string>()
    while (true) {
      const { data } = await listAdminRooms(auth.sessionId, {
        room_code: roomCodeFilter.value.trim() || undefined,
        status: roomStatusFilter.value.trim() || undefined,
        owner_user_id: roomOwnerFilter.value.trim() || undefined,
        game_server_id: roomGameServerFilter.value.trim() || undefined,
        limit: CROSS_PAGE_SELECT_SIZE,
        offset,
      })
      for (const room of data.items) {
        selected.add(room.room_code)
      }
      if (data.items.length < CROSS_PAGE_SELECT_SIZE) {
        break
      }
      offset += data.items.length
    }
    selectedRoomCodes.value = [...selected]
    await applyRoomSelectionToTable()
    ElMessage.success(`已跨页选中 ${selectedRoomCodes.value.length} 个房间`)
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '跨页全选房间失败'))
  } finally {
    selectingAllRooms.value = false
  }
}

async function selectAllFilteredMatches() {
  selectingAllMatches.value = true
  try {
    let offset = 0
    const selected = new Set<string>()
    while (true) {
      const { data } = await listAdminMatches(auth.sessionId, {
        room_code: matchRoomCodeFilter.value.trim() || undefined,
        participant_user_id: matchParticipantFilter.value.trim() || undefined,
        status: matchStatusFilter.value.trim() || undefined,
        has_replay: parseMatchReplayFilter(),
        limit: CROSS_PAGE_SELECT_SIZE,
        offset,
      })
      for (const match of data.items) {
        selected.add(match.match_id)
      }
      if (data.items.length < CROSS_PAGE_SELECT_SIZE) {
        break
      }
      offset += data.items.length
    }
    selectedMatchIds.value = [...selected]
    await applyMatchSelectionToTable()
    ElMessage.success(`已跨页选中 ${selectedMatchIds.value.length} 个对局`)
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '跨页全选对局失败'))
  } finally {
    selectingAllMatches.value = false
  }
}

function normalizePage(value: unknown): number {
  const page = Number.parseInt(String(value ?? ''), 10)
  if (!Number.isFinite(page) || page <= 0) {
    return 1
  }
  return page
}

function loadStateFromRouteQuery() {
  const tabValue = String(route.query.tab ?? '')
  if (tabValue === 'users' || tabValue === 'rooms' || tabValue === 'matches') {
    activeTab.value = tabValue
  }

  userQuery.value = String(route.query.u_q ?? '')
  userStatusFilter.value = String(route.query.u_status ?? '')
  usersPage.value = normalizePage(route.query.u_page)

  roomCodeFilter.value = String(route.query.r_code ?? '')
  roomStatusFilter.value = String(route.query.r_status ?? '')
  roomOwnerFilter.value = String(route.query.r_owner ?? '')
  roomGameServerFilter.value = String(route.query.r_server ?? '')
  roomsPage.value = normalizePage(route.query.r_page)

  matchRoomCodeFilter.value = String(route.query.m_code ?? '')
  matchParticipantFilter.value = String(route.query.m_user ?? '')
  matchStatusFilter.value = String(route.query.m_status ?? '')
  matchReplayFilter.value = String(route.query.m_replay ?? '')
  matchesPage.value = normalizePage(route.query.m_page)
}

function syncRouteQuery() {
  const query: Record<string, string> = {
    tab: activeTab.value,
    u_page: String(usersPage.value),
    r_page: String(roomsPage.value),
    m_page: String(matchesPage.value),
  }
  if (userQuery.value.trim()) query.u_q = userQuery.value.trim()
  if (userStatusFilter.value.trim()) query.u_status = userStatusFilter.value.trim()
  if (roomCodeFilter.value.trim()) query.r_code = roomCodeFilter.value.trim()
  if (roomStatusFilter.value.trim()) query.r_status = roomStatusFilter.value.trim()
  if (roomOwnerFilter.value.trim()) query.r_owner = roomOwnerFilter.value.trim()
  if (roomGameServerFilter.value.trim()) query.r_server = roomGameServerFilter.value.trim()
  if (matchRoomCodeFilter.value.trim()) query.m_code = matchRoomCodeFilter.value.trim()
  if (matchParticipantFilter.value.trim()) query.m_user = matchParticipantFilter.value.trim()
  if (matchStatusFilter.value.trim()) query.m_status = matchStatusFilter.value.trim()
  if (matchReplayFilter.value.trim()) query.m_replay = matchReplayFilter.value.trim()
  void router.replace({ query })
}

async function loadUsers(options: { page?: number; syncQuery?: boolean } = {}) {
  if (options.page != null) {
    usersPage.value = Math.max(1, options.page)
  }
  loadingUsers.value = true
  errorMessage.value = ''
  try {
    const { data } = await listAdminUsers(auth.sessionId, {
      query: userQuery.value.trim() || undefined,
      status: userStatusFilter.value.trim() || undefined,
      limit: PAGE_SIZE,
      offset: (usersPage.value - 1) * PAGE_SIZE,
    })
    users.value = data.items
    usersTotal.value = data.total
    usersHasNext.value = (usersPage.value * PAGE_SIZE) < data.total
    const draft: Record<string, string> = {}
    for (const user of data.items) {
      draft[user.user_id] = user.status
    }
    userStatusDraft.value = draft
    await applyUserSelectionToTable()
  } catch (error: any) {
    users.value = []
    usersHasNext.value = false
    usersTotal.value = 0
    usersTableRef.value?.clearSelection()
    errorMessage.value = resolveErrorMessage(error, '加载用户数据失败')
  } finally {
    loadingUsers.value = false
  }
  if (options.syncQuery !== false) {
    syncRouteQuery()
  }
}

function handleUsersPageChange(page: number) {
  void loadUsers({ page })
}

async function saveUserStatus(user: AdminUserSummary) {
  const nextStatus = userStatusDraft.value[user.user_id]
  if (!nextStatus || nextStatus === user.status) return
  try {
    await updateAdminUserStatus(auth.sessionId, user.user_id, nextStatus)
    ElMessage.success('用户状态已更新')
    await loadUsers()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '更新用户状态失败'))
  }
}

async function openUserDetail(user: AdminUserSummary) {
  userDetailOpen.value = true
  loadingUserDetail.value = true
  userDetail.value = null
  try {
    const { data } = await getAdminUserDetail(auth.sessionId, user.user_id)
    userDetail.value = data
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '加载用户详情失败'))
    userDetailOpen.value = false
  } finally {
    loadingUserDetail.value = false
  }
}

async function handleBatchUpdateUserStatus() {
  const userIds = [...selectedUserIds.value]
  const status = bulkUserStatus.value.trim()
  if (userIds.length === 0 || !status) return
  try {
    await ElMessageBox.confirm(
      `确认将 ${userIds.length} 个用户状态批量改为 ${status}？`,
      '确认批量操作',
      {
        type: 'warning',
        confirmButtonText: '确认',
        cancelButtonText: '取消',
      },
    )
  } catch {
    return
  }
  try {
    const { data } = await batchUpdateAdminUsersStatus(auth.sessionId, userIds, status)
    ElMessage.success(summarizeBatchResult('批量改状态完成', data))
    clearUserSelection()
    await loadUsers()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '批量改状态失败'))
  }
}

async function handleBatchDeleteUsers() {
  const userIds = [...selectedUserIds.value]
  if (userIds.length === 0) return
  try {
    await ElMessageBox.confirm(
      `确认批量删除 ${userIds.length} 个用户？会同时清理其会话/身份/拥有房间，并删除可能的孤儿对局。`,
      '确认批量删除用户',
      {
        type: 'warning',
        confirmButtonText: '删除',
        cancelButtonText: '取消',
      },
    )
  } catch {
    return
  }
  try {
    const { data } = await batchDeleteAdminUsers(auth.sessionId, userIds)
    const extra = Number(data.meta?.deleted_rooms ?? 0) + Number(data.meta?.deleted_orphan_matches ?? 0)
    const message = summarizeBatchResult('批量删除用户完成', data)
    if (extra > 0) {
      ElMessage.success(`${message}，附带清理 ${extra} 条关联数据`)
    } else {
      ElMessage.success(message)
    }
    clearUserSelection()
    clearRoomSelection()
    clearMatchSelection()
    await loadUsers()
    await loadRooms({ page: 1 })
    await loadMatches({ page: 1 })
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '批量删除用户失败'))
  }
}

async function loadRooms(options: { page?: number; syncQuery?: boolean } = {}) {
  if (options.page != null) {
    roomsPage.value = Math.max(1, options.page)
  }
  loadingRooms.value = true
  errorMessage.value = ''
  try {
    const { data } = await listAdminRooms(auth.sessionId, {
      room_code: roomCodeFilter.value.trim() || undefined,
      status: roomStatusFilter.value.trim() || undefined,
      owner_user_id: roomOwnerFilter.value.trim() || undefined,
      game_server_id: roomGameServerFilter.value.trim() || undefined,
      limit: PAGE_SIZE,
      offset: (roomsPage.value - 1) * PAGE_SIZE,
    })
    rooms.value = data.items
    roomsTotal.value = data.total
    roomsHasNext.value = (roomsPage.value * PAGE_SIZE) < data.total
    await applyRoomSelectionToTable()
  } catch (error: any) {
    rooms.value = []
    roomsHasNext.value = false
    roomsTotal.value = 0
    roomsTableRef.value?.clearSelection()
    errorMessage.value = resolveErrorMessage(error, '加载房间数据失败')
  } finally {
    loadingRooms.value = false
  }
  if (options.syncQuery !== false) {
    syncRouteQuery()
  }
}

function handleRoomsPageChange(page: number) {
  void loadRooms({ page })
}

async function handleEndRoom(room: AdminRoomSummary) {
  try {
    await ElMessageBox.confirm(`确认结束房间 ${room.room_code}？`, '确认操作', {
      type: 'warning',
      confirmButtonText: '结束',
      cancelButtonText: '取消',
    })
  } catch {
    return
  }
  try {
    await endAdminRoom(auth.sessionId, room.room_code)
    ElMessage.success('房间已结束')
    await loadRooms()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '结束房间失败'))
  }
}

async function handleBatchEndRooms() {
  const roomCodes = [...selectedRoomCodes.value]
  if (roomCodes.length === 0) return
  try {
    await ElMessageBox.confirm(`确认批量结束 ${roomCodes.length} 个房间？`, '确认批量操作', {
      type: 'warning',
      confirmButtonText: '结束',
      cancelButtonText: '取消',
    })
  } catch {
    return
  }
  try {
    const { data } = await batchEndAdminRooms(auth.sessionId, roomCodes)
    ElMessage.success(summarizeBatchResult('批量结束房间完成', data))
    clearRoomSelection()
    await loadRooms()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '批量结束房间失败'))
  }
}

async function handleBatchDeleteRooms() {
  const roomCodes = [...selectedRoomCodes.value]
  if (roomCodes.length === 0) return
  try {
    await ElMessageBox.confirm(`确认批量删除 ${roomCodes.length} 个房间？此操作不可撤销。`, '确认批量删除房间', {
      type: 'warning',
      confirmButtonText: '删除',
      cancelButtonText: '取消',
    })
  } catch {
    return
  }
  try {
    const { data } = await batchDeleteAdminRooms(auth.sessionId, roomCodes)
    ElMessage.success(summarizeBatchResult('批量删除房间完成', data))
    clearRoomSelection()
    await loadRooms()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '批量删除房间失败'))
  }
}

async function loadMatches(options: { page?: number; syncQuery?: boolean } = {}) {
  if (options.page != null) {
    matchesPage.value = Math.max(1, options.page)
  }
  loadingMatches.value = true
  errorMessage.value = ''
  try {
    const { data } = await listAdminMatches(auth.sessionId, {
      room_code: matchRoomCodeFilter.value.trim() || undefined,
      participant_user_id: matchParticipantFilter.value.trim() || undefined,
      status: matchStatusFilter.value.trim() || undefined,
      has_replay: parseMatchReplayFilter(),
      limit: PAGE_SIZE,
      offset: (matchesPage.value - 1) * PAGE_SIZE,
    })
    matches.value = data.items
    matchesTotal.value = data.total
    matchesHasNext.value = (matchesPage.value * PAGE_SIZE) < data.total
    await applyMatchSelectionToTable()
  } catch (error: any) {
    matches.value = []
    matchesHasNext.value = false
    matchesTotal.value = 0
    matchesTableRef.value?.clearSelection()
    errorMessage.value = resolveErrorMessage(error, '加载对局数据失败')
  } finally {
    loadingMatches.value = false
  }
  if (options.syncQuery !== false) {
    syncRouteQuery()
  }
}

function handleMatchesPageChange(page: number) {
  void loadMatches({ page })
}

async function handleDeleteMatch(match: AdminMatchSummary) {
  try {
    await ElMessageBox.confirm(`确认删除对局 ${match.match_id}？此操作不可撤销。`, '确认删除', {
      type: 'warning',
      confirmButtonText: '删除',
      cancelButtonText: '取消',
    })
  } catch {
    return
  }
  try {
    await deleteAdminMatch(auth.sessionId, match.match_id)
    ElMessage.success('对局记录已删除')
    await loadMatches()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '删除对局失败'))
  }
}

async function handleBatchDeleteMatches() {
  const matchIds = [...selectedMatchIds.value]
  if (matchIds.length === 0) return
  try {
    await ElMessageBox.confirm(`确认批量删除 ${matchIds.length} 个对局？此操作不可撤销。`, '确认批量删除对局', {
      type: 'warning',
      confirmButtonText: '删除',
      cancelButtonText: '取消',
    })
  } catch {
    return
  }
  try {
    const { data } = await batchDeleteAdminMatches(auth.sessionId, matchIds)
    ElMessage.success(summarizeBatchResult('批量删除对局完成', data))
    clearMatchSelection()
    await loadMatches()
  } catch (error: any) {
    ElMessage.error(resolveErrorMessage(error, '批量删除对局失败'))
  }
}

function refreshUsers() {
  clearUserSelection()
  void loadUsers({ page: 1 })
}

function refreshRooms() {
  clearRoomSelection()
  void loadRooms({ page: 1 })
}

function refreshMatches() {
  clearMatchSelection()
  void loadMatches({ page: 1 })
}

async function loadCurrentTab(options: { syncQuery?: boolean } = {}) {
  if (activeTab.value === 'users') {
    await loadUsers(options)
    return
  }
  if (activeTab.value === 'rooms') {
    await loadRooms(options)
    return
  }
  await loadMatches(options)
}

function handleTabChange(name: string | number) {
  if (name === 'users' || name === 'rooms' || name === 'matches') {
    activeTab.value = name
  } else {
    activeTab.value = 'users'
  }
  void loadCurrentTab()
}

onMounted(async () => {
  if (auth.user == null) {
    await auth.fetchUser()
  }
  loadStateFromRouteQuery()
  await loadCurrentTab({ syncQuery: false })
  syncRouteQuery()
})
</script>

<style scoped>
.page-header {
  margin-bottom: 24px;
}

.page-title {
  margin: 0 0 8px;
  font-size: 22px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.page-title-line {
  height: 2px;
  background: linear-gradient(90deg, var(--fcm-gold, #c9a020), transparent);
  max-width: 200px;
}

.error-alert {
  margin-bottom: 16px;
}

.poster-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius-lg, 12px);
  padding: 20px;
  box-shadow: var(--fcm-shadow-card);
}

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 16px;
  padding: 12px 16px;
  background: var(--fcm-surface-alt);
  border-radius: var(--fcm-radius, 6px);
}

.toolbar-input {
  width: 260px;
}

.toolbar-select {
  width: 140px;
}

.selection-count {
  display: inline-flex;
  align-items: center;
  color: var(--fcm-text-muted);
  font-size: 13px;
  font-weight: 500;
}

.inline-row {
  display: inline-flex;
  gap: 6px;
  align-items: center;
}

.server-cell {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.server-cell span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.detail-drawer {
  min-height: 240px;
}

.drawer-section-title {
  margin: 20px 0 10px;
  font-size: 14px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.status-select {
  width: 110px;
}

.pager {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 16px;
  padding-top: 12px;
  border-top: 1px solid var(--fcm-field-border);
}

.pager__label {
  color: var(--fcm-text-muted);
  font-size: 13px;
  font-weight: 500;
}
</style>
