---
phase: 01-simd-policy-subject-contract
status: ready_for_execution
workflow_step: 3_of_5
created: 2026-04-05
---

# Phase 1: SIMD Policy & Subject Contract - Test Contract

## Workflow Position

1. Discuss
2. Plan
3. Test ← current file
4. Execute
5. Verify

## Test Matrix

| Category | Status | Why | Planned files | Command |
|----------|--------|-----|---------------|---------|
| BDD | n-a | No user-facing runtime behavior changes in this docs-only phase | `docs/simd_policy.md`, `docs/kernel_architecture.md`, `docs/m0_2_freestanding_proofs.md` | N/A |
| Unit | n-a | No production code or library semantics change in this phase | `docs/simd_policy.md` | N/A |
| Integration | required | The planning/roadmap artifacts and repo docs must still parse and remain coherent with the existing branch state | `.planning/phases/01-simd-policy-subject-contract/*`, `docs/*.md` | `node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null && node ~/.codex/get-shit-done/bin/gsd-tools.cjs init progress >/dev/null` |
| E2E | n-a | No end-to-end runtime flow changes are introduced by this policy phase | `docs/simd_policy.md` | N/A |

## RED / GREEN Expectations

- Tests are written before implementation for every `required` category unless a plan explicitly states otherwise.
- Execution should leave visible evidence of test-first progression in commits or summary notes.
- If reality diverges, the executor must explain the deviation in the plan summary.

## Execution Gate

- [x] BDD decision is explicit
- [x] Unit decision is explicit
- [x] Integration decision is explicit
- [x] E2E decision is explicit
- [x] Every `n-a` has a concrete reason
- [x] Every `required` row has planned files or commands
