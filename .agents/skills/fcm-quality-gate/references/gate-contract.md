# FCM gate contract

Use this reference to select checks and format the result. Apply the strongest row touched by the change; combine rows when the diff spans multiple surfaces.

## Verification matrix

| Changed surface | Minimum verification | Additional evidence boundary |
|---|---|---|
| Markdown or governed metadata only | `python3 tools/docs_governance.py`; inspect source accuracy and semantic owner | A passing link/schema check does not prove the prose is true |
| `core/`, `gameplay/`, `modules/`, gameplay JSON, or `project.godot` | Relevant targeted scene, then strict AllTests, then docs governance | Map affected Requirement/AC; check deterministic and compatibility impact |
| `ui/`, `.tscn`, input, visual assets, or tutorial behavior | Targeted scene or smoke path, strict AllTests, docs governance | Record required visual/manual checks; automated tests cannot prove layout or usability |
| Online, platform, account, resume, or bootstrap behavior | Targeted online tests, strict AllTests, docs governance | Require real multi-process/platform/manual evidence for claims outside the headless suite |
| Test runner or CI workflow | Shell/YAML or workflow-specific checks, strict AllTests when test semantics change, docs governance | Confirm failure propagation, timeout behavior, artifact identity, and no false-green path |
| Tooling or operational command | Tool self-test or syntax check plus docs governance | Verify documented command, permissions, destructive effects, and rollback expectations |
| `.agents/skills/`, Skill routing, registry, or Skill checker | `python3 tools/skills_governance.py`; inspect trigger boundaries and Eval coverage | A structural PASS does not prove real-task benefit or independent acceptance quality |

Use the repository commands exactly unless the changed code exposes a more specific existing runner:

```bash
tools/run_headless_test.sh res://ui/scenes/tests/<target>_test.tscn <TargetName> <timeout>
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit
python3 tools/docs_governance.py
python3 tools/skills_governance.py
```

Do not hide a failing targeted test behind a later passing suite. Do not treat benign shutdown leak allowances in the runner as proof that unrelated error lines are safe.

## Evidence levels

| Evidence | Allowed claim |
|---|---|
| Command and terminal result from the current dirty working tree | Local readiness of that exact working-tree state only |
| Command and result bound to a clean commit | Commit-local verification; still not remote CI |
| CI run/Artifact bound to commit and run ID, with retained log or hash | Durable automated evidence for the recorded scope |
| Checked `docs/validation/VAL-*.md` with commit, environment, commands, verdict, limitations, and stable evidence | Long-lived summary for only the report's declared scope |
| Reviewer identity plus real user/platform steps and artifacts | Manual acceptance for only the exercised path and environment |

Never upgrade one level into another. In particular, a local `.godot/AllTests.log`, a previous commit's result, or an implementation author's assertion cannot close a manual acceptance criterion.

## Verdict rules

Issue `PASS` only if:

- the intent and comparison boundary are unambiguous;
- every changed file belongs to the scope;
- every required check completed with a successful exit and expected result;
- affected Requirement/AC rows have adequate evidence;
- current Architecture, Feature, ADR, command, and operational truth sources are synchronized;
- no blocking risk, unexplained worktree mutation, or required manual coverage remains.

Issue `BLOCK` otherwise. Describe environment unavailability or a partial run as an incomplete-verification blocker, not as a test failure and not as a pass.

## Required report

```text
PASS | BLOCK

Scope
- Feature / Small Change reason:
- Compared boundary:
- Revision: <clean commit | working tree at HEAD>

Blocking findings
- <none | severity, path/context, consequence, required resolution>

Checks
| Command | Exit | Result | Evidence identity |

Acceptance evidence
| Requirement / AC | Verdict | Evidence | Limitation |

Worktree integrity
- Before / after status:
- New artifacts or unexplained changes:

Limitations
- <manual, platform, CI, environment, or coverage boundary>

Next actions
1. <separate implementation, documentation, CI, or acceptance action>
```

Keep warnings separate from blockers. Do not add a reassuring summary that contradicts a `BLOCK` verdict.
