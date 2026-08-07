# Apple Silicon product install evidence

Date: 2026-08-07 (Asia/Shanghai)

Candidate: `0.1.0-beta.1`

Environment: isolated temporary macOS user home on Apple Silicon. The test did
not read from or write to the operator's real `~/.persome`.

Command:

```sh
bash scripts/smoke-install.sh --uninstall-via-receipt
```

Observed result:

- installed the Runtime pinned by `runtime.lock`;
- installed managed Python 3.12.13 and the pinned Persome package;
- downloaded and verified the Apple Silicon Node 24.15.0 archive from
  `nodejs.org`;
- installed production-only Personal Card dependencies;
- created `~/Applications/Who Am I.app`;
- passed Runtime quick verification;
- passed product verification, including product version, managed Node version,
  launcher identity and the absence of development fixtures/tests;
- produced healthy privacy-safe diagnostics;
- preserved Personal Model data during preserve-data uninstall;
- repeated preserve-data uninstall without side effects; and
- removed the isolated Runtime only after the explicit `DELETE` confirmation.

Result: **PASS**

Scope note: this is pre-publication local Apple Silicon evidence. It does not
replace the required post-publication Apple Silicon artifact test, Intel macOS
test, notarization decision or signed release approval.
