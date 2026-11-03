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
$NewSHA='50651c09f8367e66e2cdb51e69c552c866fc4313'
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
 if($label -ceq 'Indicator settings'){
  try{
   $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
   $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$label)
   $targets=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
   $rows=@()
   foreach($target in $targets){
    $r=$target.Current.BoundingRectangle
    $rows+=@{name=$target.Current.Name;type=$target.Current.ControlType.ProgrammaticName;enabled=$target.Current.IsEnabled;offscreen=$target.Current.IsOffscreen;left=$r.Left;top=$r.Top;width=$r.Width;height=$r.Height}
   }
   Write-Host ('SETTINGS_NATIVE_BUTTON_DIAGNOSTIC='+(@{count=$targets.Count;controls=$rows}|ConvertTo-Json -Compress -Depth 5))
  }catch{}
 }
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


function SettingsNumeric([object]$shell,[string]$label,[int]$seconds=35){
 $until=(Get-Date).AddSeconds($seconds)
 do{
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
  $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  foreach($node in $nodes){
   try{
    if($node.Current.IsOffscreen -or !$node.Current.IsEnabled -or $node.Current.Name -cne $label){continue}
    if($node.Current.ControlType -notin @([System.Windows.Automation.ControlType]::Edit,[System.Windows.Automation.ControlType]::Spinner)){continue}
    $value=$null
    if($node.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)){
     return [pscustomobject]@{node=$node;value=[System.Windows.Automation.ValuePattern]$value;range=$null}
    }
    $range=$null
    if($node.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern,[ref]$range)){
     return [pscustomobject]@{node=$node;value=$null;range=[System.Windows.Automation.RangeValuePattern]$range}
    }
   }catch{}
  }
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $until)
 throw ('SETTINGS_NATIVE_NUMERIC_CONTROL_NOT_OBSERVED_'+$label)
}
function SettingsNumber([object]$control){
 if($null -ne $control.value){return [double]::Parse($control.value.Current.Value,[Globalization.CultureInfo]::InvariantCulture)}
 return [double]$control.range.Current.Value
}
function SetSettingsNumber([object]$shell,[string]$label,[double]$number){
 $control=SettingsNumeric $shell $label
 if($null -ne $control.value){$control.value.SetValue($number.ToString('G17',[Globalization.CultureInfo]::InvariantCulture))}
 else{$control.range.SetValue($number)}
 Require ([Math]::Abs((SettingsNumber (SettingsNumeric $shell $label))-$number) -lt 0.000000001) 'SETTINGS_NATIVE_FIELD_DID_NOT_ACCEPT_EXACT_VALUE'
}
function AssertSettingsFields([object]$shell,[hashtable]$expected){
 foreach($label in $expected.Keys){
  Require ([Math]::Abs((SettingsNumber (SettingsNumeric $shell $label))-[double]$expected[$label]) -lt 0.000000001) ('SETTINGS_NATIVE_FIELD_VALUE_DRIFT_'+$label)
 }
}
function SettingsCatalogApply([object]$shell,[string]$name){
 ClickUI $shell 'Indicators';ClickUI $shell 'Technicals'
 $search=FindUI $shell 'Search indicator catalog' $false 20
 $value=$null
 Require ($search.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$value)) 'SETTINGS_NATIVE_CATALOG_SEARCH_UNAVAILABLE'
 ([System.Windows.Automation.ValuePattern]$value).SetValue($name)
 ClickUI $shell ('Apply '+$name)
 # Wait for the real catalog to close after its asynchronous Go Apply.
 # An already-enabled settings button may otherwise be covered by that modal.
 $until=(Get-Date).AddSeconds(35);$closed=$false
 do{
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
  $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,('Apply '+$name))
  $buttons=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
  $visible=0
  foreach($button in $buttons){try{if(!$button.Current.IsOffscreen){$visible++}}catch{}}
  if($visible -eq 0){$closed=$true;break}
  Start-Sleep -Milliseconds 200
 }while((Get-Date) -lt $until)
 Require $closed 'SETTINGS_CATALOG_ASYNC_APPLY_DID_NOT_CLOSE'
 ClickUI $shell 'Indicator settings'
}
function SettingsCatalogCode([string]$origin,[string]$name){
 $html=(Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/chart') -TimeoutSec 15).Content
 $pattern="(?s)'"+[regex]::Escape($name)+"':\s*"+[char]96+"(?<source>[^"+[char]96+"]+)"+[char]96
 $match=[regex]::Match($html,$pattern)
 Require $match.Success 'SETTINGS_ORIGINAL_SERVED_CATALOG_SOURCE_NOT_FOUND'
 return $match.Groups['source'].Value.Replace(([string][char]13+[string][char]10),[string][char]10).Replace([string][char]13,[string][char]10)
}
function SettingsRead([string]$origin,[string]$source){
 $body=@{code=$source;action='read'}|ConvertTo-Json -Compress -Depth 6
 $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/input-settings') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 20
 Require ($record.success -eq $true -and $record.source_sha256 -cmatch '^[a-f0-9]{64}$') 'SETTINGS_ORIGINAL_GO_READ_FAILED'
 return $record
}
function SettingsValuesMatch([object]$actual,[hashtable]$expected){
 if(@($actual.PSObject.Properties).Count -ne $expected.Count){return $false}
 foreach($key in $expected.Keys){
  $property=$actual.PSObject.Properties[$key]
  if($null -eq $property -or [Math]::Abs([double]$property.Value-[double]$expected[$key]) -ge 0.000000001){return $false}
 }
 return $true
}
function SettingsWorkspace([string]$origin,[string]$source,[hashtable]$expected){
 $lastDiagnostic=@{observed=$false}
 $until=(Get-Date).AddSeconds(35)
 do{
  try{
   $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
   # workspaceSnapshot uses inputs,omitempty: an absent field means the
   # unchanged script defaults, not a failed request or an invented value.
   $property=$record.workspace.PSObject.Properties['inputs']
   $actual=[pscustomobject]@{}
   if($null -ne $property){$actual=$property.Value}
   # Identity diagnostics only; retain strict equality and unchanged timeout.
   # No source text, broker credentials, or owner data are emitted.
   $observedCode=[string]$record.workspace.code
   $requestedCode=$source.Trim()
   $hashExpected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($requestedCode))).ToLowerInvariant()
   $hashObserved=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($observedCode))).ToLowerInvariant()
   $lastDiagnostic=@{observed=$true;success=$record.success;source_equal=($observedCode -ceq $requestedCode);expected_keys=@($expected.Keys);actual_keys=@($actual.PSObject.Properties|ForEach-Object {$_.Name});inputs_property_present=($null -ne $property);expected_source_sha256=$hashExpected;actual_source_sha256=$hashObserved;expected_code_chars=$requestedCode.Length;actual_code_chars=$observedCode.Length}
   if($record.success -eq $true -and $record.workspace.code -ceq $source.Trim() -and (SettingsValuesMatch $actual $expected)){return}
  }catch{}
  Start-Sleep -Milliseconds 300
 }while((Get-Date) -lt $until)
 Write-Host ('SETTINGS_WORKSPACE_OBSERVED_DIAGNOSTIC='+($lastDiagnostic|ConvertTo-Json -Compress -Depth 4))
 throw 'SETTINGS_ACTUAL_GO_OVERLAY_INPUT_BINDINGS_NOT_OBSERVED'
}
function SettingsDisarmed([string]$origin){
 $cap=Invoke-RestMethod -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 5
 Require ($cap.paper_orders_enabled -eq $false -and $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false) 'SETTINGS_CHANGED_TRADING_AUTHORITY'
}
function MarkerCaptureChart([object]$shell,[string]$phase){
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
  Write-Host ('PINE_MARKER_SCREEN_CAPTURE='+(@{phase=$phase;left=$rect.Left;top=$rect.Top;width=$rect.Width;height=$rect.Height;png_sha256=$digest;scope='captured_original_visible_Price_chart_drawing_surface';retained_screenshot=$false}|ConvertTo-Json -Compress))
  return [pscustomobject]@{bitmap=$bmp;rect=$rect;digest=$digest}
 }catch{$bmp.Dispose();throw}
}

