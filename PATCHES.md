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
