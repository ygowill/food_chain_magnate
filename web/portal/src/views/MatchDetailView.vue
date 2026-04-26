<template>
  <AppLayout>
    <div class="page-header">
      <el-button link @click="router.push('/matches')" class="back-link">
        <svg viewBox="0 0 20 20" fill="currentColor" class="back-link__icon"><path fill-rule="evenodd" d="M17 10a.75.75 0 01-.75.75H5.612l4.158 3.96a.75.75 0 11-1.04 1.08l-5.5-5.25a.75.75 0 010-1.08l5.5-5.25a.75.75 0 111.04 1.08L5.612 9.25H16.25A.75.75 0 0117 10z" clip-rule="evenodd"/></svg>
        返回列表
      </el-button>
      <h2 class="page-title">
        <svg class="page-title__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/></svg>
        对局详情
      </h2>
      <div class="page-title-line" />
    </div>

    <div v-loading="loading">
      <div class="info-card">
        <h3 class="card-title">基本信息</h3>
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="房间号">
            <span class="room-code">{{ match?.room_code ?? '-' }}</span>
          </el-descriptions-item>
          <el-descriptions-item label="状态">
            <span class="status-badge" :class="statusClass(match?.status)">
              <span class="status-badge__dot" />
              {{ statusLabel(match?.status) }}
            </span>
          </el-descriptions-item>
          <el-descriptions-item label="时长">{{ formatDuration(match?.duration_sec) }}</el-descriptions-item>
          <el-descriptions-item label="开始时间">{{ formatTime(match?.started_at) }}</el-descriptions-item>
          <el-descriptions-item label="结束时间">{{ formatTime(match?.ended_at) }}</el-descriptions-item>
          <el-descriptions-item label="游戏版本">{{ match?.game_version ?? '-' }}</el-descriptions-item>
          <el-descriptions-item label="种子">
            <code class="seed-code">{{ match?.seed ?? '-' }}</code>
          </el-descriptions-item>
        </el-descriptions>
      </div>

      <div v-if="match?.summary" class="info-card">
        <h3 class="card-title">游戏设置</h3>
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="总回合数">{{ match.summary.round_number }}</el-descriptions-item>
          <el-descriptions-item label="银行余额">
            <span class="cash-value">${{ match.summary.bank_total }}</span>
          </el-descriptions-item>
          <el-descriptions-item label="银行破产次数">{{ match.summary.bank_broke_count }}</el-descriptions-item>
          <el-descriptions-item label="储备金注入">
            <span class="cash-value">${{ match.summary.bank_reserve_added }}</span>
          </el-descriptions-item>
          <el-descriptions-item label="广告投放数">{{ match.summary.marketing_count }}</el-descriptions-item>
          <el-descriptions-item label="启用模组" :span="2">
            <template v-if="nonBaseModules.length">
              <el-tag v-for="mod in nonBaseModules" :key="mod" size="small" class="mod-tag">{{ moduleName(mod) }}</el-tag>
            </template>
            <span v-else class="empty-hint">仅基础模组</span>
          </el-descriptions-item>
        </el-descriptions>
      </div>

      <div v-if="sortedParticipants.length" class="player-cards-grid">
        <div
          v-for="(participant, idx) in sortedParticipants"
          :key="participant.user_id"
          class="player-card"
          :class="{ 'player-card--winner': participant.result === 'win' && !participant.score?.forfeited }"
        >
          <div class="player-card__color-bar" :style="{ background: playerColors[idx % playerColors.length] }" />

          <div class="player-card__header">
            <div class="player-card__identity">
              <img
                v-if="participantLogoUrl(participant)"
                :src="participantLogoUrl(participant)!"
                :alt="participantLogoLabel(participant)"
                class="player-card__logo"
              />
              <div>
                <div class="player-card__name">#{{ idx + 1 }} {{ participantName(participant) }}</div>
                <div class="player-card__id">{{ participant.user_id.slice(0, 12) }}</div>
              </div>
            </div>
            <div class="player-card__status">
              <span v-if="participant.score?.forfeited" class="result-badge result-badge--forfeit">弃权</span>
              <span v-else-if="participant.result === 'win'" class="result-badge result-badge--win">
                <svg viewBox="0 0 20 20" fill="currentColor" class="result-badge__icon"><path fill-rule="evenodd" d="M10 1a.75.75 0 01.65.38l2.1 3.63 4.13.73a.75.75 0 01.41 1.27l-2.97 3.04.67 4.1a.75.75 0 01-1.08.78L10 12.82l-3.91 1.95a.75.75 0 01-1.08-.78l.67-4.1L2.71 6.85a.75.75 0 01.41-1.27l4.13-.73 2.1-3.63A.75.75 0 0110 1z" clip-rule="evenodd"/></svg>
                胜利
              </span>
            </div>
          </div>

          <div class="player-card__cash">
            <span class="player-card__cash-label">现金</span>
            <span class="player-card__cash-value">${{ participant.score?.cash ?? 0 }}</span>
          </div>

          <div class="detail-grid">
            <div class="detail-section">
              <h4 class="section-title">库存</h4>
              <div v-if="participant.score && Object.keys(participant.score.inventory).length" class="tag-list">
                <el-tag v-for="(count, productId) in participant.score.inventory" :key="productId" size="small" class="detail-tag">
                  {{ productName(productId as string) }}: {{ count }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无库存数据</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">员工 ({{ participant.score?.employees?.length ?? 0 }})</h4>
              <div v-if="participant.score?.employees?.length" class="tag-list">
                <el-tag v-for="(employeeId, index) in participant.score.employees" :key="`${employeeId}-${index}`" size="small" type="info" class="detail-tag">
                  {{ employeeName(employeeId as string) }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无员工数据</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">里程碑 ({{ participant.score?.milestones?.length ?? 0 }})</h4>
              <div v-if="participant.score?.milestones?.length" class="tag-list">
                <el-tag v-for="(milestoneId, index) in participant.score.milestones" :key="`${milestoneId}-${index}`" size="small" type="warning" class="detail-tag">
                  {{ milestoneName(milestoneId as string) }}
                </el-tag>
              </div>
              <span v-else class="empty-hint">无里程碑</span>
            </div>

            <div class="detail-section">
              <h4 class="section-title">玩家摘要</h4>
              <el-descriptions :column="1" size="small" border>
                <el-descriptions-item label="餐厅数">{{ participant.score?.restaurants ?? '-' }}</el-descriptions-item>
                <el-descriptions-item label="营销中">{{ participant.score?.marketing_campaigns ?? '-' }}</el-descriptions-item>
              </el-descriptions>
            </div>
          </div>
        </div>
      </div>

      <div class="info-card">
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
                  <div class="player-column-dot" :style="{ background: playerColors[idx % playerColors.length] }" />
                  <img
                    v-if="participantLogoUrl(participant)"
                    :src="participantLogoUrl(participant)!"
                    :alt="participantLogoLabel(participant)"
                    class="player-logo-sm"
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

      <div v-if="match?.latest_save" class="info-card">
        <h3 class="card-title">服务端存档</h3>
        <div class="artifact-info">
          <el-descriptions :column="2" border size="small">
            <el-descriptions-item label="最新回合">R{{ match.latest_save.round_number }}</el-descriptions-item>
            <el-descriptions-item label="保存类型">{{ snapshotKindLabel(match.latest_save.snapshot_kind) }}</el-descriptions-item>
            <el-descriptions-item label="文件大小">{{ formatBytes(match.latest_save.size_bytes) }}</el-descriptions-item>
            <el-descriptions-item label="保存时间">{{ formatTime(match.latest_save.updated_at ?? match.latest_save.created_at) }}</el-descriptions-item>
            <el-descriptions-item label="状态哈希" :span="2">
              <code class="seed-code">{{ match.latest_save.state_hash ?? '-' }}</code>
            </el-descriptions-item>
            <el-descriptions-item label="校验和" :span="2">
              <code class="seed-code">{{ match.latest_save.checksum ?? '-' }}</code>
            </el-descriptions-item>
          </el-descriptions>
          <el-button type="primary" class="artifact-action" @click="downloadLatestSave">
            <svg viewBox="0 0 20 20" fill="currentColor" class="button-icon"><path d="M10.75 2.75a.75.75 0 00-1.5 0v8.69L6.53 8.72a.75.75 0 00-1.06 1.06l4 4a.75.75 0 001.06 0l4-4a.75.75 0 10-1.06-1.06l-2.72 2.72V2.75z"/><path d="M3.5 13.75a.75.75 0 011.5 0v1.5h10v-1.5a.75.75 0 011.5 0v2.25a.75.75 0 01-.75.75H4.25a.75.75 0 01-.75-.75v-2.25z"/></svg>
            下载最新存档
          </el-button>
        </div>
      </div>

      <div v-if="mapSnapshots.length" class="info-card">
        <div class="snapshot-header">
          <h3 class="card-title">地图回看</h3>
          <div class="snapshot-header__meta">{{ mapSnapshots.length }} 张截图</div>
        </div>
        <div class="snapshot-viewer">
          <div class="snapshot-stage">
            <img
              v-if="selectedSnapshot"
              :src="buildSessionDownloadUrl(selectedSnapshot.download_url)"
              :alt="snapshotAlt(selectedSnapshot)"
              class="snapshot-image"
            />
          </div>
          <div class="snapshot-panel">
            <div class="snapshot-panel__actions">
              <el-button size="small" :disabled="!selectedSnapshot" @click="downloadSelectedSnapshot">
                <svg viewBox="0 0 20 20" fill="currentColor" class="button-icon"><path d="M10.75 2.75a.75.75 0 00-1.5 0v8.69L6.53 8.72a.75.75 0 00-1.06 1.06l4 4a.75.75 0 001.06 0l4-4a.75.75 0 10-1.06-1.06l-2.72 2.72V2.75z"/><path d="M3.5 13.75a.75.75 0 011.5 0v1.5h10v-1.5a.75.75 0 011.5 0v2.25a.75.75 0 01-.75.75H4.25a.75.75 0 01-.75-.75v-2.25z"/></svg>
                下载当前截图
              </el-button>
            </div>
            <div class="snapshot-list">
              <button
                v-for="snapshot in mapSnapshots"
                :key="snapshot.id"
                class="snapshot-item"
                :class="{ 'snapshot-item--active': selectedSnapshot?.id === snapshot.id }"
                type="button"
                @click="selectedSnapshotId = snapshot.id"
              >
                <span class="snapshot-item__round">R{{ snapshot.round_number }}</span>
                <span class="snapshot-item__kind">{{ snapshotKindLabel(snapshot.snapshot_kind) }}</span>
                <span class="snapshot-item__size">{{ formatBytes(snapshot.size_bytes) }}</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <div v-if="match?.has_replay" class="info-card">
        <h3 class="card-title">对局回放</h3>
        <div v-if="replay" class="replay-info">
          <el-descriptions :column="2" border size="small">
            <el-descriptions-item label="文件大小">{{ formatBytes(replay.size_bytes) }}</el-descriptions-item>
            <el-descriptions-item label="校验和">
              <code class="seed-code">{{ replay.checksum ?? '-' }}</code>
            </el-descriptions-item>
          </el-descriptions>
          <el-button type="primary" style="margin-top: 16px" @click="downloadReplay">下载回放</el-button>
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
import { getMatch, getReplay, type MatchArtifactInfo, type MatchDetail, type ParticipantInfo, type ReplayInfo } from '../api/matches'
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
const selectedSnapshotId = ref<string | null>(null)

const matchId = route.params.id as string

const playerColors = [
  '#ba3b2e', '#2e7d9b', '#5a8a3c', '#c9a020', '#8b5cf6', '#d97706',
]

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

const mapSnapshots = computed(() => match.value?.map_snapshots ?? [])

const selectedSnapshot = computed(() => {
  const snapshots = mapSnapshots.value
  if (!snapshots.length) return null
  return snapshots.find(snapshot => snapshot.id === selectedSnapshotId.value) ?? snapshots[snapshots.length - 1]
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

function statusClass(status: string | undefined): string {
  if (!status) return ''
  if (status === '已结束' || status === 'completed') return 'status-badge--completed'
  if (status === '进行中' || status === 'in_progress') return 'status-badge--active'
  if (status === '等待中' || status === 'waiting') return 'status-badge--waiting'
  return ''
}

function statusLabel(status: string | undefined): string {
  if (!status) return '-'
  if (status === 'completed') return '已结束'
  if (status === 'in_progress') return '进行中'
  if (status === 'waiting') return '等待中'
  return status
}

function snapshotKindLabel(kind: string | null | undefined): string {
  if (kind === 'game_over') return '终局'
  return '回合结束'
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
    // ignore
  }
  return `match-${matchId}-replay.json`
}

function buildSessionDownloadUrl(uri: string): string {
  try {
    const url = new URL(uri, window.location.origin)
    if (
      url.pathname.startsWith('/v1/matches/')
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

function buildReplayDownloadUrl(uri: string): string {
  return buildSessionDownloadUrl(uri)
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

function inferArtifactFileName(artifact: MatchArtifactInfo): string {
  if (artifact.artifact_type === 'autosave_latest') {
    return `match-${matchId}-latest-autosave.json`
  }
  return `match-${matchId}-round-${String(artifact.round_number).padStart(4, '0')}-${artifact.snapshot_kind ?? 'snapshot'}.png`
}

function snapshotAlt(snapshot: MatchArtifactInfo): string {
  return `第 ${snapshot.round_number} 回合${snapshotKindLabel(snapshot.snapshot_kind)}地图截图`
}

function downloadArtifact(artifact: MatchArtifactInfo | null | undefined) {
  if (!artifact?.download_url) return
  const link = document.createElement('a')
  link.href = buildSessionDownloadUrl(artifact.download_url)
  link.download = inferArtifactFileName(artifact)
  link.rel = 'noopener'
  link.style.display = 'none'
  document.body.appendChild(link)
  link.click()
  link.remove()
}

function downloadLatestSave() {
  downloadArtifact(match.value?.latest_save)
}

function downloadSelectedSnapshot() {
  downloadArtifact(selectedSnapshot.value)
}

onMounted(async () => {
  loading.value = true
  try {
    const { data } = await getMatch(matchId, auth.sessionId)
    match.value = data
    const snapshots = data.map_snapshots ?? []
    selectedSnapshotId.value = snapshots.length ? snapshots[snapshots.length - 1].id : null
  } catch {
    match.value = null
    selectedSnapshotId.value = null
  }
  loading.value = false
})
</script>

<style scoped>
.page-header {
  margin-bottom: 24px;
}

.back-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-bottom: 4px;
}

.back-link__icon {
  width: 16px;
  height: 16px;
}

.page-title {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 8px 0;
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
  max-width: 200px;
  background: linear-gradient(90deg, var(--fcm-gold), transparent);
}

.info-card {
  margin-bottom: 20px;
  padding: 20px 24px;
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius-lg);
  box-shadow: var(--fcm-shadow-card);
}

.card-title {
  margin: 0 0 16px;
  font-size: 16px;
  font-weight: 600;
  color: var(--fcm-text-primary);
  display: flex;
  align-items: center;
  gap: 8px;
}

.room-code {
  font-family: monospace;
  font-weight: 600;
  font-size: 13px;
  background: var(--fcm-gold-light);
  padding: 2px 8px;
  border-radius: 4px;
}

.seed-code {
  font-family: monospace;
  font-size: 12px;
  background: rgba(43, 33, 23, 0.06);
  padding: 2px 6px;
  border-radius: 3px;
}

.cash-value {
  font-weight: 600;
  color: var(--fcm-gold);
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
}

.status-badge--waiting {
  color: var(--fcm-gold);
  background: var(--fcm-gold-light);
}
.status-badge--waiting .status-badge__dot {
  background: var(--fcm-gold);
}

.mod-tag {
  margin-right: 4px;
  margin-bottom: 2px;
}

/* ---- Player Cards ---- */
.player-cards-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 20px;
  margin-bottom: 20px;
}

@media (max-width: 1360px) {
  .player-cards-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}

@media (max-width: 900px) {
  .player-cards-grid { grid-template-columns: 1fr; }
}

.player-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius-lg);
  box-shadow: var(--fcm-shadow-card);
  overflow: hidden;
  transition: box-shadow 0.2s;
}

.player-card:hover {
  box-shadow: var(--fcm-shadow-card-hover);
}

.player-card--winner {
  border-color: var(--fcm-gold-border);
}

.player-card__color-bar {
  height: 4px;
}

.player-card__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 16px 20px 0;
  gap: 8px;
}

.player-card__identity {
  display: flex;
  align-items: center;
  gap: 12px;
}

.player-card__logo {
  width: 52px;
  height: 52px;
  border-radius: var(--fcm-radius);
  object-fit: cover;
  border: 2px solid var(--fcm-field-border);
  flex-shrink: 0;
}

.player-card--winner .player-card__logo {
  border-color: var(--fcm-gold-border);
}

.player-card__name {
  font-size: 15px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.player-card__id {
  font-size: 11px;
  color: var(--fcm-text-muted);
  margin-top: 2px;
  font-family: monospace;
}

.result-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 600;
  padding: 4px 10px;
  border-radius: 999px;
}

.result-badge__icon {
  width: 14px;
  height: 14px;
}

.result-badge--win {
  color: var(--fcm-gold);
  background: var(--fcm-gold-light);
  border: 1px solid var(--fcm-gold-border);
}

.result-badge--forfeit {
  color: var(--fcm-primary);
  background: var(--fcm-primary-light);
}

.player-card__cash {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 12px 20px 16px;
}

.player-card__cash-label {
  font-size: 13px;
  color: var(--fcm-text-muted);
}

.player-card__cash-value {
  font-family: var(--fcm-font-display);
  font-size: 28px;
  font-weight: 700;
  color: var(--fcm-gold);
  letter-spacing: -0.02em;
}

.detail-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 8px;
  padding: 0 16px 16px;
}

