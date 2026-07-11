---
name: fcm-quality-gate
description: >-
  Independently verify whether an FCM change is ready for review or a governed status transition by checking intent, diff scope, targeted tests, strict AllTests when runtime behavior is affected, documentation governance, and evidence coverage. Use when implementation is complete, a PR or review is being prepared, or a Feature may move to validation or done. Not for: designing or implementing a change, fixing review findings, or performing independent user acceptance. Output: a PASS or BLOCK gate report with commands, exit codes, revision/worktree identity, Requirement/AC evidence, limitations, and next actions.
---

# FCM Quality Gate

Act as an independent verifier. Inspect and execute checks; do not edit implementation or governed documentation, relax a criterion, stage files, commit, push, or merge. Report defects as findings for a separate implementation pass.

Read [references/gate-contract.md](references/gate-contract.md) before selecting checks or issuing a verdict.

## Workflow

### 1. Establish the evidence boundary

1. Run `git status --short`, record `git rev-parse HEAD`, and inspect the relevant diff with `git diff --stat`, `git diff`, and, when applicable, the user-specified base or PR diff.
2. Use the base supplied by the user or hosting context. If no base is discoverable, assess only the current working tree and label that boundary explicitly; do not guess a branch relationship.
3. Snapshot the pre-check working tree. Treat unrelated or unexplained changes as user-owned and never discard them.
4. Identify whether the result can bind to a commit. For uncommitted changes, identify it as `working tree at <HEAD>` and never describe it as commit-level evidence.

### 2. Recover the intended contract

1. Find the Feature ID or the explicit Small Change reason.
2. Read the Feature page, referenced Requirement IDs, Non-goals, accepted ADRs, current Architecture, and relevant Plan or issue.
3. Extract the acceptance criteria affected by the diff. Do not substitute test names or implementation details for missing intent.
4. Return `BLOCK` if the change has no stable scope, conflicts with a Requirement, or depends on an unresolved product or architecture decision.

### 3. Review the change before running checks

1. Inspect every changed path and explain how it belongs to the stated scope.
2. Check module boundaries: keep reusable logic in `core/`, module-owned gameplay content in `modules/*/content/`, and UI glue in `ui/`.
3. Check Godot 4.x correctness, deterministic/headless behavior, data compatibility, security, rollback risk, and GDScript tab indentation where relevant.
4. Check whether behavior, architecture, commands, or operations changed without the corresponding current truth source being updated.
5. Do not fix findings during the gate. Record them and continue only with checks that remain meaningful.

### 4. Select and run verification

1. Run the narrowest relevant test scene first. Use existing `core/tests/` coverage and `ui/scenes/tests/*_test.tscn` runners rather than inventing ad hoc success probes.
2. Run `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit` whenever runtime code, scenes, gameplay data, test infrastructure, or Godot project configuration changed.
3. Run `python3 tools/docs_governance.py` for every review-readiness gate. Do not run `--write-index`; a stale generated index is a finding, not something the verifier silently repairs.
4. Run `python3 tools/skills_governance.py` when `.agents/skills/`, Skill routing in `AGENTS.md`, the Skills registry, or Skill governance tooling changed. Do not regenerate a stale Skill index inside this read-only gate.
5. Add syntax, import, build, cross-process, platform, visual, or manual checks required by the changed surface. Never infer UI, online, platform, or user acceptance from AllTests alone.
6. Capture the exact command, exit code, concise result, scope, environment, and revision identity. Treat missing tools, timeouts, unavailable services, and non-reproducible environments as incomplete verification.

### 5. Judge evidence without upgrading it

1. Map each affected Requirement or AC to `pass`, `fail`, `deferred`, or `not-covered` and cite the evidence that supports only that scope.
2. Treat ignored `.godot/*.log` files as local diagnostic evidence. Do not cite them as durable proof unless a stable CI Artifact or checked Validation summary preserves the run identity and result.
3. Require a reverse-linked `completed + pass` Validation covering the relevant Requirement IDs before accepting a Feature transition to `done`.
4. Return `BLOCK` for any failed required check, material finding, missing critical evidence, unexplained diff, unauthorized scope expansion, or unavailable required environment.
5. Return `PASS` only when every required check for the stated boundary passed and all uncovered items are non-blocking and explicitly disclosed.

### 6. Verify non-interference and report

1. Run `git status --short` again and compare it with the pre-check snapshot.
2. Distinguish expected ignored test output from new tracked or untracked source changes. Do not delete either automatically.
3. Use the report contract in the reference. Lead with exactly `PASS` or `BLOCK`, then state scope, revision/worktree identity, findings, commands and exits, AC evidence, limitations, and next actions.
4. State plainly that a local working-tree PASS is not a remote CI, merge, release, or independent acceptance approval.
