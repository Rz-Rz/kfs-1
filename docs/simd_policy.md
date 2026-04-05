# KFS-1 SIMD / MMX / SSE Policy

Purpose:
- define the current repo policy for MMX, SSE, and SSE2 work
- separate subject constraints from toolchain and runtime constraints
- state what later implementation phases must prove before accelerated code is allowed

This document is a current-state policy note.
It is not a claim that SIMD is already enabled in the kernel.

## 1. Subject Requirements And Non-Requirements

The subject requires:
- a 32-bit x86 kernel environment (`i386 (x86)` in the subject wording)
- GRUB bootability
- no host runtime dependencies

The subject does not explicitly require:
- that FPU, MMX, SSE, or SSE2 be disabled
- that FPU, MMX, SSE, or SSE2 be enabled

Current interpretation:
- the subject constrains the final kernel artifact and runtime environment
- it does not by itself settle the SIMD instruction policy

Source: [`docs/subject.pdf`](/home/motero/Code/kfs-1/docs/subject.pdf)

## 2. SIMD Is Not A Host-Linkage Question

MMX/SSE/SSE2 usage and host linkage are different concerns.

Host-linkage / freestanding questions are about whether the final kernel artifact:
- requests a host interpreter or dynamic loader
- carries dynamic-link metadata
- depends on unresolved host-provided symbols

Those properties are currently proven by the repo's freestanding checks in
[`docs/m0_2_freestanding_proofs.md`](/home/motero/Code/kfs-1/docs/m0_2_freestanding_proofs.md).

MMX/SSE/SSE2 usage is an instruction-set and runtime-state question instead:
- which CPU features are assumed or detected
- whether the kernel has initialized the required machine state
- whether the kernel preserves or constrains floating-point/SIMD state correctly

Policy consequence:
- do not claim that SSE/SSE2 is forbidden because it would "link against the system"
- do not claim that enabling SIMD is safe just because the artifact remains freestanding

## 3. Current Build Baseline

Current repo reality:
- the final kernel artifact remains ELF32 with machine `Intel 80386`
- the boot and link path remain 32-bit x86 (`elf_i386`, GRUB, `qemu-system-i386`)
- the Rust codegen target currently uses `i586-unknown-linux-gnu`

This is a deliberate current-state compromise.

Why the repo does not currently use `i686-unknown-linux-gnu`:
- the stable Rust `i686-unknown-linux-gnu` target carries an SSE2-based ABI expectation
- the repo's current freestanding kernel policy forbids accidental XMM/SSE instruction emission
- disabling `sse2` on the `i686` target is being phased into a hard compiler error

Current limitation:
- the repo currently satisfies the subject's 32-bit x86 requirement through the final artifact and boot path
- it does not currently guarantee a literal 80386 Rust instruction baseline

This limitation must remain explicit until it is either resolved or accepted as a deliberate compatibility boundary.

## 4. Current Kernel SIMD Policy

Today the kernel policy is:
- no MMX/SSE/SSE2 implementation is enabled in the freestanding kernel
- accelerated helper routines are not yet part of the runtime contract
- accidental XMM/SSE-family instruction emission is treated as a regression

This is a runtime-safety and toolchain-policy choice, not a subject-only choice.

The current no-SSE artifact gate lives in
[`scripts/stability-tests/freestanding-simd.sh`](/home/motero/Code/kfs-1/scripts/stability-tests/freestanding-simd.sh).

## 5. Preconditions For Future Enablement

Later phases must not introduce MMX/SSE/SSE2 execution until all of the following are owned explicitly:

1. CPU capability policy
- whether acceleration is optional or required
- which instructions are gated by runtime detection
- what the scalar fallback path is

2. Machine-state initialization
- required control-register and processor-state setup before accelerated instructions are legal
- explicit ordering relative to the existing boot and early-init path

3. Execution-boundary rules
- how floating-point/SIMD state is preserved, restored, or deliberately constrained
- what assumptions remain valid in the current single-kernel execution model

