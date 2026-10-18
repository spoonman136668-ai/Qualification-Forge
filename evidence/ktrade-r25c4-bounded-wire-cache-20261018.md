# KTRADE R25-C4 — bounded historical serialization and Pine cache reconciliation

Status: **FOCUSED WINDOWS PASS; FULL GO VET BLOCKED**. Qualification must not be interpreted as installed-product acceptance.

## Immutable identity and custody

- KTRADE recovered parent (draft PR #28): `9e288a7a280416c9a8eaf660ece0aecab31efbd1`.
- Historical compatibility-test baseline: `4aefd8eeea9d0a9fe4007cf80e4fa7d0ea583d24`.
- Bounded candidate: `dba1ba0e07e29f79e184997120d1724870328d37` (tree `356665612ac675e6334d822002b426ece3c5c1cd`); KTRADE draft [PR #30](https://github.com/spoonman136668-ai/ktrade/pull/30), unmerged.
- Test-only baseline [Qualification-Forge run #39125193350](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39125193350) PASS.
- Original exact JSON-wire fingerprint [run #39125323883](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39125323883) PASS.
- Corrected candidate exact-head [run #39125786421](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39125786421) **PASS** (GitHub-hosted Windows 2022).
- Earlier R25-C3 vet differential [#39123473948](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39123473948) confirmed 4,191 inherited defects; no post-migration new defect signature.

## Preserved historical contracts

The frozen R25-C4 tests assert byte-identical JSON marshal results for two representative generated governance records, including non-serialization of fields with previously ambiguous duplicated JSON tags:

- Phase11B T297 historical JSON-wire SHA256: `1054905d366070cba11e222e0c2d351b9c0d7338b52a77f4515389780187f3ba`.
- Phase11B T407 historical JSON-wire SHA256: `fbefe30642ef90c2740a7b86ec4c73ab62004e223264b4708b3c0ded047dcf9b`.

The candidate makes the **43 ambiguous fields** in those two generated governance source files explicitly `json:"-"`, preserving their already-omitted wire behavior. Go field names, types, struct layout, validators, durable records, independent custody rules, and trading behavior remain unchanged.

Pine F4 cache identity uses the dynamic AST node pointer via `reflect.Value.Pointer()` instead of the inherited unsafe interface-layout reinterpretation. Tests assert pointer-alias cache hits, no false hits for distinct AST nodes, environment-version isolation, typed-nil key identity, and performance-counter snapshots.

## Exact-head Windows focused qualification findings

- `TestR25C4*` with `-vet=off`: PASS (focused tests only).
- `go vet -unsafeptr ./pkg`: **PASS**.
- `go vet -structtag ./pkg`: **FAIL** with **4,150 remaining inherited diagnostics**; this analyzer was invoked only to measure the controlled reduction, not to waive errors.
- Original structtag diagnostics: 4,190. Corrected in narrow candidate: 40 (one T297, 39 T407).
- **Full Go vet was NOT repeated or qualified. Full regression was NOT rerun on this newer candidate.**
- Production promotion, live/paper order authority, historical installed-user migration, full Windows executable builds, genuine Chromium acceptance, and synthetic clean-install/rollback remain unqualified under the current exact source.

## Next scientific/engineering acceptance gate

R25-C5 should source-review and preserve exact wire behavior for remaining generated governance contracts before additional mechanical tag corrections. An initial repository-tree survey found 111 sequential T297–T407 governance-pin Go files (about 19.7 MB of source), a potential tranche—not evidence that all 4,150 remaining errors are necessarily confined there. Require source-proven JSON encoding fingerprints and batch-limited tests; do not silently mass-relabel tags or suppress vet analyzers. After eliminating the inherited structtag backlog, independently rerun mandatory full `go vet ./...`, then a single final full Windows regression and remaining synthetic/browser gates on one frozen qualified source head.

All real-user files remain untouched. No Codex or paid API was used; GH Actions used only disposable GitHub-hosted Windows source snapshots.
