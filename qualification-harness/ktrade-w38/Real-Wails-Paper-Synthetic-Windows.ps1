# W38: genuine source-built isolated Wails PAPER desktop, test-only W13 market.
# No production installed source, broker, release, owner data, or LIVE mutation.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CandidateCheckout)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$ok,[string]$msg){if(!$ok){throw $msg}}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function IsOrdinary([string]$p,[bool]$dir){
 $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
 Require ($i.PSIsContainer -eq $dir -and !$i.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) 'W38_NONORDINARY_ASSET'
}
function JSONPost([string]$base,[string]$endpoint,[object]$payload){
 $body=ConvertTo-Json -InputObject $payload -Compress -Depth 7
 return Invoke-RestMethod -Method Post -Uri ($base+$endpoint) -Headers @{Origin=$base} -ContentType 'application/json' -Body $body -TimeoutSec 18
}
function HTTPCode([string]$base,[string]$endpoint,[object]$payload){
 $body=ConvertTo-Json -InputObject $payload -Compress -Depth 7
 try{
  $r=Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($base+$endpoint) -Headers @{Origin=$base} -ContentType 'application/json' -Body $body -TimeoutSec 18 -ErrorAction Stop
  return [int]$r.StatusCode
 }catch{
  if($_.Exception.Response){return [int]$_.Exception.Response.StatusCode}
  throw
 }
}
Require ($env:OS -ceq 'Windows_NT' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted') 'W38_EPHEMERAL_WINDOWS_ONLY'
Require ($env:RUNNER_TEMP -and (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container)) 'W38_TEMP_REQUIRED'
$sha='0059d4b794552818b3f32798da7df27c75e21c5c'
$tree='9f1e559560ac14f4e6fc823dac9150e3a95f2c4d'
Require ((& git -C $CandidateCheckout rev-parse HEAD).Trim() -ceq $sha -and
 (& git -C $CandidateCheckout rev-parse 'HEAD^{tree}').Trim() -ceq $tree -and $LASTEXITCODE -eq 0) 'W38_EXACT_SOURCE_DRIFT'
$dirty=@(& git -C $CandidateCheckout status --porcelain --untracked-files=no)
Require ($dirty.Count -eq 0) 'W38_CANDIDATE_DIRTY'
Write-Host '::notice::W38_PINNED_W34_SOURCE_AND_TREE=PASS'
$env:KTRADE_W13_QUALIFICATION_ONLY='1'
$stageRoot=Join-Path ([IO.Path]::GetTempPath()) ('ktrade-w03-package-'+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $stageRoot 'KTRADE-WailsPortable'
$parent=$null;$engine=$null;$port=0;$base=''
$ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
Require (Test-Path -LiteralPath $ps51) 'W38_WINDOWS_PS_MISSING'
Push-Location $CandidateCheckout
try{
 & npm ci --ignore-scripts --no-audit --no-fund --silent
 Require ($LASTEXITCODE -eq 0) 'W38_ASSET_NPM_LOCK_STAGE_FAILED'
 & node scripts/stage_offline_vendor.cjs
 Require ($LASTEXITCODE -eq 0) 'W38_ORIGINAL_MONACO_STAGE_FAILED'
 & (Join-Path $CandidateCheckout 'windows/Build-KTRADE-WailsPortable.ps1') -OutputRoot $stageRoot -ExpectedSourceSha $sha -W13QualificationFixture
 Require ($LASTEXITCODE -eq 0) 'W38_ORIGINAL_DISPOSABLE_WAILS_PACKAGE_BUILD_FAILED'
}finally{Pop-Location}
IsOrdinary $stage $true
$sourceReceipt=Get-Content -LiteralPath (Join-Path $stageRoot 'source-manifest.json') -Raw|ConvertFrom-Json
Require ($sourceReceipt.schema -ceq 'ktrade.wails.package-qualification.v1' -and
 $sourceReceipt.source_sha -ceq $sha -and $sourceReceipt.live_armed -eq $false -and
 $sourceReceipt.fixture_mode -ceq 'w13-compile-time-only' -and
 $sourceReceipt.release_candidate -eq $false) 'W38_PACKAGE_NOT_BOUNDED_SYNTHETIC'
$pair=Get-Content -LiteralPath (Join-Path $stage 'wails-paper-package-proof.json') -Raw|ConvertFrom-Json
$fresh=Get-Content -LiteralPath (Join-Path $stage 'data/wails-paper-fresh-data-proof.json') -Raw|ConvertFrom-Json
Require ($pair.live_armed -eq $false -and $fresh.live_armed -eq $false -and
 $pair.wails_exe_sha256 -ceq (Hash (Join-Path $stage 'ktrade.exe')) -and
 $pair.engine_exe_sha256 -ceq (Hash (Join-Path $stage 'ktrade-engine.exe')) -and
 $pair.wails_exe_sha256 -ceq $fresh.wails_exe_sha256 -and
 $pair.engine_exe_sha256 -ceq $fresh.engine_exe_sha256) 'W38_PAIRED_BINARIES_NOT_SOURCE_BOUND'
# Windows Server .NET GetTempPath() and Go os.TempDir() can select
# distinct OS TEMP roots (GetTempPath2 vs GetTempPath). Build using the
# original W03 builder's required .NET root; move only the fully fresh
# disposable package, unchanged, to the Go runtime's verified OS TEMP.
# This does not loosen the original builder or Wails stage admission.
$goTempProbe=Join-Path $env:RUNNER_TEMP ('w38-gotemp-'+[guid]::NewGuid().ToString('N')+'.go')
$goProbe=@'
package main
import ("fmt";"os")
func main(){fmt.Println(os.TempDir())}
'@
[IO.File]::WriteAllText($goTempProbe,$goProbe,[Text.UTF8Encoding]::new($false))
try {
 $goTempRaw=@(& go run $goTempProbe)
 Require ($LASTEXITCODE -eq 0 -and $goTempRaw.Count -eq 1) 'W38_GO_RUNTIME_TEMP_PROBE_FAILED'
 $goTemp=[IO.Path]::GetFullPath($goTempRaw[0]).TrimEnd([char]'\')
 IsOrdinary $goTemp $true
 $builderTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char]'\')
 if(![string]::Equals($goTemp,$builderTemp,[StringComparison]::OrdinalIgnoreCase)){
  $dest=Join-Path $goTemp (Split-Path -Leaf $stageRoot)
  Require (!(Test-Path -LiteralPath $dest)) 'W38_GO_TEMP_STAGE_ALREADY_EXISTS'
  Move-Item -LiteralPath $stageRoot -Destination $dest -ErrorAction Stop
  $stageRoot=$dest
  $stage=Join-Path $stageRoot 'KTRADE-WailsPortable'
  IsOrdinary $stage $true
  Require ((Hash (Join-Path $stage 'ktrade.exe')) -ceq $pair.wails_exe_sha256 -and
   (Hash (Join-Path $stage 'ktrade-engine.exe')) -ceq $pair.engine_exe_sha256) 'W38_RELOCATED_BINARY_DIGEST_DRIFT'
 }
 Write-Host ('::notice::W38_NET_AND_GO_TEMP_STAGE_IDENTITY=PASS')
}finally {Remove-Item -LiteralPath $goTempProbe -Force -ErrorAction SilentlyContinue}
Write-Host '::notice::W38_FRESH_WAILS_AND_GO_PAIRED_PACKAGE=PASS'

Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W35BNative {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint x,uint y,uint z,UIntPtr u);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,System.Text.StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool IsChild(IntPtr parent,IntPtr child);
}
'@
function FindUI([object]$shell,[string]$label,[bool]$isButton,[int]$seconds=35){
 $until=(Get-Date).AddSeconds($seconds)
 do{
  $shell.Refresh()
  Require (!$shell.HasExited) 'W35B_SHELL_EXITED_BEFORE_UI_READY'
  if($shell.MainWindowHandle -ne [IntPtr]::Zero){
   $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
   $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
   foreach($node in $nodes){
    try{
     if($node.Current.IsOffscreen -or !$node.Current.Name.Contains($label)){continue}
     if(!$isButton){return $node}
     if($node.Current.Name -cne $label -or !$node.Current.IsEnabled){continue}
     $h=[IntPtr]$node.Current.NativeWindowHandle
     $native=$false
     if($h -ne [IntPtr]::Zero -and [W35BNative]::IsChild($shell.MainWindowHandle,$h)){
      $sb=New-Object Text.StringBuilder(512)
      if([W35BNative]::GetClassName($h,$sb,512) -gt 0){$native=($sb.ToString() -match '^(?:WindowsForms10\.)?BUTTON(?:\.|$)')}
     }
     if($native -or $node.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button){return $node}
    }catch{}
   }
  }
  Start-Sleep -Milliseconds 350
 }while((Get-Date) -lt $until)
 throw ('W35B_NATIVE_UI_NOT_OBSERVED_'+$label)
}
function ClickUI([object]$shell,[string]$label){
 $node=FindUI $shell $label $true
 $rect=$node.Current.BoundingRectangle
 $outer=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require (!$rect.IsEmpty -and $rect.Width -gt 8 -and $rect.Height -gt 8 -and
  $rect.Left -ge $outer.Left -and $rect.Right -le $outer.Right -and
  $rect.Top -ge $outer.Top -and $rect.Bottom -le $outer.Bottom) 'W35B_FOREIGN_CONTROL'
 [void][W35BNative]::SetForegroundWindow($shell.MainWindowHandle)
 Start-Sleep -Milliseconds 200
 Require ([W35BNative]::GetForegroundWindow() -eq $shell.MainWindowHandle) 'W35B_FOREIGN_FOCUS'
 Require ([W35BNative]::SetCursorPos([int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))) 'W35B_NATIVE_POINTER_REFUSED'
 [W35BNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [W35BNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}

function StartOriginal(){
 $stderr=Join-Path $env:RUNNER_TEMP ('W38-wails-'+[guid]::NewGuid().ToString('N')+'.err')
 $stdout=Join-Path $env:RUNNER_TEMP ('W38-wails-'+[guid]::NewGuid().ToString('N')+'.out')
 # Native CreateProcess, not ShellExecute. Preserve the exact Go TEMP
 # environment used by the stage provenance probe and build; Explorer's
 # separate environment can select a different TEMP and would rightly fail
 # the original portable path ownership check.
 $psi=[Diagnostics.ProcessStartInfo]::new((Join-Path $stage 'ktrade.exe'))
 $psi.UseShellExecute=$false
 $psi.WorkingDirectory=$stage
 $psi.RedirectStandardError=$true
 $psi.RedirectStandardOutput=$true
 $script:parent=[Diagnostics.Process]::Start($psi)
 Require ($null -ne $script:parent) 'W38_NATIVE_CREATE_PROCESS_REFUSED'
 $deadline=(Get-Date).AddSeconds(50)
 do{
  $script:parent.Refresh()
  if($script:parent.HasExited){
   $log=try{$script:parent.StandardError.ReadToEnd()}catch{'GUI stderr unavailable'}
   if($log.Length -gt 1500){$log=$log.Substring($log.Length-1500)}
   throw ('W38_WAILS_SHELL_PREMATURE_EXIT code='+$script:parent.ExitCode+' stderr='+$log)
  }
  if($script:parent.MainWindowHandle -ne [IntPtr]::Zero){break}
  Start-Sleep -Milliseconds 350
 }while((Get-Date) -lt $deadline)
 Require ($script:parent.MainWindowHandle -ne [IntPtr]::Zero) 'W38_NATIVE_WAILS_WINDOW_NOT_VISIBLE'
 $enginePath=Join-Path $stage 'ktrade-engine.exe'
 do{
  $owned=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$script:parent.Id)|Where-Object {
   $_.Name -ceq 'ktrade-engine.exe' -and $_.ExecutablePath -ieq $enginePath
  })
  if($owned.Count -eq 1){break}
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $deadline)
 Require ($owned.Count -eq 1) 'W38_NATIVE_GO_ENGINE_NOT_OWNED'
 $script:engine=[int]$owned[0].ProcessId
 $ports=@(Get-NetTCPConnection -OwningProcess $script:engine -State Listen|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W38_NOT_SINGLE_LOCAL_LOOPBACK'
 $script:port=[int]$ports[0].LocalPort
 $script:base='http://127.0.0.1:'+$script:port
}
function Cap(){
 return Invoke-RestMethod -Uri ($script:base+'/api/operator/capabilities') -TimeoutSec 10
}
function Stopped([object]$c){
 Require ($c.schema -ceq 'ktrade.operator.capabilities.v1' -and
 $c.mode -ceq 'PAPER_STOPPED' -and $c.paper_orders_enabled -eq $false -and
 $c.live_orders_enabled -eq $false -and $c.requires_review -eq $true) 'W38_DISARMED_CAPABILITY_MISMATCH'
}
function StopOriginal(){
 Require ($script:parent.CloseMainWindow()) 'W38_UI_CLOSE_REJECTED'
 Require ($script:parent.WaitForExit(30000)) 'W38_WINDOW_STUCK'
 Require (!(Get-Process -Id $script:engine -ErrorAction SilentlyContinue)) 'W38_ORPHAN_ENGINE'
 $script:parent=$null;$script:engine=$null
}
try{
 StartOriginal
 Stopped (Cap)
 ClickUI $script:parent 'Verify chart UI'
 $null=FindUI $script:parent 'Original chart DOM, Monaco editor and preferences controls observed.' $false 20
 Write-Host '::notice::W38_REAL_WAILS_WEBVIEW2_ORIGINAL_CHART_MONACO_NATIVE_UI=PASS'
 $pine='//@version=5'+[Environment]::NewLine+
  'strategy("W38 fresh synthetic Wails PAPER")'+[Environment]::NewLine+
  'if bar_index == 5'+[Environment]::NewLine+
  '    strategy.entry("L", strategy.long, qty=1)'
 $created=JSONPost $script:base '/api/pine-library' @{
  display_name='W38 source-bound synthetic strategy';kind='strategy';source=$pine
 }
 Require ($created.metadata.id -cmatch '^[a-zA-Z0-9_-]{8,100}$' -and
  $created.metadata.ownership -ceq 'user' -and $created.source -ceq $pine) 'W38_ORIGINAL_PINE_LIBRARY_CUSTODY'
 $scriptID=$created.metadata.id
 $fund=@{script_id=$scriptID;product_id='BTC-USDC';timeframe='1m';
  initial_cash='600';simulated_fee_bps=100;fee_model_acknowledged=$true}
 $invalid=$fund.Clone();$invalid.fee_model_acknowledged=$false
 Require ((HTTPCode $script:base '/api/paper/session/start' $invalid) -ne 200) 'W38_UNACKNOWLEDGED_FEES_ADMITTED'
 Stopped (Cap)
 Require ((HTTPCode $script:base '/api/orders/place' @{product_id='BTC-USDC';side='BUY'}) -eq 423) 'W38_LEGACY_ORDER_NOT_LOCKED'
 $running=JSONPost $script:base '/api/paper/session/start' $fund
 Require ($running.mode -ceq 'PAPER_ISOLATED_RUNNING' -and
 $running.paper_orders_enabled -eq $true -and $running.live_armed -eq $false) 'W38_ORIGINAL_PAPER_START_FAILED'
 $runningCap=Cap
 Require ($runningCap.mode -ceq 'PAPER_ISOLATED_RUNNING' -and
 $runningCap.paper_orders_enabled -eq $true -and
 $runningCap.live_orders_enabled -eq $false -and
 $runningCap.strategy_execution_enabled -eq $true -and
 $runningCap.paper_accounting_enabled -eq $true) 'W38_RUNNING_CAPABILITY_DRIFT'
 Write-Host '::notice::W38_VERIFIED_DESKTOP_GO_PAPER_FUNDED_ONLY_AFTER_ORIGINAL_FEE_ACK=PASS'
 $evaluation=JSONPost $script:base '/api/paper/session/evaluate' @{
  script_id=$scriptID;product_id='BTC-USDC';timeframe='1m'
 }
 Require (($evaluation|ConvertTo-Json -Depth 9 -Compress).Contains('ISOLATED_PAPER_FILLED_OR_DEDUPLICATED')) 'W38_NATIVE_FINAL_CANDLE_PAPER_REFUSED'
 $archive=Invoke-RestMethod -Uri ($script:base+'/api/paper/session/archive') -TimeoutSec 15
 $archiveJSON=$archive|ConvertTo-Json -Depth 20 -Compress
 Require ($archiveJSON.Contains('"fill_count":1') -and $archiveJSON.Contains('"original_risk_proof_verified":true')) 'W38_ORIGINAL_RISK_LEDGER_FILL_MISSING'
 $account=Invoke-RestMethod -Uri ($script:base+'/api/paper/accounting') -TimeoutSec 15
 $accountJSON=$account|ConvertTo-Json -Depth 20 -Compress
 Require ($accountJSON.Contains('"fees_paid":"0.4"') -and $accountJSON.Contains('"position_qty":"1"')) 'W38_AUTHENTIC_FINANCIAL_ACCOUNTING_INCOMPLETE'
 Write-Host '::notice::W38_GENUINE_WAILS_OWNED_GO_PAPER_FILL_RISK_AND_FEES=PASS'
 $stop=JSONPost $script:base '/api/paper/session/stop' @{reason='W38 explicit disposable operator Stop'}
 Require ($stop.stopped -eq $true -and $stop.paper_orders_enabled -eq $false) 'W38_STOP_NOT_PERSISTED'
 Stopped (Cap)
 Require ((HTTPCode $script:base '/api/paper/session/evaluate' @{
  script_id=$scriptID;product_id='BTC-USDC';timeframe='1m'
 }) -ne 200) 'W38_STOPPED_EVALUATION_ADMITTED'
 Write-Host '::notice::W38_STOP_PREVENTED_FURTHER_PAPER_EXECUTION=PASS'
 StopOriginal
 StartOriginal
 Stopped (Cap)
 $cold=Invoke-RestMethod -Uri ($script:base+'/api/paper/session/archive') -TimeoutSec 15
 $coldJSON=$cold|ConvertTo-Json -Depth 20 -Compress
 Require ($coldJSON.Contains('"fill_count":1') -and
  $coldJSON.Contains('"original_risk_proof_verified":true') -and
  $coldJSON.Contains('"execution_restore_eligible":false')) 'W38_COLD_ARCHIVE_OR_NO_REARM_INCOMPLETE'
 Write-Host '::notice::W38_REAL_WAILS_RESTART_COLD_ARCHIVE_NO_AUTO_REARM=PASS'
 StopOriginal
 Write-Host '::notice::W38_NO_REAL_BROKER_NO_OWNER_DATA_NO_RELEASE_NO_LIVE=PASS'
}finally{
 if($script:parent){
  try{if(!$script:parent.HasExited){$script:parent.CloseMainWindow()|Out-Null;$script:parent.WaitForExit(8000)|Out-Null}}catch{}
  try{if(!$script:parent.HasExited){Stop-Process -Id $script:parent.Id -Force -ErrorAction SilentlyContinue}}catch{}
 }
 if($script:engine){try{Stop-Process -Id $script:engine -Force -ErrorAction SilentlyContinue}catch{}}
 Remove-Item Env:KTRADE_W13_QUALIFICATION_ONLY -ErrorAction SilentlyContinue
 # Only fresh disposable test package can be removed, never any owner profile.
 if(Test-Path -LiteralPath $stageRoot){Remove-Item -LiteralPath $stageRoot -Force -Recurse -ErrorAction SilentlyContinue}
}
