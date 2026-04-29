<template>
  <AppLayout>
    <div class="home">
      <!-- Hero Section -->
      <section class="hero">
        <div class="hero__bg" />
        <div class="hero__content">
          <img src="/logo.png" alt="Food Chain Magnate" class="hero__logo" />

          <blockquote class="hero__quote">
            <div class="hero__quote-mark">&ldquo;</div>
            <p class="hero__quote-text">
              柠檬水？他们要柠檬水？这世界怎么了！我要在所有频道每隔十五分钟投放汉堡广告。我们是"经典汉堡之家"，不是什么嬉皮养生馆。还有，在街角那栋新房子旁边立块广告牌，让他们坐在花园里每一秒都在想喝啤酒。
            </p>
            <p class="hero__quote-text">
              新来的管理培训生在 CEO 面前瑟瑟发抖，试图礼貌地指出……"什么叫人手不够？人事总监归你管。去招人！去培训！但记住，别给他们开真正的工资。我开公司不是来做慈善的。还有，把那个打折经理炒了，她只会花我的钱。从现在起，我们卖精品汉堡——一样的东西，两倍的价格。把我的营销总监叫进来！"
            </p>
          </blockquote>

          <p class="hero__desc">
            Food Chain Magnate 是一款以建立快餐连锁帝国为主题的重策桌游。通过卡牌驱动的人力资源管理系统来发展你的公司，在不断变化的城市地图上与对手展开激烈竞争。
          </p>

          <div class="hero__tags">
            <span class="hero__tag">2-6 名玩家</span>
            <span class="hero__tag-sep">|</span>
            <span class="hero__tag">在线对战</span>
            <span class="hero__tag-sep">|</span>
            <span class="hero__tag">策略桌游</span>
          </div>

          <button class="hero__btn" @click="openGame">
            <span>进入游戏</span>
            <svg class="hero__btn-arrow" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z" clip-rule="evenodd"/></svg>
          </button>
        </div>
      </section>

      <!-- Features Section -->
      <section class="features">
        <h2 class="section-title">
          <span class="section-title__line" />
          <span class="section-title__text">游戏特色</span>
          <span class="section-title__line" />
        </h2>

        <div class="features__grid">
          <div class="feature-card">
            <div class="feature-card__icon-wrap">
              <svg class="feature-card__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/></svg>
            </div>
            <h3 class="feature-card__title">策略经营</h3>
            <p class="feature-card__desc">管理你的快餐公司，建立金字塔式的组织架构。招聘、培训员工，让 CEO 统领全局，从管理培训生到高级副总裁层层晋升。</p>
          </div>

          <div class="feature-card">
            <div class="feature-card__icon-wrap">
              <svg class="feature-card__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3.75 3v11.25A2.25 2.25 0 006 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0118 16.5h-2.25m-7.5 0h7.5m-7.5 0l-1 3m8.5-3l1 3m0 0l.5 1.5m-.5-1.5h-9.5m0 0l-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"/></svg>
            </div>
            <h3 class="feature-card__title">激烈竞争</h3>
            <p class="feature-card__desc">在城市地图上与对手争夺市场份额。通过广告牌、传单、广播电台等方式创造需求，用价格战和营销策略碾压竞争对手。</p>
          </div>

          <div class="feature-card">
            <div class="feature-card__icon-wrap">
              <svg class="feature-card__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456zM16.894 20.567L16.5 21.75l-.394-1.183a2.25 2.25 0 00-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 001.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 001.423 1.423l1.183.394-1.183.394a2.25 2.25 0 00-1.423 1.423z"/></svg>
            </div>
            <h3 class="feature-card__title">丰富扩展</h3>
            <p class="feature-card__desc">支持咖啡、寿司、泡菜、面条等多种扩展模组。每局游戏都可以自由组合模组，创造独一无二的对战体验。</p>
          </div>
        </div>
      </section>

      <!-- Restaurant Brands -->
      <section class="brands">
        <h2 class="section-title">
          <span class="section-title__line" />
          <span class="section-title__text">快餐帝国</span>
          <span class="section-title__line" />
        </h2>

        <div class="brands__grid">
          <div v-for="brand in restaurants" :key="brand.key" class="brand-card" :title="brand.label">
            <img :src="brand.logo" :alt="brand.label" class="brand-card__logo" />
            <span class="brand-card__name">{{ brand.label }}</span>
          </div>
        </div>
      </section>

      <!-- Footer -->
      <footer class="site-footer">
        <div class="site-footer__inner">
          <div class="site-footer__brand">
            <span class="site-footer__title">Food Chain Magnate</span>
            <span class="site-footer__sub">在线对战平台</span>
          </div>
          <div class="site-footer__links">
            <span class="site-footer__credit">致谢 Splotter Spellen 出版了这款游戏</span>
            <span class="site-footer__sep">&middot;</span>
            <span class="site-footer__version">v0.4.2</span>
          </div>
        </div>
      </footer>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import AppLayout from '../components/AppLayout.vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const restaurants = [
  { key: 'fried_geese_donkey', label: '驴肉&烧鹅', logo: '/restaurant-logos/fried_geese_donkey.png' },
  { key: 'gluttony_inc_burgers', label: '饕餮汉堡', logo: '/restaurant-logos/gluttony_inc_burgers.png' },
  { key: 'golden_duck_diner', label: '金鸭小馆', logo: '/restaurant-logos/golden_duck_diner.png' },
  { key: 'santa_maria_pizza', label: '圣玛丽亚披萨', logo: '/restaurant-logos/santa_maria_pizza.png' },
  { key: 'xango_blues_bar', label: '尚戈蓝调酒吧', logo: '/restaurant-logos/xango_blues_bar.png' },
  { key: 'siap_faji', label: '好味来', logo: '/restaurant-logos/siap_faji.png' },
]

