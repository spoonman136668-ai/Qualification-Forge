# Execution Contract R1

## Authority
- CKB-plane owns dispatch, scope and acceptance.
- Forge executes only authorized bounded work.
- Forge cannot create a competing work queue or scheduler.

## Qualification
- Exact source commit/tree identity.
- Toolchain and harness identity.
- Bounded focused-test cache reuse.
- Affected-interface verification.
- One mandatory final full regression.
- Immutable evidence and artifact hashes.
- Fail closed on drift or provenance gaps.

## Recovery
- Typed diagnosis and bounded retries only.
- No silent widening of scope or compute budget.
- No modification of controller authority.
- No independent deployment or promotion.

## Public boundary
Only public-approved source and fixtures may be used.
No private source material or secrets may be published.
