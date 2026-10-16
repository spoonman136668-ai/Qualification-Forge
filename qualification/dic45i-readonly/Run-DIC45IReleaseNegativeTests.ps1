$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -Name (Join-Path $PSScriptRoot 'Test-DIC45IReleaseCustody.psm1') -Force

$base = Join-Path ([IO.Path]::GetTempPath()) ('DIC45I-FIXTURE-' + [guid]::NewGuid().ToString('N'))
$store = Join-Path $base 'release-store\ckb-plane'
$src = Join-Path $base 'candidate'
$old = 'PLANE-THROUGHPUT-R1P'
$next = 'PLANE-THROUGHPUT-R1P-DIC45G'
$active = Join-Path $store 'state\active-release'
$oldDir = Join-Path $store ("releases\" + $old)
$oldExe = Join-Path $oldDir 'bin\ckb-plane.exe'
$manifest = Join-Path $oldDir 'release-manifest.json'
$seal = Join-Path $oldDir 'release-seal.json'
$candidate = Join-Path $src 'ckb-plane-QUALIFICATION-ONLY.exe'

function Assert-Denied([string]$Name,[scriptblock]$Check) {
    $refused = $false
    try { & $Check | Out-Null } catch { $refused = $true }
    if (-not $refused) { throw "DIC45I_NEGATIVE_WAS_ACCEPTED=$Name" }
    Write-Host "DIC45I_NEGATIVE=$Name PASS"
}
function Readiness([string]$CandidateHash,[string]$SourceSha) {
    Test-DIC45IReleaseCustody -ReleaseStore $store -CandidateExecutable $candidate -ExpectedCandidateSHA256 $CandidateHash -ExpectedSourceSHA $SourceSha
}
try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $active),(Split-Path -Parent $oldExe),$src -Force | Out-Null
    [IO.File]::WriteAllText($active,$old + [Environment]::NewLine)
    [IO.File]::WriteAllBytes($oldExe,[byte[]](4,8,15,16,23,42))
    [IO.File]::WriteAllText($manifest,'{"schema":"existing-fixture"}')
    [IO.File]::WriteAllText($seal,'{"schema":"existing-fixture-seal-not-verified"}')
    [IO.File]::WriteAllBytes($candidate,[byte[]](7,7,7,0,1))
    $hash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    $source='4a88a8006be8fb3d83d682610ad8841345f57d5a'
    $oldHash=(Get-FileHash -LiteralPath $oldExe -Algorithm SHA256).Hash
    $originalPointer=[IO.File]::ReadAllText($active)

    $pass=Readiness $hash $source
    if ($pass.disposition -cne 'FILESYSTEM_PREFLIGHT_ONLY' -or
        $pass.versioned_release_installed -or $pass.active_pointer_changed -or
        $pass.controller_admitted -or $pass.broker_authorized -or
        $pass.candidate_binary_independently_attested -or
        $pass.predecessor_issuer_authenticated) { throw 'DIC45I_POSITIVE_SCOPE_ESCALATION' }
    Write-Host 'DIC45I_READONLY_FIXTURE=PASS'

    Assert-Denied 'wrong_source' { Readiness $hash ('0'*40) }
    Assert-Denied 'wrong_candidate_hash' { Readiness ('0'*64) $source }
    Assert-Denied 'missing_candidate' {
        Test-DIC45IReleaseCustody -ReleaseStore $store -CandidateExecutable (Join-Path $src 'missing.exe') -ExpectedCandidateSHA256 $hash -ExpectedSourceSHA $source
    }
    [IO.File]::WriteAllText($active,$next)
    Assert-Denied 'changed_active_pointer' { Readiness $hash $source }
    [IO.File]::WriteAllText($active,$old + [Environment]::NewLine)
    $target=Join-Path $store ("releases\" + $next)
    New-Item -ItemType Directory -Path $target | Out-Null
    Assert-Denied 'existing_destination' { Readiness $hash $source }
    Remove-Item -LiteralPath $target -Force
    Remove-Item -LiteralPath $seal -Force
    Assert-Denied 'missing_predecessor_seal' { Readiness $hash $source }
    [IO.File]::WriteAllText($seal,'{"schema":"existing-fixture-seal-not-verified"}')
    New-Item -ItemType Directory -Path (Join-Path $store 'tmp') -Force | Out-Null
    $inStore=Join-Path $store 'tmp\candidate.exe'
    [IO.File]::Copy($candidate,$inStore)
    Assert-Denied 'candidate_inside_active_store' {
        Test-DIC45IReleaseCustody -ReleaseStore $store -CandidateExecutable $inStore -ExpectedCandidateSHA256 $hash -ExpectedSourceSHA $source
    }
    Assert-Denied 'wrong_active_release' {
        Test-DIC45IReleaseCustody -ReleaseStore $store -CandidateExecutable $candidate -ExpectedCandidateSHA256 $hash -ExpectedSourceSHA $source -ExpectedActive 'UNKNOWN'
    }
    if ((Get-FileHash -LiteralPath $oldExe -Algorithm SHA256).Hash -cne $oldHash -or
        [IO.File]::ReadAllText($active) -cne $originalPointer) {
        throw 'DIC45I_PREDECESSOR_MUTATED'
    }
    if (Test-Path -LiteralPath (Join-Path $store ("releases\" + $next))) {
        throw 'DIC45I_TARGET_RELEASE_CREATED'
    }
    Write-Host 'DIC45I_NO_SOURCE_POINTER_OR_RELEASE_MUTATION=PASS'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