const router = useRouter()
const auth = useAuthStore()

function openGame() {
  if (!auth.isLoggedIn) {
    router.push({ name: 'login', query: { redirect: '/game' } })
    return
  }
  window.open(`/game/index.html?t=${Date.now()}&profile_online_sync=1`, '_blank')
}
</script>

<style scoped>
.home {
  margin: -32px calc(50% - 50vw);
  background: var(--fcm-page-bg);
}

/* ---- Hero ---- */
.hero {
  position: relative;
  padding: 64px 28px 56px;
  overflow: hidden;
}

.hero__bg {
  display: none;
}

.hero__content {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  max-width: 680px;
  margin: 0 auto;
}

.hero__logo {
  max-width: 360px;
  width: 100%;
  height: auto;
  filter: drop-shadow(0 4px 16px rgba(18, 13, 8, 0.15));
  margin-bottom: 32px;
}

.hero__quote {
  position: relative;
  margin: 0 0 32px;
  padding: 24px 28px 24px 36px;
  background:
    linear-gradient(135deg, rgba(250, 245, 232, 0.95) 0%, rgba(247, 240, 219, 0.9) 100%);
  border: 1px solid rgba(201, 160, 32, 0.25);
  border-left: 4px solid var(--fcm-gold);
  border-radius: 2px var(--fcm-radius) var(--fcm-radius) 2px;
  box-shadow: var(--fcm-shadow-card);
  text-align: left;
  max-width: 560px;
}

.hero__quote-mark {
  position: absolute;
  top: 8px;
  left: 12px;
  font-family: var(--fcm-font-display);
  font-size: 48px;
  line-height: 1;
  color: var(--fcm-gold);
  opacity: 0.3;
  pointer-events: none;
}

.hero__quote-text {
  margin: 0 0 12px;
  font-size: 13px;
  line-height: 2;
  color: var(--fcm-text-muted);
  font-style: italic;
}

.hero__quote-text:last-child {
  margin-bottom: 0;
}

.hero__desc {
  margin: 0 0 24px;
  font-size: 15px;
  line-height: 1.8;
  color: var(--fcm-text-muted);
  max-width: 480px;
}

.hero__tags {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 36px;
  font-size: 13px;
  color: var(--fcm-text-muted);
  letter-spacing: 0.05em;
}

.hero__tag-sep {
  color: var(--fcm-gold);
  opacity: 0.5;
}

.hero__btn {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 14px 48px;
  font-size: 16px;
  font-weight: 600;
  font-family: var(--fcm-font-body);
  color: var(--fcm-btn-text);
  background: linear-gradient(135deg, var(--fcm-primary) 0%, var(--fcm-primary-hover) 100%);
  border: 2px solid rgba(201, 160, 32, 0.3);
  border-radius: var(--fcm-radius);
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 4px 16px rgba(186, 59, 46, 0.25);
}

.hero__btn:hover {
  background: linear-gradient(135deg, var(--fcm-primary-hover) 0%, var(--fcm-primary-pressed) 100%);
  border-color: rgba(201, 160, 32, 0.5);
  box-shadow: 0 6px 24px rgba(186, 59, 46, 0.35);
  transform: translateY(-1px);
}

