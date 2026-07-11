# FCM truth-source map

Use this map after identifying the actual change. Select documents by ownership of the changed fact, not by filename similarity.

## Precedence and ownership

| Fact | Owning current truth source | Do not use as a substitute |
|---|---|---|
| Project purpose and explicit exclusions | `docs/VISION.md` | Feature aspirations or progress reports |
| Stable Requirement ID and normative definition | `docs/REQUIREMENTS.md` | AC prose copied into a Feature or Plan |
| Feature scope, Non-goals, status, AC interpretation, limitations | `docs/features/F-*.md` | Design, active Plan, issue log, or README status |
| Current implementation behavior and module boundary | `docs/architecture/` plus verified code/configuration | Archived design or historical review |
| Durable high-impact decision and supersession | `docs/decisions/*.md` | Rewritten accepted ADR or chat agreement |
| Execution steps and actual deviations | Active `docs/plans/PLAN-*.md`, then archive | Feature status or Validation conclusion |
| Commit/environment-specific test result | `docs/validation/VAL-*.md` plus stable CI/Artifact evidence | Local ignored log or author's assertion |
| Active work ordering | `docs/BACKLOG.md` | Historical issue tracker |
| Unaccepted historical implementation claims | `docs/progress/acceptance_queue.md` | Feature done state |
| Current command or operational procedure | `AGENTS.md`, `docs/testing.md`, current runbook, or relevant root README | Old plan or machine-specific note |

When code, an accepted decision, and current Architecture disagree, investigate the source of the mismatch. Do not mechanically make every document match the newest edit.

## Change-to-document routes

| Changed surface or fact | Inspect first | Common synchronized targets |
|---|---|---|
| Autoload or startup wiring | `project.godot`, `docs/architecture/10-autoload.md` | System overview and affected Feature links |
| Core engine/state/actions/rules | `docs/architecture/30-core-engine.md`, `33-core-state-model.md`, `33a-core-state-schema-contract.md` | Owning Feature, accepted ADR or proposed replacement, module guide |
| Modules V2 manifest/content/rules | `docs/architecture/60-modules-v2.md`, `62-module-development-guide.md`, `docs/features/F-001-modules-v2.md` | Requirement/AC mapping and Validation references |
| UI scene, overlay, onboarding, tutorial | `docs/architecture/20-ui.md` through `23-ui-overlay-guidelines.md`, `docs/features/F-003-tutorial-campaign.md` | Design links, manual/visual limitations, Validation when actually run |
| Online, account, resume, bootstrap, platform | `docs/architecture/70-online-multiplayer.md`, `71-online-platform-backend-and-accounts.md`, `docs/features/F-002-online-resume-bootstrap.md` | ADR-0004 or a proposed successor, online runbook/manual-check links |
| Test command, runner, timeout, strict-exit behavior | `docs/testing.md`, `AGENTS.md`, relevant README/CI workflow | Validation command only when the recorded run used it |
| Deployment or operator procedure | Current root README and relevant runbook/workflow | Security/approval language and rollback instructions |
| Feature state or acceptance result | Owning Feature and associated Validation | Backlog/progress navigation; never a copied README status |

## Semantic mutation rules

### Requirement

- Preserve an existing ID when clarifying the same obligation without changing its normative meaning.
- Require product/Owner direction when the obligation, exclusions, or success threshold changes.
- Add a new Requirement ID for a genuinely distinct obligation; do not invent it from implementation alone.

### Feature

- Keep one stable aggregation page per Feature.
- Update state only from observed lifecycle evidence.
- Keep `deferred` and `not-covered` visible; a passing aggregate test does not change them.
- Link implementation entry points and source documents instead of copying their volatile details.

### ADR

- Edit a `proposed` ADR while the decision is under review.
- Preserve an `accepted` ADR's decision and rationale.
- Express a changed accepted decision in a new proposed ADR, link both sides, and await human acceptance.

### Validation

- Bind the report to the tested commit when clean, or state that it covers a working-tree state.
- Include exact commands, environment, exits, summary, stable evidence or hash, and uncovered scope.
- Use `completed + pass`, `fail`, or `inconclusive` only for what was actually exercised.
- Never cite `.godot/*.log` as the only long-term evidence.

## Synchronization report shape

```text
Documentation synchronization: COMPLETE | BLOCKED

Boundary
- Feature / Requirements:
- Diff or revision assessed:

Impact matrix
| Changed fact | Truth source | Action | File | Owner / reason |

Lifecycle and evidence checks
- Feature status:
- ADR effect:
- Validation effect:

Commands
| Command | Exit | Result |

Manual follow-up
- <semantic owner review, acceptance evidence, or none>
```

Use `BLOCKED` when the requested semantic update lacks authority or evidence. Mechanical link or index defects may be fixed within the synchronization pass.
