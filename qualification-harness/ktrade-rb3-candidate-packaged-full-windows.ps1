# RB3 full-candidate source, frontend and installed-package acceptance slice.
# Windows-hosted, non-release, ephemeral unprivileged install only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$src=Join-Path $env:GITHUB_WORKSPACE 'candidate'
$expected='0059d4b794552818b3f32798da7df27c75e21c5c'
$tree='9f1e559560ac14f4e6fc823dac9150e3a95f2c4d'
function Must([bool]$okay,[string]$reason){if(!$okay){throw $reason}}
function RunNative([string]$cwd,[string]$name,[string[]]$args){
 Push-Location -LiteralPath $cwd
 try{
  & $name @args
  Must ($LASTEXITCODE -eq 0) ('RB3_COMMAND_FAILED_'+$name+'_'+($args -join '_'))
 }finally{Pop-Location}
}
Must ($env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and $env:RUNNER_OS -ceq 'Windows') 'RB3_NOT_FRESH_HOSTED_WINDOWS'
Must (Test-Path -LiteralPath $src -PathType Container) 'RB3_CANDIDATE_SOURCE_MISSING'
Must ((& git -C $src rev-parse HEAD).Trim() -ceq $expected -and
      (& git -C $src rev-parse 'HEAD^{tree}').Trim() -ceq $tree) 'RB3_EXACT_SOURCE_TREE_CHANGED'
Must (@(& git -C $src status --porcelain).Count -eq 0) 'RB3_SOURCE_DIRTY_AT_START'
Must ((& git -C $src rev-parse origin/main).Trim() -ceq 'a359e86d05e5ba24b71a1f4bdd8a5e36ebd31b58') 'RB3_MAIN_DRIFT'
$null=& git -C $src merge-base --is-ancestor origin/main HEAD
Must ($LASTEXITCODE -eq 0) 'RB3_UNEXPECTED_MAIN_ANCESTRY'
$paths=@(
 'windows/Build-KTRADE-FreshInstaller.ps1',
 'windows/Build-KTRADE-WailsPortable.ps1',
 'windows/Install-KTRADE-Fresh.ps1',
 'windows/Manage-KTRADE-FreshInstall.ps1',
 'tests/Test-R25C32-ReleaseAdmission.ps1',
 'docs/rebuild/RB3_WAILS_CODEX_WEB_OWNER_DECISION_20261024.md'
)
foreach($p in $paths){Must (Test-Path -LiteralPath (Join-Path $src $p) -PathType Leaf) ('RB3_REQUIRED_SOURCE_MISSING_'+$p)}
Write-Output '::notice::RB3_EXACT_431_COMMIT_CANDIDATE_SHA_TREE_UNCHANGED=PASS'

# Run every actual Node test file, with no old red cases excluded.
$allTests=@(Get-ChildItem -LiteralPath (Join-Path $src 'tests') -File -Filter '*.test.cjs' | Sort-Object Name)
Must ($allTests.Count -ge 27) 'RB3_EXPECTED_NODE_TEST_MATRIX_MISSING'
# W28F is a legacy standalone command accepting two absolute source roots,
# not a node:test module. Run it with its exact frozen previous commit, not
# just omit it from the suite or pass the same tree twice.
$special='rb3_w28f_original_browser_state.test.cjs'
Must (@($allTests|Where-Object {$_.Name -ceq $special}).Count -eq 1) 'RB3_W28F_STANDALONE_TEST_MISSING'
$tests=@($allTests|Where-Object {$_.Name -cne $special})
Push-Location $src
try{
 & node --test @($tests.FullName)
 Must ($LASTEXITCODE -eq 0) 'RB3_ALL_NODE_CHART_PINE_OPERATOR_TESTS_FAILED'
}finally{Pop-Location}
$prior='9a525c0ac1b1481c1ba9532080d52e4c94ac5b39'
$oldRoot=Join-Path $env:RUNNER_TEMP ('ktrade-w28f-prior-'+[guid]::NewGuid().ToString('N'))
$oldTar=Join-Path $env:RUNNER_TEMP ('ktrade-w28f-'+[guid]::NewGuid().ToString('N')+'.tar')
Must (!(Test-Path -LiteralPath $oldRoot) -and !(Test-Path -LiteralPath $oldTar)) 'RB3_W28F_NOT_FRESH'
Must ((& git -C $src cat-file -t $prior).Trim() -ceq 'commit') 'RB3_W28F_FROZEN_PREDECESSOR_MISSING'
New-Item -ItemType Directory -Path $oldRoot -ErrorAction Stop|Out-Null
$paths=@('static/watchlist_manager.js','static/layout_manager.js','static/indicator_library.js','static/indicator_browser.js')
& git -C $src archive --format=tar --output $oldTar $prior @paths
Must ($LASTEXITCODE -eq 0) 'RB3_W28F_PREVIOUS_SOURCE_ARCHIVE_FAILED'
& tar -xf $oldTar -C $oldRoot
Must ($LASTEXITCODE -eq 0) 'RB3_W28F_PREVIOUS_SOURCE_EXTRACT_FAILED'
foreach($file in $paths){Must (Test-Path -LiteralPath (Join-Path $oldRoot $file) -PathType Leaf) 'RB3_W28F_REQUIRED_PARENT_JS_MISSING'}
Push-Location $src
try{
 & node (Join-Path $src ('tests/'+$special)) $oldRoot $src
 Must ($LASTEXITCODE -eq 0) 'RB3_W28F_ORIGINAL_TWO_SOURCE_COMPAT_FAILED'
}finally{Pop-Location}
Write-Output ('::notice::RB3_ALL_NODE_CHART_PINE_OPERATOR_TEST_FILES_PASS='+$allTests.Count)
Write-Output ('::notice::RB3_W28F_FROZEN_PREDECESSOR_READONLY_COMPAT='+$prior)

