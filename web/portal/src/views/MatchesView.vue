<template>
  <AppLayout>
    <div class="page-header">
      <h2 class="page-title">对局历史</h2>
      <div class="page-title-line" />
    </div>
    <div class="poster-container">
      <el-table :data="matches" v-loading="loading" style="width: 100%" class="fcm-table"
        @row-click="(row: MatchSummary) => router.push(`/matches/${row.match_id}`)">
        <el-table-column prop="room_code" label="房间号" width="120" />
        <el-table-column label="状态" width="100">
          <template #default="{ row }">
            <el-tag :type="statusType(row.status)" size="small">{{ row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="玩家" min-width="180">
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
                  class="player-logo-large"
                />
                <span class="player-name">{{ participant.name }}</span>
              </div>
            </div>
            <span v-if="!row.participants?.length">-</span>
          </template>
        </el-table-column>
        <el-table-column label="时长" width="100">
          <template #default="{ row }">
            {{ formatDuration(row.duration_sec) }}
          </template>
        </el-table-column>
        <el-table-column label="开始时间" min-width="160">
          <template #default="{ row }">
            {{ row.started_at ? new Date(row.started_at).toLocaleString('zh-CN') : '-' }}
          </template>
        </el-table-column>
        <el-table-column label="结束时间" min-width="160">
          <template #default="{ row }">
            {{ row.ended_at ? new Date(row.ended_at).toLocaleString('zh-CN') : '-' }}
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
          <el-empty description="暂无对局记录" :image-size="80" />
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

function statusType(status: string): '' | 'success' | 'warning' | 'info' | 'danger' {
  if (status === '已结束' || status === 'completed') return 'info'
  if (status === '进行中' || status === 'in_progress') return 'success'
  if (status === '等待中' || status === 'waiting') return 'warning'
  return ''
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
.poster-container {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
  padding: 16px;
  box-shadow: var(--fcm-shadow-card);
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
  padding: 2px 8px 2px 2px;
  background: var(--fcm-surface-alt);
  border: 1px solid var(--fcm-field-border);
  border-radius: 999px;
}

.player-logo-large {
  width: 32px;
  height: 32px;
  flex: 0 0 32px;
  border-radius: 999px;
  object-fit: cover;
  border: 1px solid var(--fcm-field-border);
}

.player-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>

<style>
.fcm-table .el-table__header-wrapper th {
  background: var(--fcm-surface-alt) !important;
  color: var(--fcm-text-primary);
  font-weight: 500;
}
.fcm-table .el-table__row:hover > td {
  background: var(--fcm-primary-light) !important;
}
</style>
