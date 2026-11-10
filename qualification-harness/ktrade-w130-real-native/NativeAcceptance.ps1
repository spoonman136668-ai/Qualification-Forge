# W130: true native Win32 wheel and drag interactions on exact W129 KTRADE.
# Observer reads frozen chart viewport API and real Coinbase public 100T
# completed candles; never synthesizes input, trades, bars or historical data.
# Native wheel zoom and drag older/latest must change actual viewport state.
# One bounded disposable WebView2 process, no product or owner installation.
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
 $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108') 'W130_WRONG_RUNNER_OR_AUTHORITY'
Require ($ExpectedSourceSha -ceq 'b1b25156d34952c0126255e7fdb69787522ee980' -and
 $ExpectedTreeSha -ceq '442978530af4bf8bcd0bf1576869fe552f4c7e22') 'W130_EXACT_SOURCE_REQUIRED'
Require ($env:KTRADE_LIVE_TRADING -ceq 'false' -and
 $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
 $env:KTRADE_CI_COINBASE_ALLOWED -ceq '0' -and
 $env:KTRADE_PAPER_SESSION_ROOT -ceq '' -and
 $env:KTRADE_PAPER_CUSTODY_REVIEW_ROOT -ceq '' -and
 $env:KTRADE_USE_LEGACY_CDP_CONFIG -ceq '0') 'W130_DISARMED_ENVIRONMENT_REQUIRED'
$repo=Join-Path $env:GITHUB_WORKSPACE 'product'
$qualifier=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$fixture=Join-Path $qualifier 'qualification-harness/ktrade-w130-real-native/observer.js'
Require (Test-Path -LiteralPath $fixture -PathType Leaf) 'W130_EXACT_FIXTURE_SOURCE_MISSING'
$fixtureHash=(& git -C $qualifier hash-object -- $fixture).Trim()
Require ($LASTEXITCODE -eq 0 -and
 $fixtureHash -ceq '3e156f0d5e5f2056421b879d8289ce1ce676a9c8') 'W130_FIXTURE_HASH_DRIFT'
$head=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Require ($LASTEXITCODE -eq 0 -and $head -ceq $ExpectedSourceSha -and
 $tree -ceq $ExpectedTreeSha -and
 @(& git -C $repo status --porcelain).Count -eq 0 -and
 !(Test-Path -LiteralPath (Join-Path $repo '.env'))) 'W130_PRIVATE_SOURCE_CUSTODY_FAILED'
