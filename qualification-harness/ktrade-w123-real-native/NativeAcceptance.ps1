# W123: real Windows mouse input against the exact W115 KTRADE source in a
# disposable Wails WebView2 process. Passive observer, real public matches.
# No UI event synthesis, owner files, account API, orders, installation,
# account credentials, schedule or release. The product checkout stays clean.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ExpectedSourceSha,
  [Parameter(Mandatory=$true)][string]$ExpectedTreeSha
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$v,[string]$m){if(-not $v){throw $m}}
Require ($env:RUNNER_OS -ceq 'Windows' -and
 $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
 $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
 $env:GITHUB_EVENT_NAME -ceq 'push' -and
 $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108') 'W123_WRONG_RUNNER_OR_AUTHORITY'
Require ($ExpectedSourceSha -ceq 'c44bb75345b48385f784b9500f49ffb127c4411c' -and
 $ExpectedTreeSha -ceq 'c04d67b9e3b1c1a9472e0fcbb8215330f89b25cb') 'W123_EXACT_SOURCE_REQUIRED'
Require ($env:KTRADE_LIVE_TRADING -ceq 'false' -and
 $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
 $env:KTRADE_CI_COINBASE_ALLOWED -ceq '0' -and
 $env:KTRADE_PAPER_SESSION_ROOT -ceq '' -and
 $env:KTRADE_PAPER_CUSTODY_REVIEW_ROOT -ceq '' -and
 $env:KTRADE_USE_LEGACY_CDP_CONFIG -ceq '0') 'W123_DISARMED_ENVIRONMENT_REQUIRED'
$repo=Join-Path $env:GITHUB_WORKSPACE 'product'
$qualifier=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$fixture=Join-Path $qualifier 'qualification-harness/ktrade-w123-real-native/observer.js'
Require (Test-Path -LiteralPath $fixture -PathType Leaf) 'W123_EXACT_FIXTURE_SOURCE_MISSING'
$fixtureHash=(& git -C $qualifier hash-object -- $fixture).Trim()
Require ($LASTEXITCODE -eq 0 -and
 $fixtureHash -ceq '9f71b12a6d7053907159bfd7118cbef5b1aeab92') 'W123_FIXTURE_HASH_DRIFT'
$head=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Require ($LASTEXITCODE -eq 0 -and $head -ceq $ExpectedSourceSha -and
 $tree -ceq $ExpectedTreeSha -and
 @(& git -C $repo status --porcelain).Count -eq 0 -and
 !(Test-Path -LiteralPath (Join-Path $repo '.env'))) 'W123_PRIVATE_SOURCE_CUSTODY_FAILED'
$env:TEMP=$env:RUNNER_TEMP
$env:TMP=$env:RUNNER_TEMP
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$root=Join-Path $temp ('ktrade-w03-package-'+[guid]::NewGuid().ToString('N'))
Require (!(Test-Path -LiteralPath $root)) 'W123_DISPOSABLE_ROOT_EXISTS'
$stage=Join-Path $root 'KTRADE-WailsPortable'
$exe=Join-Path $stage 'ktrade.exe'
$engine=Join-Path $stage 'ktrade-engine.exe'
$log=Join-Path $temp ('w123-private-'+[guid]::NewGuid().ToString('N')+'.log')
$proc=$null;$childPID=$null
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
public static class KTRADEW123Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
  public static void Click(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W123_CURSOR_MOVE_REFUSED");
    Thread.Sleep(110);
    mouse_event(0x0002,0,0,0,UIntPtr.Zero);
    Thread.Sleep(100);
    mouse_event(0x0004,0,0,0,UIntPtr.Zero);
  }
  public static void Hover(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W123_HOVER_MOVE_REFUSED");
  }
}
'@
function Refresh-Window {
  if(!$proc){throw 'W123_WAILS_PROCESS_MISSING'}
  $proc.Refresh()
  if($proc.HasExited){throw 'W123_WAILS_PROCESS_EXITED'}
  return [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
}
function Find-Control([string]$label,[bool]$buttonOnly) {
  $win=Refresh-Window
  $scope=[System.Windows.Automation.TreeScope]::Descendants
  $condition=if($buttonOnly){
    [System.Windows.Automation.PropertyCondition]::new(
      [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Button)
  }else{[System.Windows.Automation.Condition]::TrueCondition}
  $nodes=$win.FindAll($scope,$condition)
  $match=@()
  foreach($node in $nodes){
    try{
      if($node.Current.Name -ceq $label){$match+=,$node}
    }catch{}
  }
  if($match.Count -eq 1){return $match[0]}
  return $null
}
function Wait-Control([string]$label,[bool]$buttonOnly,[int]$seconds) {
  $until=(Get-Date).AddSeconds($seconds)
  while((Get-Date) -lt $until){
    $control=Find-Control $label $buttonOnly
    if($control){
      if($control.Current.IsOffscreen -and $buttonOnly){
        # Existing horizontal toolbar scrolls; focus/ScrollItem only exposes
        # the control. Every acceptance CLICK is still native Windows input.
        try{[void]$control.SetFocus()}catch{}
        try{
          $pattern=$control.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
          $pattern.ScrollIntoView()
        }catch{}
      }
      Start-Sleep -Milliseconds 250
      try{if(!$control.Current.IsOffscreen){return $control}}catch{}
    }
    Start-Sleep -Milliseconds 330
  }
  throw 'W123_NATIVE_ACCESSIBILITY_CONTROL_UNAVAILABLE'
}
function Native-Click([string]$label) {
  $control=Wait-Control $label $true 30
  $rect=$control.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 11 -and $rect.Height -ge 11 -and
    $rect.Width -le 1500 -and $rect.Height -le 500) 'W123_UNSAFE_CLICK_GEOMETRY'
  $x=[int][Math]::Round($rect.X+$rect.Width/2)
  $y=[int][Math]::Round($rect.Y+$rect.Height/2)
  $windowRect=(Refresh-Window).Current.BoundingRectangle
  Require (!$windowRect.IsEmpty -and
    $x -gt $windowRect.Left+8 -and $x -lt $windowRect.Right-8 -and
    $y -gt $windowRect.Top+8 -and $y -lt $windowRect.Bottom-8) 'W123_CLICK_OUTSIDE_OWN_WINDOW'
  $foreground=[KTRADEW123Native]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 220
  Require ($foreground -and
    [KTRADEW123Native]::GetForegroundWindow() -eq $proc.MainWindowHandle) 'W123_WINDOW_NOT_FOREGROUND'
  [KTRADEW123Native]::Click($x,$y)
}
function Wait-Witness([string]$stage,[int]$seconds) {
  $name='W123_REAL_'+$stage+'=PASS'
  [void](Wait-Control $name $false $seconds)
  Write-Host ('QFORGE_W123_REAL_NATIVE_'+$stage+'=PASS')
}
try {
  $env:KTRADE_W13_QUALIFICATION_ONLY='1'
  $env:KTRADE_W41_QUALIFICATION_ONLY='1'
  $env:KTRADE_RECOVERY_ISOLATED='0'
  $env:KTRADE_PORTABLE_DISARMED='1'
  $env:KTRADE_USE_LEGACY_CDP_CONFIG='0'
  $env:KTRADE_LIVE_TRADING='false'
  Push-Location -LiteralPath $repo
  try{
    & npm.cmd ci --ignore-scripts --no-audit --no-fund --silent *> $log
    Require ($LASTEXITCODE -eq 0) 'W123_VENDOR_INSTALL_FAILED'
    & node scripts/stage_offline_vendor.cjs *> $log
    Require ($LASTEXITCODE -eq 0) 'W123_OFFLINE_VENDOR_FAILED'
    $builder=Join-Path $repo 'windows/Build-KTRADE-WailsPortable.ps1'
    & $builder -OutputRoot $root -ExpectedSourceSha $ExpectedSourceSha -W13QualificationFixture -W41ColdFixture *> $log
    Require ($LASTEXITCODE -eq 0 -and
      (Test-Path -LiteralPath $exe -PathType Leaf) -and
      (Test-Path -LiteralPath $engine -PathType Leaf)) 'W123_DISPOSABLE_NATIVE_BUILD_FAILED'
  }finally{Pop-Location}
  $manifest=Get-Content -LiteralPath (Join-Path $root 'source-manifest.json') -Raw|ConvertFrom-Json
  Require ($manifest.source_sha -ceq $ExpectedSourceSha -and
   $manifest.fixture_mode -ceq 'w41-frozen-disposable-restart' -and
   $manifest.live_armed -eq $false -and
   $manifest.paper_started -eq $false -and
   $manifest.release_candidate -eq $false) 'W123_DISPOSABLE_PROOF_DRIFT'
  $dest=Join-Path $stage 'static/w123_real_native_observer.js'
  Require (!(Test-Path -LiteralPath $dest)) 'W123_FIXTURE_COLLISION'
  Copy-Item -LiteralPath $fixture -Destination $dest -ErrorAction Stop
  $chartPath=Join-Path $stage 'templates/chart.tmpl'
  $original=(& git -C $repo rev-parse 'HEAD:templates/chart.tmpl').Trim()
  Require ($original -ceq '31a4a99922705ab63ab98cd66420b57020dfcb28' -and
    (& git -C $repo rev-parse 'HEAD:static/w114_tick_chart.js').Trim() -ceq
      '19965d556deabbcdda23e178b975d04ee4c7f939' -and
    (& git -C $repo rev-parse 'HEAD:cmd/ktrade/w114_tickchart_full.go').Trim() -ceq
      '944d36385739e96cd2f995fcbe7ae9727f2de486' -and
    (& git -C $repo rev-parse 'HEAD:internal/tickchart/exchange_matches_heartbeat.go').Trim() -ceq
      '861d2258ed457f12f00d724cb047cc63c13c1e8a') 'W123_PRODUCT_CHART_SOURCE_DRIFT'
  $html=[IO.File]::ReadAllText($chartPath)
  $anchor='<script src="/static/w41_wails_cold_bridge.js"></script>'
  Require ($html.Split([string[]]@($anchor),[StringSplitOptions]::None).Count -eq 2 -and
    !$html.Contains('w123_real_native_observer')) 'W123_FIXTURE_ASSET_BOUNDARY'
  $html=$html.Replace($anchor,$anchor+[Environment]::NewLine+
    '<script src="/static/w123_real_native_observer.js"></script>')
  [IO.File]::WriteAllText($chartPath,$html,[Text.UTF8Encoding]::new($false))
  Require ((& git -C $repo rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
    @(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0) 'W123_PRODUCT_WORKTREE_CHANGED'
  $proc=Start-Process -FilePath $exe -WorkingDirectory $stage -PassThru
  $until=(Get-Date).AddSeconds(45)
  $ready=$false
  while((Get-Date) -lt $until){
    $proc.Refresh()
    if($proc.HasExited){throw 'W123_NATIVE_WAILS_EARLY_EXIT'}
    if($proc.MainWindowHandle -ne [IntPtr]::Zero){$ready=$true;break}
    Start-Sleep -Milliseconds 350
  }
  Require $ready 'W123_REAL_WAILS_WINDOW_MISSING'
  $until=(Get-Date).AddSeconds(15)
  $children=@()
  while((Get-Date) -lt $until){
    $children=@(Get-CimInstance Win32_Process -Filter "name='ktrade-engine.exe'" |
      Where-Object {$_.ExecutablePath -ieq $engine -and $_.ParentProcessId -eq $proc.Id})
    if($children.Count -eq 1){break}
    Start-Sleep -Milliseconds 300
  }
  Require ($children.Count -eq 1) 'W123_EXACT_ENGINE_CHILD_MISSING'
  $childPID=[int]$children[0].ProcessId
  # Verify read-only paper and LIVE mode without accessing any account.
  $until=(Get-Date).AddSeconds(12);$ports=@()
  while((Get-Date) -lt $until){
    $ports=@(Get-NetTCPConnection -State Listen -OwningProcess $childPID -ErrorAction SilentlyContinue|
      Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
    if($ports.Count -eq 1){break}
    Start-Sleep -Milliseconds 250
  }
  Require ($ports.Count -eq 1) 'W123_NOT_EXCLUSIVE_LOOPBACK'
  $url='http://127.0.0.1:'+[int]$ports[0].LocalPort
  $cap=Invoke-RestMethod -Uri ($url+'/api/operator/capabilities') -TimeoutSec 10
  Require ($cap.mode -ceq 'PAPER_STOPPED' -and
    $cap.paper_orders_enabled -eq $false -and
    $cap.live_orders_enabled -eq $false -and
    $cap.strategy_execution_enabled -eq $false) 'W123_FINANCIAL_MODE_NOT_DISARMED'
  [void](Wait-Control 'W123_REAL_READY' $false 60)
  Write-Host 'QFORGE_W123_REAL_PUBLIC_PASSIVE_WITNESS_VISIBLE=PASS'
  Native-Click '100T'; Wait-Witness '100T_CANVAS' 115
  $canvas=Wait-Control 'Execution-count OHLCV by session bar number, not by clock time' $false 20
  $rect=$canvas.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 200 -and $rect.Height -ge 100) 'W123_NATIVE_CANVAS_GEOMETRY_INVALID'
  [KTRADEW123Native]::Hover([int]($rect.X+$rect.Width*.5),[int]($rect.Y+$rect.Height*.5))
  Wait-Witness 'HOVER' 25
  Native-Click '1m'; Wait-Witness 'TIME_RETURN' 25
  Write-Host ('QFORGE_W123_NATIVE_GENUINE_PUBLIC_100T_CHART=PASS;sha='+$ExpectedSourceSha+
    ';bars=public_matches_heartbeat;synthetic_tick_bars=zero;orders=zero;trading=disarmed')
}finally {
  if($proc){try{if(-not $proc.HasExited){$proc.CloseMainWindow()|Out-Null
    if(-not $proc.WaitForExit(7000)){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}}}catch{}}
  if($childPID){try{Stop-Process -Id $childPID -Force -ErrorAction SilentlyContinue}catch{}}
  foreach($key in @('KTRADE_W13_QUALIFICATION_ONLY','KTRADE_W41_QUALIFICATION_ONLY',
    'KTRADE_RECOVERY_ISOLATED','KTRADE_PORTABLE_DISARMED','KTRADE_LIVE_TRADING')){
    Remove-Item ('Env:\'+$key) -ErrorAction SilentlyContinue
  }
  if(Test-Path -LiteralPath $log){Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue}
  if((Test-Path -LiteralPath $root) -and
   [string]::Equals([IO.Path]::GetDirectoryName($root),$temp,[StringComparison]::OrdinalIgnoreCase) -and
   [IO.Path]::GetFileName($root) -cmatch '^ktrade-w03-package-[a-f0-9]{32}$'){
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
  }
}
