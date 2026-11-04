param(
 [Parameter(Mandatory=$true)][string]$WitnessRoot,
 [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
function Need([bool]$ok,[string]$label){if(!$ok){throw $label}}
$sourceSha='1b96c7a39d90a3bcc0485ce39bb6ab3269ab1664'
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
$builder=ReplaceExact $builder "sha='4b401d5f9c3a571c5ad61c4df33a7814120a3a4b';tree='0d8257297d53a8edd4a40b4099f102106619b2a2'" "sha='$sourceSha';tree='7143f2fa49b2027bb60d8d5106c632b2aa0c230d'" 'build-pins'
$native=ReplaceExact $native '$NewSHA=''4b401d5f9c3a571c5ad61c4df33a7814120a3a4b''' ('$NewSHA='''+$sourceSha+'''') 'native-source'
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
 $leaseHash=Hash $leased
 $dataHash=Hashes $dataRoot
 if(!$leaseHash -or $dataHash.Count -lt 1){throw 'PR244_CRASH_POST_TERMINATION_STATE_UNAVAILABLE'}
 Write-Host '::notice::PR244_CRASH_POST_KILL_LEASE_AND_DATA_HASHED=PASS'
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
 AssertHashes $dataHash (Hashes $dataRoot) 'PR244_CRASH_RELAUNCH_FINANCIAL_DATA_CHANGED'
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
