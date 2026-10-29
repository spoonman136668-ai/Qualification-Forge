# KTRADE RB3 W35B — Installed W31→W34 native cross-version witness

**State: SOURCE ONLY / NOT EXECUTED / NOT QUALIFIED.**  The scripts in this
package are a candidate for the established, authorized, ephemeral Windows
qualification lane. They are not a queue request, workflow dispatch, alternate
controller, release approval, live-trading permission, or proof of Windows PASS.

## Source and baseline identities

* W31 source `e51e03c22f906704295a24138ac1ceba5d9ea0d4`, Git tree
  `5526682f7efafe4cd328fbac77ebb97e58dc7b9`.
* W34 source `0059d4b794552818b3f32798da7df27c75e21c5c`, Git tree
  `9f1e559560ac14f4e6fc823dac9150e3a95f2c4d`, draft KTRADE PR #185.
* Required existing successful independent Windows witnesses:
  W31 `40615926800` at qualification witness
  `5c2a6200f54b4a9e50c05e00ffe45f42a2b5b413`, and W34 `40787692876`
  at qualification witness `858d21380e1e88c01555371c6e258dfab07f7446`.
* Nine setup/update/rollback/launch files must have exact identical Git blobs
  between W31 and W34. The source wrapper checks this before any package build.

## Candidate execution in an authorized hosted Windows-2022 qualification job

The job must check out both exact SHAs from the private KTRADE repository
through its already-approved read-only source mechanism, without exposing
credentials or touching installed owner data. Go 1.25, Node 24 and original
PowerShell 5.1 package builders must be available. Use only source checkouts in
isolated runner workspace. The scripts demand `RUNNER_ENVIRONMENT=github-hosted`
and create fresh, uniquely named fixture roots under `RUNNER_TEMP`.

```powershell
& .\KTRADE-W35B-Build-And-Qualify.ps1 `
  -PreviousCheckout 'C:\runner\workspace\previous' `
  -CandidateCheckout 'C:\runner\workspace\candidate' `
  -WitnessScript 'C:\runner\workspace\witness\KTRADE-W35B-Installed-CrossVersion.ps1'
```

The wrapper verifies exact SHA and tree, clean tracked checkouts, nine
immutable source blobs, and exact completed successful foundation runs. It
performs original asset staging and builds *two distinct real unsigned native
setup bundles* via `windows/Build-KTRADE-FreshInstaller.ps1` and executes the
installed cross-version witness using Windows PowerShell 5.1.

The native witness checks original Wails/WebView2 UIAutomation chart readiness
and source-bound shell/engine/loopback custody; the supported Pine/strategy
restore, excluded unknown-state migration, prior receipt backup, active update
and rollback rejection, tampered pre-rollback data refusal, two-version cold
launch/close, complete previous and new data hash parity, and root-level
unknown bytes. No unattended automatic recovery or data deletion is used.

## Acceptance and limits

Acceptance requires successful execution on the approved Windows runner,
verified source identities and original package hashes, no skipped original
checks, and a source- and workflow-pinned independent result receipt. A
source-only code review, static file verification, or successful historical
W30/W31/W34 run is **not** a W35B PASS.

This is **not** live readiness, release admission, signing, owner-data
migration, a whole-product performance/security benchmark, or an installed
PAPER fill replay. PAPER is initially stopped; LIVE stays disarmed. Keep the
full final system-level regression and release governance mandatory.

**Development-time review limitations:** No Windows/PowerShell execution or
native UIAutomation run was possible in the current session; syntax and behavior
must be verified by the original accepted Windows qualification environment.