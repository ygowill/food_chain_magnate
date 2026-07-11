# FCM Refactor Risk Matrix

Use the highest-risk applicable row to set characterization coverage and gates. Multiple rows may apply.

## Project Boundaries

| Area | Owns | Must not acquire |
| --- | --- | --- |
| `core/` | Pure reusable state, actions, rules, map, engine logic | Scene-tree, Node, UI, editor-only, or module-private dependencies |
| `gameplay/` | Runtime orchestration and validators over core contracts | Presentation ownership or hidden mutations that bypass core rules |
| `ui/` | Scenes, presentation state, input wiring, signals | Authoritative game rules that cannot run headlessly |
| `modules/*` | Module manifest, content, and module-owned rules | Direct knowledge of another module's private layout or IDs not in a contract |
| `data/config/` | Project-level configuration | Module-owned gameplay content or implicit save migrations |

## Risk and Gate Matrix

| Refactor surface | Risk | Hidden contracts to inventory | Minimum characterization before editing | Required gates | Stop condition |
| --- | --- | --- | --- | --- | --- |
| Extract pure function or class | Low–medium | Mutation order, error shape, numeric rounding, iteration order | Existing focused test or before/after input-output cases | Focused core test; full strict suite | Extraction needs new state or Node access |
| Rename or move file/symbol | Medium | String lookups, `class_name`, preload/load paths, docs, tests, autoloads | Load/instantiate affected resource and search all old references | Targeted scene/test; zero unintended old references; full strict suite | Stable public/resource identifier must change without shim |
| Split large state/rule object | High | Ownership, aliasing, mutation timing, signal/event order, serialization | Characterize representative transitions, errors, and round trip | Per-slice transition tests; replay/save gates; full strict suite | No stable seam separates responsibilities |
| Move responsibility across core/gameplay/UI | High | Dependency direction, lifecycle, signal timing, headless operation | Characterize external outcomes at old boundary | Layer-focused tests; scene loading; headless full suite | `core/` would depend on Node/UI or rules move into presentation |
| Reorganize Modules V2 | High | `module.json`, discovery order, stable IDs, content references, rule registration | Load representative modules and resolve content/rules by stable ID | Module discovery tests; content validation; replay/full suite | Requires private cross-module coupling or ID churn |
| Change scene tree or signals | High | Node paths, `%UniqueName`, exported references, connection order, animation/callable names | Instantiate scenes and exercise signal-visible behavior | Scene smoke/target tests; connection/path search; full suite | External scene contract is unknown or cannot be loaded headlessly |
| Touch data/save schema | Critical | Keys, defaults, versions, enum/string IDs, resource paths, old-data tolerance | Old fixture load plus new round trip and semantic equality | Migration/version tests; invalid/partial data tests; full suite | Old-format behavior or migration ownership is unspecified |
| Touch replay/state sequencing | Critical | Command order, RNG consumption, timestamps/ticks, hashes, event order | Deterministic replay fixture/trace and final-state assertion | Repeat-run equality; payload/hash comparison; full suite | Baseline is nondeterministic or fixture provenance is unclear |
| Replace algorithm for clarity/performance | High | Tie-breaking, precision, ordering, allocations, worst cases | Output equivalence corpus and reproducible performance baseline | Equivalence tests; before/after measurement; full suite | Intended semantic tradeoff or acceptable regression is undefined |
| Remove legacy adapter/path | High | Unsearched callers, old saves, external tools, documentation, scripts | Prove all callers migrated and compatibility window ended | Repository-wide search; compatibility tests; full suite | Consumer inventory is incomplete |

## Compatibility Inventory

Check each applicable surface before defining the plan:

- Public code: method names, argument defaults, return/error shapes, signals, `class_name`, autoload names.
- Godot resources: `res://` paths, `.tscn`/`.tres` references, exported properties, node paths, groups, callable strings.
- State and rules: action legality, mutation order, event emission, iteration/tie-breaking, RNG draw count.
- Modules: manifest schema, registration/discovery order, content IDs, rule entry points, cross-module references.
- Persistence: save version, keys, defaults, enum/string IDs, numeric representation, missing/unknown-field behavior.
- Replay/network: command schema/order, deterministic hashes, tick/frame meaning, rollback/resume boundaries.
- Operations: developer commands, tooling inputs, generated artifacts, architecture and ADR contracts.

## Slice Patterns

Choose the least disruptive pattern that exposes a testable seam:

1. **Extract and delegate:** Introduce the new component behind the old entry point; migrate internals; keep callers stable.
2. **Adapter first:** Preserve the old API or data shape while translating to the new internal model.
3. **Duplicate and compare:** Run old and new pure calculations on a bounded corpus; assert equivalence before switching.
4. **Parallel reader, single writer:** Read old and new representations during a migration; avoid dual authoritative writes unless explicitly designed.
5. **Move then prune:** Copy/move behavior with wrappers, migrate callers in batches, verify searches, then remove obsolete paths.

For every slice, record: changed contract surface, focused command, expected invariant, observed result, and rollback seam.

## Performance Evidence

Use performance gates only for affected hot paths. Keep environment and workload comparable, warm up consistently, take multiple samples, and report raw timings or allocations plus summary statistics. Treat a functional equivalence failure as blocking regardless of speed. If no regression budget exists, report the delta and uncertainty; do not invent an acceptable threshold.
