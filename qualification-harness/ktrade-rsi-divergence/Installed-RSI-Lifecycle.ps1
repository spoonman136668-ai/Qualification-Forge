# KTRADE W83: W83 original native lifecycle plus installed CANDIDATE chart/Pine/order safety.
# SOURCE-ONLY witness. No broker, owner installation, release or authority changes.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$PreviousBundle,
 [Parameter(Mandatory=$true)][string]$CandidateBundle,
 [Parameter(Mandatory=$true)][string]$QualificationRoot,
 [Parameter(Mandatory=$true)][string]$NativeInputsPath,
 [Parameter(Mandatory=$true)][string]$PaperScenarioPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$OldSHA='b03dd6e58b6120cae3ffd39a79c6965ab8e91b9a'
$NewSHA='42bf2c698d15da43632540959f9a5eea3999158b'
function Require([bool]$ok,[string]$name){if(!$ok){throw $name}}
function Hash([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()}
function Ordinary([string]$f,[bool]$dir){
 $obj=Get-Item -LiteralPath $f -Force -ErrorAction Stop
 Require ($obj.PSIsContainer -eq $dir -and !$obj.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) 'W83_NONORDINARY_ASSET'
}
function Bundle([string]$root,[string]$sha){
 Ordinary $root $true
 $path=Join-Path $root 'installer-manifest.json'
 Ordinary $path $false
 Require ((Get-Item -LiteralPath $path).Length -le 16384) 'W83_MANIFEST_SIZE_INVALID'
 $m=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 Require ($m.schema -ceq 'ktrade.setup-bundle.v2' -and $m.source_sha -ceq $sha -and
  $m.live_armed -eq $false -and $m.release_authority -ceq 'none' -and
  $m.signature_status -ceq 'unsigned') 'W83_BUNDLE_AUTHORITY_MISMATCH'
 $wanted=@('KTRADE-Setup.ps1','Manage-KTRADE-FreshInstall.ps1','release-setup.exe',
  'release-launch.exe','release-maintain.exe','KTRADE-Setup.exe','KTRADE-Payload.zip')
 Require (@($m.files).Count -eq $wanted.Count) 'W83_BUNDLE_FILE_COUNT_CHANGED'
 $seen=@{}
 foreach($row in @($m.files)){
  Require ($wanted -ccontains $row.name -and !$seen.ContainsKey($row.name) -and
   $row.sha256 -cmatch '^[a-f0-9]{64}$' -and $row.size -gt 0) 'W83_BUNDLE_ITEM_INVALID'
  $seen[$row.name]=$true
  $p=Join-Path $root $row.name
  Ordinary $p $false
  Require ((Get-Item -LiteralPath $p).Length -eq $row.size -and (Hash $p) -ceq $row.sha256) 'W83_BUNDLE_BYTES_CHANGED'
 }
 return $m
}
function Hashes([string]$dir){
 Ordinary $dir $true
 $values=@{}
 foreach($file in Get-ChildItem -LiteralPath $dir -Recurse -File -Force){
  Ordinary $file.FullName $false
  $name=$file.FullName.Substring($dir.Length).TrimStart([char]'\',[char]'/')
  $values[$name]=Hash $file.FullName
 }
 return ,$values
}
function AssertHashes([hashtable]$a,[hashtable]$b,[string]$label){
 Require ($a.Count -eq $b.Count) ($label+'_FILE_COUNT_DRIFT')
 foreach($k in $a.Keys){Require ($b.ContainsKey($k) -and $b[$k] -ceq $a[$k]) ($label+'_HASH_DRIFT_'+$k)}
}
function Setup([string]$scriptPath,[string]$action,[bool]$shouldPass=$true){
 $log=Join-Path $QualificationRoot ([guid]::NewGuid().ToString('N')+'.out')
 $errors=Join-Path $QualificationRoot ([guid]::NewGuid().ToString('N')+'.err')
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'),'-Action',$action,
  '-InstallRoot',('"'+$script:installedRoot+'"'),'-ShortcutParent',('"'+$script:shortcuts+'"'))
 # PS7's inherited module paths cannot supply PS5.1 core cmdlets.
 # Bridge only this original installer child, then restore the PS7 host.
 $modulePathBefore=$env:PSModulePath
 try{
  $env:PSModulePath=Join-Path (Split-Path -Parent $script:ps51) 'Modules'
  Require (Test-Path -LiteralPath $env:PSModulePath -PathType Container) 'W83_WINDOWS_POWERSHELL_CORE_MODULES_REQUIRED'
  $proc=Start-Process -FilePath $script:ps51 -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError $errors
 }finally{$env:PSModulePath=$modulePathBefore}
 $output=Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
 $errorText=Get-Content -LiteralPath $errors -Raw -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $log,$errors -Force -ErrorAction SilentlyContinue
 if(!$shouldPass){Require ($proc.ExitCode -ne 0) ('W83_EXPECTED_'+$action+'_REFUSAL_MISSING');return $null}
 Require ($proc.ExitCode -eq 0) ('W83_'+$action+'_FAILED_'+$errorText)
 try{return ($output|ConvertFrom-Json)}catch{throw ('W83_'+$action+'_INVALID_RECEIPT')}
}
Add-Type -AssemblyName UIAutomationClient
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W83Native {
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
  Require (!$shell.HasExited) 'W83_SHELL_EXITED_BEFORE_UI_READY'
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
     if($h -ne [IntPtr]::Zero -and [W83Native]::IsChild($shell.MainWindowHandle,$h)){
      $sb=New-Object Text.StringBuilder(512)
      if([W83Native]::GetClassName($h,$sb,512) -gt 0){$native=($sb.ToString() -match '^(?:WindowsForms10\.)?BUTTON(?:\.|$)')}
     }
     if($native -or $node.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button){return $node}
    }catch{}
   }
  }
  Start-Sleep -Milliseconds 350
 }while((Get-Date) -lt $until)
 throw ('W83_NATIVE_UI_NOT_OBSERVED_'+$label)
}
function ClickUI([object]$shell,[string]$label){
 $node=FindUI $shell $label $true
 $rect=$node.Current.BoundingRectangle
 $outer=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require (!$rect.IsEmpty -and $rect.Width -gt 8 -and $rect.Height -gt 8 -and
  $rect.Left -ge $outer.Left -and $rect.Right -le $outer.Right -and
  $rect.Top -ge $outer.Top -and $rect.Bottom -le $outer.Bottom) 'W83_FOREIGN_CONTROL'
 [void][W83Native]::SetForegroundWindow($shell.MainWindowHandle)
 Start-Sleep -Milliseconds 200
 Require ([W83Native]::GetForegroundWindow() -eq $shell.MainWindowHandle) 'W83_FOREIGN_FOCUS'
 Require ([W83Native]::SetCursorPos([int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))) 'W83_NATIVE_POINTER_REFUSED'
 [W83Native]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [W83Native]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}

