<template>
  <div class="auth-page">
    <div class="fcm-vignette" />
    <div class="auth-card" :style="{ width }">
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
  justify-content: center;
  align-items: center;
  min-height: 100vh;
  position: relative;
}

.auth-card {
  background: var(--fcm-surface);
  border: 1px solid var(--fcm-dialog-border);
  border-radius: var(--fcm-radius);
  box-shadow: var(--fcm-shadow-dialog);
  position: relative;
  z-index: 1;
}

.auth-card__inner {
  border: 1px solid var(--fcm-accent-line);
  border-radius: var(--fcm-radius);
  margin: 6px;
  padding: 32px 28px 24px;
}

.auth-card__title {
  margin: 0 0 12px;
  font-size: 20px;
  font-weight: 700;
  text-align: center;
  color: var(--fcm-text-primary);
}

.auth-card__line {
  height: 2px;
  background: var(--fcm-accent-line);
  margin-bottom: 24px;
}

.auth-card__body {
  /* slot content */
}

.auth-card__footer {
  text-align: center;
  margin-top: 16px;
  color: var(--fcm-text-muted);
  font-size: 14px;
}
</style>
