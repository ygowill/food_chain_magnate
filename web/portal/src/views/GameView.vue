<template>
  <AppLayout>
    <div class="hero">
      <img src="/logo.png" alt="Food Chain Magnate" class="hero__logo" />
      <div class="hero__line" />
      <p class="hero__flavor">
        "柠檬水？他们要柠檬水？这世界怎么了！我要在所有频道每隔十五分钟投放汉堡广告。我们是'经典汉堡之家'，不是什么嬉皮养生馆。还有，在街角那栋新房子旁边立块广告牌，让他们坐在花园里每一秒都在想喝啤酒。"新来的管理培训生在 CEO 面前瑟瑟发抖，试图礼貌地指出……"什么叫人手不够？人事总监归你管。去招人！去培训！但记住，别给他们开真正的工资。我开公司不是来做慈善的。还有，把那个打折经理炒了，她只会花我的钱。从现在起，我们卖精品汉堡——一样的东西，两倍的价格。把我的营销总监叫进来！"
      </p>
      <p class="hero__desc">
        Food Chain Magnate 是一款以建立快餐连锁帝国为主题的重策桌游。游戏核心是通过卡牌驱动的人力资源管理系统来发展你的公司——在不断变化的城市地图上，与对手在采购、营销和销售环节展开竞争，同时在人才市场争夺关键员工。
      </p>
      <div class="hero__tags">
        <span class="hero__tag">2-6 名玩家</span>
        <span class="hero__tag">在线对战</span>
      </div>
      <button class="hero__btn" @click="openGame">进入游戏</button>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import AppLayout from '../components/AppLayout.vue'

function openGame() {
  window.open(`/game/index.html?t=${Date.now()}&profile_online_sync=1`, '_blank')
}
</script>

<style scoped>
.hero {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 48px 20px 40px;
}

.hero__logo {
  max-width: 400px;
  width: 100%;
  height: auto;
}

.hero__line {
  width: 48px;
  height: 3px;
  background: var(--fcm-primary);
  margin: 16px 0 20px;
  border-radius: 2px;
}

.hero__flavor {
  margin: 16px 0 20px;
  font-size: 13px;
  line-height: 1.9;
  color: var(--fcm-text-muted);
  max-width: 480px;
  font-style: italic;
  opacity: 0.75;
}

.hero__desc {
  margin: 0 0 24px;
  font-size: 15px;
  line-height: 1.8;
  color: var(--fcm-text-muted);
  max-width: 420px;
}

.hero__tags {
  display: flex;
  gap: 10px;
  margin-bottom: 36px;
}

.hero__tag {
  font-size: 12px;
  color: var(--fcm-text-muted);
  border: 1px solid var(--fcm-field-border);
  border-radius: var(--fcm-radius);
  padding: 3px 10px;
  background: var(--fcm-surface);
}

.hero__btn {
  padding: 12px 48px;
  font-size: 16px;
  font-weight: 500;
  font-family: inherit;
  color: var(--fcm-btn-text);
  background: var(--fcm-primary);
  border: none;
  border-radius: var(--fcm-radius);
  cursor: pointer;
  transition: background 0.15s;
}

.hero__btn:hover {
  background: var(--fcm-primary-hover);
}

.hero__btn:active {
  background: var(--fcm-primary-pressed);
}
</style>
