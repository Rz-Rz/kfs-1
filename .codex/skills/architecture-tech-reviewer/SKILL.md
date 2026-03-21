---
name: architecture-tech-reviewer
description: Review software architecture documents, technical design files, kernel architecture notes, and Rust system design docs for correctness, evidence, consistency, enforceability, and improvement opportunities. Use when reading architecture proposals, ADRs, subsystem docs, kernel design docs, or technical plans and you need corrections grounded in source code plus primary references.
---

# Architecture Tech Reviewer

Use this skill to review an architecture or technical design document against:
- the actual repository state
- explicit project constraints
- primary technical references
- internal consistency and enforceability

Keep the review practical. Prefer correcting claims, missing evidence, blurred boundaries, and weak rules over stylistic rewriting.

## Inputs

Collect only what is needed:
- the target document
- the most relevant code/build files
- any governing spec or constraints
- one or two reference files from `references/`

For kernel or OS work, start with:
- `references/doc_review_framework.md`
- `references/kernel_os_rust_checks.md`

## Review Workflow

1. Identify the document type and decision pressure.
   - Architecture proposal
   - ADR
   - subsystem design
   - implementation plan
   - requirements translation

2. Extract the document's concrete claims.
   - Current-state claims
   - target-state claims
   - dependency rules
   - interface rules
   - layering rules
   - validation claims

3. Verify claims against the repo.
   - Read the minimum code/build/doc files needed.
   - Separate `observed in repo` from `recommended by author`.
   - Flag any claim that is unsupported, stale, or contradicted by code.

4. Review with the checklist in `references/doc_review_framework.md`.
   Focus on:
   - scope and stakeholder clarity
   - view completeness
   - rationale quality
   - rule enforceability
   - terminology consistency
   - evidence and traceability

5. Review domain-specific concerns with `references/kernel_os_rust_checks.md`.
   Focus on:
   - monolithic vs microkernel language accuracy
   - real ABI edges vs internal module boundaries
   - Rust module/privacy boundaries
   - unsafe and hardware-access encapsulation
   - build-system coupling that silently changes architecture

6. Produce findings in severity order.
   Use this format:
   - `Critical`: incorrect or dangerous architectural claim
   - `Major`: unclear boundary, unenforceable rule, or unsupported conclusion
   - `Moderate`: terminology drift, weak rationale, missing evidence, or stale wording
   - `Minor`: grammar, clarity, formatting, or low-risk editorial issue

7. Prefer direct edits when the correction is clear.
   - Fix factual errors
   - tighten wording
   - add missing evidence hooks
   - remove contradictions

8. Leave open questions only when a real design decision is required.

## Output Rules

When asked for a review:
- findings first, ordered by severity, with file references
- then open questions or assumptions
- then a short change summary if you edited files

When asked to patch the document:
- preserve the author's architecture direction unless the evidence disproves it
- improve explicitness and verifiability
- avoid expanding the document with speculative future design

## Evidence Standard

Every important recommendation should be traceable to one of:
- repository evidence
- stated project constraints
- a primary reference
- a clearly labeled inference

Do not present a preference as a rule unless you can justify it.

## Reference Selection

Use `references/doc_review_framework.md` for general architecture-document review criteria.

Use `references/kernel_os_rust_checks.md` when the document concerns:
- kernels
- low-level systems
- Rust module structure
- ABI boundaries
- boot/runtime layering

