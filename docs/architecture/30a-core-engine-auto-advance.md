# GameEngine：自动推进（AutoAdvance）与阶段门禁

本项目存在一类“无需玩家交互、但必须确定性可重放”的推进逻辑：例如结算阶段的自动跳过、以及某些阶段在条件满足后自动进入下一阶段。

这些逻辑统一由 `AutoAdvance` 执行，并且会在：

- 运行时命令执行后追加执行（确保玩家只需做“有意义的输入”）
- 回放/倒带重放时同样执行（确保 determinism）

## 入口与落点

- `core/engine/game_engine/auto_advance.gd`：`AutoAdvance`（门面）
- `core/engine/game_engine/auto_advance_impl.gd`：循环 drain（max_steps 防死循环）
- `core/engine/game_engine/auto_advance_try_step.gd`：单步推进规则集合
- 调用方：
  - `core/engine/game_engine/command_runner.gd`：每条命令后 `_drain_auto_advances(...)`
  - `core/engine/game_engine/replay.gd`：重放时 `AutoAdvance.drain(...)`

## 为什么必须独立于 UI

AutoAdvance 的约束是：

- 只依赖 `GameState` 与 registry（PhaseManager/ActionRegistry）
- 不依赖 UI、真实时间或外部 IO
- 必须在 replay/rewind 场景中得到一致结果

因此 auto-advance 不允许“UI 侧偷跑推进”或“只在某个界面逻辑里推进”。

## 关键规则（以当前实现为准）

AutoAdvance（单步）大致包括：

- Round 1 的阶段自动跳过/自动落地（例如某些早期阶段在无交互时直接推进）
- `Restructuring`：当 round_state 标记 finalized 且无 pending 阻断时自动 `advance_phase`
- `OrderOfBusiness`：当顺序 finalized 且无 pending 阻断时自动进入 `Working`
- 结算阶段自动跳过（默认对 `Dinnertime/Marketing/Cleanup` 生效；若存在 sub_phase 则走 `advance_sub_phase`）
- `Working`：当当前玩家在当前子阶段无“可启动的真实动作”时自动推进到下一子阶段
  - 并且会先尝试自动补完“可无参补完”的强制动作（避免其阻断推进）

## 阶段门禁：pending_phase_actions

某些阶段会通过 `round_state.pending_phase_actions` 阻断 auto-advance 或阶段推进（例如 Cleanup 的“必须先选择保留哪些库存”）。

相关工具与检查：

- `core/utils/round_state_pending_phase_actions.gd`
- `core/engine/game_engine/auto_advance_phase_blocking.gd`

约定：任何会在阶段边界引入“必须玩家确认/选择”的逻辑，应使用该门禁机制，避免阶段被自动跳过。