.hero__btn:active {
  transform: translateY(0);
  box-shadow: 0 2px 8px rgba(186, 59, 46, 0.25);
}

.hero__btn-arrow {
  width: 18px;
  height: 18px;
  transition: transform 0.2s;
}

.hero__btn:hover .hero__btn-arrow {
  transform: translateX(3px);
}

/* ---- Section Title ---- */
.section-title {
  display: flex;
  align-items: center;
  gap: 20px;
  margin: 0 0 36px;
}

.section-title__line {
  flex: 1;
  height: 1px;
  background: linear-gradient(90deg, transparent, var(--fcm-gold-border), transparent);
}

.section-title__text {
  font-family: var(--fcm-font-display);
  font-size: 22px;
  font-weight: 600;
  color: var(--fcm-text-primary);
  letter-spacing: 0.08em;
  white-space: nowrap;
}

/* ---- Features ---- */
.features {
  padding: 56px 28px;
  max-width: 960px;
  margin: 0 auto;
}

.features__grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 24px;
}

.feature-card {
  background: linear-gradient(180deg, #fff6dc 0%, #f3e3bb 100%);
  border: 1px solid rgba(43, 33, 23, 0.34);
  border-radius: var(--fcm-radius-lg);
  padding: 32px 24px;
  text-align: center;
  transition: transform 0.2s, box-shadow 0.2s;
  box-shadow: var(--fcm-shadow-card), inset 0 1px 0 rgba(255, 255, 255, 0.65);
}

.feature-card:hover {
  transform: translateY(-4px);
  box-shadow: var(--fcm-shadow-card-hover);
}

.feature-card__icon-wrap {
  width: 56px;
  height: 56px;
  margin: 0 auto 20px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--fcm-radius-lg);
  background: #ead596;
  border: 1px solid rgba(43, 33, 23, 0.18);
  color: var(--fcm-gold);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.45), 0 2px 6px rgba(18, 13, 8, 0.08);
}

.feature-card__icon {
  width: 28px;
  height: 28px;
}

.feature-card__title {
  margin: 0 0 12px;
  font-size: 17px;
  font-weight: 700;
  color: var(--fcm-text-primary);
}

.feature-card__desc {
  margin: 0;
  font-size: 13px;
  line-height: 1.8;
  color: var(--fcm-text-muted);
}

/* ---- Restaurant Brands ---- */
.brands {
  padding: 48px 28px 56px;
  max-width: 840px;
  margin: 0 auto;
}

.brands__grid {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 20px;
}

.brand-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 16px 8px;
  border-radius: var(--fcm-radius-lg);
  transition: transform 0.2s;
  cursor: default;
}

.brand-card:hover {
  transform: scale(1.06);
}

.brand-card__logo {
  width: 72px;
  height: 72px;
  border-radius: var(--fcm-radius-lg);
  object-fit: contain;
  padding: 8px;
  background: #fff6dc;
  border: 2px solid rgba(43, 33, 23, 0.32);
  box-shadow: var(--fcm-shadow-card), inset 0 1px 0 rgba(255, 255, 255, 0.7);
  transition: border-color 0.2s, background-color 0.2s;
}

.brand-card:hover .brand-card__logo {
  background: #fff0c1;
  border-color: var(--fcm-gold-border);
}

.brand-card__name {
  font-size: 12px;
  font-weight: 500;
  color: var(--fcm-text-muted);
  text-align: center;
  line-height: 1.3;
}

/* ---- Footer ---- */
.site-footer {
  background: var(--fcm-dark);
  padding: 28px;
  margin-top: 24px;
}

.site-footer__inner {
  max-width: var(--fcm-max-width);
  margin: 0 auto;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.site-footer__brand {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.site-footer__title {
  font-family: var(--fcm-font-display);
  font-size: 15px;
  font-weight: 600;
  color: rgba(247, 237, 209, 0.8);
}

.site-footer__sub {
  font-size: 12px;
  color: rgba(247, 237, 209, 0.4);
}

.site-footer__links {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 12px;
  color: rgba(247, 237, 209, 0.4);
}

.site-footer__sep {
  opacity: 0.3;
}

.site-footer__credit {
  color: rgba(247, 237, 209, 0.5);
}

.site-footer__version {
  font-family: monospace;
}
</style>
