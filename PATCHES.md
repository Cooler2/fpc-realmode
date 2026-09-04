# Patches in this fork

Free Pascal for 16-bit x86 real mode: a small set of fixes on top of a **pinned
upstream snapshot**.  The base does not move between releases: it is rebased onto a newer
upstream snapshot about once a year, with a full CI run.  Consumers pin a
release tag, not a branch.

|  |  |
| --- | --- |
| Base | [`da47439dd51b`](https://github.com/fpc/FPCSource/commit/da47439dd51b003bc45f1ad41bd2ca24614d13f7) — upstream `main`, 2026-09-01 |
| Base tag | `base/2026.1` |
| Release line | `v2026.1` |
| Version banner | `fpc -iW` reports `3.3.1-realmode` |

The base is a snapshot of `main`, not 3.2.2: the i8086 backend has moved
substantially since 3.2.x, and both fixes below apply to code that does not
exist in the 3.2.x branch.

Upstream is <https://gitlab.com/freepascal.org/fpc/source>.  Merge requests are
sent from the GitLab fork `Cooler21/fpcsource`; nothing is submitted upstream
from this repository.

## How this file is kept

Every patch must reach exactly one of two states:

- **submitted** — an upstream issue and merge request exist and are linked
  here.  Once it is merged upstream it disappears from this file at the next
  rebase, because the base already contains it.
- **fork-only** — it will not be submitted, and the reason is written down
  here.

Anything that has reached neither state yet carries a dated TODO.  A patch left
without one of the three a year from now is unanswerable: nobody will be able to
tell whether it fixed something or was an experiment.

## Branches

The **integration branch** `i8086-integration` is base plus every topic branch
below, in the listed order.  It is never committed to directly — it is rebuilt
from the topic branches.  That is the only discipline that keeps a long-lived
fork from silently accumulating changes nobody can account for.

| # | Patch | Topic branch | State |
| --- | --- | --- | --- |
| 1 | FPC_MOVE parameter order in `g_concatcopy_move` | `i8086-concatcopy-move-param-order` | **submitted**: issue [#41850], MR [!1533] |
| 2 | Segment override dropped when a copy is lowered to FPC_MOVE | `i8086-fpcmove-segment-override` | TODO 2026-09-03: file issue, open MR |
| 3 | Version banner marker | `product-version-marker` | **fork-only** |
| 4 | This file | `product-patches-manifest` | **fork-only** |
| 5 | Build workflow | `product-ci` | **fork-only** |
| 6 | Callee-saved registers pushed and popped on i8086 | `i8086-push-saved-regs` | in `i8086-integration` (2026-09-04); not submitted |
| 7 | Near pointer in a register parameter tried to store its segment | `i8086-register-paraloc-near-pointer` | in `i8086-integration` (2026-09-04); not submitted |
| 8 | Frame omitted in i8086 procedures without temps | `i8086-omit-leaf-frame` | in `i8086-integration` (2026-09-04); not submitted |

### 1. FPC_MOVE parameter order in `g_concatcopy_move`

`tcg.g_concatcopy_move` filled the three parameter locations of the `FPC_MOVE`
helper call in the order 3, 2, 1 without checking `pd.is_pushleftright`.  On a
target that pushes parameters left to right — i8086 — the helper received
`@source` where it expected `count`.

Without this fix nothing runs on `i8086-msdos` at all: the RTL is itself full of
record assignments, so the reversed call corrupted memory at the first access to
the file structures.  The defect became reachable for x86 in `b826ad8b7e` (May
2024) and survived a year and a half because no CI covers the target — which is
the reason this repository exists.

Regression test: `tests/webtbs/tw41850.pp`.

### 2. Segment override dropped when a copy is lowered to FPC_MOVE

`Tcgx86.g_concatcopy` hands its references to `g_concatcopy_move` when
`getcopymode` returns `copy_fpc_move`.  The helper takes plain pointers, so in a
near-data memory model there is nowhere to put a segment:
`tcg8086.a_loadaddr_ref_cgpara` clears it and the copy runs inside `DGROUP`.

Affected: an `absolute Seg:Ofs` variable — which is also how the RTL implements
the Turbo Pascal compatible `Mem`, `MemW` and `MemL` arrays — a dereferenced far
pointer, and a dereferenced `near cs`/`near es` pointer.  The patch withdraws
`copy_fpc_move` for those references and keeps the copy mode `getcopymode` had
chosen, which is what 3.2.2 emitted here.

Verified against upstream `da47439dd51b` on 2026-09-01: listings matched byte
for byte and the runtime failure reproduced.  No upstream test yet — one is
needed before the merge request.

### 3. Version banner marker

`compiler/version.pas`: `minorpatch` set to `-realmode`, so the banner and `-iW`
report `3.3.1-realmode`.  The marker names the product rather than the target: a
bug report quoting `3.3.1-realmode` identifies this build, while `3.3.1-i8086`
would fit any build for the target.  `version_nr`, `release_nr`, `patch_nr` and `wordversion`
are untouched, so the PPU format and everything that parses the short version —
the makefiles, fpcup, Lazarus — see an ordinary 3.3.1.

Fork-only because it exists precisely to mark a build as *not* the official one.

### 4. This file

Fork-only.  Upstream has no use for a manifest of a downstream patch set.

### 5. Build workflow

`.github/workflows/build.yml`: builds the cross compiler on x86_64-linux, then
the RTL across every target, memory model and CPU line listed below.  Upstream
has no CI for this target, which is how patch 1 stayed broken for a year and a
half.

Fork-only: it is CI for this repository's layout, not for upstream's.

### 6. Callee-saved registers pushed and popped on i8086

Under the `register` and `cdecl` conventions the callee preserves `SI`, `DI`
and `BP`.  `tcgx86.g_proc_entry` pushes them after the locals on i386, but the
block was under `{$ifdef i386}`, so i8086 fell through to the generic
`tcg.g_save_registers`: a frame slot per register, `sub sp,N` plus a 3-byte
`mov` each way — 9 bytes where `push`/`pop` cost 2.  The patch enables the
i386 path for i8086, accounts for the `DS`, `SI` and `DI` that the win16-export
and huge-model prologues push after the locals, and restores through `BP`
instead of popping when an open array copy has moved `SP`.

On the Q1 corpus with `-Ccregister` the 42 common tests go from 1275 to 1152
bytes; the `pascal` columns do not change, that convention preserves nothing
but `BP`.  Run-time check: `../issues/U10-register-abi/run-runtime.ps1`.

### 7. Near pointer in a register parameter tried to store its segment

With `-Ccregister` any call passing a `var` argument aborted the compiler with
`Internal error 2017091104`.  The generic `tcg.a_loadaddr_ref_cgpara` loads
the address straight into the parameter register, and the low-level
`tcgx86.a_loadaddr_ref_reg` on i8086, seeing a segment in the reference, moves
it into `GetNextReg` of that register — which a physical register does not
have.  For a 2-byte near pointer the segment is now dropped before the load,
exactly as `tcg8086.a_loadaddr_ref_cgpara` already does for a 2-byte push.

### 8. Frame omitted in i8086 procedures without temps

`cs_opt_stackframe` is part of `-O2` on i8086, but the block that acts on it
in `tcgprocinfo.setup_tempgen` (`psub.pas`) was under
`{$if defined(i386) or defined(x86_64) or defined(arm) ...}`, so every i8086
procedure got `push bp / mov bp,sp / leave` — 4 bytes around a leaf whose body
is one instruction.  Adding i8086 to the gate is not enough: 16-bit x86 has no
`[sp+N]` addressing, and the spill code of the register allocator puts the
temp reference straight into the instruction, past `make_simple_ref`.

The patch makes the decision in two steps.  A procedure that passes the
generic test is generated with `framepointer=sp`; `tcpuprocinfo.calc_stackframe_size`,
which runs right before the entry code, after register allocation, puts the
frame back if any temp exists (spilled register, local that could not stay in
a register, temp of an expression), and `postprocess_code` rewrites every
`[sp+N]` to `[bp+N']` by `save_regs_ref.offset` and fixes the `localloc` of
locals and parameters for the debug info.  On i8086 this is also the right
cost model: an `sp` relative access costs a `mov reg,sp` and a base register,
a frame costs 4 bytes per procedure.  `make_simple_ref` no longer lowers
`[sp+N]` in such a procedure; parents of nested procedures and procedures
using exceptions are excluded, and `cs_useebp` keeps `bp` reserved there.

On the Q1 corpus with `-Ccregister` 39 of the 42 common tests lose 4 bytes,
`R4` one; the column goes from 1152 to 1019.  The `pascal` columns do not
change, every routine there has a stack parameter.  Run-time check:
`../issues/U12-leaf-frame/run-runtime.ps1` (medium and large model, `-Ct`,
`-Cp8086`; the RTL for msdos rebuilt in both models without an error).

## Scope of the product

`compiler/Makefile.fpc` lists i8086 in `NO_NATIVE_COMPILER_CPU_LIST`: a native
`ppc8086` does not exist and cannot be built.  What this repository ships is a
**cross compiler for ordinary hosts plus an RTL matrix for the targets**.

| Axis | Shipped |
| --- | --- |
| Targets | `msdos`, `embedded` |
| Memory models | `small`, `large` |
| CPU lines | 80286 and 80386 |
| Hosts | x86_64-linux; x86_64-win64 to follow |

A memory model is shipped only if CI builds it.  `tiny` and `huge` will be asked
for; an untested model is a promise with nothing behind it.

80286 is the floor: `-Cp8086` and `-Cp80186` still work in the compiler, they are
simply not part of the matrix that gets built and tested here.  The distinction is
not cosmetic — the i8086 backend gates immediate shifts, `push imm` and `imul` with
a constant on `cputype >= cpu_186`, so a 286 build is genuinely better code than an
8086 one.

Building on an x86_64-win64 host additionally requires `OPT=-dFPC_SOFT_FPUX80`:
that host has no 80-bit `extended`, and without the define the build fails on
`TExtended80Rec`.

## Licensing

The compiler is GPLv2 and the RTL is a modified LGPL; this fork keeps every
notice and does not present itself as an official build.  Note for release
archives: `nasm` is BSD and can be bundled, but `wlib`/`wlink` from Open Watcom
are under the Sybase Open Watcom Public License, which does not combine with
GPLv2 — they are fetched by script, not shipped in the same archive.

[#41850]: https://gitlab.com/freepascal.org/fpc/source/-/issues/41850
[!1533]: https://gitlab.com/freepascal.org/fpc/source/-/merge_requests/1533