.detail-section {
  padding: 12px;
  background: var(--fcm-surface-alt);
  border-radius: var(--fcm-radius);
}

.section-title {
  margin: 0 0 8px;
  font-size: 12px;
  font-weight: 600;
  color: var(--fcm-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
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
  color: var(--fcm-text-muted);
  opacity: 0.7;
}

/* ---- Stats Matrix ---- */
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

.player-column-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.player-logo-sm {
  width: 20px;
  height: 20px;
  border-radius: 3px;
  object-fit: cover;
}

.player-column-name {
  max-width: 84px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 12px;
}

.matrix-table :deep(.el-table__cell) {
  vertical-align: middle;
}

.replay-info {
  margin-top: 4px;
}

.artifact-info {
  margin-top: 4px;
}

.artifact-action {
  margin-top: 16px;
}

.button-icon {
  width: 15px;
  height: 15px;
  margin-right: 6px;
}

.snapshot-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.snapshot-header .card-title {
  margin-bottom: 0;
}

.snapshot-header__meta {
  font-size: 12px;
  color: var(--fcm-text-muted);
}

.snapshot-viewer {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 220px;
  gap: 16px;
}

.snapshot-stage {
  min-height: 360px;
  max-height: 620px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: auto;
  background: var(--fcm-surface-alt);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
}

.snapshot-image {
  display: block;
  max-width: 100%;
  max-height: 600px;
  image-rendering: auto;
}

.snapshot-panel {
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.snapshot-panel__actions {
  display: flex;
  justify-content: flex-end;
}

.snapshot-list {
  max-height: 560px;
  overflow-y: auto;
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
}

.snapshot-item {
  width: 100%;
  display: grid;
  grid-template-columns: 54px 1fr auto;
  gap: 8px;
  align-items: center;
  padding: 9px 10px;
  border: 0;
  border-bottom: 1px solid var(--fcm-field-border);
  background: var(--fcm-surface);
  color: var(--fcm-text-primary);
  text-align: left;
  cursor: pointer;
}

.snapshot-item:last-child {
  border-bottom: 0;
}

.snapshot-item:hover,
.snapshot-item--active {
  background: var(--fcm-primary-light);
}

.snapshot-item__round {
  font-family: monospace;
  font-size: 12px;
  font-weight: 700;
}

.snapshot-item__kind,
.snapshot-item__size {
  font-size: 12px;
  color: var(--fcm-text-muted);
}

@media (max-width: 900px) {
  .snapshot-viewer {
    grid-template-columns: 1fr;
  }

  .snapshot-stage {
    min-height: 260px;
  }

  .snapshot-panel__actions {
    justify-content: flex-start;
  }
}
</style>