# W94B additions only: real desktop pixel/geometry observations, process-tree accounting.
# They do not certify Pine reference-to-pixel parity, GPU FPS or retail workstation performance.
Add-Type -AssemblyName System.Drawing
function W94BProcessTree([object]$shell){
 $all=@(Get-CimInstance Win32_Process -ErrorAction Stop)
 $ids=New-Object 'System.Collections.Generic.HashSet[int]'
 [void]$ids.Add([int]$shell.Id)
 $added=$true
 for($generation=0;$generation -lt 12 -and $added;$generation++){
  $added=$false
  foreach($p in $all){
   $pidValue=[int]$p.ProcessId
   if(!$ids.Contains($pidValue) -and $ids.Contains([int]$p.ParentProcessId)){
    [void]$ids.Add($pidValue)
    $added=$true
   }
  }
 }
 Require (!$added) 'W94B_PROCESS_DESCENDANT_DEPTH_EXCEEDED'
 $members=@($all|Where-Object {$ids.Contains([int]$_.ProcessId)})
 $web=@($members|Where-Object {$_.Name -match '^msedgewebview2(?:\.exe)?$'})
 Require ($web.Count -gt 0) 'W94B_WEBVIEW2_CHILD_PROCESS_NOT_FOUND'
 $bytes=[long]0;$observed=@()
 foreach($p in $members){
  $proc=Get-Process -Id ([int]$p.ProcessId) -ErrorAction Stop
  $bytes+=[long]$proc.WorkingSet64
  $observed+=@{pid=[int]$proc.Id;name=[string]$p.Name;working_set_bytes=[long]$proc.WorkingSet64}
 }
 return [pscustomobject]@{scope='shell,engine,and_all_current_descendants_including_WebView2';total_working_set_bytes=$bytes;process_count=$members.Count;webview2_count=$web.Count;members=$observed}
}
function W94BWaitOriginalChartBounds([object]$shell,[System.Drawing.Rectangle]$expected){
 $deadline=[DateTime]::UtcNow.AddSeconds(10)
 $stable=0
 do{
  $node=FindUI $shell 'Price chart drawing surface' $false 2
  $r=$node.Current.BoundingRectangle
  $actual=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
  if($actual.Equals($expected)){$stable++}else{$stable=0}
  if($stable -ge 3){return}
  Start-Sleep -Milliseconds 150
 }while([DateTime]::UtcNow -lt $deadline)
 throw 'W94B_ORIGINAL_CHART_BOUNDS_DID_NOT_RETURN_AFTER_EDITOR_ANIMATION'
}
function W94BCaptureChart([object]$shell,[string]$phase){
 $node=FindUI $shell 'Price chart drawing surface' $false 20
 $r=$node.Current.BoundingRectangle
 $outer=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require (!$r.IsEmpty -and $r.Width -ge 220 -and $r.Height -ge 140 -and
  $r.Left -ge $outer.Left -and $r.Right -le $outer.Right -and
  $r.Top -ge $outer.Top -and $r.Bottom -le $outer.Bottom) 'W94B_PRICE_CHART_UIA_GEOMETRY_INVALID'
 $rect=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
 Require ($rect.Width -ge 220 -and $rect.Height -ge 140 -and $rect.Width -le 3840 -and $rect.Height -le 2160) 'W94B_CHART_SCREEN_RECT_OUT_OF_SCOPE'
 $bmp=[System.Drawing.Bitmap]::new($rect.Width,$rect.Height,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
 try{
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  try{$g.CopyFromScreen($rect.Location,[System.Drawing.Point]::Empty,$rect.Size)}finally{$g.Dispose()}
  $stream=[IO.MemoryStream]::new()
  try{
   $bmp.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
   $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream.ToArray())).ToLowerInvariant()
  }finally{$stream.Dispose()}
  Write-Host ('W94B_PRICE_CHART_SCREEN_DIGEST='+(@{phase=$phase;left=$rect.Left;top=$rect.Top;width=$rect.Width;height=$rect.Height;png_sha256=$digest;scope='captured_original_visible_Price_chart_drawing_surface';retained_screenshot=$false}|ConvertTo-Json -Compress))
  return [pscustomobject]@{bitmap=$bmp;rect=$rect;digest=$digest}
 }catch{$bmp.Dispose();throw}
}
function W94BCompareChartFrames([object]$a,[object]$b){
 Require ($a.rect.Equals($b.rect)) 'W94B_CHART_GEOMETRY_CHANGED_DURING_APPLY'
 $count=0;$changed=0
 # Deterministic 4-pixel grid, genuine original desktop pixels, no DOM injection.
 for($y=4;$y -lt ($a.rect.Height-4);$y+=4){
  for($x=4;$x -lt ($a.rect.Width-4);$x+=4){
   $before=$a.bitmap.GetPixel($x,$y)
   $after=$b.bitmap.GetPixel($x,$y)
   $count++
   if([Math]::Abs([int]$before.R-[int]$after.R) -ge 12 -or
      [Math]::Abs([int]$before.G-[int]$after.G) -ge 12 -or
      [Math]::Abs([int]$before.B-[int]$after.B) -ge 12){$changed++}
  }
 }
 Require ($count -ge 500 -and $changed -ge 15) 'W94B_PRICE_PANE_VISIBLE_PIXEL_CHANGE_NOT_PROVEN'
 Write-Host ('::notice::W94B_ACTUAL_MAIN_PRICE_CHART_DESKTOP_GEOMETRY_AND_PIXEL_CHANGE=PASS')
 Write-Host ('W94B_REAL_PRICE_PANE_COMPARISON='+(@{pixel_sample_count=$count;changed_sample_count=$changed;before_sha256=$a.digest;after_sha256=$b.digest;identical_bounds=$true;scope='native_desktop_pane_difference_only_not_independent_pixel_oracle'}|ConvertTo-Json -Compress))
}

