# DIC-14: bounded independent synthetic Windows migration and rollback test.
# This is NOT signed historical 1.5.7 predecessor qualification.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$ScratchRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Fail([string]$Code){throw ('DIC14_'+$Code)}
function Require([bool]$Condition,[string]$Code){if(-not $Condition){Fail $Code}}
function Mark([string]$Code){Write-Host ('DIC14_'+$Code+'=PASS')}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function RunUpgrade([string[]]$Args,[string]$Label,[bool]$ExpectedSuccess=$true){
  $log=Join-Path $ScratchRoot 'private-upgrade.log'
  $global:LASTEXITCODE=0
  try{ & $script:Upgrade @Args *> $log }catch{$global:LASTEXITCODE=1}
  $code=$LASTEXITCODE
  if($ExpectedSuccess -and $code -ne 0){Write-Host ('DIC14_FAILURE_STEP_'+$Label+'=FAIL');Fail ($Label+'_FAILED_PRIVATE_OUTPUT_WITHHELD')}
  if(-not $ExpectedSuccess -and $code -eq 0){Fail ($Label+'_UNEXPECTED_SUCCESS')}
  Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
Require ($env:RUNNER_OS -ceq 'Windows' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted') 'NOT_HOSTED_WINDOWS'
Require ($env:KTRADE_CI_SOURCE_ONLY -ceq '1' -and $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
         $env:KTRADE_CI_COINBASE_ALLOWED -ceq '0' -and $env:KTRADE_CI_PROMOTION_ALLOWED -ceq '0') 'UNSAFE_AUTHORITY'
$root=[IO.Path]::GetFullPath($SourceRoot)
$scratch=[IO.Path]::GetFullPath($ScratchRoot)
$tmp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
Require ($scratch.StartsWith($tmp,[StringComparison]::OrdinalIgnoreCase)) 'OUTSIDE_EPHEMERAL_TEMP'
Require (-not(Test-Path -LiteralPath $scratch)) 'SCRATCH_COLLISION'
New-Item -Path $scratch -ItemType Directory|Out-Null
$ScratchRoot=$scratch
$packageLog=Join-Path $scratch 'private-package.log'
$zip=Join-Path $scratch 'synthetic-package.zip'
try{
  $global:LASTEXITCODE=0
  & (Join-Path $root 'windows/package-clean-windows.ps1') -OutputZip $zip *> $packageLog
  Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $zip)) 'PACKAGE_BUILD_FAILED'
  $extract=Join-Path $scratch 'extracted'
  Expand-Archive -LiteralPath $zip -DestinationPath $extract
  $apps=@(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter 'ktrade-upgrade.exe')
  Require ($apps.Count -eq 1) 'UPGRADER_IDENTITY'
  $script:Upgrade=$apps[0].FullName
  $app=Split-Path -Parent $script:Upgrade
  $manifest=Get-Content -LiteralPath (Join-Path $app 'MANIFEST.sha256')
  foreach($name in @('ktrade.exe','ktrade-recover.exe','ktrade-schema.exe','ktrade-upgrade.exe')){
    $exe=Join-Path $app $name
    Require (Test-Path -LiteralPath $exe) 'FOUR_EXES_MISSING'
    $entries=@($manifest | Where-Object{$_ -match ('^[0-9a-f]{64}  '+[regex]::Escape($name)+'$')})
    Require ($entries.Count -eq 1 -and $entries[0].Substring(0,64) -ceq (Hash $exe)) 'PACKAGE_MANIFEST_MISMATCH'
  }
  Mark 'FOUR_EXES_AND_MANIFEST'

  $source=Join-Path $scratch 'synthetic-predecessor-not-1_5_7'
  $sourceData=Join-Path $source 'data'
  $seed=[ordered]@{
    'config.json'='{"synthetic_preference":"DIC14_KEEP_LAYOUT","api_key":""}'
    'trading_pairs.json'='["BTC-USDC"]'
    'strategy_settings_synthetic.json'='{"enabled":false,"risk":"DIC14_KEEP_RISK"}'
    'strategy_state_synthetic.json'='{"pnl":321.45,"fills":[{"id":"SYNTHETIC_FILL"}],"fees":1.25}'
    'history\synthetic-fills.json'='{"fills":2,"pnl":321.45}'
    'accounting_epochs\synthetic-epoch.json'='{"realized_pnl":321.45}'
    'pine-library\index.json'='{"synthetic":"DIC14_KEEP_FAVORITES","favorites":["synthetic-indicator"]}'
    'pine-library\revisions\synthetic-indicator\source.pine'='//@version=5'+[Environment]::NewLine+'indicator("DIC14 synthetic")'+[Environment]::NewLine+'plot(close)'
    'pine-library\revisions\synthetic-indicator\metadata.json'='{"ownership":"user","favorite":true}'
    'client_id'='DIC14_SYNTHETIC_CLIENT_ONLY'
    'execution.journal.jsonl'='{"synthetic":"DIC14_KEEP_JOURNAL"}'
  }
  $reference=@{}
  foreach($rel in $seed.Keys){
    $path=Join-Path $sourceData $rel
    $null=New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    [IO.File]::WriteAllText($path,[string]$seed[$rel],[Text.UTF8Encoding]::new($false))
    $reference[$rel]=(Hash $path)
  }
  $sourceBrowser=Join-Path $sourceData 'browser\brave-profile\Bookmarks'
  $null=New-Item -ItemType Directory -Path (Split-Path -Parent $sourceBrowser) -Force
  [IO.File]::WriteAllText($sourceBrowser,'DIC14_BROWSER_REQUIRES_SEPARATE_ATTESTED_STAGE')
  Mark 'SYNTHETIC_PREFS_PNL_HISTORY_PINE_SEEDED'
  $snapshot=Join-Path $scratch 'verified-snapshot'
  $original=((& $script:Upgrade digest --root $source | ConvertFrom-Json).durable_digest)
  Require ($LASTEXITCODE -eq 0 -and $original -match '^[0-9a-f]{64}$') 'SOURCE_DIGEST'
  Mark 'SOURCE_DIGEST'
  RunUpgrade @('snapshot','--source-root',$source,'--snapshot-root',$snapshot,'--source-version','DIC14-SYNTHETIC-ONLY','--target-version','DIC14-SYNTHETIC-TARGET') 'SNAPSHOT'
  Mark 'SNAPSHOT_CREATED'
  RunUpgrade @('verify','--snapshot-root',$snapshot) 'VERIFY'
  Mark 'SNAPSHOT_VERIFIED'
  $man=(Get-Content -LiteralPath (Join-Path $snapshot 'upgrade-manifest.json') -Raw | ConvertFrom-Json)
  $paths=@($man.files | ForEach-Object {$_.path})
  foreach($rel in $seed.Keys){
    Require ($paths -ccontains $rel.Replace('\','/')) 'MISSING_DURABLE_PATH'
  }
  Require (@($paths).Count -eq $reference.Count) 'UNEXPECTED_DURABLE_INVENTORY'
  Require (@($paths|Where-Object{$_ -match 'browser|log|profile|\.exe'}).Count -eq 0) 'NONPORTABLE_DATA_EXPORTED'
  Mark 'COMPLETE_DURABLE_PINE_PREFS_PNL_HISTORY_INVENTORY'
  $mutated=Join-Path $scratch 'tampered-snapshot'
  Copy-Item -LiteralPath $snapshot -Destination $mutated -Recurse
  [IO.File]::AppendAllText((Join-Path $mutated 'payload\data\strategy_state_synthetic.json'),'TAMPER')
  RunUpgrade @('verify','--snapshot-root',$mutated) 'TAMPER_REJECTED' $false
  Mark 'ALTERED_SNAPSHOT_REJECTED'
  $target=Join-Path $scratch 'synthetic-target'
  $targetData=Join-Path $target 'data'
  $preserve=Join-Path $targetData 'browser\brave-profile\Bookmarks'
  $null=New-Item -ItemType Directory -Path (Split-Path -Parent $preserve) -Force
  [IO.File]::WriteAllText($preserve,'DIC14_TARGET_ONLY_BROWSER_UNCHANGED')
  $keepHash=Hash $preserve
  RunUpgrade @('install','--snapshot-root',$snapshot,'--target-root',$target) 'INSTALL'
  $installed=((& $script:Upgrade digest --root $target | ConvertFrom-Json).durable_digest)
  Require ($LASTEXITCODE -eq 0 -and $installed -ceq $original) 'INSTALLED_DIGEST_DRIFT'
  foreach($rel in $reference.Keys){
    Require ((Hash (Join-Path $targetData $rel)) -ceq $reference[$rel]) 'INSTALLED_USER_DATA_CHANGED'
    Require ((Hash (Join-Path $sourceData $rel)) -ceq $reference[$rel]) 'SOURCE_USER_DATA_CHANGED'
  }
  Require ((Hash $preserve) -ceq $keepHash) 'TARGET_BROWSER_UNEXPECTEDLY_CHANGED'
  Require (-not(Test-Path -LiteralPath (Join-Path $targetData 'browser\brave-profile\SourceBookmarks'))) 'UNEXPECTED_BROWSER_MIGRATION'
  Mark 'HASH_IDENTICAL_PREFS_PNL_HISTORY_PINE_AND_BROWSER_ISOLATION'
  RunUpgrade @('install','--snapshot-root',$snapshot,'--target-root',$target) 'DUPLICATE_INSTALL' $false
  Mark 'DUPLICATE_INSTALL_REJECTED'
  RunUpgrade @('seal-rollback','--target-root',$target) 'SEAL_ROLLBACK'
  Mark 'ROLLBACK_BASELINE_SEALED'
  $state=Join-Path $targetData 'strategy_state_synthetic.json'
  [IO.File]::AppendAllText($state,'{"new_pnl":999}')
  $changed=Hash $state
  RunUpgrade @('rollback','--target-root',$target) 'ROLLBACK_AFTER_NEW_TRADING_STATE' $false
  Require ((Hash $state) -ceq $changed) 'ROLLBACK_DESTROYED_NEW_STATE'
  Mark 'NEW_PNL_PREVENTS_DESTRUCTIVE_ROLLBACK'
  [IO.File]::WriteAllText($state,[string]$seed['strategy_state_synthetic.json'],[Text.UTF8Encoding]::new($false))
  Require ((Hash $state) -ceq $reference['strategy_state_synthetic.json']) 'RESTORE_TEST_STATE_FAILED'
  RunUpgrade @('rollback','--target-root',$target) 'SAFE_ROLLBACK'
  $afterRollback=((& $script:Upgrade digest --root $target | ConvertFrom-Json).durable_digest)
  Require ($LASTEXITCODE -eq 0 -and $afterRollback -ceq $original) 'ROLLBACK_DIGEST_CHANGED'
  foreach($rel in $reference.Keys){
    Require ((Hash (Join-Path $targetData $rel)) -ceq $reference[$rel]) 'ROLLBACK_LOST_DURABLE_DATA'
  }
  Require ((Hash $preserve) -ceq $keepHash) 'ROLLBACK_MUTATED_TARGET_BROWSER'
  Mark 'SAFE_ROLLBACK_EXACT_DATA_AND_BROWSER_PRESERVED'
  $runtimeMarker=Join-Path $sourceData 'runtime\instance.json'
  $null=New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeMarker) -Force
  [IO.File]::WriteAllText($runtimeMarker,'{"synthetic_running":true}')
  RunUpgrade @('snapshot','--source-root',$source,'--snapshot-root',(Join-Path $scratch 'blocked-live-snapshot'),'--source-version','SYNTHETIC','--target-version','SYNTHETIC') 'RUNNING_SOURCE_REJECTED' $false
  Mark 'RUNNING_SOURCE_REJECTED'
  Mark 'NO_REAL_PREDECESSOR_NO_REAL_PROFILE_NO_LIVE_BROKER'
  Mark 'SYNTHETIC_UPGRADE_ROLLBACK_QUALIFIED'
  Write-Host 'DIC14_HISTORICAL_1_5_7_COMPATIBILITY=BLOCKED_AUTHENTIC_SIGNED_PREDECESSOR_NOT_AVAILABLE'
  Write-Host 'DIC14_RELEASE_PROMOTION=PROHIBITED'
}finally{
  Remove-Item -LiteralPath $packageLog -Force -ErrorAction SilentlyContinue
}
