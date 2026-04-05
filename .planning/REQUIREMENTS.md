# Requirements: KFS-1 SIMD/MMX Enablement

**Defined:** 2026-04-05
**Core Value:** Enable SIMD acceleration only if it is architecturally safe, freestanding, and fully compatible with the kernel's boot/runtime contract

## v1 Requirements

### Compatibility & Subject Compliance

- [x] **COMP-01**: Kernel remains GRUB-bootable after SIMD/MMX support work lands
- [x] **COMP-02**: Final kernel artifact remains statically linked with no host runtime library dependencies
- [x] **COMP-03**: Scalar fallback path remains available when runtime policy or CPU capability does not allow MMX/SSE/SSE2 acceleration
- [x] **COMP-04**: Architecture docs explain the SIMD policy, CPU baseline, and freestanding constraints without ambiguity

### Hardware & Runtime Ownership

- [x] **HW-01**: Kernel determines MMX/SSE/SSE2 capability before entering any accelerated path
- [x] **HW-02**: Kernel initializes required FPU/MMX/SSE control state before any MMX/SSE/SSE2 instruction is executed
- [x] **HW-03**: Kernel defines and enforces behavior for unsupported or unavailable FP/SIMD execution paths
- [x] **HW-04**: Kernel defines how FP/SIMD state is preserved or explicitly constrained across execution boundaries

### Accelerated Primitives

- [x] **ACC-01**: `memcpy` gains an optional accelerated implementation with the same semantics as the scalar path
- [x] **ACC-02**: `memset` gains an optional accelerated implementation with the same semantics as the scalar path
- [x] **ACC-03**: Accelerated implementations live behind canonical module ownership instead of scattered ad hoc inline asm

### Verification

- [x] **VER-01**: Host tests prove semantic parity for scalar and accelerated memory/helper routines
- [x] **VER-02**: Boot/stability tests prove freestanding/no-host-linkage behavior still holds after SIMD work
- [x] **VER-03**: Boot/stability tests prove SIMD usage is policy-driven and not emitted accidentally
- [x] **VER-04**: Rejection/architecture tests prevent bypasses around the approved SIMD ownership boundaries

## v2 Requirements

### Future Acceleration

- **ACCX-01**: String helper routines gain optional accelerated implementations where worthwhile
- **ACCX-02**: VGA scroll/blit or wider screen-buffer paths gain optional accelerated implementations where worthwhile
- **ACCX-03**: Performance characterization exists for scalar vs accelerated kernel helper paths

## Out of Scope

| Feature | Reason |
|---------|--------|
| AVX/AVX2/AVX-512 | Not necessary for the subject or current kernel stage |
| x86_64 porting | Separate architecture effort |
| User-mode FP/SIMD ABI support | Kernel does not yet expose that execution model |
| Raising the kernel to an unconditional SSE2-only baseline | Too risky before the compatibility policy is decided |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| COMP-01 | Phase 5 | Complete |
| COMP-02 | Phase 5 | Complete |
| COMP-03 | Phase 2 | Complete |
| COMP-04 | Phase 1 | Complete |
| HW-01 | Phase 2 | Complete |
| HW-02 | Phase 3 | Complete |
| HW-03 | Phase 2 | Complete |
| HW-04 | Phase 3 | Complete |
| ACC-01 | Phase 4 | Complete |
| ACC-02 | Phase 4 | Complete |
| ACC-03 | Phase 4 | Complete |
| VER-01 | Phase 4 | Complete |
| VER-02 | Phase 5 | Complete |
| VER-03 | Phase 5 | Complete |
| VER-04 | Phase 5 | Complete |

**Coverage:**
- v1 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0

---
*Requirements defined: 2026-04-05*
*Last updated: 2026-04-05 after Phase 6 closeout*
