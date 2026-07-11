---
name: fcm-sync-docs
description: >-
  Synchronize FCM's governed current-truth documentation after verified changes to behavior, architecture, commands, Feature status, or operational procedures. Use when implementation or process changes require a documentation-impact assessment, current truth-source updates, relationship repair, and generated-index refresh. Not for: product discovery, inventing requirements, designing a new feature, rewriting an accepted ADR in place, or claiming unperformed validation. Output: an impact matrix, updated files or explicit no-update reasons, blockers, and documentation-governance command results.
---

# FCM Docs Sync

Update documentation as a truth-maintenance task. Derive every semantic change from code, configuration, verified behavior, an approved decision, or an identified Owner; do not turn plans, chat claims, or old reports into current truth.

Read [references/truth-source-map.md](references/truth-source-map.md) before choosing document targets or changing status and evidence metadata.

## Workflow

### 1. Establish scope and sources

1. Run `git status --short`, record `git rev-parse HEAD`, and inspect the relevant diff or user-specified comparison.
2. Identify the Feature or Small Change reason, affected Requirement IDs, current owners, and whether the implementation is committed or still a working-tree state.
3. Read `docs/README.md`, `docs/DOC_MAP.md`, `docs/governance/documentation-governance.md`, and `docs/_generated/document-index.json` as navigation and governance contracts.
4. Read the current Feature, Architecture, accepted ADRs, Plan, Validation, runbook, and command documentation relevant to the changed paths. Read archived material only for provenance.
5. Stop and report a blocker when the source is ambiguous, the Owner is missing, or implementation conflicts with approved intent. Do not resolve a product or architecture disagreement by silently changing prose.

### 2. Build a documentation-impact matrix

For each changed behavior or procedure, record:

- the observed source of truth;
- the governed fact that changed;
- the document that owns that fact;
- the required update or a concrete no-update reason;
- the Owner or approval needed;
- any downstream Feature, ADR, Validation, Plan, index, or navigation relationship.

Use the map in the reference. Do not update documents merely because their keywords match; update them only when their owned facts changed or their links became stale.

### 3. Apply lifecycle and evidence rules

1. Preserve stable IDs across moves and rewrites. Update `updated` only when content or governed relationships materially change.
2. Keep Requirement definitions in `docs/REQUIREMENTS.md`; keep Feature scope, Non-goals, AC interpretation, state, and evidence mapping in the corresponding `docs/features/F-*.md`.
3. Treat accepted ADR conclusions as immutable history. When a verified decision changes, draft a new `proposed` ADR with `supersedes` and reciprocal `superseded_by`; require the responsible human Owner to accept it.
4. Update Architecture to match verified current implementation. If code and Architecture disagree, determine which is incorrect before editing either source.
5. Record Validation only from an actual run with command, environment, exit, result, revision identity, evidence location, and limitations. Never convert a dirty-working-tree run into commit-bound evidence.
6. Do not move a Feature to `done` unless every AC is judged and a reverse-linked `completed + pass` Validation covers its relevant Requirement IDs. Preserve `deferred` and `not-covered` items.
7. Keep active Plan and Progress pages navigational. Archive completed or superseded material without allowing it to replace current Feature, Requirement, ADR, Architecture, or Validation truth.

### 4. Edit only the owned truth sources

1. Make the smallest coherent documentation change. Use `docs/templates/` when creating a new governed document.
2. Use repository-relative Markdown links and stable IDs. Do not add `/Users/...`, Downloads, worktree, ignored `.godot` log, or chat-session paths as durable references.
3. Keep owners as stable teams or responsibility roles, not Agent names or temporary workspaces.
4. Update navigation only when reachability changes. Do not copy volatile status into README or DOC MAP pages.
5. Surface unresolved decisions, missing evidence, and known limitations explicitly instead of writing optimistic completion language.

### 5. Rebuild and validate

Run the governance sequence after edits:

```bash
python3 tools/docs_governance.py --self-test
python3 tools/docs_governance.py --write-index
python3 tools/docs_governance.py
```

Then inspect `git diff --check`, review the generated-index diff, and verify that only intended current truth sources and navigation files changed. Do not repair unrelated user changes.

If checks fail, fix documentation defects within the authorized scope. Stop for Owner input when a failure exposes a semantic conflict, missing authority, or evidence gap rather than a mechanical documentation error.

### 6. Report the synchronization result

Return:

1. the comparison boundary and Feature/Requirement context;
2. an impact matrix listing updated files and explicit no-update reasons;
3. status, ADR, Validation, or Owner blockers;
4. the exact governance commands and results;
5. remaining manual review or evidence needs.

Do not claim that CI, tests, acceptance, branch protection, or external platform settings passed unless they were actually observed. Documentation synchronization is not a quality-gate or acceptance verdict.
