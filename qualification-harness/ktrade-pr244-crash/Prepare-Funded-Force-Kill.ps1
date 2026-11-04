param(
 [Parameter(Mandatory=$true)][string]$WitnessRoot,
 [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
function Need([bool]$ok,[string]$label){if(!$ok){throw $label}}
$sourceSha='2cfb0f34d65c4f19d3ed9dc6c29fa5931fd8b105'
$original=Join-Path $WitnessRoot 'qualification-harness/ktrade-pine-viewport'
$paperOriginal=Join-Path $WitnessRoot 'qualification-harness/ktrade-w83/Original-W40-Paper.ps1'
$builderPath=Join-Path $original 'Build-And-Qualify-PR243.ps1'
$nativePath=Join-Path $original 'Installed-Viewport-Lifecycle-PR243.ps1'
foreach($item in @(
 @{path='qualification-harness/ktrade-pine-viewport/Build-And-Qualify-PR243.ps1';sha='57adfe95974b14d0be92b1a7f354e119ce44044c'},
 @{path='qualification-harness/ktrade-pine-viewport/Installed-Viewport-Lifecycle-PR243.ps1';sha='6bbe4cb1cdc1c14417fbde22d42ec1a1b52d40a4'},
 @{path='qualification-harness/ktrade-w83/Original-W40-Paper.ps1';sha='c69c3c05ff7f4ef933856b036bfa23fbf0a760f1'},
 @{path='qualification-harness/ktrade-w83/Original-W40-Native-Inputs.ps1';sha='646a3dc40cb8877e7bc34690e02f74773b83529c'}
)){
 $blob=(& git -C $WitnessRoot rev-parse ('HEAD:'+$item.path)).Trim()
 Need ($blob -ceq $item.sha) ('PR244_CRASH_ORIGINAL_WITNESS_BLOB_DRIFT_'+$item.path)
}
$builder=Get-Content -LiteralPath $builderPath -Raw
$native=Get-Content -LiteralPath $nativePath -Raw
$paper=Get-Content -LiteralPath $paperOriginal -Raw
function ReplaceExact([string]$text,[string]$from,[string]$to,[string]$label){
 Need ($text.Split([string[]]@($from),[StringSplitOptions]::None).Count -eq 2) ('PR244_CRASH_ANCHOR_NOT_UNIQUE_'+$label)
 return $text.Replace($from,$to)
}
$builder=ReplaceExact $builder "sha='4b401d5f9c3a571c5ad61c4df33a7814120a3a4b';tree='0d8257297d53a8edd4a40b4099f102106619b2a2'" "sha='$sourceSha';tree='ef368f075cab7ac943582986d8c60d3d3acf4dce'" 'build-pins'
$native=ReplaceExact $native '$NewSHA=''4b401d5f9c3a571c5ad61c4df33a7814120a3a4b''' ('$NewSHA='''+$sourceSha+'''') 'native-source'
# The ORIGINAL exact-source native-Pine physical pixel/marker, catalog,
# viewport, and legacy HTTP suites already PASS at PR244 and are not
# the subject of this distinct destructive synthetic process-kill test.
# Preserve the original code and frozen pixel thresholds, untouched;
# suppress only the incidental functional probes in this ephemeral
# derivative while retaining native shortcut, verified WebView2,
# loopback, safe capabilities, update, original Pine Save/Start/first BUY,
# process/financial custody and all release restrictions.
$native=ReplaceExact $native ('$NewSHA='''+$sourceSha+'''') ('$NewSHA='''+$sourceSha+''''+[Environment]::NewLine+'$script:PR244CrashFocusedOnly=$true') 'crash-only-flag'
$native=ReplaceExact $native ' if($phase -ceq ''UPDATED''){' ' if($phase -ceq ''UPDATED'' -and !$script:PR244CrashFocusedOnly){' 'reuse-immutable-passed-pixel-suite'

# The original PREVIOUS native startup and active-update-negative are already
# PASS at exact SHA under W83. For a focused destructive CURRENT candidate
# PAPER crash, reuse that receipt without requiring a second old desktop.
# Keep original stopped predecessor, supported user-data copy, selected
# candidate update, and live-disarmed checks in this derived witness.
$oldLaunch=@'
 $script:active=StartInstalled $oldMaint $old 'PREVIOUS'
 $null=Setup $newSetup 'Update' $false
 Require ((Hash $oldReceiptPath) -ceq $oldReceiptHash) 'W83_ACTIVE_UPDATE_MUTATED_RECEIPT'
 StopInstalled $script:active;$script:active=$null
'@
$coldPrevious=@'
 Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'))) 'PR244_CRASH_PREDECESSOR_OWNER_LEASE_PRESENT'
 Require ((Hash $oldReceiptPath) -ceq $oldReceiptHash) 'PR244_CRASH_PREDECESSOR_RECEIPT_CHANGED'
 Write-Host '::notice::PR244_CRASH_PREDECESSOR_COLD_UPDATE_REUSES_EXACT_NATIVE_W83=PASS'
'@
$native=ReplaceExact $native $oldLaunch $coldPrevious 'previous-native-reused-from-immutable-w83'
$injection=@'
 $crashArchive=W33-Get '/api/paper/session/archive'
 $caps=W33-Get '/api/operator/capabilities'
 if($crashArchive.source_id -cne $firstArchive.source_id -or $crashArchive.original_risk_proof_verified -ne $true -or
    $caps.live_orders_enabled -ne $false -or $caps.paper_orders_enabled -ne $true -or
    $bought.last_ledger_hash -cnotmatch '^[a-f0-9]{64}$'){throw 'PR244_CRASH_FUNDED_SOURCE_RISK_OR_LEDGER_UNVERIFIED'}
 $leased=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 if(!(Test-Path -LiteralPath $leased)){throw 'PR244_CRASH_ACTIVE_LEASE_MISSING'}
 # The running Go owner holds the lease EXCLUSIVELY; reading/hash-open
 # while it is live is an invalid verifier operation, not an app defect.
 $dataRoot=Join-Path $stage 'data'
 if(!(Test-Path -LiteralPath $leased -PathType Leaf) -or
    !(Test-Path -LiteralPath $dataRoot -PathType Container)){throw 'PR244_CRASH_LEASE_OR_DATA_ROOT_UNAVAILABLE'}
 # Source-bound original sealed paper checkpoint, created while still
 # running, is immutable; never try to read the live exclusive process lease.
 if($crashArchive.snapshot_seal -cnotmatch '^[a-f0-9]{64}$'){throw 'PR244_CRASH_SEAL_REQUIRED'}
 $preHistory=Join-Path $dataRoot 'paper-history'
 $preSource=Join-Path $preHistory $crashArchive.source_id
 Ordinary $preHistory $true
 Ordinary $preSource $true
 $checkpointMatches=@(Get-ChildItem -LiteralPath $preSource -File -ErrorAction Stop|Where-Object {
   $_.Name -match ('^checkpoint-[0-9]{19}-'+$crashArchive.snapshot_seal.Substring(0,24)+'\.json$')
 })
 if($checkpointMatches.Count -ne 1 -or ($checkpointMatches[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw 'PR244_CRASH_ORIGINAL_CHECKPOINT_AMBIGUOUS'
 }
 $checkpointPath=$checkpointMatches[0].FullName
 Ordinary $checkpointPath $false
 $checkpoint=Get-Content -LiteralPath $checkpointPath -Raw|ConvertFrom-Json -Depth 30
 if($checkpoint.seal -cne $crashArchive.snapshot_seal -or
    $checkpoint.source_id -cne $crashArchive.source_id -or
    $checkpoint.source_sha256 -cne $script:p5SourceHash -or
    $checkpoint.live_armed -ne $false -or $null -eq $checkpoint.original_risk){
     throw 'PR244_CRASH_FINANCIAL_CHECKPOINT_SOURCE_RISK_DRIFT'
 }
 $checkpointHash=Hash $checkpointPath
 Write-Host '::notice::PR244_CRASH_SEALED_CHECKPOINT_PREKILL=PASS'
 # Both original PAPER writer leases must exist while the funded session is
 # live; check presence only, never attempt to steal or read a held handle.
 $paperApplicationLease=Join-Path $preHistory 'application-owner.lock'
 $paperSessionLease=Join-Path $preSource 'owner.lock'
 foreach($paperLease in @($paperApplicationLease,$paperSessionLease)){
   if(!(Test-Path -LiteralPath $paperLease -PathType Leaf)){
     throw 'PR244_CRASH_FUNDED_PAPER_OWNER_LEASE_MISSING_BEFORE_KILL'
   }
   Ordinary $paperLease $false
 }
 $shellPid=[int]$shell.Id
 $enginePid=[int]$engine.ProcessId
 $shellInfo=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shellPid)
 $engineInfo=Get-CimInstance Win32_Process -Filter ('ProcessId='+$enginePid)
 if(![string]::Equals($shellInfo.ExecutablePath,(Join-Path $stage 'ktrade.exe'),[StringComparison]::OrdinalIgnoreCase) -or
    ![string]::Equals($engineInfo.ExecutablePath,(Join-Path $stage 'ktrade-engine.exe'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'PR244_CRASH_UNOWNED_PROCESS_REFUSED'
 }
 Write-Output ('PR244_CRASH_REAL_FIRST_BUY='+(@{source_id=$firstArchive.source_id;source_sha256=$script:p5SourceHash;fill_count=1;cash=$buyProduct.cash;ledger_hash=$bought.last_ledger_hash;owned_shell_pid=$shellPid;owned_engine_pid=$enginePid}|ConvertTo-Json -Compress))
 # Only the synthetic installed app's exact owned process is terminated.
 Write-Host '::notice::PR244_CRASH_PRE_KILL_ONE_SETTLED_PAPER_BUY_ACCOUNT_RISK_VERIFIED=PASS'
 $shell.Kill()
 if(!$shell.WaitForExit(20000)){throw 'PR244_CRASH_SHELL_NOT_TERMINATED'}
 $until=(Get-Date).AddSeconds(20)
 do{
   if(!(Get-Process -Id $enginePid -ErrorAction SilentlyContinue)){break}
   Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $until)
 if(Get-Process -Id $enginePid -ErrorAction SilentlyContinue){throw 'PR244_CRASH_ORPHAN_ENGINE_STILL_RUNNING'}
 # After BOTH original owned processes are gone, the quarantined lock is
 # no longer held open. The post-kill hash becomes the immutable baseline
 # for the negative relaunch attempt; no live locked file is read.
 if(!(Test-Path -LiteralPath $leased -PathType Leaf)){throw 'PR244_CRASH_LEASE_SILENTLY_RELEASED'}
 # Force-kill must NOT silently delete either ORIGINAL PAPER owner lease.
 # The files can be read only after the owned engine is fully terminated.
 foreach($paperLease in @($paperApplicationLease,$paperSessionLease)){
   if(!(Test-Path -LiteralPath $paperLease -PathType Leaf)){
     throw 'PR244_CRASH_FINANCIAL_LEASE_SILENTLY_RELEASED'
   }
   Ordinary $paperLease $false
 }
 $paperApplicationLeaseHash=Hash $paperApplicationLease
 $paperSessionLeaseHash=Hash $paperSessionLease
 if(!$paperApplicationLeaseHash -or !$paperSessionLeaseHash){
   throw 'PR244_CRASH_FINANCIAL_LEASE_DIGEST_NOT_VERIFIED'
 }
 Write-Host '::notice::PR244_CRASH_BOTH_PAPER_OWNER_LEASES_SURVIVED_FORCE_KILL=PASS'
 $leaseHash=Hash $leased
 if((Hash $checkpointPath) -cne $checkpointHash){throw 'PR244_CRASH_CHECKPOINT_CHANGED_DURING_FORCE_KILL'}
 # Hash the entire durable financial and saved-strategy roots, not volatile
 # WebView2 profile lockfiles that legitimately remain open outside this scope.
 $paperHistory=Join-Path $dataRoot 'paper-history'
 $pineLibrary=Join-Path $dataRoot 'pine-library'
 $paperHistoryHash=Hashes $paperHistory
 $pineLibraryHash=Hashes $pineLibrary
 if(!$leaseHash -or $paperHistoryHash.Count -lt 2 -or $pineLibraryHash.Count -lt 1){throw 'PR244_CRASH_ORIGINAL_FINANCIAL_AND_PINE_INVENTORY_MISSING'}
 Write-Host '::notice::PR244_CRASH_SEALED_FINANCIAL_AND_PINE_FILES_VERIFIED_POSTKILL=PASS'
 function PR244ReadOrphanReport([string]$install,[string]$data,[string]$id){
   $root=Join-Path $env:GITHUB_WORKSPACE 'product/tools/wails-pilot'
   if(!(Test-Path -LiteralPath (Join-Path $root 'cmd/orphan-custody-report/main.go') -PathType Leaf)){throw 'PR244_CRASH_OPERATOR_CLI_MISSING'}
   Push-Location $root
   try{
     $raw=@(& go run -mod=readonly ./cmd/orphan-custody-report inspect $install $data $id)
     if($LASTEXITCODE -ne 0 -or $raw.Count -ne 1){throw 'PR244_CRASH_OPERATOR_CLI_REFUSED'}
     return ($raw[0]|ConvertFrom-Json -Depth 16)
   }finally{Pop-Location}
 }
 $reportBefore=PR244ReadOrphanReport $script:installedRoot $dataRoot $crashArchive.source_id
 if($reportBefore.schema -cne 'ktrade.orphan-custody.diagnostic-only.v1' -or
    $reportBefore.selected_source_sha -cne $NewSHA -or
    $reportBefore.selection_receipt_digest -cnotmatch '^[a-f0-9]{64}$' -or
    $reportBefore.paper.source_id -cne $crashArchive.source_id -or
    $reportBefore.state -cne 'QUARANTINED' -or
    $reportBefore.release_process_lease -cne 'PRESENT' -or
    $reportBefore.paper.state -cne 'QUARANTINED_OWNER_LEASES' -or
    $reportBefore.paper.application_owner_lease -cne 'PRESENT' -or
    $reportBefore.paper.session_owner_lease -cne 'PRESENT' -or
    $reportBefore.process_quiescence_proven -ne $false -or
    $reportBefore.financial_replay_verified -ne $false -or
    $reportBefore.original_risk_verified -ne $false -or
    $reportBefore.safe_to_clear -ne $false -or
    $reportBefore.execution_restore_eligible -ne $false -or
    $reportBefore.live_armed -ne $false -or
    $reportBefore.owner_data_mutated -ne $false){throw 'PR244_CRASH_OPERATOR_REPORT_QUARANTINE_OR_AUTHORITY_DRIFT'}
 $reportBeforeJSON=$reportBefore|ConvertTo-Json -Compress -Depth 16
 if((Hash $leased) -cne $leaseHash -or
   (Hash $paperApplicationLease) -cne $paperApplicationLeaseHash -or
   (Hash $paperSessionLease) -cne $paperSessionLeaseHash -or
   (Hash $checkpointPath) -cne $checkpointHash){throw 'PR244_CRASH_OPERATOR_REPORT_CHANGED_OWNER_CUSTODY'}
 AssertHashes $paperHistoryHash (Hashes $paperHistory) 'PR244_CRASH_OPERATOR_REPORT_FINANCIAL_MUTATION'
 AssertHashes $pineLibraryHash (Hashes $pineLibrary) 'PR244_CRASH_OPERATOR_REPORT_PINE_MUTATION'
 Write-Host '::notice::PR244_CRASH_OPERATOR_READONLY_QUARANTINE_JSON=PASS'

 $selected=Get-Content -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json') -Raw|ConvertFrom-Json
 if($selected.source_sha -cne $NewSHA -or $selected.live_armed -ne $false){throw 'PR244_CRASH_INSTALL_SELECTION_CHANGED'}
 $folder=Join-Path $script:shortcuts ('KTRADE-'+$selected.selection_digest.Substring(0,16))
 $shortcut=Join-Path $folder 'KTRADE.lnk'
 Ordinary $shortcut $false
 # Attempt the SAME previously verified original native shortcut; a stale
 # orphan lease must refuse it rather than silently rearm the account.
 Start-Process -FilePath $shortcut
 Start-Sleep -Seconds 6
 $candidateApps=@(Get-CimInstance Win32_Process -Filter "Name='ktrade.exe'"|Where-Object {
   [string]::Equals($_.ExecutablePath,(Join-Path $stage 'ktrade.exe'),[StringComparison]::OrdinalIgnoreCase)
 })
 if($candidateApps.Count -ne 0 -or !(Test-Path -LiteralPath $leased) -or (Hash $leased) -cne $leaseHash){
   throw 'PR244_CRASH_UNAUTHORIZED_RELAUNCH_OR_REARM'
 }
 # Retain both original orphan locks unchanged across the attempted launch.
 # A stopped operator must perform a separately authorized custody review;
 # this negative test provides no lease-clear or account-rearm operation.
 if(!(Test-Path -LiteralPath $paperApplicationLease -PathType Leaf) -or
    !(Test-Path -LiteralPath $paperSessionLease -PathType Leaf) -or
    (Hash $paperApplicationLease) -cne $paperApplicationLeaseHash -or
    (Hash $paperSessionLease) -cne $paperSessionLeaseHash){
   throw 'PR244_CRASH_ORPHAN_PAPER_OWNER_LEASE_CHANGED_DURING_REFUSED_RELAUNCH'
 }
 Write-Host '::notice::PR244_CRASH_BOTH_PAPER_OWNER_LEASES_UNCHANGED_AFTER_REFUSED_RELAUNCH=PASS'
 $reportAfter=PR244ReadOrphanReport $script:installedRoot $dataRoot $crashArchive.source_id
 if(($reportAfter|ConvertTo-Json -Compress -Depth 16) -cne $reportBeforeJSON -or
   (Hash $leased) -cne $leaseHash -or
   (Hash $paperApplicationLease) -cne $paperApplicationLeaseHash -or
   (Hash $paperSessionLease) -cne $paperSessionLeaseHash -or
   (Hash $checkpointPath) -cne $checkpointHash){throw 'PR244_CRASH_OPERATOR_REPORT_REPEAT_CHANGED_CUSTODY'}
 AssertHashes $paperHistoryHash (Hashes $paperHistory) 'PR244_CRASH_OPERATOR_REPORT_REPEAT_FINANCIAL_MUTATION'
 AssertHashes $pineLibraryHash (Hashes $pineLibrary) 'PR244_CRASH_OPERATOR_REPORT_REPEAT_PINE_MUTATION'
 Write-Host '::notice::PR244_CRASH_OPERATOR_REPORT_REPEATED_NO_MUTATION=PASS'

 if((Hash $checkpointPath) -cne $checkpointHash){throw 'PR244_CRASH_CHECKPOINT_CHANGED_DURING_REFUSED_RELAUNCH'}
 AssertHashes $paperHistoryHash (Hashes $paperHistory) 'PR244_CRASH_FINANCIAL_ARCHIVE_CHANGED_DURING_REFUSED_RELAUNCH'
 AssertHashes $pineLibraryHash (Hashes $pineLibrary) 'PR244_CRASH_SAVED_PINE_CHANGED_DURING_REFUSED_RELAUNCH'
 Write-Host '::notice::PR244_CRASH_ONE_SETTLED_PAPER_BUY_CHILD_TERMINATED_STALE_LEASE_QUARANTINED_NO_REARM=PASS'
 return
'@
$paper=ReplaceExact $paper ' $buyProduct=P5-Account $buyAccount 1 $buyExpected' (' $buyProduct=P5-Account $buyAccount 1 $buyExpected'+[Environment]::NewLine+$injection) 'first-one-buy'
$invoke='& { Set-StrictMode -Off; Run-P9NativeRoundTrips }'
$afterInvoke=@'
& { Set-StrictMode -Off; Run-P9NativeRoundTrips }
$script:active=$null
Write-Host '::notice::PR244_NATIVE_FUNDED_FORCE_KILL_QUARANTINE=PASS'
return
'@
$native=ReplaceExact $native $invoke $afterInvoke 'after-only-first-buy'
$files=@(
 @{name='Build-And-Qualify-PR244-Crash.ps1';source=$builder},
 @{name='Installed-PR244-Funded-Crash.ps1';source=$native},
 @{name='Original-W40-Paper-Crash.ps1';source=$paper}
)
foreach($file in $files){
 $dest=Join-Path $OutputRoot $file.name
 [IO.File]::WriteAllText($dest,$file.source,[Text.UTF8Encoding]::new($false))
 $tok=$null;$errs=$null
 [void][Management.Automation.Language.Parser]::ParseFile($dest,[ref]$tok,[ref]$errs)
 Need ($errs.Count -eq 0) ('PR244_CRASH_DERIVED_SCRIPT_PARSE '+$file.name+' '+(($errs|ForEach-Object {$_.ToString()}) -join '; '))
}
Write-Host '::notice::PR244_CRASH_PINNED_NATIVE_BUILDER_PAPER_SOURCE_DERIVED_WITHOUT_MUTATING_ORIGINAL=PASS'
