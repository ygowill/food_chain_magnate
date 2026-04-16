# 联机恢复房热路径重构方案（2026-04-16）

状态：设计确认中，未实施。

本文落盘本轮结论，目标不是立即修补某个卡点，而是明确：

- 哪些现有修复值得保留；
- 哪些设计假设需要推倒；
- 联机恢复房 / 完整历史 / 日志时间线 / UI 同步 应如何重新分层；
- 完整方案做完后，预计能把时延降到什么范围；
- 如何避免“这边降了，那边又涨了”的成本转移。

相关背景文档：

- `docs/online/online_resume_fastload_full_history_design_2026-04-14.md`
- `docs/online/online_session_resume_redesign_2026-04-03.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/42-gameplay-replay-timelines.md`

---

## 实施进展（本次已落地）

### 已落地

- [x] **阶段 1：把完整历史维护移出 live command 热路径**
  - live command 到达后，不再同步推进 `full_replay_engine`
  - 改为仅记录 live tail，完整历史在历史查看 / timeline 构建前按需补齐
  - 代码：
    - `autoload/net_client_online_resume_support.gd`
    - `autoload/online_resume_session_state.gd`
    - `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`
    - `autoload/net_client.gd`
    - `autoload/net_client_internal.gd`
    - `autoload/net_client/client.gd`
  - 测试：
    - `core/tests/online_resume_full_history_tail_append_test.gd`

- [x] **阶段 2：恢复房改为两阶段进入**
  - 恢复房快启动不再等待 `full_replay_ready + timeline_ready`
  - 完整历史转为后台加载，不再 gate 进入对局
  - 代码：
    - `autoload/online_match_bootstrap.gd`
    - `autoload/online_session_coordinator.gd`
  - 测试：
    - `core/tests/online_match_bootstrap_resume_history_gate_test.gd`
    - `core/tests/game_startup_online_resume_controller_test.gd`

- [x] **阶段 3（第一步）：日志时间线 UI 批量更新**
  - `head/cursor` 更新改为批量接口，避免 live command 每次在日志面板上重复做两轮 item 状态扫描
  - 代码：
    - `ui/components/game_log/game_log_panel.gd`
    - `ui/scenes/game/timeline/ui_state_support.gd`
  - 测试：
    - `ui/scenes/tests/timeline_ui_state_support_batch_update_test.gd`

### 仍待继续收敛

- [ ] **阶段 3（剩余部分）**
  - `panel_controller.sync`
  - `map_view.set_game_state`
  - 其它更细粒度的 dirty-driven UI 收敛

当前状态说明：

- 本次已经把最伤 live 热路径的“完整历史同步推进”拆出；
- 已经取消恢复房进局对完整历史 cache 的 gate；
- 已经对日志时间线状态同步做了第一步降耗；
- 但更细粒度的 panel/map 增量刷新仍可继续做，以进一步压低 `ui.online_sync.total`。

### 本次验证

- 编译检查：
  - `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`
