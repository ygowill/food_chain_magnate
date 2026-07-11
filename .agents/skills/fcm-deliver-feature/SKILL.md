---
name: fcm-deliver-feature
description: Deliver medium- or high-impact FCM features end to end from original intent and stable requirements through design, implementation, testing, documentation, and validation. Use when adding a new player-visible or system capability, or materially expanding an existing Feature across modules or layers. Not for isolated low-risk fixes, behavior-preserving refactors, review-only checks, or acceptance-only validation. Output governed Feature and Requirement updates, any required ADR or Plan, a minimal tested implementation, AC-to-evidence mapping, and a ready-for-review handoff; do not commit, push, merge, release, or perform irreversible actions unless the user authorizes them.
---

# FCM Feature Delivery

Deliver one coherent capability without losing the user's original intent or creating a second source of truth.

## Inputs

Obtain or discover:

- the user problem, desired outcome, Non-goals, and non-negotiable constraints;
- the affected Feature ID, or enough context to allocate a new one;
- the responsible owner role and risk/change level;
- relevant Requirements, Architecture, ADRs, code, tests, and current Backlog;
- any required manual, platform, multiplayer, performance, save, or replay validation.

Read `references/feature-delivery-matrix.md` when choosing the delivery lane, artifacts, or gates.

## Select the delivery lane

1. Update an existing Feature when the request changes the same user/system capability and its stable intent.
2. Create a new Feature when the request has an independent outcome, owner, lifecycle, or acceptance boundary.
3. Use the Small Change Lane only when the change is low risk, quickly reversible, and has no architecture, data, security, save/replay, or migration impact.
4. Stop and ask when intent, rules, product scope, ownership, or destructive consequences are materially ambiguous.

Do not create a Feature merely because many files change. Do not hide a real Feature behind a small-change label to avoid governance.

## Workflow

### 1. Reconstruct intent

1. Inspect `git status`, `docs/VISION.md`, `docs/REQUIREMENTS.md`, `docs/BACKLOG.md`, `docs/features/README.md`, the relevant Architecture and ADRs, nearby code, and tests.
2. State the desired result, user path, constraints, Non-goals, assumptions, and open questions.
3. Resolve contradictions against code and durable evidence. Do not treat a design, Plan, archived report, chat summary, or local log as current truth.
4. Ask only questions whose answers would materially alter scope, rules, security, compatibility, or UX. Continue with explicit low-risk assumptions otherwise.

### 2. Establish the governed contract

1. Allocate or reuse a stable `F-NNN` ID.
2. Define stable Requirement IDs in `docs/REQUIREMENTS.md`; keep normative wording there.
3. Create or update the Feature aggregation page from `docs/templates/feature.md`.
4. Record scope, Non-goals, owner, status, Requirement IDs, AC interpretation, evidence plan, Architecture, decisions, code entry points, limitations, and next action.
5. Add confirmed active work to `docs/BACKLOG.md` without copying Feature status.
6. Keep each AC falsifiable and observable. Separate automated, manual, platform, performance, and usability evidence.

Pass the Discovery Gate only when the original intent, Non-goals, Requirement IDs, owner, acceptance boundaries, and unresolved decisions are explicit.

### 3. Design proportionally

1. Trace the current call paths and data ownership before proposing new abstractions.
2. Preserve FCM boundaries: deterministic engine logic in `core/`, module-owned optional content/rules in `modules/`, gameplay wiring in `gameplay/`, and node/UI concerns in `ui/` or `autoload/` as appropriate.
3. Create a proposed ADR before a high-impact, cross-boundary, hard-to-reverse, protocol, persistence, or authority decision.
4. Create a governed `PLAN-YYYY-NNN` for medium or large implementation work. Define increments, dependencies, rollback, tests, and evidence.
5. Invoke `$fcm-safe-refactor` separately when delivery requires substantial behavior-preserving restructuring. Keep the refactor invariants distinct from the new behavior ACs.

Pass the Design Gate only when authority, data flow, failure behavior, compatibility, rollback, and test strategy are clear.

### 4. Implement the smallest vertical slice

1. Add or capture a failing test/evidence before fixing behavior when practical.
2. Implement one end-to-end slice that proves the architecture and user path.
3. Prefer explicit, local, maintainable changes. Avoid unrelated cleanup or speculative frameworks.
4. Preserve deterministic state, replay/archive compatibility, Modules V2 strict loading, headless testability, and tab indentation in GDScript.
5. Fail explicitly at trusted boundaries. Do not silently accept invalid module, state, network, or schema inputs.
6. Keep the worktree explainable and preserve unrelated user changes.

### 5. Verify each increment

1. Run the narrowest relevant tests first.
2. Run compile/import checks when resource, scene, class, or load paths change.
3. Run strict AllTests for runtime behavior changes:

   `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit`

4. Perform required manual, multi-process, platform, browser, performance, or usability checks. Mark unavailable evidence `not-covered` or `inconclusive`; never infer it from unit tests.
5. Record exact commands, exit codes, commit/worktree state, summaries, warnings, and durable Artifact locations.

### 6. Synchronize truth sources

1. Invoke `$fcm-sync-docs` after behavior, architecture, status, commands, or operational procedures change.
2. Keep Requirement definitions in `docs/REQUIREMENTS.md` and AC verdict/evidence in the Feature page or Validation.
3. Update Architecture for current behavior and create/replace ADRs for lasting decisions.
4. Regenerate and check the formal index:

   `python3 tools/docs_governance.py --write-index`

   `python3 tools/docs_governance.py`

### 7. Gate and hand off

1. Invoke `$fcm-quality-gate` before requesting review.
2. Provide the original intent, What, Why, trade-offs, risk/rollback, tests, AC-to-evidence mapping, limitations, and review focus.
3. Request independent review for cross-layer, protocol, persistence, security, data, or high-risk work.
4. Invoke `$fcm-validate-acceptance` before moving the Feature to `done` when user-path or manual acceptance matters.
5. Mark `done` only when a completed/pass Validation links back and covers all declared Requirement IDs; disclose accepted limitations.

## Stop and ask

Stop before continuing when the work requires:

- guessing an ambiguous game rule or product outcome;
- production credentials, private user data, or external authority not supplied in scope;
- destructive cleanup, migration, deployment, release, dependency introduction, or permission changes;
- silently breaking archive/replay, protocol, data, or module compatibility;
- rewriting an accepted ADR instead of proposing a superseding decision;
- claiming manual/platform/performance evidence that was not observed.

## Output contract

Return:

1. Feature ID and intended outcome;
2. scope and Non-goals;
3. Requirement/AC status and evidence matrix;
4. implementation and design decisions;
5. commands, exit codes, and durable evidence;
6. known limitations and uncovered validation;
7. exact next action and responsible owner;
8. commit/PR state, without claiming actions not performed.