$env:GOWORK='off'
$env:GOFLAGS='-p=2'
$env:GOMAXPROCS='2'
$env:CGO_ENABLED='1'
$env:TEMP=$env:RUNNER_TEMP;$env:TMP=$env:RUNNER_TEMP
RunNative $src 'go' @('test','-mod=readonly','-count=1','-tags','ktrade_full','./cmd/ktrade')
RunNative $src 'go' @('vet','-mod=readonly','-tags','ktrade_full','./cmd/ktrade')
RunNative $src 'go' @('test','-mod=readonly','-count=1','./...')
RunNative $src 'go' @('vet','-mod=readonly','./...')
$wails=Join-Path $src 'tools/wails-pilot'
RunNative $wails 'go' @('test','-mod=readonly','-count=1','./...')
RunNative $wails 'go' @('vet','-mod=readonly','./...')
Write-Output '::notice::RB3_FULL_CANDIDATE_GO_ROOT_TAGGED_AND_WAILS_TEST_VET=PASS'

# Explicit release admission remains negative for missing genuine signature
# and actual user's installed-data migration proof; fixture tests only.
Push-Location $src
try{
 & pwsh -NoProfile -NonInteractive -File (Join-Path $src 'tests/Test-R25C32-ReleaseAdmission.ps1')
 Must ($LASTEXITCODE -eq 0) 'RB3_RELEASE_ADMISSION_NEGATIVE_GUARD_FAILED'
}finally{Pop-Location}
Write-Output '::notice::RB3_MISSING_PRODUCTION_RELEASE_AUTHORITY_FAILS_CLOSED=PASS'

# Build-time-only original vendor. Never build/run the legacy Electron bundle.
Push-Location $src
try{
 & npm ci --ignore-scripts --no-audit --no-fund --silent
 Must ($LASTEXITCODE -eq 0) 'RB3_NPM_LOCK_VENDOR_FAILED'
 & node scripts/stage_offline_vendor.cjs
 Must ($LASTEXITCODE -eq 0) 'RB3_ORIGINAL_VENDOR_STAGING_FAILED'
}finally{Pop-Location}
Write-Output '::notice::RB3_LOCKED_ORIGINAL_MONACO_CHART_VENDOR_STAGING=PASS'

