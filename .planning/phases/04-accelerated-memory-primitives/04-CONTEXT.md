# Phase 4: Accelerated Memory Primitives - Context

**Gathered:** 2026-04-05
**Status:** Ready for planning and execution

<domain>
## Phase Boundary

This phase owns the first helper-family integration on top of the Phase 3 SIMD runtime state.

The kernel must:
- preserve the existing scalar `memcpy` and `memset` semantics exactly
- introduce one canonical dispatch seam inside `klib::memory`
- keep helper ownership inside `src/kernel/klib/memory/` rather than scattering SIMD decisions through callsites
- make selected backend and fallback behavior observable in both host and boot tests

This phase does not yet broaden SIMD to unrelated helper families or VGA/terminal call sites. It establishes the memory-family contract first.

</domain>

<decisions>
## Implementation Decisions

### Dispatch policy
- **D-01:** `SSE2` is the preferred future optimized tier for memory helpers on this branch; `MMX` remains optional and deferred unless it becomes necessary for legacy coverage.
- **D-02:** `Scalar` remains the canonical semantic baseline and the only allowed fallback when runtime policy, CPU capability, or backend availability blocks acceleration.
- **D-03:** Dispatch lives behind `src/kernel/klib/memory/mod.rs`; callers continue to use `memory::memcpy` / `memory::memset` and do not choose instruction families directly.

### Architecture contract
- **D-04:** Backend selection logic belongs to `klib::memory` and may query the installed SIMD policy, but it must not import `machine` or bypass `services::simd`.
- **D-05:** Boot/runtime proof remains marker-based through `core::init` plus `services::diagnostics`; `klib` does not write diagnostics directly.
- **D-06:** Until a real accelerated backend lands, the dispatch seam must stay explicitly scalar in freestanding artifacts rather than pretending acceleration exists.

### Testing contract
- **D-07:** Phase 4 must prove both semantic parity and selection behavior: host tests cover helper semantics and backend selection; boot tests cover runtime-selected backend markers; umbrella tests keep the whole kernel contract green.
- **D-08:** Artifact-policy widening is a separate explicit step. Phase 4 may prepare the dispatch layer before permitting new SIMD data-path instructions in the kernel artifact.

</decisions>

<canonical_refs>
## Canonical References

### Existing branch policy and requirements
- `docs/simd_policy.md`
- `docs/kernel_architecture.md`
- `.planning/REQUIREMENTS.md` — `ACC-01`, `ACC-02`, `ACC-03`, `VER-01`
- `.planning/ROADMAP.md` — Phase 4 goal and success criteria

### Existing code surfaces
- `src/kernel/klib/memory/mod.rs`
- `src/kernel/klib/memory/imp.rs`
- `src/kernel/klib/simd.rs`
- `src/kernel/services/simd.rs`
- `src/kernel/core/init.rs`

### Existing proof surfaces
- `tests/host_memory.rs`
- `tests/host_simd_policy.rs`
- `scripts/tests/unit/memory-helpers.sh`
- `scripts/boot-tests/memory-runtime.sh`
- `scripts/stability-tests/freestanding-simd.sh`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `src/kernel/klib/memory/imp.rs` already contains the canonical scalar byte-loop behavior.
- `src/kernel/klib/simd.rs` already exposes the runtime policy surface that helper families must query.
- `src/kernel/core/init.rs` already performs a memory sanity path and emits helper markers during test boots.

### Established constraints
- `klib` must not import `machine`, `drivers`, or `services`.
- The freestanding artifact currently rejects accidental SIMD data-path instructions.
- Host tests must link through `src/lib.rs`, not through fake-root source inclusion.

### Integration points
- The natural backend-observation point is the existing memory helper sanity path in `core::init`.
- The natural unit-proof surface is the existing `tests/host_memory.rs` plus the memory helper shell harness.
- Future optimized backends should appear as private `klib::memory` leaves under the same family, not as free-floating asm helpers.

</code_context>

<specifics>
## Specific Ideas

- Add a private dispatch leaf that maps runtime policy plus backend availability to a `MemoryBackend`.
- Expose `memcpy_backend()` and `memset_backend()` through the memory facade so boot tests can observe actual selection without bypassing `klib`.
- Extend docs to say how Phase 4 proves fallback today and how later plans will prove real SSE2 selection.

</specifics>

<deferred>
## Deferred Ideas

- Real `SSE2` data-path implementations for `memcpy` and `memset`
- `memmove`
- VGA/terminal integration
- Any `MMX` backend unless a clear compatibility need appears

</deferred>

---
*Phase: 04-accelerated-memory-primitives*
*Context gathered: 2026-04-05*