- 必测场景：
  - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`
- 结果：
  - `CheckCompile PASS`
  - `GameSmokeTest PASS`
  - `AllTests PASS (357/357)`

---

## 1. 本轮复盘范围

### 1.1 提交范围

本轮阅读并评估了以下提交：

- `15657256df26e8424da50885049cebf509c58711` `fix(ui): reduce live log rebuild work`
- `51d607a4a6c4c24dc5d2f5efd8b984ba531a1ee8` `feat(online): add sync performance tracing`
- `cbf958d77d4397f228f79a7ba2aac26151675b0a` `fix(timeline): prebuild resume history timeline cache`
- `cf3df6792df6d31237ee303db6b4705493bbd5d0` `fix(online): gate resume bootstrap on full history cache`
- `f02127bf3f93ddfaf48b0c26cb763723d5e87423` `fix(online): reuse resume timeline cache and lighten append path`
- `b0de7ff85e1e19c2a94bc464102dd4a89fedd2fe` `fix(online): defer resume timeline cache refresh`
- `1f965791e7633b491650895bb1f29d09fb0d2e14` `fix(online): remove hot-path resume timeline rebuilds`

### 1.2 运行时证据样本

额外对照了 2026-04-16 21:12:23 的一次真实联机操作日志（房间 `88MU5N`，动作 `skip_sub_phase`）。

注意：

- 该日志发生时间为 **2026-04-16 21:12:23**；
- `1f965791` 的提交时间为 **2026-04-16 21:25:36**；
- 因此该日志**不能直接验证 `1f965791`**；
- 但它足以验证此前热路径问题的主要结构性结论。

---

## 2. 更新后的根因结论

结论：

> 当前“联机卡顿、体验差”的主因，不是单一的日志面板 rebuild，也不是单一的某个 append 失败；  
> 而是 **恢复房双轨维护 + 命令后全量 UI 同步 + 完整历史缓存维护仍在主线程热路径附近** 叠加造成的。

换句话说：

1. 用户动作抵达客户端后，**runtime engine** 会执行一次；
2. 为维护恢复房完整历史，**full_replay_engine** 又会再执行一次；
3. 时间线 / cache append / cache rebuild 还会继续做一轮派生构建；
4. 然后 UI 仍按“整包同步”方式刷新地图、面板、overlay、时间线状态。

这不是“一个热点太重”，而是“一条操作链被拆成了多段重复重活”。

---

## 3. 与真实日志互相印证的证据

以下数值来自 2026-04-16 21:12:23 的样本日志。

### 3.1 网络与服务器不是主矛盾

- `client_request_to_rx_ms = 68.6`
- `server_exec_ms = 11.652`

说明：

- 从点按钮到客户端收到 `command_applied` 共约 `68.6ms`；
- 服务器执行只占约 `11.7ms`；
- 主要成本不在服务器，而在客户端收到包之后的处理链。

### 3.2 一条命令被重复处理

日志中同一动作出现了三次：

- `PhaseManager 子阶段推进: Recruit -> Train`
- `PhaseManager 子阶段推进: Recruit -> Train`
- `PhaseManager 子阶段推进: Recruit -> Train`

它们分别对应：

1. `runtime_engine` 真正 apply  
   - `ui/scenes/game/controllers/online_resync_controller.gd`
2. `full_replay_engine` 追加同一条完整历史命令  
   - `autoload/net_client_online_resume_support.gd`
3. step timeline / cache append 或 rebuild 派生逻辑再次读取并推进  
   - `autoload/net_client_online_resume_support.gd`

这说明当前不是“每个动作做一次”，而是“同一动作在不同轨道上被重复消费”。

### 3.3 前台热路径已经超出舒适预算

样本日志中的关键时段：

- `client_apply_ms = 7.4`
- `client.command_applied.resume_cache_sync = 26.4ms`
- `ui.online_sync.timeline_ui = 36.3ms`
- `ui.online_sync.panel_controller = 25.9ms`
- `ui.online_sync.total = 64.4ms`
- `client.command_applied.ui_update = 64.8ms`
- `client.command_applied.ui_settled = 145.0ms`

对应解释：

- 真正 runtime apply 只花 `7.4ms`，不算重；
- 恢复房缓存同步又吃了 `26.4ms`；
- UI 全量同步单次吃了 `64.4ms`；
- 从 `apply_done` 到 `ui_settled` 还拖了 `145.0ms`。

这说明当前体感卡顿的主要来源不是核心规则执行，而是：

- 恢复房完整历史维护；
- 命令后的 UI 全量同步。

### 3.4 后台 deferred 仍然在烧大块成本

样本日志：

- `resume_cache.timeline_cache_refresh.deferred = 516.7ms`
- `previous_processed_command_count = 258`
- `timeline_processed_command_count = 259`

说明：

- 即使只是 append 1 条命令；
- 后续 deferred timeline refresh 仍然可能消耗半秒级主线程时间。

因此当前问题不是“眼前 1 次卡顿”，而是：

- 当前帧已经有明显顿感；
- 后续还会有延迟到下一帧/后几帧的大块工作继续压主线程；
- 操作连续时，容易形成“越玩越粘”的持续卡顿。

---

## 4. 对现有修复的定性

### 4.1 应保留的部分

以下思路是合理的，应保留：

1. **性能打点体系**
   - 代表提交：`51d607a4`
   - 结论：必须保留，后续重构也要继续依赖。

2. **日志面板 append / item pool / 避免无意义 rebuild**
   - 代表提交：`15657256`
   - 结论：属于局部正确优化，不应回退。

3. **timeline cache reuse / append path 优化**
   - 代表提交：`cbf958d7`、`f02127bf`、`b0de7ff8`、`1f965791`
   - 结论：作为“冷路径 / 按需路径”优化是合理的。

### 4.2 不应继续坚持的部分

以下设计假设应明确废弃：

1. **每条联机命令都同步维护 `full_replay_engine`**
2. **恢复房进入游戏必须等待完整历史 timeline cache ready**
3. **每条命令后默认触发一整套 UI 全量同步**
4. **完整历史 cache 的构建/刷新可以长期放在主线程附近兜底**

这些假设不拆，后续优化只会继续出现“补一个热点，冒出另一个热点”。

---

## 5. 设计决策

### 5.1 总体决策

不做“整个联机系统推倒重写”，但要做：

> **联机恢复房热路径的外科式重构。**

原则：

- 保留现有外层功能语义；
- 保留现有测试资产、打点资产、局部 UI 优化；
- 重做恢复房完整历史在客户端的维护方式；
- 重做命令后 UI 刷新策略；
- 明确区分 **热路径**、**冷路径**、**按需路径**。

### 5.2 热路径定义

热路径只允许包含：

1. runtime engine 执行当前命令；
2. 必要的 sequence/hash 校验；
3. 最小必要 UI 增量刷新；
4. 玩家立即可见、立即需要的交互反馈。

热路径内**不允许默认包含**：

- 完整历史回放 engine 同步推进；
- 完整 timeline cache rebuild；
- 隐藏面板的日志 timeline build；
- 大范围地图/面板/overlay 的整包重刷。

### 5.3 冷路径 / 按需路径定义

以下工作必须转出热路径：

1. **完整历史准备**
   - 进入恢复房后后台准备；
   - 未 ready 前禁用回放入口即可；
   - 不阻塞当前对局可玩性。

2. **回放 / 历史查看**
   - 只有玩家真正打开日志 / 进入回放 / seek 历史时才触发。

3. **完整 timeline cache**
   - 只在回放/历史查看需要时构建；
   - 或在后台按帧分块推进；
   - 不再作为每条 live command 的默认副产物。

---

## 6. 新的目标架构

### 6.1 恢复房改为“两阶段进入”

#### 阶段 A：快速进局

- 使用 `runtime_archive` 构建 `runtime_engine`
- 尽快进入可玩状态
- 只保证当前对局能继续进行

#### 阶段 B：后台补齐完整历史能力

- 后台准备 `full_history_source`
- 准备 replay / seek 所需缓存
- 未 ready 前：
  - 回放按钮禁用
  - 日志只显示 live 必需内容

这意味着：

- “能玩”优先于“完整历史立即可看”；
- 历史功能延迟可接受，但 live 操作卡顿不可接受。

### 6.2 完整历史从“实时同步维护”改为“按需/后台维护”

建议第一版重构目标：

- `runtime_engine`：继续负责 live 对局
- `full_history_source`：只负责历史查看与回放

关键变化：

- 默认不在每条 `command_applied` 上强制推进 `full_replay_engine`
- 只记录最小必要的“新增命令尾部”
- 等玩家真的需要完整历史时，再补齐历史视图

可选实现方式：

1. **按需完整回放源**
   - 平时只记尾部命令；
   - 打开回放时再构造完整历史源。

2. **后台分帧补齐**
   - 完整历史准备分成多个小片段；
   - 每帧限定预算，避免一次性卡 300ms~500ms。

第一版优先建议：**后台分帧补齐 + 严格脱离热路径**。

### 6.3 UI 改为 dirty-driven

UI 需要拆成两个层次：

#### 立即层

每条命令后只刷新：

- 当前 phase / round / bank
- 当前可操作状态
- 当前玩家提示
- 与本次动作直接相关的局部控件

#### 延迟层

以下内容仅在 dirty 时刷新：

- 地图
- 右侧 action/panel 细项
- overlay
- 日志 timeline

进一步要求：

- 日志面板不可见时，不做 live timeline build；
- 地图层尽量按局部 redraw / 局部数据更新；
- panel_controller 不再默认整包 sync。

---

## 7. 分阶段实施计划

### 阶段 0：冻结热路径预算（先量清楚）

目标：

- 先明确热路径预算；
- 后续每一步优化都以预算约束来验收。

预算建议：

- `runtime apply`：`<= 10ms`
- `command_applied` 热路径附加工作：`<= 10ms`
- `ui.online_sync.total`：平均 `<= 25ms`，重场景峰值 `<= 40ms`
- `tx -> ui_settled`：
  - 同城/普通网络：目标 `<= 120~140ms`
  - 样本级操作（如 `skip_sub_phase`）：争取稳定进入 `100~130ms`

### 阶段 1：把完整历史维护移出 live command 热路径

目标：

- 取消每条 live command 的同步 `full_replay_engine` 推进；
- `resume_cache_sync` 只保留最小记录，不再执行完整派生链。

预期收益：

- 消掉日志样本中的 `26.4ms resume_cache_sync` 主体成本；
- 同时消掉同一命令的第二次 / 第三次推进。

### 阶段 2：恢复房改为“两阶段进入”

目标：

- 进入游戏只依赖 `runtime_engine ready`
- 不再 gate 在 `full_replay_ready + timeline_ready`

预期收益：

- 进入对局不再被完整历史 cache 卡在门口；
- 卡顿从“进局必须等”转为“历史功能后台补齐”。

### 阶段 3：UI 全量同步改为增量同步

重点拆解：

- `ui.online_sync.timeline_ui`
- `ui.online_sync.panel_controller`
- `ui.online_sync.map_view`

优先级：

1. `panel_controller`
2. `timeline_ui`
3. `map_view`

因为从现有日志看：

- `panel_controller` + `timeline_ui` 已经占了绝大部分前台 UI 成本。

### 阶段 4：完整历史 / 回放完全按需化

目标：

- 玩家不打开回放，就不承担完整历史可视化成本；
- 玩家打开回放时，再进入对应的冷路径/后台路径。

---

## 8. 预计性能收益

以下是基于当前样本日志做的保守预估，不是承诺值。

### 8.1 以 2026-04-16 21:12:23 的 `skip_sub_phase` 样本为基准

当前样本：

- `runtime apply = 7.4ms`
- `resume_cache_sync = 26.4ms`
- `ui.online_sync.total = 64.4ms`
- `apply_done -> ui_settled = 145.0ms`
- `deferred timeline refresh = 516.7ms`

### 8.2 完整方案完成后的保守目标

#### 热路径

- `runtime apply`：维持 `5~10ms`
- `resume_cache_sync`：降到 `0~5ms`
- `ui.online_sync.total`：降到 `15~30ms`
- `apply_done -> ui_settled`：降到 `30~60ms`

#### 端到端体感

- 类似 `skip_sub_phase` 的轻/中量操作：
  - 当前：`tx -> ui_settled` 约 `220ms`
  - 目标：`100~140ms`

换算成幅度：

- **客户端收到包后的热路径耗时**：预计降低 **60%~75%**
- **UI 同步耗时**：预计降低 **50%~75%**
- **恢复房 timeline cache 近热路径成本**：预计降低 **80%+**

### 8.3 deferred 大块卡顿的目标

当前看到的 `516.7ms deferred` 不应继续存在于主线程近实时路径。

完整方案后目标不是“完全没有后台成本”，而是：

- 这类成本必须被移到：
  - 按需打开回放时；
  - 或后台分帧限额执行；
- 不能再以单块 `300ms~500ms` 的形式抢占主线程。

---

## 9. 是否还会出现“这边降了，那边又涨了”

### 9.1 当前为什么会出现成本转移

当前之所以会出现“这边优化了，那边变慢”，原因是：

- 没有定义热路径边界；
- 没有定义每条路径的预算；
- 同一份完整历史成本可以在：
  - 进局时支付，
  - 命令后支付，
  - 打开日志时支付，
  - defer 后支付；
- 于是每次补丁只是把成本在不同阶段挪来挪去。

### 9.2 完整方案后，成本仍可能移动，但会变成“可控移动”

未来仍然可能有成本从 A 挪到 B，但必须满足：

1. **不能从冷路径挪回热路径**
2. **不能从按需路径挪回默认路径**
3. **必须有预算和打点证明新位置可接受**

例如：

- 把完整历史准备从 live command 热路径，挪到“打开回放时”的冷路径  
  - 这是允许的；
  - 因为这是玩家主动进入的次级功能。

- 把日志 timeline rebuild 从命令后，挪到日志面板显示时  
  - 这是允许的；
  - 因为未显示的 UI 不应收取实时成本。

- 把 `panel_controller.sync` 的整包成本，挪到每次 `skip_sub_phase` 之后  
  - 这是不允许的；
  - 因为它会直接伤害 live 操作。

### 9.3 防止再次“挪成本”的治理要求

后续修复必须新增这类约束：

- 为 `runtime apply / resume hot path / ui sync / replay cold path` 分别建指标；
- PR/提交不能只报“总耗时下降”，要报：
  - 哪条路径下降；
  - 哪条路径上升；
  - 是否跨越预算线；
- 没有预算数据的“感觉更快了”不视为有效优化。

---

## 10. 最终决策摘要

### 10.1 保留

- 在线性能打点体系
- 日志 append / pool / reuse 等局部 UI 优化
- timeline cache 的冷路径复用能力
- 现有恢复房相关测试资产

### 10.2 推倒重做

- 恢复房完整历史在 live command 热路径中的维护方式
- “进入对局前必须等完整历史 cache ready”的启动策略
- `update_ui()` 的默认全量同步思路

### 10.3 目标结果

希望最终把当前恢复房联机体验从：

- “每条命令都背完整历史负担”

调整为：

- “live 操作只背 live 必要成本”
- “完整历史只在玩家真正需要时付费”

---

## 11. 后续实施时的验收口径

修复计划完全完成后，至少要满足：

1. 恢复房进入游戏不再被完整历史 cache gate；
2. 样本级动作（如 `skip_sub_phase`）不再出现一次操作三次推进；
3. `resume_cache_sync` 不再出现在 live command 的主要耗时里；
4. `ui.online_sync.total` 在常见操作下明显低于当前 `64.4ms`；
5. 不再出现单次 append 1 条命令却触发 `500ms` 级 deferred timeline cache refresh；
6. 若成本被转移到回放/历史查看，必须以冷路径预算单独验证。

---

## 12. 一句话结论

> 之前这些修复并非完全错误，但它们主要是在给错误的热路径设计打补丁。  
> 下一步不该继续“修热路径上的局部热点”，而应把恢复房完整历史、时间线缓存、UI 同步重新分层：  
> **live 只做 live，history 改成按需或后台。**
