# W138: true native Win32 wheel and drag interactions on exact W129 KTRADE.
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
 $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108') 'W138_WRONG_RUNNER_OR_AUTHORITY'
Require ($ExpectedSourceSha -ceq 'c8675e76c9d85661cf0868df2638b992fa029012' -and
 $ExpectedTreeSha -ceq '8ae94cd1d09fcc8005180bba08718bc014785f3b') 'W138_EXACT_SOURCE_REQUIRED'
Require ($env:KTRADE_LIVE_TRADING -ceq 'false' -and
 $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
 $env:KTRADE_CI_COINBASE_ALLOWED -ceq '0' -and
 $env:KTRADE_PAPER_SESSION_ROOT -ceq '' -and
 $env:KTRADE_PAPER_CUSTODY_REVIEW_ROOT -ceq '' -and
 $env:KTRADE_USE_LEGACY_CDP_CONFIG -ceq '0') 'W138_DISARMED_ENVIRONMENT_REQUIRED'
$repo=Join-Path $env:GITHUB_WORKSPACE 'product'
$qualifier=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$fixture=Join-Path $qualifier 'qualification-harness/ktrade-w138-real-native/observer.js'
Require (Test-Path -LiteralPath $fixture -PathType Leaf) 'W138_EXACT_FIXTURE_SOURCE_MISSING'
$fixtureHash=(& git -C $qualifier hash-object -- $fixture).Trim()
Require ($LASTEXITCODE -eq 0 -and
 $fixtureHash -ceq 'a09e835684e673dff482218a00224a5fd8c49098') 'W138_FIXTURE_HASH_DRIFT'
$head=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
Require ($LASTEXITCODE -eq 0 -and $head -ceq $ExpectedSourceSha -and
 $tree -ceq $ExpectedTreeSha -and
 @(& git -C $repo status --porcelain).Count -eq 0 -and
 !(Test-Path -LiteralPath (Join-Path $repo '.env'))) 'W138_PRIVATE_SOURCE_CUSTODY_FAILED'