# Bounded synthetic-source visual check through the real owned Monaco editor,
# actual installed Go HTTP, and physical desktop capture. No DOM/JS injection.
function MarkerColorCounts([System.Drawing.Bitmap]$bitmap){
 $up=[long]0;$down=[long]0
 for($y=0;$y -lt $bitmap.Height;$y++){
  for($x=0;$x -lt $bitmap.Width;$x++){
   $pixel=$bitmap.GetPixel($x,$y)
   if($pixel.R -le 20 -and $pixel.G -ge 240 -and $pixel.B -ge 240){$up++}
   if($pixel.R -ge 240 -and $pixel.G -ge 240 -and $pixel.B -le 20){$down++}
  }
 }
 return @($up,$down)
}
function MarkerSource([int]$version,[bool]$enabled){
 $up='false';$down='false'
 if($enabled){$up='bar_index % 10 == 0';$down='bar_index % 10 == 5'}
 return ('//@version='+$version+"`n"+'indicator("Native original shape transport",overlay=true)'+"`n"+'plot(close,"Reference",color=color.white)'+"`n"+'plotshape('+$up+',style=shape.triangleup,location=location.belowbar,color=color.aqua,text="Up confirmed")'+"`n"+'plotshape('+$down+',style=shape.triangledown,location=location.abovebar,color=color.yellow,text="Down confirmed")')
}
# Verify original Monaco source by copying selected editor content through
# the native OS keyboard path. No DOM or JS injection; synthetic Pine only.
function PineOwnedEditorSourceProof([object]$shell,[string]$source){
 $editor=Wait-W32EUI $shell 'Pine source editor'
 Require ($editor.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
  ([System.Windows.Automation.AutomationElement]::FocusedElement).Equals($editor)) 'PINE_ORIGINAL_EDITOR_FOCUS_REQUIRED'
 Shortcut-W32E 0x41
 Shortcut-W32E 0x43
 Start-Sleep -Milliseconds 250
 $ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
 $code='Add-Type -AssemblyName System.Windows.Forms;[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([Windows.Forms.Clipboard]::GetText()))'
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $b64=((& $ps51 -NoProfile -STA -EncodedCommand $encoded|Out-String).Trim())
 Require ($LASTEXITCODE -eq 0 -and $b64 -cmatch '^[A-Za-z0-9+/]+={0,2}$') 'PINE_ORIGINAL_EDITOR_COPYBACK_UNAVAILABLE'
 try{$actual=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))}catch{throw 'PINE_ORIGINAL_EDITOR_COPYBACK_INVALID'}
 $crlf=[string][char]13+[string][char]10
 $lf=[string][char]10
 $cr=[string][char]13
 $actual=$actual.Replace($crlf,$lf).Replace($cr,$lf)
 $expected=$source.Replace($crlf,$lf).Replace($cr,$lf)
 $hashActual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($actual))).ToLowerInvariant()
 $hashExpected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($expected))).ToLowerInvariant()
 Write-Host ('PINE_ORIGINAL_MONACO_NATIVE_COPYBACK='+(@{actual_sha256=$hashActual;expected_sha256=$hashExpected;actual_chars=$actual.Length;expected_chars=$expected.Length;identical=($actual -ceq $expected);scope='native_focused_editor_clipboard_readback_no_source_disclosure_or_DOM_injection'}|ConvertTo-Json -Compress))
 Require ($actual -ceq $expected) 'PINE_ORIGINAL_MONACO_EDITOR_SOURCE_IDENTITY_FAILED'
}

