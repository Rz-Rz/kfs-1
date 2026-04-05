---
phase: 01
slug: simd-policy-subject-contract
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-05
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | repo shell tooling + GSD planning parsers |
| **Config file** | none — existing repo/tooling covers this phase |
| **Quick run command** | `node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null` |
| **Full suite command** | `make test-plain` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null`
- **After every plan wave:** Run `make test-plain`
- **Before verification:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | COMP-04 | integration | `node ~/.codex/get-shit-done/bin/gsd-tools.cjs roadmap analyze >/dev/null` | ✅ | ⬜ pending |
| 01-02-01 | 02 | 2 | COMP-04 | integration | `node ~/.codex/get-shit-done/bin/gsd-tools.cjs init progress >/dev/null` | ✅ | ⬜ pending |
| 01-03-01 | 03 | 3 | COMP-04 | integration | `make test-plain` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Existing repo/tooling already provides the commands needed for this docs-only phase.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Documentation wording is technically coherent | COMP-04 | Requires judgment about clarity and contradiction removal | Read `docs/simd_policy.md`, `docs/kernel_architecture.md`, and `docs/m0_2_freestanding_proofs.md` together and confirm they make one consistent claim set |

---

## Validation Sign-Off

- [x] All tasks have automated verify or existing infrastructure
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all missing references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
