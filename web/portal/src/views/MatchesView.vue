<template>
  <AppLayout>
    <div class="page-header">
      <h2 class="page-title">
        <svg class="page-title__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12"/></svg>
        对局历史
      </h2>
      <div class="page-title-line" />
    </div>
    <div class="table-card">
      <el-table :data="matches" v-loading="loading" style="width: 100%" class="fcm-table"
        @row-click="(row: MatchSummary) => router.push(`/matches/${row.match_id}`)">
        <el-table-column prop="room_code" label="房间号" width="120">
          <template #default="{ row }">
            <span class="room-code">{{ row.room_code || '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="110">
          <template #default="{ row }">
            <span class="status-badge" :class="statusClass(row.status)">
              <span class="status-badge__dot" />
              {{ statusLabel(row.status) }}
            </span>
          </template>
        </el-table-column>
        <el-table-column label="玩家" min-width="200">
          <template #default="{ row }">
            <div class="player-list" v-if="row.participants?.length">
              <div
                v-for="(participant, idx) in participantDisplays(row)"
                :key="`${row.match_id}-${idx}-${participant.name}`"
                class="player-pill"
                :title="participant.name"
              >
                <img
                  v-if="participant.logoUrl"
                  :src="participant.logoUrl"
                  :alt="participant.logoLabel ?? '餐厅 Logo'"
                  class="player-logo"
                />
                <span class="player-name">{{ participant.name }}</span>
              </div>
            </div>
            <span v-if="!row.participants?.length" class="empty-text">-</span>
          </template>
        </el-table-column>
        <el-table-column label="时长" width="100">
          <template #default="{ row }">
            <span class="meta-text">{{ formatDuration(row.duration_sec) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="记录" width="150">
          <template #default="{ row }">
            <div v-if="hasArtifacts(row)" class="record-badges">
              <span v-if="row.latest_save_round != null" class="record-badge">存档 R{{ row.latest_save_round }}</span>
              <span v-if="row.map_snapshot_count" class="record-badge">截图 {{ row.map_snapshot_count }}</span>
            </div>
            <span v-else class="empty-text">-</span>
          </template>
        </el-table-column>
        <el-table-column label="开始时间" min-width="160">
          <template #default="{ row }">
            <span class="meta-text">{{ row.started_at ? new Date(row.started_at).toLocaleString('zh-CN') : '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="结束时间" min-width="160">
          <template #default="{ row }">
            <span class="meta-text">{{ row.ended_at ? new Date(row.ended_at).toLocaleString('zh-CN') : '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="100">
          <template #default="{ row }">
            <el-button link type="primary" size="small" @click.stop="router.push(`/matches/${row.match_id}`)">
              查看详情
            </el-button>
          </template>
        </el-table-column>
        <template #empty>
          <div class="empty-state">
            <svg class="empty-state__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1"><path d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>
            <p class="empty-state__text">暂无对局记录</p>
            <p class="empty-state__hint">开始一场新的对局后，记录将显示在这里</p>
          </div>
        </template>
      </el-table>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { listMatches, type MatchSummary } from '../api/matches'
import { participantDisplayName, resolveParticipantLogoInfo } from '../utils/participant-display'
import AppLayout from '../components/AppLayout.vue'

const router = useRouter()
const auth = useAuthStore()
const matches = ref<MatchSummary[]>([])
const loading = ref(false)

function formatDuration(sec: number | null): string {
  if (sec == null) return '-'
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

function statusClass(status: string): string {
  if (status === '已结束' || status === 'completed') return 'status-badge--completed'
  if (status === '进行中' || status === 'in_progress') return 'status-badge--active'
  if (status === '等待中' || status === 'waiting') return 'status-badge--waiting'
  return ''
}

function statusLabel(status: string): string {
  if (status === 'completed') return '已结束'
  if (status === 'in_progress') return '进行中'
  if (status === 'waiting') return '等待中'
  return status
}

function hasArtifacts(match: MatchSummary): boolean {
  return match.latest_save_round != null || Number(match.map_snapshot_count ?? 0) > 0
}

function participantDisplays(match: MatchSummary): Array<{ name: string; logoUrl: string | null; logoLabel: string | null }> {
  const participants = [...(match.participants ?? [])].sort((a, b) => (a.seat_index ?? 99) - (b.seat_index ?? 99))
  return participants.map(participant => {
    const logo = resolveParticipantLogoInfo(participant)
    return {
      name: participantDisplayName(participant),
      logoUrl: logo.url,
      logoLabel: logo.label,
    }
  })
}

onMounted(async () => {
  if (!auth.isLoggedIn) {
    router.replace({ name: 'login', query: { redirect: '/matches' } })
    return
  }
  if (auth.user == null) {
    await auth.fetchUser()
  }
  if (!auth.isLoggedIn) {
    router.replace({ name: 'login', query: { redirect: '/matches' } })
    return
  }

  loading.value = true
  try {
    const { data } = await listMatches(auth.sessionId)
    matches.value = data
  } catch {
    matches.value = []
  } finally {
    loading.value = false
  }
})
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

.table-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius-lg);
  padding: 20px;
  box-shadow: var(--fcm-shadow-card);
}

.room-code {
  font-family: monospace;
  font-weight: 600;
  font-size: 13px;
  color: var(--fcm-text-primary);
  background: var(--fcm-gold-light);
  padding: 2px 8px;
  border-radius: 4px;
}

.status-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 500;
  padding: 3px 10px;
  border-radius: 999px;
}

.status-badge__dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
}

.status-badge--completed {
  color: var(--fcm-text-muted);
  background: rgba(43, 33, 23, 0.06);
}
.status-badge--completed .status-badge__dot {
  background: var(--fcm-text-muted);
}

.status-badge--active {
  color: var(--fcm-text-success);
  background: rgba(71, 140, 56, 0.1);
}
.status-badge--active .status-badge__dot {
  background: var(--fcm-text-success);
  animation: pulse 2s infinite;
}

.status-badge--waiting {
  color: var(--fcm-gold);
  background: var(--fcm-gold-light);
}
.status-badge--waiting .status-badge__dot {
  background: var(--fcm-gold);
}

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

.player-list {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.player-pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  max-width: 170px;
  padding: 3px 10px 3px 3px;
  background: var(--fcm-cream);
  border: 1px solid var(--fcm-field-border);
  border-radius: 999px;
  transition: border-color 0.15s;
}

.player-pill:hover {
  border-color: var(--fcm-gold-border);
}

.player-logo {
  width: 28px;
  height: 28px;
  flex: 0 0 28px;
  border-radius: 50%;
  object-fit: cover;
  border: 1px solid var(--fcm-field-border);
}

.player-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
  font-weight: 500;
}

.meta-text {
  font-size: 13px;
  color: var(--fcm-text-muted);
}

.empty-text {
  color: var(--fcm-text-muted);
}

.record-badges {
  display: flex;
  flex-wrap: wrap;
  gap: 5px;
}

.record-badge {
  display: inline-flex;
  align-items: center;
  min-height: 22px;
  padding: 2px 7px;
  border-radius: 4px;
  background: rgba(43, 33, 23, 0.06);
  color: var(--fcm-text-muted);
  font-size: 12px;
  line-height: 1.2;
}

.empty-state {
  padding: 48px 20px;
  text-align: center;
}

.empty-state__icon {
  width: 48px;
  height: 48px;
  color: var(--fcm-text-muted);
  opacity: 0.3;
  margin-bottom: 12px;
}

.empty-state__text {
  margin: 0 0 6px;
  font-size: 15px;
  font-weight: 600;
  color: var(--fcm-text-muted);
}

.empty-state__hint {
  margin: 0;
  font-size: 13px;
  color: var(--fcm-text-muted);
  opacity: 0.7;
}
</style>

<style>
.fcm-table .el-table__header-wrapper th {
  background: var(--fcm-dark, #2b2117) !important;
  color: var(--fcm-text-light, #f7edd1) !important;
  font-weight: 500;
  font-size: 13px;
}
.fcm-table .el-table__row {
  cursor: pointer;
  transition: background 0.15s;
}
.fcm-table .el-table__row:hover > td {
  background: var(--fcm-primary-light) !important;
}
</style>
