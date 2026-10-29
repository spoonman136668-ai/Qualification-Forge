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
$sha='40588f886e712223d0af289ee1d1439c6020236b'
$tree='9b5d1eabe5f2218ee56094b7e4256ccb0499b11d'
Require ((& git -C $CandidateCheckout rev-parse HEAD).Trim() -ceq $sha -and
 (& git -C $CandidateCheckout rev-parse 'HEAD^{tree}').Trim() -ceq $tree -and $LASTEXITCODE -eq 0) 'W38_EXACT_SOURCE_DRIFT'
$dirty=@(& git -C $CandidateCheckout status --porcelain --untracked-files=no)
Require ($dirty.Count -eq 0) 'W38_CANDIDATE_DIRTY'
Write-Host '::notice::W39_PINNED_ACCESSIBLE_OPERATOR_SOURCE_AND_TREE=PASS'
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
 Write-Host ('W38_TEMP_PROBE NET='+$builderTemp+' GO='+$goTemp+' STAGE_PARENT='+([IO.Path]::GetDirectoryName($stageRoot))+' CMD_TMP='+$env:TMP+' CMD_TEMP='+$env:TEMP)
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

function ClickAnyUI([object]$shell,[string]$name){
 $node=FindUI $shell $name $false 20
 $rect=$node.Current.BoundingRectangle
 $outer=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require (!$rect.IsEmpty -and $rect.Width -gt 6 -and $rect.Height -gt 6 -and $rect.Left -ge $outer.Left -and
  $rect.Right -le $outer.Right -and $rect.Top -ge $outer.Top -and $rect.Bottom -le $outer.Bottom) ('W39_NONLOCAL_CLICK_'+$name)
 [void][W35BNative]::SetForegroundWindow($shell.MainWindowHandle)
 Start-Sleep -Milliseconds 100
 Require ([W35BNative]::GetForegroundWindow() -eq $shell.MainWindowHandle) 'W39_APP_LOST_FOCUS'
 Require ([W35BNative]::SetCursorPos([int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))) 'W39_POINTER_REFUSED'
 [W35BNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [W35BNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}
function ReadAckState([object]$node){
 try{
  $pattern=$node.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
  return @{state=[string]$pattern.Current.ToggleState;via='UIA TogglePattern'}
 }catch{}
 try{
  $legacy=$node.GetCurrentPattern([System.Windows.Automation.LegacyIAccessiblePattern]::Pattern)
  if($legacy.Current.Role -eq 44){
   $state=if(($legacy.Current.State -band 16) -ne 0){'On'}else{'Off'}
   return @{state=$state;via='native checkbox LegacyIAccessible state'}
  }
 }catch{}
 return @{state='Unknown';via='not exposed by native accessibility provider'}
}
function ToggleAck([object]$shell){
 # Exactly ONE physical action on the original input. Never dispatch Toggle
 # and then click a fallback after an asynchronous readback: that can undo it.
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
 $list=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
 $matches=@($list|Where-Object {
  try{!$_.Current.IsOffscreen -and $_.Current.IsEnabled -and ([string]$_.Current.Name) -ceq 'Acknowledge simulated paper fees'}catch{$false}
 }|Sort-Object { $r=$_.Current.BoundingRectangle;$r.Width*$r.Height })
 Require ($matches.Count -ge 1) 'W39_EXACT_NATIVE_FEE_INPUT_NOT_FOUND'
 $node=$matches[0];$rect=$node.Current.BoundingRectangle;$outer=$root.Current.BoundingRectangle
 Require (!$rect.IsEmpty -and $rect.Width -ge 6 -and $rect.Height -ge 6 -and
  $rect.Left -ge $outer.Left -and $rect.Right -le $outer.Right -and
  $rect.Top -ge $outer.Top -and $rect.Bottom -le $outer.Bottom) 'W39_NONLOCAL_FEE_INPUT'
 $before=ReadAckState $node
 Require ($before.state -ne 'On') 'W39_FEE_ALREADY_ACKED_BEFORE_NATIVE_ACTION'
 [void][W35BNative]::SetForegroundWindow($shell.MainWindowHandle)
 Start-Sleep -Milliseconds 200
 Require ([W35BNative]::GetForegroundWindow() -eq $shell.MainWindowHandle) 'W39_FEE_INPUT_FOREIGN_FOCUS'
 Require ([W35BNative]::SetCursorPos([int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))) 'W39_FEE_POINTER_REFUSED'
 Write-Host ('W39_NATIVE_FEE_SINGLE_CLICK='+(@{before=$before.state;provider=$before.via;control_type=$node.Current.ControlType.ProgrammaticName;rectangle=$rect.ToString();action_count=1}|ConvertTo-Json -Compress))
 [W35BNative]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [W35BNative]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 $until=(Get-Date).AddSeconds(3)
 do{
  Start-Sleep -Milliseconds 100
  $after=ReadAckState $node
  if($after.state -eq 'On'){break}
 }while((Get-Date) -lt $until)
 Write-Host ('W39_NATIVE_FEE_AFTER_SINGLE_ACTION='+(@{after=$after.state;provider=$after.via;action_count=1}|ConvertTo-Json -Compress))
 Require ($after.state -ne 'Off' -and $after.state -ne 'Indeterminate') 'W39_SINGLE_NATIVE_FEE_CLICK_NOT_CHECKED'
 # Some WebView2 providers expose the named input without checkbox state.
 # In that case the unmodified client AND original Go Start must still prove
 # fee_model_acknowledged=true. Never bypass that positive acceptance below.
}
function WaitPaper([string]$mode,[int]$seconds=12){
 $until=(Get-Date).AddSeconds($seconds)
 do{
  try{$st=Invoke-RestMethod -Uri ($script:base+'/api/paper/session') -TimeoutSec 3
   if($st.schema -ceq 'ktrade.paper.isolated-session.v1' -and $st.mode -ceq $mode -and
    $st.live_armed -eq $false){return $st}}catch{}
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $until)
 # This is an original, disposable W13 fixture only. Preserve a bounded
 # UIA refusal description without disclosing paths, source, payloads,
 # balances or unrelated user state. Do not retry or bypass PAPER Start.
 $notes=[Collections.Generic.List[string]]::new()
 try{
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($script:parent.MainWindowHandle)
  $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach($el in $nodes){
   $name=''
   try{$name=[string]$el.Current.Name}catch{}
   if($name.Length -lt 4 -or $name.Length -gt 240){continue}
   if($name -notmatch '(PAPER|paper|fee|Fee|Save a user|strategy|USDC|Coinbase|unverified|refus|Source|script|acknowledge|ack|funded|STOPPED)'){continue}
   if($notes.Count -ge 32){break}
   $label=$name -replace '[^\x20-\x7E]',' '
   $notes.Add($label.Substring(0,[Math]::Min(180,$label.Length)))
  }
 }catch{}
 $statusValue=''
 try{$statusValue=(Invoke-RestMethod -Uri ($script:base+'/api/paper/session') -TimeoutSec 4).mode}catch{}
 Write-Host ('W39_TEST_ONLY_UI_REFUSAL mode='+$statusValue+' names='+($notes -join ' | '))
 throw ('W39_PAPER_UI_TRANSITION_NOT_OBSERVED_'+$mode)
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
 # Windows GUI subsystem may compute a different default temp root than
 # a regular console helper. Pin the child OS temp variables to the
 # independently probed, original source-required stage location.
 $runtimeTemp=[IO.Path]::GetDirectoryName($stageRoot)
 Require ([string]::Equals($runtimeTemp,$goTemp,[StringComparison]::OrdinalIgnoreCase)) 'W38_STAGE_TEMP_PARENT_DRIFT'
 $psi.Environment['TEMP']=$runtimeTemp
 $psi.Environment['TMP']=$runtimeTemp
 $psi.Environment['TMPDIR']=$runtimeTemp
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

 # Source-controlled Go library preparation only. All PAPER Start/Evaluate/Stop
 # operations below MUST originate from real WebView2 UIAutomation clicks.
 $pine='//@version=5'+[Environment]::NewLine+
  'strategy("W39 native operator UI")'+[Environment]::NewLine+
  'if bar_index == 5'+[Environment]::NewLine+
  '    strategy.entry("L", strategy.long, qty=1)'
 $created=JSONPost $script:base '/api/pine-library' @{
  display_name='W39 native UI synthetic strategy';kind='strategy';source=$pine
 }
 Require ($created.metadata.id -cmatch '^[a-f0-9]{32}$' -and $created.metadata.ownership -ceq 'user' -and
  $created.source -ceq $pine) 'W39_SOURCE_ONLY_PROVISION_FAILED'
 $scriptID=$created.metadata.id
 Require ((HTTPCode $script:base '/api/orders/place' @{product_id='BTC-USDC';side='BUY'}) -eq 423) 'W39_LEGACY_ORDER_NOT_LOCKED'
 $initial=WaitPaper 'PAPER_NOT_FUNDED'
 Require ($initial.paper_orders_enabled -eq $false) 'W39_START_BEFORE_UI_INTERACTION'
 ClickUI $script:parent 'Pine Editor'
 ClickUI $script:parent 'Open saved Pine library'
 ClickUI $script:parent 'W39 native UI synthetic strategy'
 $null=FindUI $script:parent 'Opened stored Pine script' $false 15
 Write-Host '::notice::W39_NATIVE_PINE_EDITOR_SELECTED_CANONICAL_SAVED_STRATEGY=PASS'
 ClickAnyUI $script:parent 'BTCUSD'
 # The source-owned market list now exposes exact, focusable ARIA identity,
 # and its click/Enter/Space handler remains the original changeSym.
 ClickUI $script:parent 'Select BTC-USDC'
 # The original market list uses UIA group/text semantics that need not
 # expose the header's abbreviated label. Source/product admission is
 # instead proven by the original Go PAPER Start with BTC-USDC only.
 Write-Host '::notice::W39_NATIVE_CHART_OPERATOR_REQUESTED_SPOT_USDC=PASS'
 # Must try the real Start button with no acknowledgment first: no funding.
 ClickUI $script:parent 'Start isolated paper'
 Start-Sleep -Milliseconds 1000
 $beforeAck=WaitPaper 'PAPER_NOT_FUNDED'
 Require ($beforeAck.paper_orders_enabled -eq $false) 'W39_UNACKNOWLEDGED_UI_START_FUNDED'
 Write-Host '::notice::W39_UI_FEE_ACK_REQUIRED_AND_UNFUNDED=PASS'
 ToggleAck $script:parent
 ClickUI $script:parent 'Start isolated paper'
 $running=WaitPaper 'PAPER_ISOLATED_RUNNING' 20
 Require ($running.paper_orders_enabled -eq $true -and $running.live_armed -eq $false) 'W39_UI_START_DID_NOT_FUND_NATIVE_OWNER'
 $runningCap=Cap
 Require ($runningCap.mode -ceq 'PAPER_ISOLATED_RUNNING' -and $runningCap.paper_orders_enabled -eq $true -and
  $runningCap.live_orders_enabled -eq $false -and $runningCap.strategy_execution_enabled -eq $true -and
  $runningCap.paper_accounting_enabled -eq $true) 'W39_RUNNING_CAPABILITY_DRIFT'
 Write-Host '::notice::W39_NATIVE_UI_EXPLICIT_PAPER_START_AND_FEE_CONSENT=PASS'
 ClickUI $script:parent 'Evaluate final bar'
 $deadline=(Get-Date).AddSeconds(16)
 do{
  $state=Invoke-RestMethod -Uri ($script:base+'/api/paper/session') -TimeoutSec 4
  if($state.fill_count -eq 1){break}
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $deadline)
 Require ($state.fill_count -eq 1 -and $state.live_armed -eq $false) 'W39_UI_FINAL_CANDLE_DID_NOT_FILL'
 $archive=Invoke-RestMethod -Uri ($script:base+'/api/paper/session/archive') -TimeoutSec 12
 $archiveText=$archive|ConvertTo-Json -Compress -Depth 18
 Require ($archiveText.Contains('"fill_count":1') -and
  $archiveText.Contains('"original_risk_proof_verified":true')) 'W39_UI_RISK_AND_LEDGER_CUSTODY'
 Write-Host '::notice::W39_NATIVE_UI_EVALUATE_VERIFIED_ORIGINAL_RISK_AND_LEDGER_FILL=PASS'
 ClickUI $script:parent 'Stop paper'
 $stopped=WaitPaper 'PAPER_STOPPED' 20
 Require ($stopped.stopped -eq $true -and $stopped.paper_orders_enabled -eq $false) 'W39_UI_STOP_CUSTODY_UNVERIFIED'
 Stopped (Cap)
 Require ((HTTPCode $script:base '/api/paper/session/evaluate' @{
  script_id=$scriptID;product_id='BTC-USDC';timeframe='1m'
 }) -ne 200) 'W39_STOPPED_SESSION_STILL_EVALUABLE'
 Write-Host '::notice::W39_NATIVE_UI_PAPER_STOP_AND_EVALUATE_LOCKOUT=PASS'
 StopOriginal
 StartOriginal
 Stopped (Cap)
 $cold=Invoke-RestMethod -Uri ($script:base+'/api/paper/session/archive') -TimeoutSec 15
 $coldJSON=$cold|ConvertTo-Json -Depth 20 -Compress
 Require ($coldJSON.Contains('"fill_count":1') -and
  $coldJSON.Contains('"original_risk_proof_verified":true') -and
  $coldJSON.Contains('"execution_restore_eligible":false')) 'W38_COLD_ARCHIVE_OR_NO_REARM_INCOMPLETE'
 Write-Host '::notice::W39_REAL_WAILS_RESTART_COLD_ARCHIVE_NO_AUTO_REARM=PASS'
 StopOriginal
 Write-Host '::notice::W39_NO_REAL_BROKER_NO_OWNER_DATA_NO_RELEASE_NO_LIVE=PASS'
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
