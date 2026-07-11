---
name: fcm-validate-acceptance
description: >-
  Independently validate an FCM feature or change against its original intent, canonical Requirements, acceptance criteria, Non-goals, ADRs, and required automated, manual, or platform evidence. Use when implementation is complete, a Feature may leave validation, or a claimed completion needs an audit. Not for: implementing or repairing the feature, performing a generic pre-review quality gate, or approving work produced by the same validator. Output: an evidence-bounded pass, fail, or inconclusive verdict with an AC matrix, limitations, and next actions.
---

# FCM Acceptance Validation

Produce an independent, evidence-bounded acceptance verdict. Treat implementation and governed source documents as inputs; do not improve the implementation while validating it.

Read [references/evidence-policy.md](references/evidence-policy.md) before collecting evidence or assigning a verdict.

## Boundaries

- Keep the implementation read-only. If remediation is requested, end the validation role and start a separate task; require a fresh independent validation afterward.
- Never validate or approve your own implementation. If independence cannot be established, return `inconclusive` and request another validator.
- Do not change a Feature to `done`, merge, release, or claim owner approval. A `pass` verdict is a technical finding, not governance approval.
- Do not substitute a generic green test suite for acceptance intent, Non-goals, manual observation, real platform behavior, performance, or user experience.
- Do not treat chat claims, terminal scrollback, screenshots without context, or ignored `.godot/` logs as durable evidence.
- Stop before actions requiring credentials, production access, external messages, destructive changes, or platform cost unless the user explicitly authorizes them.

## Workflow

### 1. Freeze the target

1. Record the repository, exact commit, working-tree state, Feature ID, and requested validation scope.
2. Identify the implementation author or agent and the validator. If they are the same, return `inconclusive` without issuing approval.
3. Treat uncommitted changes as a distinct target. Record their diff; do not silently combine them with the recorded commit.

### 2. Reconstruct the contract

Read current sources in this order:

1. `docs/governance/documentation-governance.md` for lifecycle and evidence rules.
2. `docs/REQUIREMENTS.md` for normative Requirement definitions.
3. The `docs/features/F-*.md` page for current scope, Non-goals, acceptance interpretation, status, and known limits.
4. Accepted ADRs and current Architecture linked by the Feature.
5. Original request, source material, and completed Plan for intent and historical context.
6. Code and tests for actual implementation behavior.

Do not let a stale Plan, Design, progress report, archived document, or implementation detail override a current Requirement, Feature scope, accepted ADR, or Architecture contract. Report conflicts instead of choosing the most convenient interpretation.

### 3. Build the acceptance matrix

Create one row for every in-scope Requirement and acceptance criterion. Record:

- stable ID and exact normative statement;
- Feature-specific acceptance interpretation;
- relevant Non-goal or prohibited behavior;
- required evidence mode: automated, manual, platform, or a combination;
- planned test, inspection, or observation;
- observed evidence and its durability;
- criterion verdict: `pass`, `fail`, or `inconclusive`.

Do not omit a criterion because evidence is unavailable. Mark it `inconclusive` and explain the gap.

### 4. Inspect before executing

Trace each criterion to implementation and tests. Check boundaries and negative behavior, not only happy paths. Look for:

- behavior that contradicts a Non-goal;
- missing failure handling, isolation, determinism, or ownership boundaries;
- tests that only repeat implementation details rather than prove the requirement;
- mocks or headless paths that bypass the behavior being accepted;
- evidence from a different commit, environment, or configuration.

### 5. Collect appropriate evidence

Run the smallest targeted checks first. For runtime changes, run the required strict headless suite after targeted checks unless the scope explicitly excludes it. Record every command, environment, exit code, summary, and exact target commit.

Perform manual or platform validation only when it is required and safely available. Record expected versus observed behavior, environment, build/commit, topology or account roles, and a stable artifact reference. If required real-platform, multi-process, Web, performance, or usability validation cannot be performed, do not replace it with a local unit test; mark the affected criteria `inconclusive`.

Preserve a durable summary in a governed Validation report when asked to write repository evidence. Prefer commit-bound CI artifacts or stable object storage for raw logs, with hash and retention metadata. Treat local ignored logs only as ephemeral supporting material.

### 6. Assign the verdict

Use exactly one overall verdict:

- `pass`: every in-scope criterion passes with the required evidence mode; Non-goals remain intact; the target commit and environment are unambiguous; independence is established.
- `fail`: any required behavior demonstrably fails, a Non-goal is violated, a regression or unsafe behavior is observed, or the implementation contradicts a governing contract.
- `inconclusive`: any required source is missing or conflicting, required evidence is unavailable or non-durable, the target cannot be reproduced, manual/platform coverage is missing, or validator independence is absent.

Do not average verdicts. One failed criterion makes the overall verdict `fail`; otherwise one inconclusive criterion makes it `inconclusive`.

### 7. Report without self-approval

Return, in this order:

1. target Feature, commit/diff, environment, scope, and validator independence;
2. overall verdict and one-sentence rationale;
3. Requirement/AC matrix with per-row verdict and evidence mode;
4. Non-goal audit;
5. automated, manual, and platform evidence executed or missing;
6. warnings, limitations, and durable evidence locations;
7. blocking remediation or next validation action;
8. explicit statement that the Feature owner or repository approver—not the validator—decides status, merge, or release.

If repository evidence is requested, create or update `docs/validation/VAL-YYYY-NNN-*.md` from `docs/templates/validation.md`, bind it to the exact commit and Feature/Requirement IDs, and keep `status`, `verdict`, commands, exit codes, artifact locations, hashes, limitations, and reverse links consistent. Run the documentation governance checks after writing it.
