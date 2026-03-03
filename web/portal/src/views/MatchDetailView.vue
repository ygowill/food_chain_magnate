<template>
  <AppLayout>
    <div class="page-header">
      <el-button link @click="router.push('/matches')">&larr; 返回列表</el-button>
      <h2 class="page-title">对局详情</h2>
      <div class="page-title-line" />
    </div>

    <div v-loading="loading">
      <div class="poster-card">
        <h3 class="card-title">基本信息</h3>
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="房间号">{{ match?.room_code ?? '-' }}</el-descriptions-item>
          <el-descriptions-item label="状态">
            <el-tag :type="statusType(match?.status)" size="small">{{ match?.status ?? '-' }}</el-tag>
          </el-descriptions-item>
          <el-descriptions-item label="时长">{{ formatDuration(match?.duration_sec) }}</el-descriptions-item>
          <el-descriptions-item label="开始时间">{{ formatTime(match?.started_at) }}</el-descriptions-item>
          <el-descriptions-item label="结束时间">{{ formatTime(match?.ended_at) }}</el-descriptions-item>
          <el-descriptions-item label="游戏版本">{{ match?.game_version ?? '-' }}</el-descriptions-item>
          <el-descriptions-item label="种子">{{ match?.seed ?? '-' }}</el-descriptions-item>
        </el-descriptions>
      </div>

      <div v-if="match?.summary" class="poster-card">
        <h3 class="card-title">游戏设置</h3>
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="总回合数">{{ match.summary.round_number }}</el-descriptions-item>
          <el-descriptions-item label="银行余额">${{ match.summary.bank_total }}</el-descriptions-item>
          <el-descriptions-item label="银行破产次数">{{ match.summary.bank_broke_count }}</el-descriptions-item>
          <el-descriptions-item label="储备金注入">${{ match.summary.bank_reserve_added }}</el-descriptions-item>
          <el-descriptions-item label="广告投放数">{{ match.summary.marketing_count }}</el-descriptions-item>
          <el-descriptions-item label="启用模组" :span="2">
            <template v-if="nonBaseModules.length">
              <el-tag v-for="mod in nonBaseModules" :key="mod" size="small" class="mod-tag">{{ moduleName(mod) }}</el-tag>
            </template>
            <span v-else>仅基础模组</span>
          </el-descriptions-item>
        </el-descriptions>
      </div>

      <div v-if="sortedParticipants.length" class="player-cards-grid">
        <div v-for="(participant, idx) in sortedParticipants" :key="participant.user_id" class="poster-card player-card">
          <h3 class="card-title player-card-title">
            <span class="player-title-main">
              <img
                v-if="participantLogoUrl(participant)"
                :src="participantLogoUrl(participant)!"
                :alt="participantLogoLabel(participant)"
                class="player-logo player-logo--card"
              />
              <span>#{{ idx + 1 }} {{ participantName(participant) }}</span>
            </span>
            <el-tag v-if="participant.score?.forfeited" type="danger" size="small" class="status-tag">弃权</el-tag>
            <el-tag v-else-if="participant.result === 'win'" type="success" size="small" class="status-tag">胜利</el-tag>
          </h3>
          <div class="player-id-hint">ID: {{ participant.user_id.slice(0, 12) }}</div>

          <div class="detail-grid">
            <div class="detail-section">
              <h4 class="section-title">库存</h4>
              <div v-if="participant.score && Object.keys(participant.score.inventory).length" class="tag-list">
                <el-tag
                  v-for="(count, productId) in participant.score.inventory"
                  :key="productId"
                  size="small"
                  class="detail-tag"
                >
                  {{ productName(productId as string) }}: {{ count }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无库存数据</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">员工 ({{ participant.score?.employees?.length ?? 0 }})</h4>
              <div v-if="participant.score?.employees?.length" class="tag-list">
                <el-tag
                  v-for="(employeeId, index) in participant.score.employees"
                  :key="`${employeeId}-${index}`"
                  size="small"
                  type="info"
                  class="detail-tag"
                >
                  {{ employeeName(employeeId as string) }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无员工数据</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">里程碑 ({{ participant.score?.milestones?.length ?? 0 }})</h4>
              <div v-if="participant.score?.milestones?.length" class="tag-list">
                <el-tag
                  v-for="(milestoneId, index) in participant.score.milestones"
                  :key="`${milestoneId}-${index}`"
                  size="small"
                  type="warning"
                  class="detail-tag"
                >
                  {{ milestoneName(milestoneId as string) }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无里程碑</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">玩家摘要</h4>
              <el-descriptions :column="1" size="small" border>
                <el-descriptions-item label="现金">${{ participant.score?.cash ?? '-' }}</el-descriptions-item>
                <el-descriptions-item label="餐厅数">{{ participant.score?.restaurants ?? '-' }}</el-descriptions-item>
                <el-descriptions-item label="营销中">{{ participant.score?.marketing_campaigns ?? '-' }}</el-descriptions-item>
              </el-descriptions>
            </div>
          </div>
        </div>
      </div>

      <div class="poster-card">
        <h3 class="card-title">统计总表</h3>
        <div v-if="sortedParticipants.length && playerStatMatrixRows.length" class="stats-table-wrap">
          <el-table :data="playerStatMatrixRows" class="fcm-table matrix-table" size="small" table-layout="fixed">
            <el-table-column prop="label" label="统计项" fixed="left" width="170" />
            <el-table-column
              v-for="(participant, idx) in sortedParticipants"
              :key="participant.user_id"
              :label="participantName(participant)"
              min-width="92"
              align="center"
            >
              <template #header>
                <div class="player-column-header" :title="participantName(participant)">
                  <img
                    v-if="participantLogoUrl(participant)"
                    :src="participantLogoUrl(participant)!"
                    :alt="participantLogoLabel(participant)"
                    class="player-logo player-logo--table"
                  />
                  <span class="player-column-name">#{{ idx + 1 }} {{ participantName(participant) }}</span>
                </div>
              </template>
              <template #default="{ row }">{{ row.values[participant.user_id] ?? 0 }}</template>
            </el-table-column>
          </el-table>
        </div>
        <span v-else class="empty-hint">无统计数据</span>
      </div>

      <div v-if="match?.has_replay" class="poster-card">
        <h3 class="card-title">对局回放</h3>
        <div v-if="replay" class="replay-info">
          <el-descriptions :column="2" border size="small">
            <el-descriptions-item label="文件大小">{{ formatBytes(replay.size_bytes) }}</el-descriptions-item>
            <el-descriptions-item label="校验和">{{ replay.checksum ?? '-' }}</el-descriptions-item>
          </el-descriptions>
          <el-button type="primary" style="margin-top: 12px" @click="downloadReplay">下载回放</el-button>
        </div>
        <el-button v-else type="primary" size="small" @click="loadReplay">加载回放信息</el-button>
      </div>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import AppLayout from '../components/AppLayout.vue'
import { getMatch, getReplay, type MatchDetail, type ParticipantInfo, type ReplayInfo } from '../api/matches'
import { employeeName, milestoneName, moduleName, productName } from '../utils/game-names'
import { buildPlayerStatMatrixRows } from '../utils/match-stats'
import { participantDisplayName, resolveParticipantLogoInfo } from '../utils/participant-display'
import { useAuthStore } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const match = ref<MatchDetail | null>(null)
const replay = ref<ReplayInfo | null>(null)
const loading = ref(false)

const matchId = route.params.id as string

const sortedParticipants = computed(() => {
  if (!match.value?.participants) return []
  return [...match.value.participants].sort((a, b) => {
    if (a.score?.forfeited && !b.score?.forfeited) return 1
    if (!a.score?.forfeited && b.score?.forfeited) return -1
    return (b.score?.cash ?? 0) - (a.score?.cash ?? 0)
  })
})

const nonBaseModules = computed(() => {
  if (!match.value?.summary?.modules) return []
  return match.value.summary.modules.filter(moduleId => !moduleId.startsWith('base_'))
})

const playerStatMatrixRows = computed(() => {
  const modules = match.value?.summary?.modules ?? []
  return buildPlayerStatMatrixRows(
    sortedParticipants.value.map(participant => ({
      userId: participant.user_id,
      score: participant.score,
      context: {
        modules,
        milestones: participant.score?.milestones ?? [],
        employees: participant.score?.employees ?? [],
      },
    })),
    productName,
  )
})

const participantDisplayMetaByUserId = computed<Record<string, { name: string; logoUrl: string | null; logoLabel: string | null }>>(() => {
  const out: Record<string, { name: string; logoUrl: string | null; logoLabel: string | null }> = {}
  for (const participant of sortedParticipants.value) {
    const logo = resolveParticipantLogoInfo(participant)
    out[participant.user_id] = {
      name: participantDisplayName(participant),
      logoUrl: logo.url,
      logoLabel: logo.label,
    }
  }
  return out
})

function participantName(participant: ParticipantInfo): string {
  return participantDisplayMetaByUserId.value[participant.user_id]?.name ?? participantDisplayName(participant)
}

function participantLogoUrl(participant: ParticipantInfo): string | null {
  return participantDisplayMetaByUserId.value[participant.user_id]?.logoUrl ?? resolveParticipantLogoInfo(participant).url
}

function participantLogoLabel(participant: ParticipantInfo): string {
  return participantDisplayMetaByUserId.value[participant.user_id]?.logoLabel ?? '餐厅 Logo'
}

function formatDuration(seconds: number | null | undefined): string {
  if (seconds == null) return '-'
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

function formatTime(iso: string | null | undefined): string {
  if (!iso) return '-'
  return new Date(iso).toLocaleString('zh-CN')
}

function formatBytes(bytes: number | null | undefined): string {
  if (bytes == null) return '-'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function statusType(status: string | undefined): '' | 'success' | 'warning' | 'info' | 'danger' {
  if (!status) return ''
  if (status === '已结束' || status === 'completed') return 'info'
  if (status === '进行中' || status === 'in_progress') return 'success'
  if (status === '等待中' || status === 'waiting') return 'warning'
  return ''
}

async function loadReplay() {
  try {
    const { data } = await getReplay(matchId, auth.sessionId)
    replay.value = data
  } catch {
    replay.value = null
  }
}

function inferReplayFileName(uri: string): string {
  try {
    const url = new URL(uri, window.location.origin)
    const name = url.pathname.split('/').filter(Boolean).pop()
    if (name) return name
  } catch {
    // ignore parse failure
  }
  return `match-${matchId}-replay.json`
}

function buildReplayDownloadUrl(uri: string): string {
  try {
    const url = new URL(uri, window.location.origin)
    if (
      url.pathname.startsWith('/v1/matches/')
      && url.pathname.endsWith('/replay/download')
      && !url.searchParams.has('session_id')
      && auth.sessionId
    ) {
      url.searchParams.set('session_id', auth.sessionId)
    }
    return url.toString()
  } catch {
    return uri
  }
}

function downloadReplay() {
  if (!replay.value?.storage_uri) return
  const link = document.createElement('a')
  link.href = buildReplayDownloadUrl(replay.value.storage_uri)
  link.download = inferReplayFileName(replay.value.storage_uri)
  link.rel = 'noopener'
  link.style.display = 'none'
  document.body.appendChild(link)
  link.click()
  link.remove()
}

onMounted(async () => {
  loading.value = true
  try {
    const { data } = await getMatch(matchId, auth.sessionId)
    match.value = data
  } catch {
    match.value = null
  }
  loading.value = false
})
</script>

<style scoped>
.page-header {
  margin-bottom: 20px;
}

.page-title {
  margin: 8px 0;
  font-size: 20px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.page-title-line {
  height: 2px;
  max-width: 120px;
  background: var(--fcm-accent-line);
}

.poster-card {
  margin-bottom: 16px;
  padding: 16px;
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
  box-shadow: var(--fcm-shadow-card);
}

.card-title {
  margin: 0 0 12px;
  font-size: 16px;
  font-weight: 600;
  color: var(--fcm-text-primary);
}

.mod-tag {
  margin-right: 4px;
  margin-bottom: 2px;
}

.player-logo {
  width: 28px;
  height: 28px;
  border-radius: 4px;
  object-fit: cover;
  border: 1px solid var(--fcm-field-border);
}

.player-logo--table {
  width: 20px;
  height: 20px;
}

.player-logo--card {
  width: 56px;
  height: 56px;
  border-radius: 6px;
}

.stats-table-wrap {
  width: 100%;
  overflow-x: auto;
}

.player-column-header {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  line-height: 1.1;
}

.player-column-name {
  max-width: 84px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.matrix-table :deep(.el-table__cell) {
  vertical-align: middle;
}

.player-cards-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
}

@media (max-width: 1360px) {
  .player-cards-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 900px) {
  .player-cards-grid {
    grid-template-columns: 1fr;
  }
}

.player-card {
  margin-bottom: 0;
}

.player-card-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.player-title-main {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.status-tag {
  margin-left: 8px;
}

.player-id-hint {
  margin-bottom: 10px;
  font-size: 12px;
  color: var(--fcm-text-muted, #999);
}

.detail-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 12px;
}

.detail-section {
  padding: 12px;
  background: var(--fcm-surface-alt, #fafafa);
  border-radius: 6px;
}

.section-title {
  margin: 0 0 8px;
  font-size: 13px;
  font-weight: 600;
  color: var(--fcm-text-secondary, #666);
}

.tag-list {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.detail-tag {
  margin: 0;
}

.empty-hint {
  font-size: 12px;
  color: var(--fcm-text-muted, #999);
}

.replay-info {
  margin-top: 4px;
}
</style>
