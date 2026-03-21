# Architecture Document Review Framework

This reference compresses guidance from architecture-documentation practice into a review checklist.

Primary references used to derive this checklist:
- SEI Views and Beyond overview: architecture should be documented as relevant views plus cross-view information such as rationale, constraints, and mappings.
- SEI documentation guidance: documentation should stay current, fit stakeholder needs, and be reviewed for fitness of purpose.

## What a strong architecture document should answer

1. What is being described?
   - system or subsystem scope
   - current state vs target state
   - assumptions and constraints

2. Why does this architecture exist?
   - drivers, tradeoffs, and rationale
   - why alternatives were rejected

3. How is it structured?
   - module decomposition or layer view
   - dependency relations
   - interfaces and boundaries
   - mapping between views if more than one is used

4. How can readers use it?
   - what rules are enforceable
   - what decisions are still open
   - how the architecture is validated in code/tests/build rules

## Review questions

### Scope and intent
- Does the document clearly say whether it describes the current repo, a target architecture, or both?
- Are requirements and non-goals explicit?
- Does it distinguish project constraints from author preferences?

### Views and consistency
- Is there at least one clear structural view?
- If the document mixes build, module, ABI, and runtime views, does it say so explicitly?
- Do tables, examples, and prose use the same terms for the same concepts?

### Rationale and alternatives
- Are alternatives compared using criteria relevant to the project?
- Does the selected option follow from the evidence, or does the document jump to a conclusion?
- Are tradeoffs named, not implied?

### Enforceability
- Can the stated rules be checked in code, build logic, tests, or review?
- Would two maintainers make the same placement decision for a new file?
- Are exceptions explicitly listed?

### Evidence quality
- Are claims about current state backed by file paths, build rules, or symbols?
- Are claims about external practice grounded in primary references?
- Is speculation labeled as speculation?

### Maintenance quality
- Will the document become stale if one file moves?
- Are examples representative of the real repo?
- Is the doc short enough to stay updated but specific enough to guide design?

## Common failure modes

- Mixing current-state description with target-state prescription without marking the switch
- Treating build artifacts as architecture without explaining why
- Naming layers without dependency rules
- Calling something an interface without defining who may call it
- Using diagrams or tables that are not backed by repository evidence
- Stating architectural intent that cannot be enforced mechanically or socially

