# Acceptance Evidence Policy

Use this policy to decide whether evidence proves the requested acceptance claim. Match evidence to the behavior under test; a stronger-looking artifact cannot compensate for testing the wrong layer.

## Evidence classes

| Class | Suitable for | Minimum record | Common limitation |
|---|---|---|---|
| Automated | Deterministic logic, contracts, regressions, headless-safe flows | Exact command, commit, environment, exit code, test identity, result summary | Cannot prove real UI perception, platform integration, network topology, or performance unless those are actually exercised |
| Manual | Visual behavior, interaction, wording, accessibility, usability, exploratory flows | Named step, expected and observed result, build/commit, environment, reviewer role, dated capture or notes | Subjective and hard to reproduce unless the procedure and context are explicit |
| Platform | Real backend/API, authentication, multi-client/process, Web export, device, weak network, deployment | Commit/build, platform/environment, topology/account roles, steps, timestamps, observed result, stable artifact | A local mock or single process does not substitute for it |
| Inspection | Static contracts, links, configuration, ownership boundaries, forbidden dependencies | Exact files/lines or generated report, revision, method used | Proves structure, not runtime behavior |

Combine evidence classes when the Requirement crosses layers. For example, use automated tests for bootstrap state transitions and platform evidence for real multi-client recovery.

## Durability levels

Treat evidence as durable only when another reviewer can retrieve it later and bind it to the validated revision.

Durable evidence includes:

- a committed governed Validation report containing commands, environment, exit codes, result summaries, limitations, and exact commit;
- a commit-bound CI artifact with stable run URL, hash or artifact identity, and retention period;
- stable approved object storage with revision, hash, access expectations, and retention metadata;
- a committed small fixture or structured result when repository policy permits it.

Ephemeral evidence includes:

- ignored `.godot/` logs, local terminal output, temporary files, and uncommitted screenshots;
- an agent's statement that a test passed;
- a screenshot without build, environment, steps, and expected/observed context;
- a CI status or artifact from another commit;
- a link whose access or retention is unknown.

An ignored `.godot/` log may support a local observation, but never label it durable or use it as the sole long-term proof. Preserve a governed summary and, when raw logs matter, upload a commit-bound artifact with retention and integrity metadata.

## Evidence matching rules

1. Bind every item to the exact commit or explicitly recorded uncommitted diff.
2. Require the evidence mode stated or implied by the Requirement. Do not downgrade real-platform, multi-process, performance, or usability acceptance to headless automation.
3. Require both positive and relevant negative/boundary checks.
4. Separate test success from scope completeness. A green suite can coexist with an `inconclusive` acceptance verdict.
5. Record warnings and leaks even when the test process exits successfully.
6. Treat mocks as proof of caller behavior only; do not claim they prove the mocked service or platform.
7. Treat historical evidence as context unless it matches the current commit, material configuration, and environment.
8. Preserve missing evidence as a visible matrix row; never delete or silently defer it to obtain `pass`.

## Verdict decision table

| Condition | Criterion verdict | Overall effect |
|---|---|---|
| Required behavior observed with matching, sufficient evidence and no contradictory evidence | `pass` | Remains eligible for `pass` |
| Required behavior contradicts observation, regression is reproduced, or a Non-goal is violated | `fail` | Overall `fail` |
| Required evidence mode was not run, evidence targets the wrong revision/layer, source contracts conflict, or independence is absent | `inconclusive` | Overall `inconclusive` unless another criterion fails |

Do not use `pass with caveats`. If a caveat affects a required criterion, assign `inconclusive` or `fail`. If it is genuinely outside scope, state the exclusion and show why the governing Feature and Requirements permit it.

## Independence and authority

- Keep implementer and acceptance validator roles separate. If the validator changed the implementation under review, invalidate the independent verdict and require a fresh validator.
- Permit the validator to create an evidence report only when requested; do not let that authorship become product implementation authorship.
- Treat a validator `pass` as evidence for an owner decision, not as authorization to mark a Feature `done`, merge, release, deploy, or waive unmet coverage.
- Escalate unresolved intent or source conflicts to the responsible human owner. Return `inconclusive` until the contract is clarified in the appropriate truth source.