function MarkerPhysicalApply([object]$shell,[string]$origin,[string]$source){
 ClickUI $shell 'Pine Editor'
 Set-W32EPine $shell $source
 PineOwnedEditorSourceProof $shell $source
 ClickUI $shell 'Compile'
 $null=FindUI $shell 'Compiled. Not applied or started.' $false 30
 ClickUI $shell 'Add to chart'
 SettingsWorkspace $origin $source @{}
 $null=FindUI $shell 'Pine plots applied.' $false 40
 ClickUI $shell 'Collapse'
}
function MarkerOriginalHTTP([string]$origin,[string]$source,[bool]$enabled){
 $workspace=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
 Require ($workspace.success -eq $true -and $workspace.workspace.code -ceq $source.Trim()) 'MARKER_ACTUAL_NATIVE_SOURCE_NOT_APPLIED'
 $body=@{code=$source;symbol=$workspace.workspace.symbol;timeframe=$workspace.workspace.timeframe;limit=300}|ConvertTo-Json -Compress
 $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/overlay') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 25
 Require ($record.success -eq $true -and @($record.candles).Count -ge 30) 'MARKER_ORIGINAL_INSTALLED_HTTP_REFUSED'
 $expected=0;$up=0;$down=0
 for($i=0;$i -lt @($record.candles).Count;$i++){if($enabled -and ($i%10 -eq 0 -or $i%10 -eq 5)){$expected++}}
 Require (@($record.shapes).Count -eq $expected) 'MARKER_ORIGINAL_INSTALLED_HTTP_COUNT_MISMATCH'
 foreach($shape in @($record.shapes)){
  $bar=[int]$shape.bar_index
  Require ($bar -ge 0 -and $bar -lt @($record.candles).Count) 'MARKER_HTTP_BAR_OUT_OF_RESPONSE'
  $candle=$record.candles[$bar]
  if($bar%10 -eq 0){
   Require ($shape.style -ceq 'triangleup' -and $shape.location -ceq 'belowbar' -and $shape.text -ceq 'Up confirmed' -and $shape.color -ceq '#00FFFF' -and [Math]::Abs([double]$shape.price-[double]$candle.low) -lt 0.00000001) 'MARKER_HTTP_UP_PRESENTATION_LOST'
   $up++
  }elseif($bar%10 -eq 5){
   Require ($shape.style -ceq 'triangledown' -and $shape.location -ceq 'abovebar' -and $shape.text -ceq 'Down confirmed' -and $shape.color -ceq '#FFFF00' -and [Math]::Abs([double]$shape.price-[double]$candle.high) -lt 0.00000001) 'MARKER_HTTP_DOWN_PRESENTATION_LOST'
   $down++
  }else{throw 'MARKER_HTTP_CONFIRMATION_BAR_MISMATCH'}
 }
 return @{candles=@($record.candles).Count;shapes=@($record.shapes).Count;up=$up;down=$down;actual_response_bar_price_and_style_checked=$true}
}
function MarkerNative([object]$shell,[string]$origin){
 $node=FindUI $shell 'Price chart drawing surface' $false 20
 $bounds=$node.Current.BoundingRectangle
 $closedRect=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($bounds.Left),[int][Math]::Ceiling($bounds.Top),[int][Math]::Floor($bounds.Width),[int][Math]::Floor($bounds.Height))
 foreach($version in @(5,6)){
  $baselineSource=MarkerSource $version $false
  MarkerPhysicalApply $shell $origin $baselineSource
  $baselineHTTP=MarkerOriginalHTTP $origin $baselineSource $false
  W94BWaitOriginalChartBounds $shell $closedRect
  $baseline=MarkerCaptureChart $shell ('MARKER_BASELINE_V'+$version)
  $after=$null
  try{
   $baselineColors=@(MarkerColorCounts $baseline.bitmap)
   Require ($baselineColors.Count -eq 2 -and $baselineColors[0] -le 2 -and $baselineColors[1] -le 2) 'MARKER_BASELINE_NOT_VISUALLY_CLEAR'
   $markedSource=MarkerSource $version $true
   MarkerPhysicalApply $shell $origin $markedSource
   $markedHTTP=MarkerOriginalHTTP $origin $markedSource $true
   W94BWaitOriginalChartBounds $shell $baseline.rect
   $after=MarkerCaptureChart $shell ('MARKER_APPLIED_V'+$version)
   $markedColors=@(MarkerColorCounts $after.bitmap)
   # Native chart pixels can arrive after the Go HTTP response and editor
   # geometry have settled. Sample the unchanged original screen up to five
   # times. Preserve every original hard pixel/geometry/negative requirement.
   # If all observations fail, fail closed and print counts to distinguish
   # delayed WebView presentation from off-viewport marker content.
   $renderVerified=$false;$observations=@()
   for($sample=1;$sample -le 5;$sample++){
    $renderVerified=($baseline.rect.Equals($after.rect) -and $markedColors.Count -eq 2 -and
      $markedColors[0] -ge 40 -and $markedColors[1] -ge 40 -and $baseline.digest -cne $after.digest)
    $observations+=@{sample=$sample;up_pixels=$markedColors[0];down_pixels=$markedColors[1];
      identical_bounds=$baseline.rect.Equals($after.rect);same_sha=($baseline.digest -ceq $after.digest)}
    if($renderVerified -or $sample -eq 5){break}
    $after.bitmap.Dispose();$after=$null
    Start-Sleep -Milliseconds 750
    W94BWaitOriginalChartBounds $shell $baseline.rect
    $after=MarkerCaptureChart $shell ('MARKER_APPLIED_V'+$version+'_RECHECK_'+$sample)
    $markedColors=@(MarkerColorCounts $after.bitmap)
   }
   Write-Host ('PINE_MARKER_NATIVE_SCREEN_RENDER_DIAGNOSTIC='+(@{version=$version;observations=$observations;original_go_shape_count=$markedHTTP.shapes;scope='original_native_pixels_unchanged_thresholds_no_JS_injection'}|ConvertTo-Json -Depth 5 -Compress))
   Require $renderVerified 'MARKER_BOTH_PHYSICAL_ARROW_COLORS_NOT_OBSERVED'
   SettingsDisarmed $origin
   Write-Host ('PINE_MARKER_ACTUAL_NATIVE_COLOR_AND_ORIGINAL_HTTP='+(@{version=$version;baseline_http=$baselineHTTP;marked_http=$markedHTTP;baseline_up_pixels=$baselineColors[0];baseline_down_pixels=$baselineColors[1];marked_up_pixels=$markedColors[0];marked_down_pixels=$markedColors[1];identical_bounds=$true;baseline_sha256=$baseline.digest;marked_sha256=$after.digest;physical_editor_compile_and_apply=$true;scope='bounded_synthetic_source_actual_Go_bar_price_style_and_both_native_marker_colors_not_full_RSI_pixel_oracle'}|ConvertTo-Json -Depth 5 -Compress))
  }finally{if($null -ne $after){$after.bitmap.Dispose()};$baseline.bitmap.Dispose()}
 }
 Write-Host '::notice::PINE_MARKER_NATIVE_ORIGINAL_V5_V6_HTTP_AND_PHYSICAL_BOTH_ARROW_COLOR_OBSERVATION=PASS'
}

function GuideCapturePane([object]$shell,[string]$phase){
 $node=GuidePane $shell
 $r=$node.Current.BoundingRectangle
 $outer=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require (!$r.IsEmpty -and $r.Width -ge 220 -and $r.Height -ge 90 -and
  $r.Left -ge $outer.Left -and $r.Right -le $outer.Right -and
  $r.Top -ge $outer.Top -and $r.Bottom -le $outer.Bottom) 'W94B_PRICE_CHART_UIA_GEOMETRY_INVALID'
 $rect=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
 Require ($rect.Width -ge 220 -and $rect.Height -ge 90 -and $rect.Width -le 3840 -and $rect.Height -le 2160) 'W94B_CHART_SCREEN_RECT_OUT_OF_SCOPE'
 $bmp=[System.Drawing.Bitmap]::new($rect.Width,$rect.Height,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
 try{
  $g=[System.Drawing.Graphics]::FromImage($bmp)
  try{$g.CopyFromScreen($rect.Location,[System.Drawing.Point]::Empty,$rect.Size)}finally{$g.Dispose()}
  $stream=[IO.MemoryStream]::new()
  try{
   $bmp.Save($stream,[System.Drawing.Imaging.ImageFormat]::Png)
   $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream.ToArray())).ToLowerInvariant()
  }finally{$stream.Dispose()}
  Write-Host ('PINE_HLINE_SCREEN_CAPTURE='+(@{phase=$phase;left=$rect.Left;top=$rect.Top;width=$rect.Width;height=$rect.Height;png_sha256=$digest;scope='captured_original_visible_Pine_indicator_pane_region';retained_screenshot=$false}|ConvertTo-Json -Compress))
  return [pscustomobject]@{bitmap=$bmp;rect=$rect;digest=$digest}
 }catch{$bmp.Dispose();throw}
}


