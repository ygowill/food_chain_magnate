# 启发式人机对手：Bot 基线与实现顺序

本文聚焦搜索策略的实现顺序，以及 RandomLegalBot / GreedyBot 的定位。StrategyBot 与搜索增强分别见 [StrategyBot](strategy_bot.md) 和 [OSLA / Beam / MCTS](search_osla_beam_mcts.md)。

## 11. 搜索策略

### 11.1 实现顺序

1. `RandomLegalBot`
2. `ScriptBot`
3. `GreedyBot`（流程探针，不作为主力 AI）
4. `StrategyBot`
5. `OSLABot`
6. `BeamBot`
7. `MCTSBot`

首版没有直接上纯随机 rollout 的 MCTS；当前已接入的是启发式引导、以候选和 forward simulation 为核心的树搜索骨架。

### 11.2 RandomLegalBot

用途：

- 验证 action registry 接入。
- 自对弈压力测试。
- 避免 Bot controller 软锁。

要求：

- 只从 `get_player_initiatable_actions()` 与候选参数生成器中选择。
- 对需要参数的 action 必须有最小合法参数生成器。
- 若无真实动作，选择 `skip_sub_phase` 或 `skip`。

### 11.3 GreedyBot（流程探针）

GreedyBot 的流程仍保留：

1. 识别决策点。
2. 生成 topN 候选。
3. 对每个候选 fork engine 执行。
4. 让 auto-advance 跑到稳定点或指定 horizon。
5. 用 Evaluator 打分。
6. 选择最高分合法命令。

但验收范围只到 smoke baseline：

- 固定 seed 下 deterministic。
- 能跑过关键阶段并暴露候选/模拟/评分链路问题。
- 不以长期胜率、完整局强度或稳定经济路线作为验收目标。
