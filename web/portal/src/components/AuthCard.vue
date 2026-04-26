<template>
  <div class="auth-page">
    <div class="auth-page__bg" />
    <div class="auth-card-wrap" :style="{ width }">
      <img src="/logo.png" alt="Food Chain Magnate" class="auth-card__logo" />
      <div class="auth-card">
        <div class="auth-card__inner">
          <h2 class="auth-card__title">{{ title }}</h2>
          <div class="auth-card__line" />
          <div class="auth-card__body">
            <slot />
          </div>
          <div v-if="$slots.footer" class="auth-card__footer">
            <slot name="footer" />
          </div>
        </div>
      </div>
    </div>
    <div class="auth-page__footer">
      Food Chain Magnate &middot; 在线对战平台
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  title: string
  width?: string
}>()
</script>

<style scoped>
.auth-page {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  position: relative;
  padding: 40px 20px;
}

.auth-page__bg {
  position: fixed;
  inset: 0;
  pointer-events: none;
  background:
    radial-gradient(ellipse at 30% 20%, rgba(201, 160, 32, 0.06) 0%, transparent 60%),
    radial-gradient(ellipse at 70% 80%, rgba(186, 59, 46, 0.05) 0%, transparent 60%),
    repeating-conic-gradient(rgba(43, 33, 23, 0.025) 0% 25%, transparent 0% 50%) 0 0 / 48px 48px,
    radial-gradient(ellipse at center, transparent 40%, rgba(18, 13, 8, 0.12) 100%);
  z-index: 0;
}

.auth-card-wrap {
  position: relative;
  z-index: 1;
  animation: card-enter 0.4s ease-out;
}

@keyframes card-enter {
  from {
    opacity: 0;
    transform: translateY(16px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.auth-card__logo {
  position: relative;
  z-index: 2;
  display: block;
  width: 400px;
  max-width: 85%;
  height: auto;
  margin: 0 auto -36px;
  filter: drop-shadow(0 4px 16px rgba(18, 13, 8, 0.18));
}

.auth-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-dialog-border);
  border-radius: var(--fcm-radius-lg);
  box-shadow: var(--fcm-shadow-elevated);
  position: relative;
}

.auth-card__inner {
  border: 1px solid var(--fcm-gold-border);
  border-radius: calc(var(--fcm-radius-lg) - 2px);
  margin: 6px;
  padding: 48px 32px 28px;
}

.auth-card__title {
  margin: 0 0 12px;
  font-family: var(--fcm-font-display);
  font-size: 24px;
  font-weight: 700;
  text-align: center;
  color: var(--fcm-text-primary);
  letter-spacing: 0.02em;
}

.auth-card__line {
  height: 2px;
  background: linear-gradient(90deg, transparent, var(--fcm-gold-border), transparent);
  margin-bottom: 28px;
}

.auth-card__footer {
  text-align: center;
  margin-top: 20px;
  padding-top: 16px;
  border-top: 1px solid rgba(43, 33, 23, 0.1);
  color: var(--fcm-text-muted);
  font-size: 14px;
}

.auth-page__footer {
  position: relative;
  z-index: 1;
  margin-top: 32px;
  font-size: 12px;
  color: var(--fcm-text-muted);
  opacity: 0.6;
  font-family: var(--fcm-font-display);
  letter-spacing: 0.05em;
}
</style>