function StartInstalled([string]$maintenance,[object]$receipt,[string]$phase){
 $startWatch=[Diagnostics.Stopwatch]::StartNew()
 # Mirror the independently qualified PREVIOUS native operator path: ShellExecute
 # the original, current selection-bound .lnk, rather than spawning a redirected
 # console launcher that can hide or detach the first real WebView2 window.
 $current=Get-Content -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json') -Raw|ConvertFrom-Json
 Require ($current.source_sha -ceq $receipt.source_sha -and $current.selection_digest -cmatch '^[a-f0-9]{64}$') 'W83_SELECTED_SHORTCUT_SOURCE_DRIFT'
 $folder=Join-Path $script:shortcuts ('KTRADE-'+$current.selection_digest.Substring(0,16))
 $shortcut=Join-Path $folder 'KTRADE.lnk'
 $proof=Join-Path $folder '.ktrade-shortcut-receipt.json'
 Ordinary $shortcut $false
 Ordinary $proof $false
 $owned=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
 Require ($owned.schema -ceq 'ktrade.windows-shortcut.v1' -and
  $owned.source_sha -ceq $receipt.source_sha -and
  $owned.selection_digest -ceq $current.selection_digest -and
  $owned.root -ceq $script:installedRoot -and
  $owned.target -ceq (Join-Path $receipt.candidate_directory 'ktrade.exe') -and
  $owned.live_armed -eq $false -and
  (Hash $shortcut) -ceq $owned.link_sha256) 'W83_ORIGINAL_SHORTCUT_CUSTODY_DRIFT'
 Start-Process -FilePath $shortcut
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 $until=(Get-Date).AddSeconds(45)
 do{
  if(Test-Path -LiteralPath $lease){try{$owner=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json;if($owner.pid -gt 0){break}}catch{}}
  Start-Sleep -Milliseconds 300
 }while((Get-Date) -lt $until)
 Require (Test-Path -LiteralPath $lease) ('W83_'+$phase+'_NO_OWNER_LEASE')
 $owner=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json
 Require ($owner.source_sha -ceq $receipt.source_sha -and $owner.live_armed -eq $false) 'W83_SOURCE_OR_DISARM_DRIFT'
 $shell=Get-Process -Id $owner.pid
 $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shell.Id)
 Require ([string]::Equals($cim.ExecutablePath,(Join-Path $receipt.candidate_directory 'ktrade.exe'),[StringComparison]::OrdinalIgnoreCase)) 'W83_SHELL_EXE_DRIFT'
 if($receipt.source_sha -ceq $NewSHA){ClickUI $shell 'Desktop diagnostics'}
 $verified=$false
 for($attempt=1;$attempt -le 3;$attempt++){
  ClickUI $shell 'Verify chart UI'
  try{
   $null=FindUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.' $false 12
   $verified=$true
   break
  }catch{
   if($attempt -eq 3){throw ('W83_'+$phase+'_NATIVE_WEBVIEW2_NOT_VERIFIED')}
   Start-Sleep -Seconds 2
  }
 }
 Require $verified 'W83_WEBVIEW2_NOT_VERIFIED'
 $engine=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
 Require ($engine.Count -eq 1) 'W83_NATIVE_ENGINE_OWNERSHIP_DRIFT'
 $ports=@(Get-NetTCPConnection -OwningProcess $engine[0].ProcessId -State Listen|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W83_UNEXPECTED_LOOPBACK'
 $cap=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$ports[0].LocalPort+'/api/operator/capabilities') -TimeoutSec 5
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and $cap.paper_orders_enabled -eq $false -and
  $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false -and
  $cap.paper_accounting_enabled -eq $false -and $cap.requires_review -eq $true) 'W83_OPERATOR_CAPABILITIES_DRIFT'
 if($phase -ceq 'UPDATED'){
  # Real installed CANDIDATE Go-engine HTTP; compile does not evaluate or dispatch.
  $origin='http://127.0.0.1:'+$ports[0].LocalPort
  $headers=@{Origin=$origin}
  $page=Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/chart') -TimeoutSec 12
  Require ($page.StatusCode -eq 200 -and
   $page.Content.Contains('pineCompile') -and $page.Content.Contains('chart')) 'W83_INSTALLED_ORIGINAL_CHART_NOT_SERVED'
  $render=Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/static/pine_plot_renderer.js') -TimeoutSec 12
  Require ($render.StatusCode -eq 200 -and $render.Content.Length -gt 1200) 'W83_INSTALLED_ORIGINAL_PINE_RENDERER_NOT_SERVED'
  Write-Host '::notice::W83_INSTALLED_CANDIDATE_ORIGINAL_CHART_AND_PINE_RENDERER=PASS'
  foreach($version in @(5,6)){
   $code='//@version='+$version+[Environment]::NewLine+'indicator("W83 Windows installed",overlay=true)'+[Environment]::NewLine+'plot(close)'
   $body=@{name='W83Offline';code=$code}|ConvertTo-Json -Compress
   $response=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/compile') -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 20
   Require ($response.success -eq $true -and $response.kind -ceq 'indicator') ('W83_NATIVE_PINE_V'+$version+'_REFUSED')
  }
  $invalid=@{name='W83Rejected';code=('//@version=6'+[Environment]::NewLine+'indicator(')}|ConvertTo-Json -Compress
  $negative=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/compile') -Headers $headers -ContentType 'application/json' -Body $invalid -TimeoutSec 20
  Require ($negative.success -eq $false -and ![string]::IsNullOrWhiteSpace($negative.error)) 'W83_MALFORMED_PINE_ACCEPTED'
  Write-Host '::notice::W83_INSTALLED_CANDIDATE_REAL_GO_PINE_V5_V6_COMPILE_AND_REFUSAL=PASS'
  # W94B probes must execute in the original candidate lifecycle, before
  # opening any catalog dialog so the baseline contains only the actual chart.
  $w94Before=W94BCaptureChart $shell 'BEFORE_SUPERTREND'
  $w94BeforeProcesses=W94BProcessTree $shell
  Write-Host ('W94B_PROCESS_TREE_BEFORE='+($w94BeforeProcesses|ConvertTo-Json -Depth 5 -Compress))
  # Genuine owned WebView2 UIA and physical-pointer catalog interaction.
  # Verify the numerically qualified catalog entry; never inject DOM code or issue a trading command.
  ClickUI $shell 'Indicators'
  ClickUI $shell 'Technicals'
  $null=FindUI $shell 'Apply Relative Strength Index' $true 35
  $uiRoot=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
  foreach($label in @('Apply RSI Divergence')){
    $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$label)
    $aliasNodes=$uiRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
    Require ($aliasNodes.Count -eq 1 -and $aliasNodes[0].Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and $aliasNodes[0].Current.IsEnabled) 'RSI_CONFIRMED_CATALOG_ENTRY_NOT_VISIBLY_ENABLED_IN_NATIVE_UIA'
  }
  # W93 first: real owned WebView2 overlay-plot Apply before Williams,
  # preventing stale status from the earlier separate-pane plot.
  $superSearch=FindUI $shell 'Search indicator catalog' $false 20
  $superValue=$null
  Require ($superSearch.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
    $superSearch.Current.IsEnabled -and
    $superSearch.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$superValue)) 'W93_ORIGINAL_CATALOG_SEARCH_UNAVAILABLE'
  ([System.Windows.Automation.ValuePattern]$superValue).SetValue('Supertrend')
  $supertrend=FindUI $shell 'Apply Supertrend' $false 35
  Require ($supertrend.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
   $supertrend.Current.IsEnabled) 'W93_ORIGINAL_SUPERTREND_BUTTON_NOT_ENABLED'
  ClickUI $shell 'Apply Supertrend'
  # Overlay=true plots render on the MAIN price chart. Their titles are
  # intentionally excluded from the separate Pine pane caption. The real
  # source request sets this success status only AFTER PinePlots.apply has
  # allocated the original chart's series and finished without throwing.
  # Open the actual browser editor via physical UI, not DOM injection.
  ClickUI $shell 'Pine Editor'
  $null=FindUI $shell 'Pine plots applied.' $false 45
  ClickUI $shell 'Collapse'
  $afterSuper=Invoke-RestMethod -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 5
  Require ($afterSuper.mode -ceq 'PAPER_STOPPED' -and $afterSuper.paper_orders_enabled -eq $false -and
    $afterSuper.live_orders_enabled -eq $false -and $afterSuper.strategy_execution_enabled -eq $false) 'W93_SUPERTREND_APPLY_CHANGED_TRADING_AUTHORITY'
  Write-Host '::notice::W93_REAL_INSTALLED_WEBVIEW2_SUPERTREND_ENABLED_PHYSICAL_APPLY_ORIGINAL_MAIN_CHART_RENDER_STATUS_NO_TRADING=PASS'
  $w94After=$null
  try{
   # Original UI closePinePanel schedules resize after its 300ms CSS transition.
   # Wait for the SAME original bounds; never weaken comparison or resize via JS.
   W94BWaitOriginalChartBounds $shell $w94Before.rect
   $w94After=W94BCaptureChart $shell 'AFTER_SUPERTREND'
   W94BCompareChartFrames $w94Before $w94After
   $w94AfterProcesses=W94BProcessTree $shell
   Write-Host ('W94B_PROCESS_TREE_AFTER='+($w94AfterProcesses|ConvertTo-Json -Depth 5 -Compress))
   Write-Host '::notice::W94B_ACTIVE_PIXEL_AND_WEBVIEW_PROCESS_PROBES_EXECUTED=PASS'
  }finally{
   if($null -ne $w94After){$w94After.bitmap.Dispose()}
   $w94Before.bitmap.Dispose()
  }
  # W90 retained: original different, separate-pane Williams indicator must
  # physically Apply and show its own Pine: Williams %R pane title.
  ClickUI $shell 'Indicators'
  ClickUI $shell 'Technicals'
  $search=FindUI $shell 'Search indicator catalog' $false 20
  Require ($search.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and $search.Current.IsEnabled) 'W90_REAL_CATALOG_SEARCH_NOT_ENABLED'
  $value=$null
  Require ($search.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)) 'W90_NATIVE_SEARCH_VALUE_PATTERN_UNAVAILABLE'
  ([System.Windows.Automation.ValuePattern]$value).SetValue('Williams %R')
  ClickUI $shell 'Apply Williams %R'
  $null=FindUI $shell 'Pine: Williams %R' $false 45
  $catalogAfter=Invoke-RestMethod -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 5
  Require ($catalogAfter.mode -ceq 'PAPER_STOPPED' -and $catalogAfter.paper_orders_enabled -eq $false -and $catalogAfter.live_orders_enabled -eq $false) 'W90_CATALOG_APPLY_CHANGED_TRADING_AUTHORITY'
  Write-Host '::notice::W90_NATIVE_CATALOG_EXPLICIT_WILLIAMS_APPLY_ORIGINAL_GO_RENDERED_NO_TRADING=PASS'

  # Real physical Apply of the independently qualified regular-divergence
  # script. This proves installed native integration, not a pixel/marker oracle.
  ClickUI $shell 'Indicators'
  ClickUI $shell 'Technicals'
  $rsiSearch=FindUI $shell 'Search indicator catalog' $false 20
  $rsiValue=$null
  Require ($rsiSearch.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
    $rsiSearch.Current.IsEnabled -and
    $rsiSearch.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$rsiValue)) 'RSI_NATIVE_SEARCH_UNAVAILABLE'
  ([System.Windows.Automation.ValuePattern]$rsiValue).SetValue('RSI Divergence')
  $rsiApply=FindUI $shell 'Apply RSI Divergence' $false 35
  Require ($rsiApply.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -and
    $rsiApply.Current.IsEnabled) 'RSI_NATIVE_APPLY_NOT_ENABLED'
  ClickUI $shell 'Apply RSI Divergence'
  # The original pane renderer uses plot labels, not the indicator name.
  # This script has one pane plot: plot(osc, "RSI", ...).
  $rsiPane=FindUI $shell 'Pine: RSI' $false 45
  Require ($rsiPane.Current.Name -ceq 'Pine: RSI') 'RSI_NATIVE_EXACT_PLOT_CAPTION_REQUIRED'
  Write-Host ('RSI_NATIVE_PANE_CAPTION='+$rsiPane.Current.Name)
  $rsiAfter=Invoke-RestMethod -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 5
  Require ($rsiAfter.mode -ceq 'PAPER_STOPPED' -and $rsiAfter.paper_orders_enabled -eq $false -and
    $rsiAfter.live_orders_enabled -eq $false -and $rsiAfter.strategy_execution_enabled -eq $false) 'RSI_NATIVE_APPLY_CHANGED_TRADING_AUTHORITY'
  Write-Host '::notice::RSI_REAL_INSTALLED_WEBVIEW2_CONFIRMED_DIVERGENCE_PHYSICAL_APPLY_RSI_PANE_NO_TRADING=PASS'

  $refusedCode=0
  try{
   $null=Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($origin+'/api/orders/place') -Headers $headers -ContentType 'application/json' -Body '{"product_id":"BTC-USDC","side":"buy"}' -TimeoutSec 12 -ErrorAction Stop
  }catch{
   if($_.Exception.Response){$refusedCode=[int]$_.Exception.Response.StatusCode}else{throw}
  }
  Require ($refusedCode -eq 423) ('W83_REAL_INSTALLED_LEGACY_ORDER_NOT_DISARMED_'+$refusedCode)
  $after=Invoke-RestMethod -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 5
  Require ($after.mode -ceq 'PAPER_STOPPED' -and $after.paper_orders_enabled -eq $false -and $after.live_orders_enabled -eq $false) 'W83_ORDER_REFUSAL_CHANGED_AUTHORITY'
  Write-Host '::notice::W83_INSTALLED_CANDIDATE_LEGACY_ORDER_HTTP_423_AND_NO_REARM=PASS'
 }
 Write-Host ('::notice::W83_NATIVE_'+$phase+'_WEBVIEW2_AND_PAPER_STOPPED=PASS')
 $startWatch.Stop()
 $engineProcess=Get-Process -Id $engine[0].ProcessId
 $memory=[long]$shell.WorkingSet64+[long]$engineProcess.WorkingSet64
 Require ($startWatch.Elapsed.TotalSeconds -le 120) 'W83_NATIVE_STARTUP_EXCEEDED_PROSPECTIVE_120S_BUDGET'
 Require ($memory -le 1073741824) 'W83_SHELL_ENGINE_RESIDENT_EXCEEDED_PROSPECTIVE_1GIB_BUDGET'
 Write-Host ('W83_NATIVE_START_MEASUREMENT='+(@{phase=$phase;elapsed_ms=$startWatch.Elapsed.TotalMilliseconds;shell_engine_resident_bytes=$memory;startup_budget_ms=120000;resident_budget_bytes=1073741824;scope='native selected shortcut to verified WebView2 and safe capability; hosted VM; WebView child memory excluded'}|ConvertTo-Json -Compress))
 return [pscustomobject]@{shell=$shell;handle=$shell.Handle;enginePid=[int]$engine[0].ProcessId}
}
function StopInstalled([object]$run){
 Require ([W83Native]::PostMessage($run.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'W83_NORMAL_CLOSE_FAILED'
 Require ($run.shell.WaitForExit(30000)) 'W83_PROCESS_SHUTDOWN_FAILED'
 Require (!(Get-Process -Id $run.enginePid -ErrorAction SilentlyContinue)) 'W83_ORPHAN_ENGINE'
 Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'))) 'W83_LEASE_NOT_RELEASED'
 Start-Sleep -Seconds 2
}
Require ($env:OS -ceq 'Windows_NT' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted') 'W83_EPHEMERAL_WINDOWS_ONLY'
. $NativeInputsPath
. $PaperScenarioPath
$script:ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
Require (Test-Path -LiteralPath $script:ps51) 'W83_POWERSHELL_51_MISSING'
$QualificationRoot=[IO.Path]::GetFullPath($QualificationRoot)
$runnerTemp=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
Require (([IO.Path]::GetDirectoryName($QualificationRoot)).TrimEnd('\') -ieq $runnerTemp.TrimEnd('\')) 'W83_NOT_EPHEMERAL_TEMP_CHILD'
Require (!(Test-Path -LiteralPath $QualificationRoot)) 'W83_ROOT_ALREADY_EXISTS'
$null=New-Item -ItemType Directory -Path $QualificationRoot
$script:installedRoot=Join-Path $QualificationRoot 'KTRADE-W83 installed with spaces'
$script:shortcuts=Join-Path $QualificationRoot 'Shortcuts'
$null=New-Item -ItemType Directory -Path $script:shortcuts
$null=Bundle $PreviousBundle $OldSHA
$null=Bundle $CandidateBundle $NewSHA
$oldSetup=Join-Path $PreviousBundle 'KTRADE-Setup.ps1'
$newSetup=Join-Path $CandidateBundle 'KTRADE-Setup.ps1'
$script:active=$null
$savedPath=$env:PATH
$env:PATH=(Join-Path $env:WINDIR 'System32')+';'+(Split-Path -Parent $script:ps51)+';'+$env:WINDIR
Require (@(Get-Command go.exe,node.exe -ErrorAction SilentlyContinue).Count -eq 0) 'W83_BUILD_TOOLS_ON_RUNTIME_PATH'
try{
 $old=Setup $oldSetup 'Install'
 Require ($old.source_sha -ceq $OldSHA -and $old.app_launched -eq $false -and $old.live_armed -eq $false) 'W83_OLD_INSTALL_DRIFT'
 $oldMaint=Join-Path $script:installedRoot 'maintenance'
 $oldReceiptPath=Join-Path $script:installedRoot '.ktrade-w29-install.json'
 $oldReceiptHash=Hash $oldReceiptPath
 $unknown=Join-Path $script:installedRoot 'unknown-owner-file.bin'
 [IO.File]::WriteAllBytes($unknown,[byte[]](0,255,3,19,73,254))
 $unknownHash=Hash $unknown
 $script:active=StartInstalled $oldMaint $old 'PREVIOUS'
 $null=Setup $newSetup 'Update' $false
 Require ((Hash $oldReceiptPath) -ceq $oldReceiptHash) 'W83_ACTIVE_UPDATE_MUTATED_RECEIPT'
 StopInstalled $script:active;$script:active=$null
 foreach($item in @(@{path='pine-library/w35b-retained.pine';body='//@version=6 indicator W83'},
                  @{path='strategies/w35b-retained.pine';body='//@version=6 strategy W83'},
                  @{path='unknown/w35b-local-state';body='DO_NOT_MIGRATE_THIS_UNKNOWN_STATE'})){
  $path=Join-Path $old.candidate_directory ('data/'+$item.path)
  $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
  [IO.File]::WriteAllText($path,$item.body,[Text.UTF8Encoding]::new($false))
 }
 $oldHashes=Hashes (Join-Path $old.candidate_directory 'data')
 $updated=Setup $newSetup 'Update'
 Require ($updated.schema -ceq 'ktrade.installed-transition.v1' -and $updated.action -ceq 'select' -and
  $updated.before.source_sha -ceq $OldSHA -and $updated.after.source_sha -ceq $NewSHA -and
  $updated.live_armed -eq $false) 'W83_UPDATE_IDENTITY_INVALID'
 $new=$updated.after
 $newMaint=Join-Path $script:installedRoot ('maintenance-'+(Split-Path -Leaf (Split-Path -Parent $new.candidate_directory)))
 $newSetupInstalled=Join-Path $newMaint 'KTRADE-Setup.ps1'
 $newInspect=Setup $newSetupInstalled 'Inspect'
 Require ($newInspect.source_sha -ceq $NewSHA) 'W83_UPDATED_MAINTENANCE_MISMATCH'
 AssertHashes $oldHashes (Hashes (Join-Path $old.candidate_directory 'data')) 'W83_OLD_DATA'
 Require ((Hash (Join-Path $script:installedRoot '.ktrade-w30-before-000002.json')) -ceq $oldReceiptHash) 'W83_OLD_RECEIPT_BACKUP_DRIFT'
 foreach($rel in @('pine-library/w35b-retained.pine','strategies/w35b-retained.pine')){
  Require ((Hash (Join-Path $old.candidate_directory ('data/'+$rel))) -ceq
   (Hash (Join-Path $new.candidate_directory ('data/'+$rel)))) 'W83_SUPPORTED_BYTES_CHANGED'
 }
 Require (!(Test-Path -LiteralPath (Join-Path $new.candidate_directory 'data/unknown/w35b-local-state'))) 'W83_UNSUPPORTED_STATE_MIGRATED'
 Require ((Hash $unknown) -ceq $unknownHash) 'W83_UNKNOWN_ROOT_BYTES_CHANGED'
 $script:active=StartInstalled $newMaint $new 'UPDATED'
 $null=Setup $newSetupInstalled 'Rollback' $false
 # Run the ORIGINAL W40 current-market native Save/Start/four-fill/Stop/cold
 # scenario against this actual selected, newly updated installation.
 $script:stage=$new.candidate_directory
 $script:shell=$script:active.shell
 W33B-OwnEngine
 & { Set-StrictMode -Off; Run-P9NativeRoundTrips }
 $script:active=[pscustomobject]@{shell=$shell;handle=$shell.Handle;enginePid=[int]$engine.ProcessId}
 Require ((Get-Content -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json') -Raw|ConvertFrom-Json).source_sha -ceq $NewSHA) 'W83_PAPER_COLD_SELECTION_DRIFT'
 Write-Output '::notice::W83_REAL_UPDATED_INSTALL_NATIVE_SAVE_FOUR_CURRENT_FILLS_STOP_COLD_ACCOUNT=PASS'
 StopInstalled $script:active;$script:active=$null
 $newHashes=Hashes (Join-Path $new.candidate_directory 'data')
 $opaque=Join-Path $old.candidate_directory 'data/unknown/w35b-local-state'
 $original=[IO.File]::ReadAllBytes($opaque)
 try{
  [IO.File]::WriteAllBytes($opaque,[byte[]]($original+[byte]120))
  $null=Setup $newSetupInstalled 'Rollback' $false
 }finally{[IO.File]::WriteAllBytes($opaque,$original)}
 $rolled=Setup $newSetupInstalled 'Rollback'
 Require ($rolled.action -ceq 'rollback' -and $rolled.after.source_sha -ceq $OldSHA -and
  $rolled.live_armed -eq $false) 'W83_ROLLBACK_IDENTITY_INVALID'
 AssertHashes $oldHashes (Hashes (Join-Path $old.candidate_directory 'data')) 'W83_ROLLBACK_OLD_DATA'
 AssertHashes $newHashes (Hashes (Join-Path $new.candidate_directory 'data')) 'W83_ROLLBACK_NEW_DATA'
 Require ((Hash $unknown) -ceq $unknownHash) 'W83_UNKNOWN_ROOT_BYTES_AFTER_ROLLBACK'
 $oldAgain=Setup (Join-Path $oldMaint 'KTRADE-Setup.ps1') 'Inspect'
 Require ($oldAgain.source_sha -ceq $OldSHA) 'W83_ROLLED_BACK_MAINTENANCE_INVALID'
 $script:active=StartInstalled $oldMaint $oldAgain 'ROLLED_BACK'
 StopInstalled $script:active;$script:active=$null
 AssertHashes $newHashes (Hashes (Join-Path $new.candidate_directory 'data')) 'W83_RETAINED_NEW_DATA'
 Write-Output '::notice::W83_PREVIOUS_TO_CANDIDATE_REAL_INSTALLED_UPDATE_ROLLBACK=PASS'
 Write-Output '::notice::W83_NO_OWNER_DATA_NO_LIVE_NO_RELEASE=PASS'
}finally{
 $env:PATH=$savedPath
 if($null -ne $script:active){Write-Warning 'W83_ABORTED_WITH_OWNED_PROCESS: fail-closed ephemeral runner required; no automatic retry or takeover'}
}
