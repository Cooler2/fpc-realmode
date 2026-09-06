# FPC Real Mode

FPC Real Mode is an **unofficial, pinned build of Free Pascal** for 16-bit x86
real-mode development. It packages a cross-compiler and a tested RTL matrix for
targets that receive little coverage upstream, while keeping every compiler
change isolated and suitable for upstream review where possible.

This is not a separate Pascal implementation and does not try to track Free
Pascal `main` continuously. It starts from one recorded upstream snapshot,
applies a small audited patch set, and rebases to a newer snapshot about once a
year after a full regression run.

| | Current line |
| --- | --- |
| Upstream base | [`da47439dd51b`](https://github.com/fpc/FPCSource/commit/da47439dd51b003bc45f1ad41bd2ca24614d13f7), 2026-09-01 |
| Base tag | `base/2026.1` |
| Product version | `3.3.1-realmode` |
| Integration branch | `i8086-integration` |
| Planned first release | `v2026.1` |

There is no release archive yet. Until the first release passes CI and runtime
checks, the integration branch is development material rather than a published
toolchain. Consumers should ultimately pin a release tag, not a moving branch.

## Why this repository exists

The upstream i8086 backend is useful but lacks continuous integration for the
configurations used by real DOS and freestanding systems code. Correctness
regressions can therefore survive even when the compiler and RTL appear to
build successfully. The initial patch set includes correctness fixes needed to
run generated MS-DOS programs, fixes for the existing i8086 register calling
convention, and measured code-generation improvements.

Every downstream change is listed in [`PATCHES.md`](PATCHES.md), including its
topic branch, verification status, upstream issue or merge request where one
exists, and whether it is intentionally product-only.

## Product scope

FPC cannot build a native 16-bit `ppc8086`; this product is a cross-compiler
for ordinary hosts plus target RTL units.

| Axis | Current product matrix |
| --- | --- |
| Targets | `msdos`, `embedded` |
| Memory models | `small`, `large` |
| CPU lines | 80286, 80386 |
| CI host | x86_64-linux |
| Planned host | x86_64-win64 |

The compiler still understands older CPUs and other memory models, but they are
not product promises unless they are part of CI. A configuration is shipped
only after the compiler, matching RTL and relevant runtime boundary have been
tested together.

## Branch and release model

- `i8086-integration` is the product branch: the pinned base plus all accepted
  topic branches in the order recorded in `PATCHES.md`.
- Each behavioral change is developed and verified on its own topic branch.
  Upstream candidates are also submitted through the Free Pascal GitLab fork;
  product-only changes use a `product-*` branch.
- `base/<line>` identifies the exact upstream snapshot. `v<line>` identifies a
  tested product release built from the integration branch.
- GitHub Actions builds the cross-compiler and the RTL matrix on pushes to the
  integration branch and on manual dispatch. Runtime execution, code-size
  regression checks and release packaging are being added separately.

The authoritative Free Pascal repository remains
<https://gitlab.com/freepascal.org/fpc/source>. This repository is a downstream
product repository, not the place from which upstream merge requests are sent.

## Provenance and contributors

The complete upstream Free Pascal commit history is deliberately preserved.
GitHub therefore lists upstream FPC authors as contributors. This reflects
authorship of inherited commits; it does **not** imply participation in or
endorsement of FPC Real Mode.

Preserving the history keeps authorship visible, makes every downstream diff
reviewable against its real base, and allows the annual rebase to use ordinary
Git operations instead of reconstructing provenance from a source snapshot.

## License

The original Free Pascal licensing remains unchanged. The compiler is licensed
under GPL v2; the run-time library and packages use the modified LGPL described
by the files in the source tree. See [`LICENSE`](LICENSE),
[`rtl/COPYING.txt`](rtl/COPYING.txt) and [`rtl/COPYING.FPC`](rtl/COPYING.FPC).

FPC Real Mode is not an official Free Pascal release. All original copyright
and license notices are retained.

## About Free Pascal

[Free Pascal](https://www.freepascal.org/) is an open-source Pascal and Object
Pascal compiler. This source tree contains the compiler, RTL, packages,
utilities and compiler test suite. Upstream documentation is available at
<https://docs.freepascal.org/>.