$env:TEMP=$env:RUNNER_TEMP
$env:TMP=$env:RUNNER_TEMP
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$root=Join-Path $temp ('ktrade-w03-package-'+[guid]::NewGuid().ToString('N'))
Require (!(Test-Path -LiteralPath $root)) 'W130_DISPOSABLE_ROOT_EXISTS'
$stage=Join-Path $root 'KTRADE-WailsPortable'
$exe=Join-Path $stage 'ktrade.exe'
$engine=Join-Path $stage 'ktrade-engine.exe'
$log=Join-Path $temp ('w130-private-'+[guid]::NewGuid().ToString('N')+'.log')
$proc=$null;$childPID=$null
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
public static class KTRADEW130Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
  public static void Click(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W130_CURSOR_MOVE_REFUSED");
    Thread.Sleep(110);
    mouse_event(0x0002,0,0,0,UIntPtr.Zero);
    Thread.Sleep(100);
    mouse_event(0x0004,0,0,0,UIntPtr.Zero);
  }
  public static void Hover(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W130_HOVER_MOVE_REFUSED");
  }
  public static void Wheel(int x,int y,int delta){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W130_WHEEL_MOVE_REFUSED");
    Thread.Sleep(150);
    mouse_event(0x0800,0,0,unchecked((uint)delta),UIntPtr.Zero);
  }
  public static void Drag(int sx,int sy,int ex,int ey){
    if(!SetCursorPos(sx,sy))throw new InvalidOperationException("W130_DRAG_START_REFUSED");
    Thread.Sleep(130);
    mouse_event(0x0002,0,0,0,UIntPtr.Zero);
    Thread.Sleep(140);
    for(int i=1;i<=12;i++){
      int xx=sx+(ex-sx)*i/12,yy=sy+(ey-sy)*i/12;
      if(!SetCursorPos(xx,yy))throw new InvalidOperationException("W130_DRAG_MOVE_REFUSED");
      Thread.Sleep(32);
    }
    Thread.Sleep(120);
    mouse_event(0x0004,0,0,0,UIntPtr.Zero);
  }
}
'@
function Refresh-Window {
  if(!$proc){throw 'W130_WAILS_PROCESS_MISSING'}
  $proc.Refresh()
  if($proc.HasExited){throw 'W130_WAILS_PROCESS_EXITED'}
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
  throw 'W130_NATIVE_ACCESSIBILITY_CONTROL_UNAVAILABLE'
}
function Native-Click([string]$label) {
  $control=Wait-Control $label $true 30
  $rect=$control.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 11 -and $rect.Height -ge 11 -and
    $rect.Width -le 1500 -and $rect.Height -le 500) 'W130_UNSAFE_CLICK_GEOMETRY'
  $x=[int][Math]::Round($rect.X+$rect.Width/2)
  $y=[int][Math]::Round($rect.Y+$rect.Height/2)
  $windowRect=(Refresh-Window).Current.BoundingRectangle
  Require (!$windowRect.IsEmpty -and
    $x -gt $windowRect.Left+8 -and $x -lt $windowRect.Right-8 -and
    $y -gt $windowRect.Top+8 -and $y -lt $windowRect.Bottom-8) 'W130_CLICK_OUTSIDE_OWN_WINDOW'
  $foreground=[KTRADEW130Native]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 220
  Require ($foreground -and
    [KTRADEW130Native]::GetForegroundWindow() -eq $proc.MainWindowHandle) 'W130_WINDOW_NOT_FOREGROUND'
  [KTRADEW130Native]::Click($x,$y)
}
function Real-CanvasRect {
  $control=Wait-Control 'Execution-count OHLCV by session bar number, not by clock time' $false 20
  $rect=$control.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 280 -and $rect.Height -ge 140) 'W130_NATIVE_CANVAS_GEOMETRY_INVALID'
  $bounds=(Refresh-Window).Current.BoundingRectangle
  Require ($rect.X -ge $bounds.X -and $rect.Y -ge $bounds.Y -and
    $rect.Right -le $bounds.Right+1 -and $rect.Bottom -le $bounds.Bottom+1) 'W130_CANVAS_OUT_OF_WINDOW'
  return $rect
}
function Real-CanvasFocus {
  $foreground=[KTRADEW130Native]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 190
  Require ($foreground -and [KTRADEW130Native]::GetForegroundWindow() -eq $proc.MainWindowHandle) 'W130_WINDOW_NOT_FOREGROUND'
}
function Native-Wheel([int]$delta) {
  $rect=Real-CanvasRect
  Real-CanvasFocus
  $x=[int][Math]::Round($rect.X+$rect.Width*.5)
  $y=[int][Math]::Round($rect.Y+$rect.Height*.50)
  [KTRADEW130Native]::Wheel($x,$y,$delta)
}
function Native-Drag([bool]$older) {
  $rect=Real-CanvasRect
  Real-CanvasFocus
  $left=[int][Math]::Round($rect.X+$rect.Width*.36)
  $right=[int][Math]::Round($rect.X+$rect.Width*.72)
  $y=[int][Math]::Round($rect.Y+$rect.Height*.51)
  if($older){[KTRADEW130Native]::Drag($left,$y,$right,$y)}
  else{[KTRADEW130Native]::Drag($right,$y,$left,$y)}
}
function Wait-Witness([string]$stage,[int]$seconds) {
  $name='W130_REAL_'+$stage+'=PASS'
  [void](Wait-Control $name $false $seconds)
  Write-Host ('QFORGE_W130_REAL_NATIVE_'+$stage+'=PASS')
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
    Require ($LASTEXITCODE -eq 0) 'W130_VENDOR_INSTALL_FAILED'
    & node scripts/stage_offline_vendor.cjs *> $log
    Require ($LASTEXITCODE -eq 0) 'W130_OFFLINE_VENDOR_FAILED'
    $builder=Join-Path $repo 'windows/Build-KTRADE-WailsPortable.ps1'
    & $builder -OutputRoot $root -ExpectedSourceSha $ExpectedSourceSha -W13QualificationFixture -W41ColdFixture *> $log
    Require ($LASTEXITCODE -eq 0 -and
      (Test-Path -LiteralPath $exe -PathType Leaf) -and
      (Test-Path -LiteralPath $engine -PathType Leaf)) 'W130_DISPOSABLE_NATIVE_BUILD_FAILED'
  }finally{Pop-Location}
  $manifest=Get-Content -LiteralPath (Join-Path $root 'source-manifest.json') -Raw|ConvertFrom-Json
  Require ($manifest.source_sha -ceq $ExpectedSourceSha -and
   $manifest.fixture_mode -ceq 'w41-frozen-disposable-restart' -and
   $manifest.live_armed -eq $false -and
   $manifest.paper_started -eq $false -and
   $manifest.release_candidate -eq $false) 'W130_DISPOSABLE_PROOF_DRIFT'
  $dest=Join-Path $stage 'static/w130_real_native_observer.js'
  Require (!(Test-Path -LiteralPath $dest)) 'W130_FIXTURE_COLLISION'
  Copy-Item -LiteralPath $fixture -Destination $dest -ErrorAction Stop
  $chartPath=Join-Path $stage 'templates/chart.tmpl'
  $original=(& git -C $repo rev-parse 'HEAD:templates/chart.tmpl').Trim()
  Require ($original -ceq '31a4a99922705ab63ab98cd66420b57020dfcb28' -and
    (& git -C $repo rev-parse 'HEAD:cmd/ktrade/w114_tickchart_full.go').Trim() -ceq
      '944d36385739e96cd2f995fcbe7ae9727f2de486' -and
    (& git -C $repo rev-parse 'HEAD:internal/tickchart/exchange_matches_heartbeat.go').Trim() -ceq
      '89654865bcede98793921f873beaf6f8c39f2b34' -and
    (& git -C $repo rev-parse 'HEAD:static/w114_tick_chart.js').Trim() -ceq
      'c94193f71ae563d58cd2d954d785c84f2e97c287' -and
    (& git -C $repo rev-parse 'HEAD:tests/w126_stale_tick_chart.test.cjs').Trim() -ceq
      '4ba8676fd16458ce11db9021c31af7b6fa7e84bf' -and
    (& git -C $repo rev-parse 'HEAD:tests/w129_tick_interaction.test.cjs').Trim() -ceq
      '900a8c36a41c53083a04af0ba6af5e6e6cc8c64e') 'W130_PRODUCT_CHART_SOURCE_DRIFT'
  $html=[IO.File]::ReadAllText($chartPath)
  $anchor='<script src="/static/w41_wails_cold_bridge.js"></script>'
  Require ($html.Split([string[]]@($anchor),[StringSplitOptions]::None).Count -eq 2 -and
    !$html.Contains('w130_real_native_observer')) 'W130_FIXTURE_ASSET_BOUNDARY'
  $html=$html.Replace($anchor,$anchor+[Environment]::NewLine+
    '<script src="/static/w130_real_native_observer.js"></script>')
  [IO.File]::WriteAllText($chartPath,$html,[Text.UTF8Encoding]::new($false))
  Require ((& git -C $repo rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
    @(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0) 'W130_PRODUCT_WORKTREE_CHANGED'
  $proc=Start-Process -FilePath $exe -WorkingDirectory $stage -PassThru
  $until=(Get-Date).AddSeconds(45)
  $ready=$false
  while((Get-Date) -lt $until){
    $proc.Refresh()
    if($proc.HasExited){throw 'W130_NATIVE_WAILS_EARLY_EXIT'}
    if($proc.MainWindowHandle -ne [IntPtr]::Zero){$ready=$true;break}
    Start-Sleep -Milliseconds 350
  }
  Require $ready 'W130_REAL_WAILS_WINDOW_MISSING'
  $until=(Get-Date).AddSeconds(15)
  $children=@()
  while((Get-Date) -lt $until){
    $children=@(Get-CimInstance Win32_Process -Filter "name='ktrade-engine.exe'" |
      Where-Object {$_.ExecutablePath -ieq $engine -and $_.ParentProcessId -eq $proc.Id})
    if($children.Count -eq 1){break}
    Start-Sleep -Milliseconds 300
  }
  Require ($children.Count -eq 1) 'W130_EXACT_ENGINE_CHILD_MISSING'
  $childPID=[int]$children[0].ProcessId
  # Verify read-only paper and LIVE mode without accessing any account.
  $until=(Get-Date).AddSeconds(12);$ports=@()
  while((Get-Date) -lt $until){
    $ports=@(Get-NetTCPConnection -State Listen -OwningProcess $childPID -ErrorAction SilentlyContinue|
      Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
    if($ports.Count -eq 1){break}
    Start-Sleep -Milliseconds 250
  }
  Require ($ports.Count -eq 1) 'W130_NOT_EXCLUSIVE_LOOPBACK'
  $url='http://127.0.0.1:'+[int]$ports[0].LocalPort
  $cap=Invoke-RestMethod -Uri ($url+'/api/operator/capabilities') -TimeoutSec 10
  Require ($cap.mode -ceq 'PAPER_STOPPED' -and
    $cap.paper_orders_enabled -eq $false -and
    $cap.live_orders_enabled -eq $false -and
    $cap.strategy_execution_enabled -eq $false) 'W130_FINANCIAL_MODE_NOT_DISARMED'
  [void](Wait-Control 'W130_REAL_READY' $false 60)
  Write-Host 'QFORGE_W130_REAL_PUBLIC_PASSIVE_WITNESS_VISIBLE=PASS'
  Native-Click '100T'
  try{
    Wait-Witness 'FIRST_100T_PUBLIC_CANVAS' 125
  }catch{
    $signals=@(
      'SOURCE_SET','VIEW_INSTALLED','NATIVE_SELECTION',
      'TICK_SOCKET_CREATED','TICK_SOCKET_OPEN','TICK_OVERLAY_ACTIVE',
      'BLANK_PIXELS_CAPTURED','PUBLIC_CANDLE_STATUS',
      'VIEW_COMPLETED_BARS','NEW_CANVAS_PIXELS'
    )
    $passed=@()
    foreach($label in $signals){
      if(Find-Control ('W130_DIAG_'+$label+'=PASS') $false){$passed+=,$label}
    }
    $classification=if($passed -cnotcontains 'VIEW_INSTALLED'){'CHART_INSTALL_VIEW_NOT_CAPTURED'}
      elseif($passed -cnotcontains 'TICK_SOCKET_CREATED'){'TICK_SUBSCRIPTION_NOT_CREATED'}
      elseif($passed -cnotcontains 'TICK_SOCKET_OPEN'){'TICK_SOCKET_NOT_OPEN'}
      elseif($passed -cnotcontains 'PUBLIC_CANDLE_STATUS'){'NO_VERIFIED_PUBLIC_100T_IN_BUDGET'}
      elseif($passed -cnotcontains 'BLANK_PIXELS_CAPTURED'){'EMPTY_FRAME_WITNESS_MISSED'}
      elseif($passed -cnotcontains 'NEW_CANVAS_PIXELS'){'CANVAS_DID_NOT_REPAINT'}
      else{'FIRST_BAR_WITNESS_MISMATCH'}
    Write-Host ('QFORGE_W130B_DIAGNOSTIC='+
      $classification+';observed='+($passed -join ',')+
      ';source='+$ExpectedSourceSha+';orders=zero;synthetic=zero')
    throw 'W130B_NATIVE_REAL_FIRST_BAR_UNVERIFIED'
  }
  $rect=Real-CanvasRect
  Real-CanvasFocus
  [KTRADEW130Native]::Hover([int]($rect.X+$rect.Width*.5),[int]($rect.Y+$rect.Height*.5))
  Wait-Witness 'NATIVE_CROSSHAIR' 25
  Native-Wheel 120; Wait-Witness 'NATIVE_WHEEL_ZOOM_IN' 25
  Native-Wheel -120; Wait-Witness 'NATIVE_WHEEL_ZOOM_OUT' 25
  # 14 complete 100T bars require 1400 genuine public executions.
  # At low trade rates, fail closed as an insufficient-coverage budget
  # instead of fabricating candles or replaying source history.
  Wait-Witness 'REAL_14_BARS' 700
  Native-Drag $true; Wait-Witness 'NATIVE_DRAG_OLDER' 30
  Native-Drag $false; Wait-Witness 'NATIVE_DRAG_LATEST' 30
  Native-Click '1m'; Wait-Witness 'TIME_RETURN' 25
  Write-Host ('QFORGE_W130_NATIVE_PUBLIC_WHEEL_DRAG_CROSSHAIR=PASS;sha='+$ExpectedSourceSha+
    ';bars=real_public_matches_heartbeat;minimum_real_trades=1400;wheel=native;drag=native;crosshair=native;synthetic_tick_bars=zero;orders=zero;trading=disarmed')
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