4. Proof obligations
- how capability detection is verified
- how pre-init use is prevented
- how freestanding/no-host-linkage proofs continue to hold

Until those are implemented and verified, MMX/SSE/SSE2 remains out of bounds for kernel execution.

## 6. Scalar-First Acceleration Rule

Future acceleration work must start from a scalar-correct baseline.

Required policy:
- scalar semantics remain canonical
- accelerated paths are optional optimizations over the same contract
- unsupported hardware or disabled policy paths must stay on the scalar implementation

This keeps the branch aligned with the current subject interpretation and avoids forcing a higher CPU baseline before the repo is ready to own it explicitly.

## 7. Compatibility Boundary

The branch has not yet decided whether future SIMD support will be:
- permanently optional with scalar fallback, or
- eventually tied to a stronger minimum CPU baseline

Current policy direction:
- prefer optional acceleration with scalar fallback
- avoid raising the minimum CPU baseline in Phase 1

Any later decision to require SSE2-class hardware must be made explicitly and documented as a compatibility change.

## 8. Ownership Boundaries

Future SIMD-related work must preserve the repo's existing ownership model.

Expected ownership split:
- `src/arch/` owns unavoidable raw assembly entry/runtime helpers and any truly arch-bound machine-state edges
- `src/kernel/core/` owns sequencing and runtime policy transitions into later SIMD-safe execution
- `src/kernel/machine/` owns typed low-level machine primitives that later layers can call without reintroducing raw assembly everywhere
- `src/kernel/klib/` owns scalar and accelerated helper dispatch once runtime policy says acceleration is legal
- `docs/` and `scripts/` own the written contract and the proof harness that guards it

Current Phase 2 realization:
- `src/kernel/machine/cpu.rs` owns CPUID-based capability probing
- `src/kernel/services/simd.rs` installs the Phase 2 scalar-only runtime policy
- `src/kernel/klib/simd.rs` exposes the canonical guardrail state that helper families can query
- `src/kernel/klib/memory/mod.rs` exposes the current memory-facing guardrail seam without importing `machine`

Disallowed pattern:
- ad hoc inline assembly or target-policy shortcuts scattered through unrelated service/driver/helper code

## 9. Proof Obligations

Later phases must prove each new SIMD/MMX/SSE2 capability at the right boundary.

Minimum proof obligations:
1. capability policy proof
- show how the kernel decides whether acceleration is allowed
- prove unsupported or disabled paths remain scalar

2. initialization-order proof
- show that required machine-state setup occurs before any accelerated path is reachable
- prove pre-init execution is impossible or rejected

3. artifact-policy proof
- if the repo continues to forbid unconditional SIMD emission, keep artifact checks that catch accidental XMM/SSE-family instructions
- if policy changes, update the artifact checks in the same change

4. semantic parity proof
- accelerated `memcpy` / `memset` / later helpers must preserve the scalar contract
- host and freestanding tests must prove parity and fallback behavior

5. freestanding proof continuity
- all SIMD work must leave the existing no-host-linkage proofs intact
- freestanding ELF checks remain mandatory even after acceleration is introduced

## 10. Open Risks

The following questions remain intentionally unresolved after Phase 1:
- **Strict 80386 compatibility:** the final artifact is ELF32 `Intel 80386`, but the current Rust baseline is still `i586-unknown-linux-gnu`
- **x87 interaction:** the repo does not yet define a full x87 policy and does not currently prove absence of every floating-point instruction family
- **MMX cleanup and transition rules:** later phases must define how MMX state and any required cleanup interact with subsequent floating-point/SSE use
- **Future minimum CPU policy:** the branch has not yet decided whether optional acceleration remains permanent or later evolves into a stronger CPU baseline requirement

These are design risks to manage explicitly, not details to hand-wave away in later implementation phases.

---
*Policy written: 2026-04-05*
*Update when SIMD ownership or compatibility rules change*