# Original RSI hline rendering through owned native editor controls and pixels.
function GuidePane([object]$shell){
 $until=[DateTime]::UtcNow.AddSeconds(20)
 do{
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle)
  $condition=[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'Pine indicator pane')
  $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
  $visible=@($nodes|Where-Object {!$_.Current.IsOffscreen -and !$_.Current.BoundingRectangle.IsEmpty})
  if($visible.Count -eq 1){return $visible[0]}
  Start-Sleep -Milliseconds 200
 }while([DateTime]::UtcNow -lt $until)
 throw 'HLINE_EXACT_VISIBLE_OWNED_PINE_PANE_NOT_FOUND'
}
function GuideWaitStable([object]$shell,[object]$expected=$null,[object]$closedChart=$null){
 # A briefly stationary intermediate resize is not the closed editor geometry.
 # Keep the original rectangle as the comparison contract; never crop/rebase it.
 $until=[DateTime]::UtcNow.AddSeconds(20);$last=$null;$stable=0;$actual=$null
 do{
  $node=GuidePane $shell;$r=$node.Current.BoundingRectangle
  $actual=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
  $matches=($null -eq $expected -or $actual.Equals($expected))
  if($null -ne $closedChart){$matches=$matches -and $actual.Left -eq $closedChart.Left -and $actual.Width -eq $closedChart.Width}
  if($matches -and $null -ne $last -and $actual.Equals($last)){$stable++}else{$stable=0}
  if($stable -ge 7){return $actual}
  $last=$actual;Start-Sleep -Milliseconds 150
 }while([DateTime]::UtcNow -lt $until)
 Write-Host ('HLINE_PANE_GEOMETRY_TIMEOUT='+(@{actual=[string]$actual;expected=[string]$expected;closed_chart=[string]$closedChart;stable_observations=$stable}|ConvertTo-Json -Compress))
 throw 'HLINE_PINE_PANE_DID_NOT_RETURN_TO_ORIGINAL_CLOSED_EDITOR_GEOMETRY'
}
function GuideGrayRows([System.Drawing.Bitmap]$bitmap){
 $threshold=[Math]::Max(40,[int][Math]::Floor($bitmap.Width*0.18));$rows=@();$last=$null
 for($y=0;$y -lt $bitmap.Height;$y++){
  $count=0
  for($x=0;$x -lt $bitmap.Width;$x+=2){
   $p=$bitmap.GetPixel($x,$y)
   $minimum=[Math]::Min($p.R,[Math]::Min($p.G,$p.B));$maximum=[Math]::Max($p.R,[Math]::Max($p.G,$p.B))
   # Include native antialiasing of CSS gray on the original dark pane;
   # original blue plots and dark colored grid lines are outside this band.
   if($minimum -ge 65 -and $maximum -le 145 -and $maximum-$minimum -le 12){$count++}
  }
  if($count -ge $threshold){
   if($null -ne $last -and $y-$last.last_row -le 2){$last.last_row=$y;$last.max_samples=[Math]::Max($last.max_samples,$count)}
   else{$last=[pscustomobject]@{first_row=$y;last_row=$y;max_samples=$count;threshold=$threshold};$rows+=$last}
  }
 }
 return $rows
}
function GuideOriginalHTTP([string]$origin,[string]$source,[bool]$expectedGuides){
 $workspace=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
 Require ($workspace.success -eq $true -and $workspace.workspace.code -ceq $source.Trim()) 'HLINE_NATIVE_APPLIED_SOURCE_MISMATCH'
 $body=@{code=$source;symbol=$workspace.workspace.symbol;timeframe=$workspace.workspace.timeframe;limit=300}|ConvertTo-Json -Compress
 $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/overlay') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 25
 Require ($record.success -eq $true -and $record.overlay -eq $false -and @($record.candles).Count -ge 30) 'HLINE_ORIGINAL_INSTALLED_HTTP_REFUSED'
 $lines=@($record.hlines)
 if(!$expectedGuides){Require ($lines.Count -eq 0) 'HLINE_EMPTY_ORIGINAL_HTTP_NOT_CLEAR';return @()}
 Require ($lines.Count -eq 3) 'HLINE_THREE_ORIGINAL_RSI_GUIDES_REQUIRED'
 $levels=@(70,30,50);$titles=@('Overbought','Oversold','Middle')
 for($i=0;$i -lt 3;$i++){Require ($lines[$i].price -eq $levels[$i] -and $lines[$i].title -ceq $titles[$i] -and $lines[$i].color -ceq 'gray' -and $lines[$i].linestyle -ceq 'dashed' -and $lines[$i].linewidth -eq 1) 'HLINE_ORIGINAL_LEVEL_STYLE_OR_TITLE_LOST'}
 return $levels
}
function GuideNative([object]$shell,[string]$origin){
 $closedNode=FindUI $shell 'Price chart drawing surface' $false 20
 $r=$closedNode.Current.BoundingRectangle
 $closedChart=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
 $catalog=SettingsCatalogCode $origin 'RSI Divergence'
 Require ([regex]::Matches($catalog,'(?m)^hline\(').Count -eq 3) 'HLINE_EXACT_ORIGINAL_RSI_SOURCE_REQUIRED'
 foreach($version in @(5,6)){
  $source=$catalog.Replace('//@version=5',('//@version='+$version+[string][char]10+'// Native horizontal guide observation'))
  $baselineSource=[regex]::Replace($source,'(?m)^hline\([^\r\n]*\)\r?\n?','')
  MarkerPhysicalApply $shell $origin $baselineSource
  $null=FindUI $shell 'Pine: RSI' $false 20
  $null=GuideOriginalHTTP $origin $baselineSource $false
  W94BWaitOriginalChartBounds $shell $closedChart
  $null=GuideWaitStable $shell $null $closedChart
  $baseline=GuideCapturePane $shell ('HLINE_BASELINE_V'+$version);$after=$null;$removed=$null
  try{
   $beforeRows=@(GuideGrayRows $baseline.bitmap)
   Require ($beforeRows.Count -eq 0) 'HLINE_BASELINE_HAS_UNEXPECTED_GRAY_HORIZONTAL_ROWS'
   MarkerPhysicalApply $shell $origin $source
   $levels=@(GuideOriginalHTTP $origin $source $true)
   W94BWaitOriginalChartBounds $shell $closedChart
   $null=GuideWaitStable $shell $baseline.rect $closedChart
   $after=GuideCapturePane $shell ('HLINE_APPLIED_V'+$version)
   $afterRows=@(GuideGrayRows $after.bitmap)
   Require ($after.rect.Equals($baseline.rect) -and $afterRows.Count -eq 3 -and $after.digest -cne $baseline.digest) 'HLINE_THREE_ACTUAL_NATIVE_GRAY_GUIDES_NOT_OBSERVED'
   MarkerPhysicalApply $shell $origin $baselineSource
   $null=GuideOriginalHTTP $origin $baselineSource $false
   W94BWaitOriginalChartBounds $shell $closedChart
   $null=GuideWaitStable $shell $baseline.rect $closedChart
   $removed=GuideCapturePane $shell ('HLINE_REMOVED_V'+$version)
   $removedRows=@(GuideGrayRows $removed.bitmap)
   Require ($removed.rect.Equals($baseline.rect) -and $removedRows.Count -eq 0) 'HLINE_NATIVE_REAPPLY_DID_NOT_REMOVE_GUIDES'
   SettingsDisarmed $origin
   Write-Host ('PINE_HLINE_ACTUAL_NATIVE_RSI_GUIDE_ROWS='+(@{version=$version;actual_original_go_levels=$levels;baseline_rows=$beforeRows;applied_rows=$afterRows;removed_rows=$removedRows;physical_editor_compile_apply_and_remove=$true;identical_bounds=$true;baseline_sha256=$baseline.digest;applied_sha256=$after.digest;removed_sha256=$removed.digest;scope='original_Go_RSI_levels_and_native_horizontal_gray_row_presence_removal_not_independent_numeric_to_pixel_position_oracle'}|ConvertTo-Json -Compress -Depth 5))
  }finally{if($null -ne $removed){$removed.bitmap.Dispose()};if($null -ne $after){$after.bitmap.Dispose()};$baseline.bitmap.Dispose()}
 }
 Write-Host '::notice::PINE_HLINE_NATIVE_ORIGINAL_V5_V6_RSI_THREE_LEVELS_PHYSICAL_GUIDE_ROWS_AND_REMOVAL=PASS'
}