# The build creates an UNSIGNED, explicitly non-accepted fresh installer, not
# an owner installation or deployable release. Both roots live in OS TEMP.
$packageRoot=Join-Path $env:RUNNER_TEMP ('ktrade-setup-package-'+[guid]::NewGuid().ToString('N'))
$installRoot=Join-Path $env:RUNNER_TEMP ('ktrade-rb3-disposable-install-'+[guid]::NewGuid().ToString('N'))
Must (!(Test-Path -LiteralPath $packageRoot) -and !(Test-Path -LiteralPath $installRoot)) 'RB3_NOT_FRESH_ROOT'
$packageInfo=[IO.Path]::GetFullPath($packageRoot)
$installInfo=[IO.Path]::GetFullPath($installRoot)
Must ($packageInfo.StartsWith([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -and
      $installInfo.StartsWith([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) 'RB3_DISPOSABLE_ROOT_NOT_TEMP'
Push-Location $src
try{
 & (Join-Path $src 'windows/Build-KTRADE-FreshInstaller.ps1') -OutputRoot $packageRoot -ExpectedSourceSha $expected
 Must ($LASTEXITCODE -eq 0) 'RB3_ORIGINAL_UNSIGNED_SETUP_BUILD_FAILED'
}finally{Pop-Location}
$bundle=Join-Path $packageRoot 'KTRADE-SetupBundle'
$manifest=Get-Content -LiteralPath (Join-Path $bundle 'installer-manifest.json') -Raw | ConvertFrom-Json
Must ($manifest.schema -ceq 'ktrade.setup-bundle.v2' -and $manifest.source_sha -ceq $expected -and
      $manifest.signature_status -ceq 'unsigned' -and $manifest.release_authority -ceq 'none' -and
      $manifest.live_armed -eq $false) 'RB3_UNEXPECTED_INSTALLER_RELEASE_AUTHORITY'
$build=Get-Content -LiteralPath (Join-Path $packageRoot 'setup-build-receipt.json') -Raw | ConvertFrom-Json
Must ($build.source_sha -ceq $expected -and $build.live_armed -eq $false -and
      $build.release_authority -ceq 'none' -and $build.signature_status -ceq 'unsigned') 'RB3_SETUP_BUILD_RECEIPT_UNTRUSTED'
$archive=Join-Path $packageRoot 'KTRADE-SetupBundle.zip'
Must ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $build.archive_sha256) 'RB3_SETUP_ARCHIVE_HASH_CHANGED'
Write-Output '::notice::RB3_SOURCE_PINNED_UNSIGNED_WAILS_SETUP_BUNDLE_HASHED=PASS'

# Exercise actual source-compiled release-setup and maintenance binaries.
# No Start Menu, user registry, existing installed files or owner profile.
$setup=Join-Path $bundle 'release-setup.exe'
$installed=(& $setup install $bundle $installRoot) -join [Environment]::NewLine
Must ($LASTEXITCODE -eq 0) 'RB3_REAL_NATIVE_DISPOSABLE_INSTALL_FAILED'
$i=$installed | ConvertFrom-Json
Must ($i.schema -ceq 'ktrade.fresh-installation.v1' -and $i.source_sha -ceq $expected -and
      $i.root -ceq $installRoot -and $i.fresh_only -eq $true -and
      $i.app_launched -eq $false -and $i.owner_data_imported -eq $false -and
      $i.orders_enabled -eq $false -and $i.live_armed -eq $false -and
      $i.release_accepted -eq $false) 'RB3_NATIVE_INSTALLATION_AUTHORITY_INVALID'
$inspected=((& $setup inspect $installRoot) -join [Environment]::NewLine) | ConvertFrom-Json
Must ($LASTEXITCODE -eq 0 -and $inspected.selection_digest -ceq $i.selection_digest) 'RB3_INSTALLED_SELECTION_DRIFT'
$maint=Join-Path $bundle 'release-maintain.exe'
$stopped=((& $maint inspect-stopped $installRoot) -join [Environment]::NewLine) | ConvertFrom-Json
Must ($LASTEXITCODE -eq 0 -and $stopped.source_sha -ceq $expected) 'RB3_STOPPED_NATIVE_INSTALL_NOT_ADMITTED'
Write-Output '::notice::RB3_ACTUAL_UNSIGNED_SETUP_FRESH_STOPPED_INSTALL_INSPECT=PASS'

# Unknown owner-like bytes are purely synthetic and must survive actual native
# source-owned uninstall. Nothing in the installed root is silently deleted.
$userData=Join-Path $i.candidate_directory 'data'
Must (Test-Path -LiteralPath $userData -PathType Container) 'RB3_DISPOSABLE_DATA_MISSING'
$unknown=Join-Path $userData 'rb3-unknown-private-keep.bin'
$bytes=[byte[]](0,1,2,3,13,10,255,128,55,29)
[IO.File]::WriteAllBytes($unknown,$bytes)
$before=(Get-FileHash -LiteralPath $unknown -Algorithm SHA256).Hash.ToLowerInvariant()
$out=(& $maint uninstall $installRoot) -join [Environment]::NewLine
Must ($LASTEXITCODE -eq 0) 'RB3_ACTUAL_NATIVE_DISPOSABLE_UNINSTALL_FAILED'
$removed=$out | ConvertFrom-Json
Must ($removed.schema -ceq 'ktrade.fresh-uninstallation.v1' -and
      $removed.completed -eq $true -and $removed.user_data_preserved -eq $true -and
      $removed.live_armed -eq $false -and $removed.code_files_removed -gt 0) 'RB3_UNINSTALL_SOURCE_PROOF_INVALID'
Must ((Get-FileHash -LiteralPath $unknown -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $before) 'RB3_UNKNOWN_PRIVATE_DATA_WAS_MODIFIED'
Must (!(Test-Path -LiteralPath (Join-Path $i.candidate_directory 'ktrade.exe'))) 'RB3_UNINSTALL_KTRADE_EXE_RETAINED'
Write-Output '::notice::RB3_REAL_UNSIGNED_NATIVE_INSTALL_UNINSTALL_UNKNOWN_PRIVATE_BYTES_PRESERVED=PASS'
Write-Output ('RB3_BOUNDED_PACKAGE_ACCEPTANCE='+(@{
 schema='ktrade.rb3.package-acceptance.v1';source=$expected;tree=$tree;
 node_test_files=$allTests.Count;full_go_wails_vet=$true;
 unsigned_bundle_sha256=$build.archive_sha256;installed_disposable_root=$true;
 installed_native_source_bound=$true;unknown_bytes_preserved_sha256=$before;
 uninstalled_code_files=$removed.code_files_removed;release_authority='none';
 live_armed=$false;owner_data_accessed=$false;actual_broker_orders=$false
}|ConvertTo-Json -Compress))
