# Commentary Guidelines

This project now expects comments to teach, not just label.

## Goal

Write comments so that a junior developer with very little systems experience can still follow what the code is doing.

## Rules To Follow

- Every function must have a comment directly above it.
- Explain what the function does in plain language before talking about low-level details.
- Do not assume the reader already knows words like "volatile", "pointer", "linker symbol", or "VGA". If one of those ideas matters, explain it in simple words.
- Prefer short comments that answer "what is this for?" and "why is it safe or necessary?".
- Keep comments honest. If a function is limited, risky, or only exists for tests, say so clearly.
- Match the file's language and style:
  - Use `///` doc comments for Rust functions that are part of the codebase API or core behavior.
  - Use `//` comments for Rust test functions when a quick test explanation is enough.
  - Use `#` comments above shell functions.
- Do not describe obvious syntax line by line. Explain intent, not punctuation.
- Do not change program behavior while adding commentary unless a real bug must also be fixed.
- When a function is `unsafe`, mention what the caller must guarantee in simple terms.

## Good Comment Pattern

Use a two-part structure when helpful:

1. First sentence: say what the function is for.
2. Second sentence: say the important detail a new reader would otherwise miss.

Example:

```rust
/// This copies bytes from one memory area into another.
/// The caller must make sure both areas are valid for the full copy length.
pub unsafe fn memcpy(dst: *mut u8, src: *const u8, len: usize) -> *mut u8 {
```

## Things To Avoid

- Comments that only rename the code in English.
- Comments that are so advanced they require more knowledge than the code.
- Very long comment blocks for tiny helper functions.
- Jokes, vague notes, or outdated explanations.

## Review Checklist

Before finishing a change, check these points:

- Every new or existing function has a nearby comment.
- The wording is understandable to a beginner.
- Unsafe behavior and special cases are explained.
- Test comments describe the behavior being checked.
- The comments still match the real code after the final edit.
