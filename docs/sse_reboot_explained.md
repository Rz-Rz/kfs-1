# Why The Kernel Looked Like It Was Rebooting (SSE Crash Guide)

This file explains a real bug we hit in this repo:

- tests passed
- but QEMU in graphical mode looked like it was rebooting over and over
- user text did not stay visible

The root cause was not GRUB.  
The root cause was CPU instructions (SSE) being used too early.

---

## 1. What You Saw

Symptoms:

- QEMU window flickers
- you keep seeing early boot messages (BIOS/GRUB style text)
- your own `vga_puts(...)` text is missing or unstable

What this usually means in kernel work:

- the kernel crashed very early
- machine reset happens fast
- then boot starts again

To a human, that feels like a "reboot loop flicker".

---

## 2. Quick Mental Model (No Prior Knowledge Needed)

Think of CPU features like tools in a workshop:

- basic integer math tools are ready from the start
- advanced SIMD/SSE tools are *not* always ready at the first instruction

If you use an advanced tool before turning it on, the CPU throws an exception.
In early boot, that exception can become a reset loop if handlers are not set up yet.

---

## 3. What Is SSE In Simple Words?

SSE is a CPU feature for fast math and data operations.
It uses special registers (`xmm0`, `xmm1`, ...).

In assembly, SSE instructions look like:

- `xorps`
- `movaps`

In our bug, these appeared inside `vga_putusize`, even though we never wrote SSE by hand.
The compiler generated them.

---

## 4. Why This Happened In Our Code

We had code that looked harmless:

```rust
let mut digits = [0u8; MAX_USIZE_DECIMAL_DIGITS];
```

The compiler may choose an SSE instruction sequence to zero that local array quickly.
That optimization is fine in normal userspace apps, but dangerous in early kernel boot.

So the issue was:

1. `kmain` called `vga_putusize`
2. `vga_putusize` executed compiler-generated SSE instructions
3. SSE was not initialized/enabled for this boot stage
4. CPU faulted and the VM restarted

---

## 5. Why Tests Still Passed

Host tests (`rustc --test`, shell checks) mostly verify logic and symbols.
They do not always execute the exact same early-boot CPU environment as real QEMU boot.

So you can have:

- logic tests = green
- real boot = crash

Both can be true at the same time.

---

## 6. The Fix We Applied

We changed the formatting path to avoid zero-initializing local arrays in a way that can trigger SSE codegen.

Instead of:

```rust
let mut digits = [0u8; N];
```

we use `MaybeUninit<[u8; N]>` and only write the bytes we need.

This keeps the function in simple integer/byte operations for this use case.

Files involved:

- `src/kernel/vga.rs` (`vga_putusize`)
- `src/kernel/vga/vga_format_impl.rs` (format helper path)

### 6.1 What `MaybeUninit<[u8; N]>` Means

`MaybeUninit<T>` means:

- "I have reserved memory for `T`"
- "but I am telling Rust this memory is not fully initialized yet"

For our case, `T` is `[u8; N]`, so:

- we reserve space for `N` bytes
- we do **not** ask the compiler to fill all `N` bytes with zero first

That second point is the key.  
No forced "fill everything now" step means less chance of SIMD/SSE code in this boot path.

### 6.2 Step-By-Step: How The Code Actually Works

From `vga_putusize`:

```rust
let mut digits_uninit = core::mem::MaybeUninit::<[u8; MAX_USIZE_DECIMAL_DIGITS]>::uninit();
let digits = unsafe { &mut *digits_uninit.as_mut_ptr() };
let rendered = format_usize_decimal(value, digits);
```

What happens in plain language:

1. `MaybeUninit::uninit()` reserves stack space for `[u8; 20]` but does not initialize all bytes.
2. `as_mut_ptr()` gives a raw pointer to that reserved memory.
3. We temporarily view that pointer as `&mut [u8; 20]` and pass it to `format_usize_decimal`.
4. `format_usize_decimal` writes only the decimal digits we need (`'0'..'9'`) into that buffer.
5. It returns a slice (`rendered`) that points only to the bytes it wrote.
6. `vga_putusize` iterates only over `rendered` and prints those bytes.

### 6.3 Why This Avoids The Old Problem

Old version:

- local array started as `[0u8; N]`
- compiler could emit a fast bulk-zero sequence
- that sequence sometimes used SSE instructions (`xorps`, `movaps`)

New version:

- local array starts as "uninitialized reserved memory"
- we manually write required bytes with integer operations
- there is no requirement to zero the whole array first

So we removed the pattern that encouraged SSE in this path.

### 6.4 Safety Rules (Very Important)

`MaybeUninit` is powerful but easy to misuse.  
The code is safe here because we follow strict rules:

1. Never read uninitialized bytes.
2. Only return/read the part that was explicitly written.
3. Do not assume the entire `[u8; N]` is valid.

How our code enforces that:

- `format_usize_decimal` writes each produced digit with `core::ptr::write(...)`
- then returns a slice built from the initialized region only
- printing loop reads only from that returned slice

If we read outside that returned range, it would be undefined behavior.

### 6.5 Junior-Friendly Memory Picture

Imagine 20 lockers:

- with `[0u8; 20]`, you first put a `0` card in every locker (all 20)
- with `MaybeUninit<[u8; 20]>`, lockers exist but may contain garbage cards
- then you place real digit cards only in the lockers you need (for example just 3 lockers for `123`)
- when printing, you open only those 3 known-good lockers

This is why it is both faster for this boot path and safer than touching unknown lockers.

---

## 7. How To Verify This Specific Problem

Build and inspect assembly:

```bash
make clean
make all arch=i386
objdump -d build/kernel-i386.bin | sed -n '/<vga_putusize>:/,/^$/p'
```

If you still see `xorps` / `movaps` in this early path, you are still using SSE there.

Also run the full gate:

```bash
make test arch=i386
```

And for runtime behavior:

```bash
make iso-in-container
make run
```

---

## 8. How To Avoid This In Future Kernel Code

Use this checklist for early boot code (before full CPU setup):

1. Keep code integer-only and simple.
2. Avoid patterns that may trigger bulk zeroing/vectorized code in hot boot paths.
3. Inspect assembly for critical boot functions (`objdump` is your friend).
4. Treat "tests pass but QEMU reboots" as a likely low-level environment mismatch.
5. Debug with `-no-reboot -no-shutdown` when needed, so crashes are easier to inspect.

---

## 9. Important Distinction

Seeing some BIOS/GRUB text at startup is normal.  
Seeing that screen repeatedly with no stable kernel output is not normal.

Normal:

- one boot flow
- then your kernel text appears and stays

Problem case:

- repeated early boot text
- your kernel output never stabilizes

That second case is exactly what this SSE-early-use bug can cause.