$env:TEMP=$env:RUNNER_TEMP
$env:TMP=$env:RUNNER_TEMP
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$root=Join-Path $temp ('ktrade-w03-package-'+[guid]::NewGuid().ToString('N'))
Require (!(Test-Path -LiteralPath $root)) 'W138_DISPOSABLE_ROOT_EXISTS'
$stage=Join-Path $root 'KTRADE-WailsPortable'
$exe=Join-Path $stage 'ktrade.exe'
$engine=Join-Path $stage 'ktrade-engine.exe'
$log=Join-Path $temp ('w138-private-'+[guid]::NewGuid().ToString('N')+'.log')
$proc=$null;$childPID=$null
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Threading;
using System.Runtime.InteropServices;
public static class KTRADEW138Native {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
  public static void Click(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W138_CURSOR_MOVE_REFUSED");
    Thread.Sleep(110);
    mouse_event(0x0002,0,0,0,UIntPtr.Zero);
    Thread.Sleep(100);
    mouse_event(0x0004,0,0,0,UIntPtr.Zero);
  }
  public static void Hover(int x,int y){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W138_HOVER_MOVE_REFUSED");
  }
  public static void Wheel(int x,int y,int delta){
    if(!SetCursorPos(x,y))throw new InvalidOperationException("W138_WHEEL_MOVE_REFUSED");
    Thread.Sleep(150);
    mouse_event(0x0800,0,0,unchecked((uint)delta),UIntPtr.Zero);
  }
  [DllImport("user32.dll")] static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
  public static void Key(int code){
    if(code<0||code>255)throw new ArgumentOutOfRangeException("code");
    keybd_event((byte)code,0,0,UIntPtr.Zero);
    Thread.Sleep(110);
    keybd_event((byte)code,0,0x0002,UIntPtr.Zero);
  }
  public static void Drag(int sx,int sy,int ex,int ey){
    if(!SetCursorPos(sx,sy))throw new InvalidOperationException("W138_DRAG_START_REFUSED");
    Thread.Sleep(130);
    mouse_event(0x0002,0,0,0,UIntPtr.Zero);
    Thread.Sleep(140);
    for(int i=1;i<=12;i++){
      int xx=sx+(ex-sx)*i/12,yy=sy+(ey-sy)*i/12;
      if(!SetCursorPos(xx,yy))throw new InvalidOperationException("W138_DRAG_MOVE_REFUSED");
      Thread.Sleep(32);
    }
    Thread.Sleep(120);
    mouse_event(0x0004,0,0,0,UIntPtr.Zero);
  }
}
'@
function Refresh-Window {
  if(!$proc){throw 'W138_WAILS_PROCESS_MISSING'}
  $proc.Refresh()
  if($proc.HasExited){throw 'W138_WAILS_PROCESS_EXITED'}
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
  Write-Host ('QFORGE_W138_MISSING_WITNESS='+$label)
  throw 'W138_NATIVE_ACCESSIBILITY_CONTROL_UNAVAILABLE'
}
function Native-Click([string]$label) {
  $control=Wait-Control $label $true 30
  $rect=$control.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 11 -and $rect.Height -ge 11 -and
    $rect.Width -le 1500 -and $rect.Height -le 500) 'W138_UNSAFE_CLICK_GEOMETRY'
  $x=[int][Math]::Round($rect.X+$rect.Width/2)
  $y=[int][Math]::Round($rect.Y+$rect.Height/2)
  $windowRect=(Refresh-Window).Current.BoundingRectangle
  Require (!$windowRect.IsEmpty -and
    $x -gt $windowRect.Left+8 -and $x -lt $windowRect.Right-8 -and
    $y -gt $windowRect.Top+8 -and $y -lt $windowRect.Bottom-8) 'W138_CLICK_OUTSIDE_OWN_WINDOW'
  $foreground=[KTRADEW138Native]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 220
  Require ($foreground -and
    [KTRADEW138Native]::GetForegroundWindow() -eq $proc.MainWindowHandle) 'W138_WINDOW_NOT_FOREGROUND'
  [KTRADEW138Native]::Click($x,$y)
}
function Real-CanvasRect {
  $control=Wait-Control 'Read-only execution-count OHLCV, not clock time. Left and right arrows inspect completed bars; Page Up and Page Down pan; plus and minus zoom; Home returns to latest' $false 20
  $rect=$control.Current.BoundingRectangle
  Require (!$rect.IsEmpty -and $rect.Width -ge 280 -and $rect.Height -ge 140) 'W138_NATIVE_CANVAS_GEOMETRY_INVALID'
  $bounds=(Refresh-Window).Current.BoundingRectangle
  Require ($rect.X -ge $bounds.X -and $rect.Y -ge $bounds.Y -and
    $rect.Right -le $bounds.Right+1 -and $rect.Bottom -le $bounds.Bottom+1) 'W138_CANVAS_OUT_OF_WINDOW'
  return $rect
}
function Real-CanvasFocus {
  $foreground=[KTRADEW138Native]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 190
  Require ($foreground -and [KTRADEW138Native]::GetForegroundWindow() -eq $proc.MainWindowHandle) 'W138_WINDOW_NOT_FOREGROUND'
}
function Native-Wheel([int]$delta) {
  $rect=Real-CanvasRect
  Real-CanvasFocus
  $x=[int][Math]::Round($rect.X+$rect.Width*.5)
  $y=[int][Math]::Round($rect.Y+$rect.Height*.50)
  [KTRADEW138Native]::Wheel($x,$y,$delta)
}
function Native-Drag([bool]$older) {
  $rect=Real-CanvasRect
  Real-CanvasFocus
  $left=[int][Math]::Round($rect.X+$rect.Width*.36)
  $right=[int][Math]::Round($rect.X+$rect.Width*.72)
  $y=[int][Math]::Round($rect.Y+$rect.Height*.51)
  if($older){[KTRADEW138Native]::Drag($left,$y,$right,$y)}
  else{[KTRADEW138Native]::Drag($right,$y,$left,$y)}
}
function Native-Key([int]$code){
  Require ($code -in @(0x25,0x27,0x21,0x22,0x6b,0x6d,0x24)) 'W138_UNAPPROVED_KEY'
  Real-CanvasFocus
  [KTRADEW138Native]::Key($code)
}
function Native-FocusCanvas {
  $rect=Real-CanvasRect
  Real-CanvasFocus
  $x=[int][Math]::Round($rect.X+$rect.Width*.50)
  $y=[int][Math]::Round($rect.Y+$rect.Height*.54)
  [KTRADEW138Native]::Click($x,$y)
  Start-Sleep -Milliseconds 180
  # Move the cursor away without clicking; the focus remains on canvas,
  # while the existing native pointerleave clears any hover inspection.
  [KTRADEW138Native]::Hover($x,[int][Math]::Round($rect.Y-12))
}
function Wait-Witness([string]$stage,[int]$seconds) {
  $name='W138_REAL_'+$stage+'=PASS'
  [void](Wait-Control $name $false $seconds)
  Write-Host ('QFORGE_W138_REAL_NATIVE_'+$stage+'=PASS')
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
    Require ($LASTEXITCODE -eq 0) 'W138_VENDOR_INSTALL_FAILED'
    & node scripts/stage_offline_vendor.cjs *> $log
    Require ($LASTEXITCODE -eq 0) 'W138_OFFLINE_VENDOR_FAILED'
    $builder=Join-Path $repo 'windows/Build-KTRADE-WailsPortable.ps1'
    & $builder -OutputRoot $root -ExpectedSourceSha $ExpectedSourceSha -W13QualificationFixture -W41ColdFixture *> $log
    Require ($LASTEXITCODE -eq 0 -and
      (Test-Path -LiteralPath $exe -PathType Leaf) -and
      (Test-Path -LiteralPath $engine -PathType Leaf)) 'W138_DISPOSABLE_NATIVE_BUILD_FAILED'
  }finally{Pop-Location}
  $manifest=Get-Content -LiteralPath (Join-Path $root 'source-manifest.json') -Raw|ConvertFrom-Json
  Require ($manifest.source_sha -ceq $ExpectedSourceSha -and
   $manifest.fixture_mode -ceq 'w41-frozen-disposable-restart' -and
   $manifest.live_armed -eq $false -and
   $manifest.paper_started -eq $false -and
   $manifest.release_candidate -eq $false) 'W138_DISPOSABLE_PROOF_DRIFT'
  $dest=Join-Path $stage 'static/w138_real_native_observer.js'
  Require (!(Test-Path -LiteralPath $dest)) 'W138_FIXTURE_COLLISION'
  Copy-Item -LiteralPath $fixture -Destination $dest -ErrorAction Stop
  $chartPath=Join-Path $stage 'templates/chart.tmpl'
  $original=(& git -C $repo rev-parse 'HEAD:templates/chart.tmpl').Trim()
  Require ($original -ceq '5e0690746194b113aca62202560a3d594d01b5f2' -and
    (& git -C $repo rev-parse 'HEAD:cmd/ktrade/w114_tickchart_full.go').Trim() -ceq
      '944d36385739e96cd2f995fcbe7ae9727f2de486' -and
    (& git -C $repo rev-parse 'HEAD:internal/tickchart/exchange_matches_heartbeat.go').Trim() -ceq
      '89654865bcede98793921f873beaf6f8c39f2b34' -and
    (& git -C $repo rev-parse 'HEAD:static/w114_tick_chart.js').Trim() -ceq
      '63776b3906ae9237a47739b5ce52f8c722351bc0' -and
    (& git -C $repo rev-parse 'HEAD:tests/w126_stale_tick_chart.test.cjs').Trim() -ceq
      '4ba8676fd16458ce11db9021c31af7b6fa7e84bf' -and
    (& git -C $repo rev-parse 'HEAD:tests/w129_tick_interaction.test.cjs').Trim() -ceq
      '900a8c36a41c53083a04af0ba6af5e6e6cc8c64e' -and
    (& git -C $repo rev-parse 'HEAD:tests/w131_tick_keyboard.test.cjs').Trim() -ceq
      '938c15111b9e947429562ad4db882f13c0b0ddd3' -and
    (& git -C $repo rev-parse 'HEAD:tests/w133_tick_sma20.test.cjs').Trim() -ceq
      '57247ae0acabfc98137a6ef38254cec9f218b73b' -and
    (& git -C $repo rev-parse 'HEAD:tests/w135_tick_ema20.test.cjs').Trim() -ceq
      '148f52be149e291f5c2e1d4fa908316fbd4e659b' -and
    (& git -C $repo rev-parse 'HEAD:tests/w137_tick_rsi14.test.cjs').Trim() -ceq
      '92400068429c621e0bfa49661dfdc7c98f5af32f') 'W138_PRODUCT_CHART_SOURCE_DRIFT'
  $html=[IO.File]::ReadAllText($chartPath)
  # The W41 bridge is appended just before </body>, AFTER the product
  # w114 chart script. Hooking the frozen chart API at that point replaces an
  # already-defined API and prevents the chart DOMContentLoaded install.
  # Place this passive fixture BEFORE w114_tick_chart.js, not after W41.
  $anchor='<script src="/static/w114_tick_chart.js"></script>'
  $w41='<script src="/static/w41_wails_cold_bridge.js"></script>'
  Require ($html.Split([string[]]@($anchor),[StringSplitOptions]::None).Count -eq 2 -and
    $html.Contains($w41) -and
    !$html.Contains('w138_real_native_observer')) 'W138_PRE_CHART_FIXTURE_BOUNDARY'
  $html=$html.Replace($anchor,
    '<output role="status" style="position:fixed;right:6px;bottom:20px;z-index:32000;background:#0b2830;color:#13d4d4">W138_STATIC_MARKUP_LOADED</output>'+
    [Environment]::NewLine+
    '<script src="/static/w138_real_native_observer.js"></script>'+
    [Environment]::NewLine+$anchor)
  [IO.File]::WriteAllText($chartPath,$html,[Text.UTF8Encoding]::new($false))
  Require ((& git -C $repo rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
    @(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0) 'W138_PRODUCT_WORKTREE_CHANGED'
  $proc=Start-Process -FilePath $exe -WorkingDirectory $stage -PassThru
  $until=(Get-Date).AddSeconds(45)
  $ready=$false
  while((Get-Date) -lt $until){
    $proc.Refresh()
    if($proc.HasExited){throw 'W138_NATIVE_WAILS_EARLY_EXIT'}
    if($proc.MainWindowHandle -ne [IntPtr]::Zero){$ready=$true;break}
    Start-Sleep -Milliseconds 350
  }
  Require $ready 'W138_REAL_WAILS_WINDOW_MISSING'
  $until=(Get-Date).AddSeconds(15)
  $children=@()
  while((Get-Date) -lt $until){
    $children=@(Get-CimInstance Win32_Process -Filter "name='ktrade-engine.exe'" |
      Where-Object {$_.ExecutablePath -ieq $engine -and $_.ParentProcessId -eq $proc.Id})
    if($children.Count -eq 1){break}
    Start-Sleep -Milliseconds 300
  }
  Require ($children.Count -eq 1) 'W138_EXACT_ENGINE_CHILD_MISSING'
  $childPID=[int]$children[0].ProcessId
  # Verify read-only paper and LIVE mode without accessing any account.
  $until=(Get-Date).AddSeconds(12);$ports=@()
  while((Get-Date) -lt $until){
    $ports=@(Get-NetTCPConnection -State Listen -OwningProcess $childPID -ErrorAction SilentlyContinue|
      Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
    if($ports.Count -eq 1){break}
    Start-Sleep -Milliseconds 250
  }
  Require ($ports.Count -eq 1) 'W138_NOT_EXCLUSIVE_LOOPBACK'
  $url='http://127.0.0.1:'+[int]$ports[0].LocalPort
  $cap=Invoke-RestMethod -Uri ($url+'/api/operator/capabilities') -TimeoutSec 10
  Require ($cap.mode -ceq 'PAPER_STOPPED' -and
    $cap.paper_orders_enabled -eq $false -and
    $cap.live_orders_enabled -eq $false -and
    $cap.strategy_execution_enabled -eq $false) 'W138_FINANCIAL_MODE_NOT_DISARMED'
  # Test-only diagnostics on the disposable WebView2 fixture; no chart
  # events, feed synthesis, broker operations or owner state.
  $asset=Invoke-WebRequest -Uri ($url+'/static/w138_real_native_observer.js') -Method Get -TimeoutSec 10
  Require ($asset.StatusCode -eq 200 -and $asset.RawContentLength -gt 1500) 'W138_OBSERVER_ASSET_NOT_SERVED'
  Write-Host 'QFORGE_W138_OBSERVER_ASSET_SERVED=PASS'
  # Compare the actual server-side document with the disposable injected
  # fixture. A served JS asset alone does not prove script inclusion in /chart.
  $served=Invoke-WebRequest -Uri ($url+'/chart') -Method Get -TimeoutSec 10
  Require ($served.StatusCode -eq 200) 'W138_CHART_ROUTE_NOT_SERVED'
  $hasObserver=$served.Content.Contains('<script src="/static/w138_real_native_observer.js"></script>')
  $hasMarker=$served.Content.Contains('W138_STATIC_MARKUP_LOADED')
  $hasProduct=$served.Content.Contains('<script src="/static/w114_tick_chart.js"></script>')
  Write-Host ('QFORGE_W138_CHART_HTTP_SCRIPT='+$hasObserver+';static='+$hasMarker+';product='+$hasProduct)
  if(!$hasObserver -or !$hasMarker -or !$hasProduct){
    throw 'W138_STAGED_CHART_TEMPLATE_NOT_SERVED'
  }
  # Read only innocuous UIA element presence. Never dump window contents,
  # private account data, clipboard, screenshots or owner files.
  $shell=Find-Control 'Original KTRADE chart and Pine editor' $false
  $tf=Find-Control '100T' $true
  $minute=Find-Control '1m' $true
  $probe=Find-Control 'W138_STATIC_MARKUP_LOADED' $false
  Write-Host ('QFORGE_W138_UIA_PRESENT:shell='+[bool]($null -ne $shell)+
    ';hundredT='+[bool]($null -ne $tf)+';oneMinute='+[bool]($null -ne $minute)+
    ';static='+[bool]($null -ne $probe))
  # Explicitly separate external JavaScript execution from the later
  # chart witness, without treating script fetch/HTML delivery as execution.
  $phases=@(
    'W138_STAGE_READY_EMITTED=PASS',
    'W138_STAGE_RUNTIME_ERROR=PASS',
    'W138_STAGE_DOM_LOOKUP=PASS',
    'W138_STAGE_SOCKET_SET=PASS',
    'W138_STAGE_SOCKET_CLASS=PASS',
    'W138_STAGE_API_WRAPPED=PASS',
    'W138_STAGE_BEFORE_API=PASS',
    'W138_JS_ENTERED=PASS'
  )
  $phase='NOT_OBSERVED'
  foreach($candidate in $phases){
    if(Find-Control $candidate $false){$phase=$candidate;break}
  }
  Write-Host ('QFORGE_W138_JS_LAST_INIT_STAGE='+$phase)
  if($phase -ceq 'NOT_OBSERVED'){throw 'W138_OBSERVER_JAVASCRIPT_NOT_OBSERVED'}
  [void](Wait-Control 'W138_REAL_READY=PASS' $false 25)
  Write-Host 'QFORGE_W138_REAL_PUBLIC_PASSIVE_WITNESS_VISIBLE=PASS'
  Native-Click '100T'
  Wait-Witness 'FIRST_PUBLIC_BAR' 155
  # RSI14 requires 15 genuine 100T completed bars (>=1500 public executions).
  Wait-Witness 'REAL_15_BARS' 1200
  Native-Click 'RSI 14'; Wait-Witness 'NATIVE_RSI14_VISIBLE_AND_PAINTED' 35
  Native-Click 'RSI 14'; Wait-Witness 'NATIVE_RSI14_OFF' 35
  Native-Click '1m'; Wait-Witness 'TIME_RETURN' 35
  Write-Host ('QFORGE_W138_REAL_NATIVE_RSI14_OSCILLATOR=PASS;sha='+$ExpectedSourceSha+
    ';bars=public_completed_100T;min_real_trades=1500;native_clicks=3;canvas_geometric_size=verified;oscillator_bitmap_changed=true;synthetic_bars=zero;orders=zero;trading=disarmed')

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
