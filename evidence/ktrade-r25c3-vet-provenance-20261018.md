# KTRADE R25-C3 historical Go vet provenance (Windows)

## Authority and scope
- **Pre-migration frozen commit**: `6d9bf14e39f2df87743ac7dc9decb4d8a082efa1`; Git tree `0d54e849c7c7a32e0b5876e2d694852b076be074`.
- **Recovery frozen commit**: `9e288a7a280416c9a8eaf660ece0aecab31efbd1`; Git tree `1a3c0f506d4f305e798afa6f1c9319d2ad7ef9f5` (KTRADE draft PR #28).
- Qualification environment: isolated GitHub-hosted Windows 2022, Go 1.23.x, exact source SHA and tree, read-only dependency download, private raw diagnostic logs destroyed on runner.
- All real trading, broker, data migration, production promotion and installed user-profile inspection prohibited. This is a diagnostic, **not** release qualification.

## Independently reproduced results
- R25-C2 consolidated regression: [39121382990](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39121382990): **one full Go regression PASS**; mandatory full Go vet **FAIL**; subsequent builds, browser and synthetic rollback skipped as required.
- Exact-source historic/recovery vet differential: [39123473948](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39123473948): 4,191 distinct diagnostic signatures for **each** commit, exactly **zero newly introduced or resolved diagnostic signatures**; one failing package `ktrade/pkg`; both vet exit 1. The empty printed SUM fields for new/resolved line totals represent zero; the distinct counts were verified as 0.
- Original-source vet root-cause sample: [39123801034](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39123801034): repeated `json` field tags in the original, large Phase11B generated release-readiness governance structs, with up to 39 findings in sampled files.
- Analyzer isolation (current recovery, not a full vet PASS): [39124052908](https://github.com/spoonman136668-ai/Qualification-Forge/actions/runs/39124052908): `go vet -structtag=false ./pkg` still reports **1** finding, `possible misuse of unsafe.Pointer` in `pkg/pine_phasef_f4_perf.go`; `go vet -structtag=false -unsafeptr=false ./...` **PASS**. Thus the full historical backlog comprises **4,190 structtag findings and 1 unsafe-pointer finding**. Disabling analyzers was diagnostic isolation only, **not** acceptance or a waiver.
- Unchanged Pine performance-cache source: `pkg/pine_phasef_f4_perf.go` has the same original and recovery Git blob `a41a6ee516d5fe5eeb7762f2a7e35ac4d7fcfdd0`.
- As of R25-C3 inventory, 6,609 of the 6,646 recovery `pkg/*.go` blobs match pre-migration exactly; 31 changed and 6 new (mostly separate recovery test/source additions).

## Safe disposition
- No new Go vet defects attributable to post-migration recovery on the frozen source. This satisfies the **differential attribution** question, **not** full go vet acceptance.
- Do **not** silently patch thousands of JSON struct tags: changing duplicate tag names can change persisted/on-wire serialization of historical governance evidence. Investigate compatibility with exact prior serialization snapshots and schema tests before any bounded remediation.
- Do **not** suppress `structtag`/`unsafeptr` analyzers or represent selective vet PASS as full vet PASS.
- The unsafe-pointer perf-expression cache implementation is inherited. A replacement requires explicit AST identity/cache-hit-equivalence tests before changing its pointer derivation.
- Full Windows `go vet ./...` remains **FAIL**, so R25-C3 vet qualification **BLOCKED**; executable build, genuine browser acceptance, synthetic snapshot/rollback acceptance and promotion remain unqualified/skipped. R25-C2 full regression PASS is retained and must not be mislabeled as full-product acceptance.
- KTRADE PR #28 remains draft and unmerged. No KTRADE source changes in R25-C3.
