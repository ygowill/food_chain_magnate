---
name: fcm-safe-refactor
description: >-
  Refactor existing FCM_new Godot 4.5 code while preserving explicit observable behavior and compatibility. Use when restructuring, extracting, renaming, moving, decoupling, deduplicating, simplifying, or replacing internals in GDScript, scenes, resources, Modules V2, state, save, or replay-sensitive paths. Not for: adding features, fixing incorrect behavior, changing public contracts without migration, or documentation-only cleanup. Output: explicit invariants, baseline evidence, reversible implementation slices, compatibility results, exact validation commands, and residual risks.
---

# FCM Safe Refactor

Preserve behavior deliberately. Establish the current contract, add characterization coverage where needed, then change one reversible slice at a time.

## Apply the Skill

Use this skill to:

- improve structure without intentionally changing player-visible or integration behavior;
- move responsibilities across `core/`, `gameplay/`, `ui/`, or `modules/` while preserving dependency direction;
- rename or extract public-adjacent code while retaining compatible call sites, signals, paths, data, saves, and replays;
- replace an implementation whose outputs, ordering, determinism, and performance envelope must remain controlled.

Do not use this skill as the primary workflow to:

- add a new player capability or acceptance criterion; use the feature-delivery skill;
- diagnose or correct wrong behavior; use the issue-solving workflow, then use this skill for a separate cleanup;
- make documentation-only, formatting-only, or mechanical generated-file updates;
- redesign a public contract, save format, replay semantics, or UX without explicit approval and migration criteria.

## Produce These Outputs

Return:

1. the refactor scope, non-goals, affected boundaries, and risk class;
2. explicit behavior and compatibility invariants;
3. baseline evidence and any characterization tests added before structural changes;
4. the ordered implementation slices and per-slice validation gates;
5. the implemented changes, with each slice left buildable and reviewable;
6. exact validation commands and observed results;
7. save, replay, data, scene, API, and performance compatibility findings;
8. residual risks, unverified assumptions, rollback seams, and documentation impact.

Do not report “behavior preserved,” “compatible,” or “faster” without evidence tied to the affected surface.

## Follow the Workflow

### 1. Inspect Before Editing

- Read `AGENTS.md`, `docs/README.md`, `docs/DOC_MAP.md`, affected architecture contracts, accepted ADRs, nearby code, and nearby tests.
- Run `git status --short` and preserve unrelated user changes.
- Map callers, signals, scene/resource paths, autoloads, serialized keys, module manifests, and tests with `rg` and repository navigation.
- Read [references/refactor-matrix.md](references/refactor-matrix.md) and select the row matching the highest-risk affected surface.
- Classify the request as a true behavior-preserving refactor. Stop if the desired behavior is changing but no feature or bug-fix contract exists.

### 2. Freeze the Behavior Contract

- Write observable invariants before modifying production code.
- Cover action legality, state transitions, event/signal order, return and error shapes, visible UI outcomes, deterministic RNG usage, and timing-sensitive contracts where relevant.
- Preserve public method, signal, autoload, resource, scene-node, and module identifiers unless a compatibility shim or approved migration is part of the task.
- Preserve serialized keys, version fields, resource IDs, JSON shapes, save/load round trips, and replay command/order semantics.
- State non-goals explicitly. Treat any newly discovered behavior change as scope expansion.

### 3. Establish a Reproducible Baseline

- Run the smallest existing tests that exercise the affected contract before editing.
- Add focused characterization tests first when risky behavior is not covered. Assert externally meaningful outcomes rather than private implementation details.
- Capture representative save/load or replay fixtures when those paths are affected. Use repository-safe fixtures; never depend on ignored `.godot/` logs as durable evidence.
- Measure a comparable baseline before claiming performance improvement. Keep hardware, build, input, warm-up, and sample method constant; report the raw before/after result and variance.
- Distinguish pre-existing failures and warnings from refactor regressions. Do not normalize an unexplained failing baseline.

### 4. Design Reversible Slices

- Prefer seams such as extract-and-delegate, introduce adapter, duplicate-and-switch, or move-with-compatibility-wrapper.
- Keep each slice behavior-preserving, buildable, independently testable, and small enough to review.
- Order slices as: coverage, new seam, caller migration, compatibility verification, obsolete-path removal, documentation.
- Keep `core/` pure and independent of Nodes/UI. Keep Godot presentation in `ui/`, orchestration in `gameplay/`, and module-owned rules/content under `modules/*`.
- Avoid cross-module knowledge of private internals. Use established contracts and stable IDs.
- Define a rollback seam for high-risk slices before implementation.
- Create incremental commits only when the user authorized commits. Never commit a broken intermediate state or unrelated changes.

### 5. Implement One Slice at a Time

- Make the smallest coherent edit for the current slice.
- Preserve local GDScript conventions and tabs; never mix tabs and spaces.
- Avoid opportunistic cleanup outside the declared scope.
- Run the slice gate immediately. Fix or revert the slice before proceeding if the gate fails.
- Re-search renamed or moved symbols and paths after migration. Inspect `.tscn`, `.tres`, JSON, documentation, tests, and string-based references, not only GDScript call sites.
- Remove compatibility wrappers only after all callers and persisted/replay compatibility are verified.

### 6. Apply Compatibility Gates

- For `core/` or rules changes, run focused pure-logic tests and deterministic replay/state assertions.
- For `ui/` changes, validate scene loading, node paths, signal connections, user-visible state, and headless-safe behavior.
- For `modules/` changes, validate `module.json`, content/rule discovery, stable IDs, and absence of private cross-module coupling.
- For data/save changes, prove old-data load behavior and new-data round trips, or stop for an approved migration/versioning plan.
- For replay-sensitive changes, compare command order, serialized payloads, hashes/traces, RNG consumption, and final state.
- For performance-sensitive changes, repeat the baseline method and report both regressions and improvements without overstating precision.

### 7. Run Final Gates

- Run targeted tests first.
- When runtime behavior or code changed, run:

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit
```

- Run the documentation governance gate when governed documentation or links changed:

```bash
python3 tools/docs_governance.py
```

- Run `git diff --check`, inspect `git diff --stat` and the full relevant diff, and re-check indentation and generated artifacts.
- Update current architecture/ADR/Feature/Validation material in the same change when contracts, ownership, commands, or evidence changed.
- Record only commands actually run and results actually observed.

## Stop and Ask

Stop before expanding or finalizing when:

- the current and desired observable behavior cannot both be stated clearly;
- the existing targeted baseline fails for an unexplained reason;
- the refactor would alter a public API, signal, resource path, module ID, scene contract, save schema, or replay semantics without approved compatibility criteria;
- old saves or replays are unavailable and the affected compatibility risk cannot be bounded;
- a delete, bulk rename, data migration, or dependency-direction reversal is required but was not authorized;
- tests cannot observe a high-risk path and a safe characterization seam cannot be added;
- the change crosses substantially more layers or modules than the agreed scope;
- performance is an acceptance claim but no comparable measurement is possible.

Report the specific decision, evidence already collected, safe options, and consequences. Do not guess through a compatibility boundary.
