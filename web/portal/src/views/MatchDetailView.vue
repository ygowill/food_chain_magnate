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

// TODO: 删除测试数据
const MOCK_DETAILS: Record<string, MatchDetail> = {
  '1': {
    match_id: '1',
    room_code: 'ABC123',
    status: '已结束',
    player_count: 4,
    started_at: '2026-02-25T14:00:00Z',
    ended_at: '2026-02-25T17:30:00Z',
    duration_sec: 12600,
    seed: '48291037',
    game_version: '0.4.2',
    schema_version: '2',
    final_hash: null,
    has_replay: true,
    summary: {
      modules: ['base_rules', 'base_employees', 'base_products', 'ketchup_mechanism', 'coffee', 'new_milestones'],
      round_number: 18,
      bank_total: 45,
      bank_broke_count: 1,
      bank_reserve_added: 50,
      marketing_count: 6,
    },
    participants: [
      {
        user_id: 'a1b2c3d4e5f6',
        display_name: '老王',
        restaurant_logo_id: 0,
        role: 'player',
        seat_index: 0,
        result: 'win',
        score: {
          cash: 320,
          restaurants: 3,
          forfeited: false,
          employees: ['ceo', 'burger_cook', 'pizza_cook', 'errand_boy', 'cart_operator', 'burger_cook', 'management_trainee', 'kitchen_trainee', 'pricing_manager', 'discount_manager', 'waitress', 'trainer'],
          milestones: ['first_burger_sold', 'first_pizza_sold'],
          inventory: { burger: 3, pizza: 2, coffee: 1, soda: 1 },
          marketing_campaigns: 2,
          stats: {
            marketing_actions: 9,
            marketing_by_type: { billboard: 4, mailbox: 2, radio: 1 },
            hired_employees: 8,
            trained_employees: 5,
            metrics: { house_built: 2, restaurant_built: 1, procurement_actions: 6 },
            produced: { burger: 21, pizza: 8, coffee: 3, soda: 6, beer: 2 },
            sold: { burger: 16, pizza: 5, coffee: 2, coke: 4, beer: 1 },
          },
        },
      },
      {
        user_id: 'f6e5d4c3b2a1',
        display_name: '小李',
        restaurant_logo_id: 3,
        role: 'player',
        seat_index: 1,
        result: 'lose',
        score: {
          cash: 180,
          restaurants: 2,
          forfeited: false,
          employees: ['ceo', 'truck_driver', 'burger_cook', 'errand_boy', 'waitress', 'management_trainee', 'hr_director', 'regional_manager'],
          milestones: ['first_lemonade_sold'],
          inventory: { lemonade: 4, burger: 1, beer: 1 },
          marketing_campaigns: 1,
          stats: {
            marketing_actions: 6,
            marketing_by_type: { billboard: 2, mailbox: 3 },
            hired_employees: 6,
            trained_employees: 3,
            metrics: { house_built: 1, restaurant_built: 2, procurement_actions: 5 },
            produced: { lemonade: 18, burger: 6, beer: 3 },
            sold: { lemonade: 13, burger: 5, beer: 2 },
          },
        },
      },
      {
        user_id: '1122334455aa',
        display_name: '阿陈',
        restaurant_logo_id: 5,
        role: 'player',
        seat_index: 2,
        result: 'lose',
        score: {
          cash: 95,
          restaurants: 1,
          forfeited: false,
          employees: ['ceo', 'pizza_cook', 'errand_boy', 'cart_operator', 'kitchen_trainee', 'brand_director'],
          milestones: [],
          inventory: { pizza: 5 },
          marketing_campaigns: 0,
          stats: {
            marketing_actions: 3,
            marketing_by_type: { billboard: 1, mailbox: 1 },
            hired_employees: 4,
            trained_employees: 2,
            metrics: { house_built: 1, procurement_actions: 2 },
            produced: { pizza: 11 },
            sold: { pizza: 6 },
          },
        },
      },
      {
        user_id: 'bbccddee7788',
        display_name: '赵老板',
        restaurant_logo_key: 'restaurant_logo_xango_blues_bar',
        role: 'player',
        seat_index: 3,
        result: 'lose',
        score: {
          cash: 0,
          restaurants: 2,
          forfeited: true,
          employees: ['ceo', 'burger_cook', 'truck_driver', 'errand_boy', 'waitress'],
          milestones: [],
          inventory: {},
          marketing_campaigns: 0,
          stats: {
            marketing_actions: 1,
            marketing_by_type: { billboard: 0, mailbox: 0 },
            hired_employees: 2,
            trained_employees: 0,
            metrics: { house_built: 0, restaurant_built: 1 },
            produced: { burger: 4, lemonade: 2 },
            sold: { burger: 1, lemonade: 1 },
          },
        },
      },
    ],
  },
  '2': {
    match_id: '2',
    room_code: 'XYZ789',
    status: '进行中',
    player_count: 3,
    started_at: '2026-02-27T09:15:00Z',
    ended_at: null,
    duration_sec: null,
    seed: '77120394',
    game_version: '0.4.2',
    schema_version: '2',
    final_hash: null,
    has_replay: false,
    summary: {
      modules: ['base_rules', 'base_employees', 'coffee'],
      round_number: 7,
      bank_total: 120,
      bank_broke_count: 0,
      bank_reserve_added: 0,
      marketing_count: 2,
    },
    participants: [
      {
        user_id: 'aabbccdd1122',
        display_name: '测试玩家',
        restaurant_logo_id: 2,
        role: 'player',
        seat_index: 0,
        result: null,
        score: null,
      },
    ],
  },
}

const MOCK_REPLAYS: Record<string, ReplayInfo> = {
  '1': {
    match_id: '1',
    storage_uri: '/replays/archive_match_demo_20260228.json',
    checksum: '026f34144c7a259022c412c33499837b9d185bc031c0a30905eac509ea3cb72f',
    size_bytes: 70262,
  },
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
    if (MOCK_REPLAYS[matchId]) {
      replay.value = MOCK_REPLAYS[matchId]
    }
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
    // fallback to local mock when backend is unavailable
  }
  if (!match.value && MOCK_DETAILS[matchId]) {
    match.value = MOCK_DETAILS[matchId]
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
