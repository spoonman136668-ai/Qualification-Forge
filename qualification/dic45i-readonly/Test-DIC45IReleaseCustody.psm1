Set-StrictMode -Version Latest

function Assert-DIC45IRegular([string]$Path, [string]$Code) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $Code }
    $info = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($Code + '_REPARSE') }
    if ($info.Length -eq 0) { throw ($Code + '_EMPTY') }
}

function Assert-DIC45INonReparseParents([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'DIC45I_REPARSE_PATH_FORBIDDEN'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or
            [string]::Equals($parent, $current, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $parent
    }
}

function Test-DIC45IReleaseCustody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReleaseStore,
        [Parameter(Mandatory)][string]$CandidateExecutable,
        [Parameter(Mandatory)][string]$ExpectedCandidateSHA256,
        [Parameter(Mandatory)][string]$ExpectedSourceSHA,
        [string]$ExpectedActive = 'PLANE-THROUGHPUT-R1P',
        [string]$Target = 'PLANE-THROUGHPUT-R1P-DIC45G'
    )
    if ($ExpectedSourceSHA -cne '4a88a8006be8fb3d83d682610ad8841345f57d5a') {
        throw 'DIC45I_SOURCE_IDENTITY_DRIFT'
    }
    if ($ExpectedActive -cne 'PLANE-THROUGHPUT-R1P' -or
        $Target -cne 'PLANE-THROUGHPUT-R1P-DIC45G') {
        throw 'DIC45I_RELEASE_IDENTITY_DRIFT'
    }
    if ($ExpectedCandidateSHA256 -cnotmatch '^[A-Fa-f0-9]{64}$') {
        throw 'DIC45I_CANDIDATE_HASH_INVALID'
    }
    if (-not (Test-Path -LiteralPath $ReleaseStore -PathType Container)) {
        throw 'DIC45I_RELEASE_STORE_MISSING'
    }

    $store = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ReleaseStore -ErrorAction Stop).ProviderPath)
    if (-not [IO.Path]::IsPathRooted($CandidateExecutable)) { throw 'DIC45I_CANDIDATE_NOT_ABSOLUTE' }
    $candidate = [IO.Path]::GetFullPath($CandidateExecutable)
    Assert-DIC45INonReparseParents $store
    Assert-DIC45INonReparseParents $candidate

    $storePrefix = $store.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) +
        [IO.Path]::DirectorySeparatorChar
    if ($candidate.StartsWith($storePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'DIC45I_CANDIDATE_MUST_BE_OUTSIDE_LIVE_STORE'
    }
    Assert-DIC45IRegular $candidate 'DIC45I_CANDIDATE_MISSING'
    if (-not [string]::Equals([IO.Path]::GetExtension($candidate), '.exe', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'DIC45I_CANDIDATE_NOT_EXE'
    }
    $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($candidateHash -cne $ExpectedCandidateSHA256.ToUpperInvariant()) {
        throw 'DIC45I_CANDIDATE_BINARY_HASH_DRIFT'
    }

    $activeFile = Join-Path $store 'state\active-release'
    Assert-DIC45INonReparseParents $activeFile
    Assert-DIC45IRegular $activeFile 'DIC45I_ACTIVE_POINTER_MISSING'
    $active = [IO.File]::ReadAllText($activeFile).Trim()
    if ($active -cne $ExpectedActive) { throw 'DIC45I_ACTIVE_RELEASE_CHANGED' }

    $predecessor = Join-Path $store ("releases\" + $ExpectedActive)
    $activeBinary = Join-Path $predecessor 'bin\ckb-plane.exe'
    $manifest = Join-Path $predecessor 'release-manifest.json'
    $seal = Join-Path $predecessor 'release-seal.json'
    foreach ($path in @($activeBinary, $manifest, $seal)) {
        Assert-DIC45INonReparseParents $path
        Assert-DIC45IRegular $path 'DIC45I_PREDECESSOR_FILE_MISSING'
    }
    # Existing release metadata are presence-checked, NOT issuer-authenticated here.
    $predecessorHash = (Get-FileHash -LiteralPath $activeBinary -Algorithm SHA256).Hash
    $manifestHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    $sealHash = (Get-FileHash -LiteralPath $seal -Algorithm SHA256).Hash
    $destination = Join-Path $store ("releases\" + $Target)
    Assert-DIC45INonReparseParents $destination
    if (Test-Path -LiteralPath $destination) { throw 'DIC45I_DESTINATION_ALREADY_EXISTS' }

    # Return an unprivileged, path-free report. No files, Git refs, release
    # pointers, service states, databases or controller settings are written.
    [pscustomobject][ordered]@{
        schema = 'ckb-plane.dic45i.readonly-release-custody.v1'
        disposition = 'FILESYSTEM_PREFLIGHT_ONLY'
        candidate_source_sha = $ExpectedSourceSHA
        candidate_executable_sha256 = $candidateHash
        predecessor_release = $ExpectedActive
        predecessor_binary_sha256 = $predecessorHash
        predecessor_manifest_sha256 = $manifestHash
        predecessor_seal_sha256 = $sealHash
        proposed_release = $Target
        predecessor_issuer_authenticated = $false
        candidate_binary_independently_attested = $false
        existing_controller_status_authenticated = $false
        versioned_release_installed = $false
        active_pointer_changed = $false
        controller_admitted = $false
        broker_authorized = $false
        production_promotion_authorized = $false
    }
}
Export-ModuleMember -Function Test-DIC45IReleaseCustody
