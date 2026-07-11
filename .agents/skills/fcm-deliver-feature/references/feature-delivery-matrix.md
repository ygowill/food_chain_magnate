# Feature delivery matrix

Use this reference to choose the minimum responsible process. Do not lower a level to avoid a gate.

## Change levels

| Level | Typical scope | Required artifacts | Review / evidence |
|---|---|---|---|
| L1 | Local, reversible behavior or copy change; no architecture/data/security impact | Issue or Feature link, Why, targeted test, docs impact | Normal review; manual check when UI changes |
| L2 | New capability, cross-file/layer behavior, save/replay or protocol-compatible extension | Feature, stable Requirements/AC, Plan when multi-step, Architecture update, Validation | Independent technical review; strict AllTests; relevant manual/platform evidence |
| L3 | Authority/security change, migration, destructive operation, incompatible protocol/data, release infrastructure | Feature, ADR, Plan, rollback/runbook, explicit owner approval, Validation | Required human approval; cold-start acceptance; production operations remain out of scope until authorized |

## Artifact decision table

| Condition | Feature | Requirement | ADR | Plan | Validation |
|---|---:|---:|---:|---:|---:|
| New independent user/system capability | yes | yes | if lasting trade-off | usually | yes |
| Material expansion of an existing capability | update | update/add | if decision changes | if multi-step | yes |
| Behavior-preserving refactor | link existing | unchanged | only if architecture policy changes | usually | baseline + comparison |
| Small reversible bug/copy change | optional link | unchanged unless semantics change | no | no | PR evidence may suffice |
| Protocol, persistence, authority, migration | yes | yes | yes | yes | yes plus rollback evidence |

## FCM verification routing

- Pure engine/rule behavior: add deterministic `core/tests/*_test.gd` coverage.
- Module packaging/content: test dependency planning, strict loading, schema/reference failures, and disabled-module absence.
- Gameplay wiring: test validators/actions and command/replay determinism.
- UI scenes/controllers: add headless scene/contract coverage and manual visual evidence when appearance or interaction matters.
- Online behavior: separate in-process logic tests from real multi-client/platform/WebSocket validation.
- Archive/replay/state changes: add round-trip, compatibility, hash/determinism, and failure-path tests.
- Performance claims: capture scenario, command count/data size, environment, timings, comparison, and raw evidence.

## Status movement

`discovery → planned → in-progress → validation → done`

Move forward only when the corresponding gate passes. Move back or remain in place when evidence reveals missing scope. A passing aggregate test suite does not convert an uncovered user path into `pass`.