function GuideOnlyNative([object]$shell,[string]$origin){
 foreach($version in @(5,6)){
  $source=('//@version='+$version+"`n"+'indicator("Original guide-only pane",overlay=false)'+"`n"+'hline(70,"Overbought")'+"`n"+'hline(30,"Oversold")'+"`n"+'hline(50,"Middle")')
  MarkerPhysicalApply $shell $origin $source
  $expected='Pine: Overbought, Oversold, Middle'
  $caption=FindUI $shell $expected $false 25
  Require ($caption.Current.Name -ceq $expected) 'GUIDE_ONLY_ACTUAL_PANE_CAPTION_NOT_OBSERVED'
  $levels=@(GuideOriginalHTTP $origin $source $true)
  $workspace=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
  Require ($workspace.success -eq $true -and $workspace.workspace.code -ceq $source.Trim()) 'GUIDE_ONLY_APPLIED_SOURCE_MISMATCH'
  $body=@{code=$source;symbol=$workspace.workspace.symbol;timeframe=$workspace.workspace.timeframe;limit=300}|ConvertTo-Json -Compress
  $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/overlay') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 25
  $panes=@($record.pane_model)
  Require ($record.success -eq $true -and @($record.plots).Count -eq 0 -and $panes.Count -eq 1 -and $panes[0].overlay -eq $false -and @($panes[0].plots).Count -eq 0) 'GUIDE_ONLY_ORIGINAL_GO_INVENTED_PLOT_OR_PANE'
  $null=GuideWaitStable $shell
  $frame=GuideCapturePane $shell ('GUIDE_ONLY_V'+$version)
  try{
   $rows=@(GuideGrayRows $frame.bitmap)
   Require ($rows.Count -eq 3) 'GUIDE_ONLY_THREE_ACTUAL_NATIVE_LEVELS_NOT_VISIBLE'
   SettingsDisarmed $origin
   Write-Host ('PINE_GUIDE_ONLY_NATIVE_ACTUAL='+(@{version=$version;actual_pane_caption=$caption.Current.Name;original_go_plot_count=@($record.plots).Count;original_go_model_plot_count=@($panes[0].plots).Count;original_go_levels=$levels;actual_guide_rows=$rows;native_pane_sha256=$frame.digest;physical_editor_compile_and_apply=$true;scope='original_Go_guide_only_metadata_actual_native_caption_and_gray_row_presence_not_independent_numeric_to_pixel_oracle'}|ConvertTo-Json -Compress -Depth 5))
  }finally{$frame.bitmap.Dispose()}
 }
 Write-Host '::notice::PINE_GUIDE_ONLY_NATIVE_ORIGINAL_V5_V6_ZERO_PLOTS_THREE_LEVELS_AND_ACTUAL_PANE_CAPTION=PASS'
}

# Original label transport and native color observation, not a price/glyph oracle.
function LabelOriginalHTTP([string]$origin,[string]$source,[bool]$enabled){
 $workspace=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
 Require ($workspace.success -eq $true -and $workspace.workspace.code -ceq $source.Trim()) 'LABEL_ACTUAL_NATIVE_SOURCE_NOT_APPLIED'
 $body=@{code=$source;symbol=$workspace.workspace.symbol;timeframe=$workspace.workspace.timeframe;limit=300}|ConvertTo-Json -Compress
 $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/overlay') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 25
 Require ($record.success -eq $true -and @($record.candles).Count -ge 30) 'LABEL_ORIGINAL_INSTALLED_HTTP_REFUSED'
 $labels=@($record.labels);$expected=0;$seen=@{}
 if($enabled){for($i=0;$i -lt @($record.candles).Count;$i++){if($i%10 -eq 0){$expected++}}}
 Require ($labels.Count -eq $expected) 'LABEL_ORIGINAL_NATIVE_HTTP_COUNT_MISMATCH'
 foreach($label in $labels){
  $bar=[int]$label.bar_index
  Require ($bar -ge 0 -and $bar -lt @($record.candles).Count -and $bar%10 -eq 0 -and !$seen.ContainsKey($bar)) 'LABEL_ORIGINAL_NATIVE_BAR_INDEX_MISMATCH'
  $seen[$bar]=$true
  Require ($label.xloc -ceq 'bar_index' -and $label.yloc -ceq 'belowbar' -and $label.style -ceq 'label_up' -and $label.text -ceq 'Native original label' -and $label.color -ieq '#00ffff' -and $label.deleted -eq $false -and $label.pane -ceq 'price') 'LABEL_ORIGINAL_NATIVE_METADATA_LOST'
 }
 return @{candles=@($record.candles).Count;labels=$labels.Count;original_go_bar_style_pane_color_and_text_checked=$true}
}
function LabelNative([object]$shell,[string]$origin){
 $node=FindUI $shell 'Price chart drawing surface' $false 20;$r=$node.Current.BoundingRectangle
 $closedRect=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($r.Left),[int][Math]::Ceiling($r.Top),[int][Math]::Floor($r.Width),[int][Math]::Floor($r.Height))
 foreach($version in @(5,6)){
  $base=('//@version='+$version+"`n"+'indicator("Native label response",overlay=true)'+"`n"+'plot(close,"Reference",color=color.white)')
  MarkerPhysicalApply $shell $origin $base;$beforeHTTP=LabelOriginalHTTP $origin $base $false
  W94BWaitOriginalChartBounds $shell $closedRect
  $before=MarkerCaptureChart $shell ('LABEL_BASELINE_V'+$version);$after=$null
  try{
   $beforeColors=@(MarkerColorCounts $before.bitmap)
   Require ($beforeColors[0] -le 2) 'LABEL_NATIVE_BASELINE_HAS_CYAN_MARKERS'
   $source=$base+"`n"+'if bar_index % 10 == 0'+"`n"+'    label.new(bar_index,low,"Native original label",yloc=yloc.belowbar,color=color.aqua,style=label.style_label_up)'
   MarkerPhysicalApply $shell $origin $source;$afterHTTP=LabelOriginalHTTP $origin $source $true
   W94BWaitOriginalChartBounds $shell $before.rect
   $after=MarkerCaptureChart $shell ('LABEL_APPLIED_V'+$version);$afterColors=@(MarkerColorCounts $after.bitmap)
   Require ($before.rect.Equals($after.rect) -and $afterColors[0] -ge 40 -and $before.digest -cne $after.digest) 'LABEL_NATIVE_ORIGINAL_CYAN_MARKERS_NOT_OBSERVED'
   SettingsDisarmed $origin
   Write-Host ('PINE_LABEL_ACTUAL_NATIVE_COLOR_AND_ORIGINAL_HTTP='+(@{version=$version;baseline_http=$beforeHTTP;applied_http=$afterHTTP;baseline_cyan_pixels=$beforeColors[0];applied_cyan_pixels=$afterColors[0];identical_bounds=$true;physical_editor_compile_and_apply=$true;baseline_sha256=$before.digest;applied_sha256=$after.digest;scope='bounded_original_Go_label_metadata_and_native_cyan_observation_not_independent_label_time_price_glyph_or_pane_pixel_oracle'}|ConvertTo-Json -Depth 5 -Compress))
  }finally{if($null -ne $after){$after.bitmap.Dispose()};$before.bitmap.Dispose()}
 }
 Write-Host '::notice::PINE_LABEL_NATIVE_ORIGINAL_V5_V6_HTTP_AND_PHYSICAL_CYAN_OBSERVATION=PASS'
}

function SettingsWarm([object]$shell,[string]$origin){
 $script:settingsCases=@()
 foreach($case in @(
  @{name='Supertrend';fields=@{'ATR Period'=3;'Multiplier'=2.5};defaults=@{'ATR Period'=10;'Multiplier'=3};values=@{input_0=3;input_1=2.5}},
  @{name='RSI Divergence';fields=@{'RSI Period'=3};defaults=@{'RSI Period'=14};values=@{input_0=3}}
 )){
  $source=SettingsCatalogCode $origin $case.name
  $before=SettingsRead $origin $source
  Require ($before.persistence -ceq 'defaults' -and $before.revision -ceq 'missing') 'SETTINGS_FRESH_INSTALL_HAS_UNEXPECTED_PREFS'
  SettingsCatalogApply $shell $case.name
  AssertSettingsFields $shell $case.defaults
  if($case.name -ceq 'Supertrend'){
   SetSettingsNumber $shell 'ATR Period' 3.5
   ClickUI $shell 'Apply and save inputs'
   $null=FindUI $shell 'ATR Period requires a finite integer.' $false 15
   SettingsWorkspace $origin $source @{}
   $unchanged=SettingsRead $origin $source
   Require ($unchanged.revision -ceq 'missing') 'SETTINGS_INVALID_NATIVE_VALUE_WAS_PERSISTED'
  }
  foreach($label in $case.fields.Keys){SetSettingsNumber $shell $label $case.fields[$label]}
  ClickUI $shell 'Apply and save inputs'
  $null=FindUI $shell 'Inputs applied and saved.' $false 35
  AssertSettingsFields $shell $case.fields
  SettingsWorkspace $origin $source $case.values
  $saved=SettingsRead $origin $source
  Require ($saved.persistence -ceq 'saved' -and $saved.revision -cmatch '^[a-f0-9]{64}$' -and (SettingsValuesMatch $saved.values $case.values)) 'SETTINGS_PHYSICAL_SAVE_NOT_ACKNOWLEDGED_BY_ORIGINAL_GO'
  Write-Host ('PINE_SETTINGS_ACTUAL_NATIVE_WARM_SAVE='+(@{name=$case.name;source_sha256=$saved.source_sha256;revision=$saved.revision;values=$case.values}|ConvertTo-Json -Compress -Depth 4))
  $script:settingsCases+=@{name=$case.name;source=$source;fields=$case.fields;defaults=$case.defaults;values=$case.values;source_sha256=$saved.source_sha256;revision=$saved.revision}
  ClickUI $shell 'Close indicator settings'
 }
 SettingsDisarmed $origin
 Write-Host '::notice::PINE_SETTINGS_NATIVE_PHYSICAL_NUMERIC_APPLY_SAVE_VALIDATION_AND_SOURCE_CUSTODY=PASS'
}
function SettingsCold([object]$run,[string]$candidateDirectory){
 $ports=@(Get-NetTCPConnection -OwningProcess $run.enginePid -State Listen|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'SETTINGS_COLD_OWNED_LOOPBACK_REQUIRED'
 $origin='http://127.0.0.1:'+$ports[0].LocalPort
 Require ($script:settingsCases.Count -eq 2) 'SETTINGS_WARM_SAVE_PROOFS_REQUIRED'
 foreach($case in $script:settingsCases){
  $file=Join-Path $candidateDirectory ('data/pine-library/indicator-inputs-v1/'+$case.source_sha256+'.json')
  Ordinary $file $false
  Require ((Hash $file) -ceq $case.revision) 'SETTINGS_COLD_DISK_BYTES_NOT_PRESERVED'
  $before=SettingsRead $origin $case.source
  Require ($before.persistence -ceq 'saved' -and $before.revision -ceq $case.revision -and (SettingsValuesMatch $before.values $case.values)) 'SETTINGS_COLD_ORIGINAL_GO_PERSISTENCE_NOT_RESTORED'
  SettingsCatalogApply $run.shell $case.name
  AssertSettingsFields $run.shell $case.fields
  SettingsWorkspace $origin $case.source $case.values
  ClickUI $run.shell 'Reset input defaults'
  $null=FindUI $run.shell 'Defaults applied. Saved inputs cleared.' $false 35
  AssertSettingsFields $run.shell $case.defaults
  SettingsWorkspace $origin $case.source @{}
  $cleared=SettingsRead $origin $case.source
  Require ($cleared.persistence -ceq 'defaults' -and $cleared.revision -ceq 'missing' -and !(Test-Path -LiteralPath $file)) 'SETTINGS_EXPLICIT_RESET_NOT_PERSISTED'
  Write-Host ('PINE_SETTINGS_ACTUAL_NATIVE_COLD_RESTORE_RESET='+(@{name=$case.name;source_sha256=$case.source_sha256;saved_revision=$case.revision;restored_values=$case.values;default_fields=$case.defaults;disk_and_original_go_verified=$true;explicit_reset_verified=$true}|ConvertTo-Json -Compress -Depth 5))
  ClickUI $run.shell 'Close indicator settings'
 }
 SettingsDisarmed $origin
 Write-Host '::notice::PINE_SETTINGS_NATIVE_COLD_REOPEN_RESTORE_AND_EXPLICIT_DEFAULT_RESET=PASS'
}


# Bounded real desktop time-axis evidence. No JavaScript/DOM injection.
function ViewportAxis([object]$shell,[string]$phase){
 $frame=MarkerCaptureChart $shell ('VIEWPORT_'+$phase)
 $strip=$null
 try{
  $crop=[System.Drawing.Rectangle]::new(8,$frame.bitmap.Height-20,$frame.bitmap.Width-104,18)
  Require ($crop.Width -ge 120 -and $crop.Y -gt 0) 'VIEWPORT_AXIS_CAPTURE_BOUNDS_INVALID'
  $strip=$frame.bitmap.Clone($crop,[System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $ink=0
  for($y=0;$y -lt $strip.Height;$y++){
   for($x=0;$x -lt $strip.Width;$x++){
    $p=$strip.GetPixel($x,$y)
    if($p.R -ge 110 -and $p.R -le 240 -and $p.G -ge 110 -and $p.G -le 240 -and $p.B -ge 110 -and $p.B -le 240 -and [Math]::Abs([int]$p.R-[int]$p.G) -le 40 -and [Math]::Abs([int]$p.G-[int]$p.B) -le 40){$ink++}
   }
  }
  $frame.bitmap.Save((Join-Path $env:RUNNER_TEMP ('pr240-viewport-axis-'+$phase+'-context.png')),[System.Drawing.Imaging.ImageFormat]::Png)
  Require ($ink -ge 8) 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED'
  $file=Join-Path $env:RUNNER_TEMP ('pr240-viewport-axis-'+$phase+'.png')
  $strip.Save($file,[System.Drawing.Imaging.ImageFormat]::Png)
  $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  return @{phase=$phase;axis_sha256=$hash;label_pixels=$ink;width=$crop.Width;height=$crop.Height;left=$frame.rect.Left;top=$frame.rect.Top;chart_width=$frame.rect.Width;chart_height=$frame.rect.Height}
 }finally{if($null -ne $strip){$strip.Dispose()};$frame.bitmap.Dispose()}
}

# Real time-axis screenshot equality, with one narrowly bounded current-session
# calendar/last-bar label region. All other tick labels remain byte-for-byte
# identical, unlike real pan/zoom, which must change multiple separated ticks.
# This does not certify logical-range equality or relax the independent navigation
# positive control. It records every allowed single-label exception.
function ViewportAxisEquivalent([object]$reference,[object]$candidate,[string]$phase){
 if($reference.width -ne $candidate.width -or $reference.height -ne $candidate.height -or
    $reference.chart_width -ne $candidate.chart_width -or $reference.chart_height -ne $candidate.chart_height -or
    $reference.left -ne $candidate.left -or $reference.top -ne $candidate.top){return $false}
 if($reference.axis_sha256 -ceq $candidate.axis_sha256){return $true}
 $beforePath=Join-Path $env:RUNNER_TEMP ('pr240-viewport-axis-'+$reference.phase+'.png')
 $afterPath=Join-Path $env:RUNNER_TEMP ('pr240-viewport-axis-'+$candidate.phase+'.png')
 $before=[System.Drawing.Bitmap]::new($beforePath);$after=[System.Drawing.Bitmap]::new($afterPath)
 try{
  if($before.Width -ne $after.Width -or $before.Height -ne $after.Height -or $before.Width -ne $reference.width -or $before.Height -ne 18){return $false}
  $minX=$before.Width;$maxX=-1;$changes=0
  for($y=0;$y -lt $before.Height;$y++){
   for($x=0;$x -lt $before.Width;$x++){
    $a=$before.GetPixel($x,$y);$b=$after.GetPixel($x,$y)
    if([Math]::Abs([int]$a.R-[int]$b.R) -ge 8 -or
       [Math]::Abs([int]$a.G-[int]$b.G) -ge 8 -or
       [Math]::Abs([int]$a.B-[int]$b.B) -ge 8){
      $changes++;if($x -lt $minX){$minX=$x};if($x -gt $maxX){$maxX=$x}
    }
   }
  }
  # The observed original current-session date/time label is at 68-80%
  # of the axis. Moving the chart or changing other tick labels fails closed.
  if($changes -lt 1 -or $changes -gt 900 -or $minX -lt [Math]::Floor($before.Width*0.65) -or
     $maxX -gt [Math]::Ceiling($before.Width*0.84) -or
     ($maxX-$minX+1) -gt [Math]::Ceiling($before.Width*0.14)){return $false}
  # Count unchanged, separated actual text-label clusters outside the date
  # label, using the same ink predicate as the original ViewportAxis.
  $runs=0;$last=-100;$inkCols=0
  for($x=0;$x -lt $before.Width;$x++){
   if($x -ge ($minX-7) -and $x -le ($maxX+7)){continue}
   $ink=$false
   for($y=0;$y -lt $before.Height;$y++){
    $p=$before.GetPixel($x,$y)
    if($p.R -ge 110 -and $p.R -le 240 -and
       $p.G -ge 110 -and $p.G -le 240 -and
       $p.B -ge 110 -and $p.B -le 240 -and
       [Math]::Abs([int]$p.R-[int]$p.G) -le 40 -and
       [Math]::Abs([int]$p.G-[int]$p.B) -le 40){$ink=$true;break}
   }
   if($ink){
    if(($x-$last) -gt 6){$runs++}
    $inkCols++;$last=$x
   }
  }
  if($runs -lt 6 -or $inkCols -lt 60){return $false}
  Write-Host ('PINE_VIEWPORT_BOUNDED_SESSION_LABEL='+(@{phase=$phase;reference_sha256=$reference.axis_sha256;observed_sha256=$candidate.axis_sha256;changed_pixels=$changes;left=$minX;right=$maxX;axis_width=$before.Width;unchanged_label_clusters=$runs;outside_single_label_pixels_identical=$true;scope='single_original_native_session_calendar_label_only_not_pixel_to_logical_range_oracle'}|ConvertTo-Json -Compress))
  return $true
 }finally{$before.Dispose();$after.Dispose()}
}

function ViewportMouseAway([object]$shell){
 $r=[System.Windows.Automation.AutomationElement]::FromHandle($shell.MainWindowHandle).Current.BoundingRectangle
 Require ([W83Native]::SetCursorPos([int]($r.Left+12),[int]($r.Top+10))) 'VIEWPORT_MOUSE_AWAY_FAILED'
 Start-Sleep -Milliseconds 600
}
function ViewportStableAxis([object]$shell,[string]$phase){
 ViewportMouseAway $shell
 $a=ViewportAxis $shell ($phase+'_A')
 Start-Sleep -Milliseconds 350
 $b=ViewportAxis $shell $phase
 Require ($a.axis_sha256 -ceq $b.axis_sha256 -and $a.width -eq $b.width -and $a.height -eq $b.height) 'VIEWPORT_AXIS_NOT_STABLE_BEFORE_COMPARISON'
 return $b
}
function ViewportWaitStableLayout([object]$shell,[int]$expectedLeft,[int]$expectedWidth){
 # Pane height may legitimately change, but price time-axis width/left may not.
 # Wait until layout has stopped moving rather than comparing animation frames.
 $until=[DateTime]::UtcNow.AddSeconds(12);$stable=0;$previousHeight=-1
 do{
  $node=FindUI $shell 'Price chart drawing surface' $false 2
  $r=$node.Current.BoundingRectangle
  $left=[int][Math]::Ceiling($r.Left);$width=[int][Math]::Floor($r.Width);$height=[int][Math]::Floor($r.Height)
  if($left -eq $expectedLeft -and $width -eq $expectedWidth -and $height -eq $previousHeight){$stable++}else{$stable=0}
  if($stable -ge 3){return}
  $previousHeight=$height
  Start-Sleep -Milliseconds 160
 }while([DateTime]::UtcNow -lt $until)
 throw 'VIEWPORT_ORIGINAL_NATIVE_LAYOUT_DID_NOT_STABILIZE_AT_BASELINE_WIDTH'
}

function ViewportNative([object]$shell,[string]$origin){
 # Capture authoritative native chart geometry with the Pine panel closed,
 # before baseline Compile opens/reflows that panel.
 $initialNode=FindUI $shell 'Price chart drawing surface' $false 20
 $initialBox=$initialNode.Current.BoundingRectangle
 $initialRect=[System.Drawing.Rectangle]::new([int][Math]::Ceiling($initialBox.Left),[int][Math]::Ceiling($initialBox.Top),[int][Math]::Floor($initialBox.Width),[int][Math]::Floor($initialBox.Height))
 Require ($initialRect.Width -ge 220 -and $initialRect.Height -ge 140) 'VIEWPORT_ORIGINAL_NATIVE_PRICE_BOUNDS_INVALID'
 # Use the same syntactically qualified original v6 plot form already proven
 # by LabelNative, before adding wheel/drag viewport interaction.
 # Do not introduce a second unqualified bare-plot rendering control here.
 # Monaco and Go's native request normalize the submitted Pine source to LF;
 # build the exact identity now rather than comparing Windows CRLF to LF.
 $baselineSource=('//@version=6'+"`n"+'indicator("Viewport baseline",overlay=true)'+"`n"+'plot(close,"Reference",color=color.white)')
 $baselineBytes=[Text.Encoding]::UTF8.GetBytes($baselineSource)
 $baselineSha=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($baselineBytes)).ToLowerInvariant()
 Require ($baselineSha -ceq '592148256f1b16286315e345d830c74efa39dd96c580cdd1e970149ccb4578e2') 'VIEWPORT_INDEPENDENT_LF_BASELINE_SHA_DRIFT'
 MarkerPhysicalApply $shell $origin $baselineSource
 # The original editor close schedules a 300ms chart resize. Match the
 # exact pre-open bounds before taking two allegedly stable native captures.
 W94BWaitOriginalChartBounds $shell $initialRect
 $baseline=ViewportStableAxis $shell 'BASELINE'
 $node=FindUI $shell 'Price chart drawing surface' $false 20
 $r=$node.Current.BoundingRectangle
 $focused=[W83Native]::SetForegroundWindow($shell.MainWindowHandle)
 Require ($focused -or [W83Native]::GetForegroundWindow() -eq $shell.MainWindowHandle) 'VIEWPORT_OWNED_FOREGROUND_FAILED'
 $x=[int]($r.Left+$r.Width*0.45);$y=[int]($r.Top+$r.Height*0.40)
 Require ([W83Native]::SetCursorPos($x,$y)) 'VIEWPORT_MOUSE_POSITION_FAILED'
 [W83Native]::mouse_event(0x0800,0,0,360,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 500
 [W83Native]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 try{
  for($i=1;$i -le 8;$i++){
   Require ([W83Native]::SetCursorPos(($x+[int]($r.Width*0.22*$i/8)),$y)) 'VIEWPORT_PHYSICAL_DRAG_FAILED'
   Start-Sleep -Milliseconds 35
  }
 }finally{[W83Native]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)}
 $panned=ViewportStableAxis $shell 'PANNED'
 Require ($baseline.axis_sha256 -cne $panned.axis_sha256 -and $baseline.width -eq $panned.width -and $baseline.chart_width -eq $panned.chart_width) 'VIEWPORT_PHYSICAL_PAN_ZOOM_DID_NOT_CHANGE_TIME_AXIS'
 Require (!(ViewportAxisEquivalent $baseline $panned 'NEGATIVE_REAL_PAN')) 'VIEWPORT_REAL_PAN_MUST_ALTER_MORE_THAN_ONE_TICK'
 Write-Host ('PINE_VIEWPORT_ACTUAL_PHYSICAL_NAVIGATION='+(@{baseline=$baseline;panned=$panned;physical_mouse_wheel_and_drag=$true}|ConvertTo-Json -Depth 5 -Compress))
 foreach($version in @(5,6)){
  foreach($overlay in @($true,$false)){
   $mode=if($overlay){'OVERLAY'}else{'PANE'}
   $word=if($overlay){'true'}else{'false'}
   # Monaco normalizes incoming edited sources to LF; preserve byte-exact
   # evaluated source equality across all four v5/v6 overlay/pane cases.
   $source=('//@version='+$version+"`n"+'indicator("Viewport native '+$version+' '+$mode+'",overlay='+$word+')'+"`n"+'plot(close*1.0001)')
   MarkerPhysicalApply $shell $origin $source
   ViewportWaitStableLayout $shell $initialRect.Left $initialRect.Width
   $workspace=Invoke-RestMethod -Method Post -Uri ($origin+'/api/workspace/save') -Headers @{Origin=$origin} -ContentType 'application/json' -Body '{}' -TimeoutSec 10
   Require ($workspace.success -eq $true -and $workspace.workspace.code -ceq $source.Trim()) 'VIEWPORT_ACTUAL_APPLIED_SOURCE_MISMATCH'
   $body=@{code=$source;symbol=$workspace.workspace.symbol;timeframe=$workspace.workspace.timeframe;limit=300}|ConvertTo-Json -Compress
   $record=Invoke-RestMethod -Method Post -Uri ($origin+'/api/pine/overlay') -Headers @{Origin=$origin} -ContentType 'application/json' -Body $body -TimeoutSec 25
   Require ($record.success -eq $true -and $record.overlay -eq $overlay -and @($record.candles).Count -ge 30 -and @($record.pane_model).Count -ge 1) 'VIEWPORT_ORIGINAL_GO_EVALUATION_REQUIRED'
   $plotCount=0;foreach($pane in @($record.pane_model)){$plotCount+=@($pane.plots).Count}
   Require ($plotCount -eq 1) 'VIEWPORT_ACTUAL_ORIGINAL_PLOT_REQUIRED'
   $after=ViewportStableAxis $shell ('V'+$version+'_'+$mode)
   Require ((ViewportAxisEquivalent $panned $after ('V'+$version+'_'+$mode)) -and $after.width -eq $panned.width -and $after.height -eq $panned.height -and $after.chart_width -eq $panned.chart_width) 'VIEWPORT_APPLY_CHANGED_DETACHED_TIME_AXIS'
   SettingsDisarmed $origin
   Write-Host ('PINE_VIEWPORT_ACTUAL_NATIVE_APPLY='+(@{version=$version;overlay=$overlay;before_axis_sha256=$panned.axis_sha256;after_axis_sha256=$after.axis_sha256;bounded_original_session_label_comparison=$true;label_pixels=$after.label_pixels;axis_width=$after.width;axis_height=$after.height;physical_compile_apply=$true;original_go_source_and_response_checked=$true;scope='real owned WebView2 physical pan zoom and exact stable visible time-axis pixels; not full logical-range or HiDPI certification'}|ConvertTo-Json -Compress))
  }
 }
 Write-Host '::notice::PINE_VIEWPORT_NATIVE_V5_V6_OVERLAY_AND_PANE_PHYSICAL_PAN_ZOOM_TIME_AXIS_PRESERVED=PASS'
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
 # The startup metric ends at its declared boundary: the real selected
 # shortcut has opened the verified WebView2 chart and safe capabilities.
 # Keep all later functional probes and the original 120s/1GiB limits.
 $startWatch.Stop()
 $readyMemory=[long](Get-Process -Id $shell.Id).WorkingSet64+[long](Get-Process -Id $engine[0].ProcessId).WorkingSet64
 Write-Host ('W83_NATIVE_READY_MEASUREMENT='+(@{phase=$phase;elapsed_ms=$startWatch.Elapsed.TotalMilliseconds;shell_engine_resident_bytes=$readyMemory;startup_budget_ms=120000;resident_budget_bytes=1073741824;scope='native selected shortcut to verified WebView2 and safe capability; hosted VM; WebView child memory excluded'}|ConvertTo-Json -Compress))
 Require ($startWatch.Elapsed.TotalSeconds -le 120) 'W83_NATIVE_STARTUP_EXCEEDED_PROSPECTIVE_120S_BUDGET'
 Require ($readyMemory -le 1073741824) 'W83_SHELL_ENGINE_RESIDENT_EXCEEDED_PROSPECTIVE_1GIB_BUDGET'
 $functionalWatch=[Diagnostics.Stopwatch]::StartNew()
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
  SettingsWarm $shell $origin
  MarkerNative $shell $origin
  GuideNative $shell $origin
  GuideOnlyNative $shell $origin
  LabelNative $shell $origin
  ViewportNative $shell $origin

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
 $functionalWatch.Stop()
 Write-Host ('W83_NATIVE_FUNCTIONAL_PROBES_MEASUREMENT='+(@{phase=$phase;elapsed_ms=$functionalWatch.Elapsed.TotalMilliseconds;scope='all original and new installed functional probes; separate from native startup; existing workflow timeout unchanged'}|ConvertTo-Json -Compress))
 $engineProcess=Get-Process -Id $engine[0].ProcessId
 $memory=[long]$shell.WorkingSet64+[long]$engineProcess.WorkingSet64
 Write-Host ('W83_NATIVE_PRE_ASSERT_MEASUREMENT='+(@{phase=$phase;elapsed_ms=$startWatch.Elapsed.TotalMilliseconds;shell_engine_resident_bytes=$memory;startup_budget_ms=120000;resident_budget_bytes=1073741824;scope='native startup at actual safe UI readiness; guards unchanged; functional duration reported separately'}|ConvertTo-Json -Compress))
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
 SettingsCold $script:active $new.candidate_directory
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
