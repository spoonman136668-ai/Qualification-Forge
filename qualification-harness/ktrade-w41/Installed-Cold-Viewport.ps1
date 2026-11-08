# KTRADE W41 installed cold-reopen proof. Derived verbatim native UI/pixel
# helpers from the W83 qualified witness blob 36bb0a7dac5cca866a2fe0bd018faa365fdeeb7c.
# Read-only evidence: original unsigned installed app, isolated RUNNER_TEMP only.
# No owner data, no broker interaction, no live authority, no UI JS injection.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageZip)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$NewSHA='4c8fd0fc9db6cb07d7f899a13940e6e24b7c94bb'
function Require([bool]$ok,[string]$name){if(!$ok){throw $name}}
Require ($env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
 $env:OS -ceq 'Windows_NT' -and $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
 $env:KTRADE_LIVE_TRADING -ceq 'false') 'W41_INSTALLED_HOSTED_DISARMED_ONLY'
Require (![string]::IsNullOrEmpty($env:RUNNER_TEMP) -and (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container)) 'W41_RUNNER_TEMP_REQUIRED'
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
$zip=[IO.Path]::GetFullPath($PackageZip)
Require ($zip.StartsWith(($temp+'\'),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $zip -PathType Leaf)) 'W41_UNTRUSTED_INSTALLER_PATH'
$QualificationRoot=Join-Path $temp ('W41-installed-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $QualificationRoot
$script:installedRoot=Join-Path $QualificationRoot 'KTRADE-W41 installed with spaces'
$script:shortcuts=Join-Path $QualificationRoot 'Shortcuts'
$null=New-Item -ItemType Directory -Path $script:shortcuts
$script:ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
Require (Test-Path -LiteralPath $script:ps51) 'W41_WINDOWS_POWERSHELL_REQUIRED'

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
  $frame.bitmap.Save((Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$phase+'-context.png')),[System.Drawing.Imaging.ImageFormat]::Png)
  Require ($ink -ge 8) 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED'
  $file=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$phase+'.png')
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
function ViewportSingleSessionLabelEquivalent([object]$reference,[object]$candidate,[string]$phase){
 if($reference.width -ne $candidate.width -or $reference.height -ne $candidate.height -or
    $reference.chart_width -ne $candidate.chart_width -or $reference.chart_height -ne $candidate.chart_height -or
    $reference.left -ne $candidate.left -or $reference.top -ne $candidate.top){return $false}
 if($reference.axis_sha256 -ceq $candidate.axis_sha256){return $true}
 $beforePath=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$reference.phase+'.png')
 $afterPath=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$candidate.phase+'.png')
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


# The original trading chart can slightly respace ticks when the independent
# Pine price scale is first shown. Prove that SIX distinct actual time-label
# glyph clusters survive in order and move no farther than twelve pixels.
# Do not infer text from OCR or accept only hashes or a generic color match.
function ViewportIsInk([System.Drawing.Color]$p){
 return ($p.R -ge 110 -and $p.R -le 240 -and
   $p.G -ge 110 -and $p.G -le 240 -and
   $p.B -ge 110 -and $p.B -le 240 -and
   [Math]::Abs([int]$p.R-[int]$p.G) -le 40 -and
   [Math]::Abs([int]$p.G-[int]$p.B) -le 40)
}
function ViewportLabelRuns([System.Drawing.Bitmap]$bitmap){
 $ranges=New-Object 'System.Collections.Generic.List[object]'
 $last=-1000
 for($x=0;$x -lt $bitmap.Width;$x++){
  $ink=$false
  for($y=0;$y -lt $bitmap.Height;$y++){
   if(ViewportIsInk ($bitmap.GetPixel($x,$y))){$ink=$true;break}
  }
  if(!$ink){continue}
  if($x-$last -gt 6){$ranges.Add([pscustomobject]@{start=$x;end=$x})}
  else{$ranges[$ranges.Count-1].end=$x}
  $last=$x
 }
 return @($ranges.ToArray())
}
function ViewportGlyphCoverage([System.Drawing.Bitmap]$source,[object]$a,[System.Drawing.Bitmap]$target,[object]$b){
 $inkCount=0;$matched=0
 for($y=0;$y -lt $source.Height;$y++){
  for($x=[int]$a.start;$x -le [int]$a.end;$x++){
   if(!(ViewportIsInk ($source.GetPixel($x,$y)))){continue}
   $inkCount++
   $relative=$x-[int]$a.start
   $found=$false
   foreach($dy in @(-1,0,1)){
    $yy=$y+$dy
    if($yy -lt 0 -or $yy -ge $target.Height){continue}
    foreach($dx in @(-1,0,1)){
     $xx=[int]$b.start+$relative+$dx
     if($xx -lt [int]$b.start-1 -or $xx -gt [int]$b.end+1 -or $xx -lt 0 -or $xx -ge $target.Width){continue}
     if(ViewportIsInk ($target.GetPixel($xx,$yy))){$found=$true;break}
    }
    if($found){break}
   }
   if($found){$matched++}
  }
 }
 return ($inkCount -ge 8 -and ($matched/$inkCount) -ge 0.90)
}
function ViewportGlyphAnchors([object]$reference,[object]$candidate,[string]$phase){
 if($reference.width -ne $candidate.width -or $reference.height -ne $candidate.height -or
   $reference.chart_width -ne $candidate.chart_width -or $reference.chart_height -ne $candidate.chart_height -or
   $reference.left -ne $candidate.left -or $reference.top -ne $candidate.top){return $false}
 $before=[System.Drawing.Bitmap]::new((Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$reference.phase+'.png')))
 $after=[System.Drawing.Bitmap]::new((Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$candidate.phase+'.png')))
 try{
  if($before.Width -ne $after.Width -or $before.Height -ne $after.Height -or $before.Height -ne 18){return $false}
  $runsA=@(ViewportLabelRuns $before);$runsB=@(ViewportLabelRuns $after)
  $pairs=New-Object 'System.Collections.Generic.List[object]'
  $lastEnd=-1
  foreach($a in $runsA){
   foreach($b in $runsB){
    if($b.start -le $lastEnd -or
      [Math]::Abs([int]$a.start-[int]$b.start) -gt 12 -or
      [Math]::Abs(([int]$a.end-[int]$a.start)-([int]$b.end-[int]$b.start)) -gt 3){continue}
    if(!(ViewportGlyphCoverage $before $a $after $b)){continue}
    if(!(ViewportGlyphCoverage $after $b $before $a)){continue}
    $pairs.Add([pscustomobject]@{before=[int]$a.start;after=[int]$b.start;drift=[int]$b.start-[int]$a.start})
    $lastEnd=[int]$b.end
    break
   }
  }
  if($pairs.Count -lt 6){return $false}
  # Original view changed by physical pan, not Apply: six genuine matching
  # same-glyph time ticks within twelve pixels must not be found by accident.
  Write-Host ('PINE_VIEWPORT_NATIVE_ANCHORED_TICKS='+(@{phase=$phase;reference_sha256=$reference.axis_sha256;observed_sha256=$candidate.axis_sha256;matched_tick_glyphs=$pairs.Count;max_allowed_drift_pixels=12;one_pixel_shape_tolerance=$true;pairs=@($pairs.ToArray());scope='bounded_actual_native_unchanged_ordered_time_label_glyphs_after_pane_reflow_not_full_logical_range_oracle'}|ConvertTo-Json -Compress -Depth 6))
  return $true
 }finally{$before.Dispose();$after.Dispose()}
}
function ViewportAxisEquivalent([object]$reference,[object]$candidate,[string]$phase){
 if(ViewportSingleSessionLabelEquivalent $reference $candidate $phase){return $true}
 return (ViewportGlyphAnchors $reference $candidate $phase)
}

# Diagnostic only: compare the exact native time-axis strip already
# captured by the strict acceptance oracle. Never export screenshot pixels,
# change scoring or infer a semantic viewport pass from this measurement.
function W41-AxisDifference([object]$reference,[object]$candidate){
 $ap=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$reference.phase+'.png')
 $bp=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$candidate.phase+'.png')
 $a=[System.Drawing.Bitmap]::new($ap)
 $b=[System.Drawing.Bitmap]::new($bp)
 try{
  Require ($a.Width -eq $b.Width -and $a.Height -eq $b.Height -and
   $a.Width -eq $reference.width -and $b.Width -eq $candidate.width -and
   $a.Height -eq 18) 'W41_DIAG_AXIS_DIMENSION_DRIFT'
  $changed=0;$lo=$a.Width;$hi=-1;$perBand=@(0,0,0,0)
  for($y=0;$y -lt $a.Height;$y++){
   for($x=0;$x -lt $a.Width;$x++){
    $p=$a.GetPixel($x,$y);$q=$b.GetPixel($x,$y)
    if([Math]::Abs([int]$p.R-[int]$q.R) -ge 8 -or
       [Math]::Abs([int]$p.G-[int]$q.G) -ge 8 -or
       [Math]::Abs([int]$p.B-[int]$q.B) -ge 8){
     $changed++;$lo=[Math]::Min($lo,$x);$hi=[Math]::Max($hi,$x)
     $band=[Math]::Min(3,[int][Math]::Floor(4.0*$x/$a.Width))
     $perBand[$band]++
    }
   }
  }
  $ra=@(ViewportLabelRuns $a);$rb=@(ViewportLabelRuns $b)
  # A categorical read-only comparison of the six observed original axis
  # glyph runs, ordered left to right; never infer trading time or text.
  $pairs=@()
  $pairCount=[Math]::Min($ra.Count,$rb.Count)
  for($i=0;$i -lt $pairCount;$i++){
   $aa=$ra[$i];$bb=$rb[$i]
   $symmetric=(ViewportGlyphCoverage $a $aa $b $bb) -and
    (ViewportGlyphCoverage $b $bb $a $aa)
   $pairs+=@{ordinal=$i;start_shift_pixels=([int]$bb.start-[int]$aa.start);
    width_before=([int]$aa.end-[int]$aa.start+1);
    width_after=([int]$bb.end-[int]$bb.start+1);
    glyph_equivalent=$symmetric}
  }
  Write-Host ('W41_NATIVE_AXIS_GLYPH_PAIR_DIAGNOSTIC='+(@{
   before_clusters=$ra.Count;after_clusters=$rb.Count;ordered_pairs=$pairs;
   interpretation='same_ordinals_shape_test_only_not_OCR_or_acceptance';
   full_pixel_oracle_unchanged=$true
  }|ConvertTo-Json -Compress -Depth 5))
  Write-Host ('W41_NATIVE_AXIS_STRIP_DIFFERENCE='+(@{
   changed_pixels=$changed;first_changed_x=if($changed){$lo}else{-1};
   last_changed_x=$hi;per_quarter_changed_pixels=$perBand;
   before_label_clusters=$ra.Count;after_label_clusters=$rb.Count;
   width=$a.Width;height=$a.Height;
   same_capture_geometry=($reference.chart_width -eq $candidate.chart_width -and
    $reference.chart_height -eq $candidate.chart_height -and
    $reference.left -eq $candidate.left -and $reference.top -eq $candidate.top);
   scope='test_owned_native_axis_only_no_screenshot_export_no_acceptance_relaxation'
  }|ConvertTo-Json -Compress))
 }finally{$a.Dispose();$b.Dispose()}
}
# Read-only native pixel witness: identify the original LightweightCharts
# up/down candle colors at each chart-plot X column. Unlike the time axis,
# candle-column positions should survive time-label formatting changes.
# No UI injection, price values, screenshot uploads or pass substitution.
function W41-CandleColorColumns([string]$phase){
 $file=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$phase+'-context.png')
 Require (Test-Path -LiteralPath $file -PathType Leaf) 'W41_CANDLE_PIXEL_CONTEXT_MISSING'
 $bmp=[System.Drawing.Bitmap]::new($file)
 try{
  $left=20;$right=$bmp.Width-114;$top=25;$bottom=$bmp.Height-40
  Require ($right-$left -ge 240 -and $bottom-$top -ge 120) 'W41_CANDLE_PIXEL_ROI_INVALID'
  $tags=[Collections.Generic.List[int]]::new()
  for($x=$left;$x -lt $right;$x+=2){
   $up=0;$down=0
   for($y=$top;$y -lt $bottom;$y+=2){
    $p=$bmp.GetPixel($x,$y)
    if([Math]::Abs([int]$p.R-38) -le 18 -and
       [Math]::Abs([int]$p.G-166) -le 18 -and
       [Math]::Abs([int]$p.B-154) -le 18){$up++}
    if([Math]::Abs([int]$p.R-239) -le 18 -and
       [Math]::Abs([int]$p.G-83) -le 18 -and
       [Math]::Abs([int]$p.B-80) -le 18){$down++}
   }
   $tag=0
   if($up -ge 2 -and $up -gt $down*2){$tag=1}
   elseif($down -ge 2 -and $down -gt $up*2){$tag=-1}
   $tags.Add($tag)
  }
  $active=0;$runs=0;$prior=0
  foreach($tag in $tags){
   if($tag -ne 0){$active++;if($tag -ne $prior){$runs++}}
   $prior=$tag
  }
  return [pscustomobject]@{
   phase=$phase;tags=[int[]]$tags.ToArray();
   active_columns=$active;color_runs=$runs;plot_width=$right-$left
  }
 }finally{$bmp.Dispose()}
}
function W41-CompareCandleColumns([object]$first,[object]$second){
 Require ($first.tags.Length -eq $second.tags.Length) 'W41_CANDLE_PIXEL_COLUMN_DIMENSION_DRIFT'
 $hitFirst=0;$hitSecond=0;$both=0
 for($i=0;$i -lt $first.tags.Length;$i++){
  $a=[int]$first.tags[$i];$b=[int]$second.tags[$i]
  if($a -ne 0){
   for($j=[Math]::Max(0,$i-1);$j -le [Math]::Min($first.tags.Length-1,$i+1);$j++){
    if([int]$second.tags[$j] -eq $a){$hitFirst++;break}
   }
  }
  if($b -ne 0){
   for($j=[Math]::Max(0,$i-1);$j -le [Math]::Min($second.tags.Length-1,$i+1);$j++){
    if([int]$first.tags[$j] -eq $b){$hitSecond++;break}
   }
  }
  if($a -ne 0 -and $a -eq $b){$both++}
 }
 return @{from=$first.phase;to=$second.phase;
   active_from=$first.active_columns;active_to=$second.active_columns;
   runs_from=$first.color_runs;runs_to=$second.color_runs;
   same_x_same_color=$both;
   matched_from_within_2px=$hitFirst;matched_to_within_2px=$hitSecond;
   directed_pct_from=if($first.active_columns){[Math]::Round(100.0*$hitFirst/$first.active_columns,1)}else{0};
   directed_pct_to=if($second.active_columns){[Math]::Round(100.0*$hitSecond/$second.active_columns,1)}else{0}
 }
}
# Second independent native screenshot diagnostic: classify each original
# candlestick pixel in both X AND Y (2px grid) with signed up/down color.
# This must discriminate the actual physical pan negative. Reports counts
# only; it cannot override the unchanged original installed visual gate.
function W41-CandlePixelMap([string]$phase){
 $file=Join-Path $env:RUNNER_TEMP ('w41-installed-viewport-axis-'+$phase+'-context.png')
 Require (Test-Path -LiteralPath $file -PathType Leaf) 'W41_CANDLE_2D_CONTEXT_MISSING'
 $bmp=[System.Drawing.Bitmap]::new($file)
 try{
  $left=24;$top=20;$right=$bmp.Width-116;$bottom=$bmp.Height-48
  Require ($right-$left -ge 240 -and $bottom-$top -ge 120) 'W41_CANDLE_2D_ROI_INVALID'
  $cols=[int][Math]::Ceiling(($right-$left)/2.0)
  $rows=[int][Math]::Ceiling(($bottom-$top)/2.0)
  $map=New-Object 'System.Byte[]' ($cols*$rows)
  $greenPixels=0;$redPixels=0
  for($y=0;$y -lt $rows;$y++){
   for($x=0;$x -lt $cols;$x++){
    $p=$bmp.GetPixel($left+2*$x,$top+2*$y)
    $idx=$y*$cols+$x
    if([Math]::Abs([int]$p.R-38) -le 18 -and
       [Math]::Abs([int]$p.G-166) -le 18 -and
       [Math]::Abs([int]$p.B-154) -le 18){$map[$idx]=1;$greenPixels++}
    elseif([Math]::Abs([int]$p.R-239) -le 18 -and
       [Math]::Abs([int]$p.G-83) -le 18 -and
       [Math]::Abs([int]$p.B-80) -le 18){$map[$idx]=2;$redPixels++}
   }
  }
  return [pscustomobject]@{
   phase=$phase;columns=$cols;rows=$rows;pixels=$map;
   up_pixels=$greenPixels;down_pixels=$redPixels
  }
 }finally{$bmp.Dispose()}
}
function W41-CompareCandlePixels([object]$a,[object]$b){
 Require ($a.columns -eq $b.columns -and $a.rows -eq $b.rows) 'W41_CANDLE_2D_GEOMETRY_DRIFT'
 $hitA=0;$hitB=0;$exact=0
 for($i=0;$i -lt $a.pixels.Length;$i++){
  $p=[int]$a.pixels[$i];$q=[int]$b.pixels[$i]
  if($p -ne 0 -and $p -eq $q){$exact++}
  $cx=$i%$a.columns;$cy=[int][Math]::Floor($i/$a.columns)
  if($p -ne 0){
   $found=$false
   for($dy=-1;$dy -le 1 -and !$found;$dy++){
    $yy=$cy+$dy
    if($yy -lt 0 -or $yy -ge $a.rows){continue}
    for($dx=-1;$dx -le 1;$dx++){
     $xx=$cx+$dx
     if($xx -lt 0 -or $xx -ge $a.columns){continue}
     if([int]$b.pixels[$yy*$a.columns+$xx] -eq $p){$found=$true;break}
    }
   }
   if($found){$hitA++}
  }
  if($q -ne 0){
   $found=$false
   for($dy=-1;$dy -le 1 -and !$found;$dy++){
    $yy=$cy+$dy
    if($yy -lt 0 -or $yy -ge $a.rows){continue}
    for($dx=-1;$dx -le 1;$dx++){
     $xx=$cx+$dx
     if($xx -lt 0 -or $xx -ge $a.columns){continue}
     if([int]$a.pixels[$yy*$a.columns+$xx] -eq $q){$found=$true;break}
    }
   }
   if($found){$hitB++}
  }
 }
 $nA=$a.up_pixels+$a.down_pixels;$nB=$b.up_pixels+$b.down_pixels
 return @{from=$a.phase;to=$b.phase;map_columns=$a.columns;map_rows=$a.rows;
  colored_pixels_from=$nA;colored_pixels_to=$nB;
  exact_same_xy_same_color=$exact;match_2px_from=$hitA;match_2px_to=$hitB;
  directed_pct_from=if($nA){[Math]::Round(100.0*$hitA/$nA,1)}else{0};
  directed_pct_to=if($nB){[Math]::Round(100.0*$hitB/$nB,1)}else{0}
 }
}

# Read only the already-published categorical frame and 3 local pixel anchors.
function W41-ReadFrame([object]$shell){
 try{
  $node=FindUI $shell 'Price chart drawing surface' $false 10
  $m=[regex]::Match([string]$node.Current.Name,
    ';frame:tf=([0-9a-z]+);count=([0-9]+);record=(match|none);live=(yes|no);size=([0-9]+)x([0-9]+);points=([0-9n:|\\-]+)')
  if(!$m.Success){return [pscustomobject]@{available=$false}}
  $v=@()
  foreach($s in $m.Groups[7].Value.Split('|')){
   $p=$s.Split(':')
   if($p.Count -ne 3){continue}
   $x=$null;$y=$null
   if($p[1] -match '^-?[0-9]+
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


# All screenshot pixels stay on this isolated runner. Log only measurement hashes.
Add-Type -AssemblyName System.Drawing
function W41-Candles([string]$origin){
 $data=Invoke-RestMethod -Method Get -Uri ($origin+'/api/candles?product=BTC-USD&tf=1h') -TimeoutSec 20
 $rows=@($data.candles)
 Require ($data.success -eq $true -and $rows.Count -ge 30 -and
  [long]$rows[0].time -gt 0 -and [long]$rows[$rows.Count-1].time -gt [long]$rows[0].time) 'W41_REAL_CANDLE_DATA_UNAVAILABLE'
 # The chart's v2 restore key hashes ALL six fields, not just time boundaries.
 # Match the original JS DataView float64 big-endian byte order without logging
 # source prices, sizes, private profile contents, or market records.
 $bytes=[Collections.Generic.List[byte]]::new()
 foreach($c in $rows){
  foreach($field in @('time','open','high','low','close','volume')){
   $value=[double]$c.$field
   Require (![double]::IsNaN($value) -and ![double]::IsInfinity($value)) 'W41_HISTORY_NONFINITE_FIELD'
   $part=[BitConverter]::GetBytes($value)
   if([BitConverter]::IsLittleEndian){[Array]::Reverse($part)}
   $bytes.AddRange([byte[]]$part)
  }
 }
 $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray())).ToLowerInvariant()
 return [pscustomobject]@{count=$rows.Count;first=[long]$rows[0].time;last=[long]$rows[$rows.Count-1].time;history=$digest}
}
function W41-Start([string]$candidate){
 $chosen=Join-Path $script:installedRoot '.ktrade-w29-install.json'
 Require (Test-Path -LiteralPath $chosen -PathType Leaf) 'W41_INSTALLED_SELECTION_ABSENT'
 $receipt=Get-Content -LiteralPath $chosen -Raw|ConvertFrom-Json
 Require ($receipt.source_sha -ceq $NewSHA -and $receipt.live_armed -eq $false -and
  $receipt.selection_digest -cmatch '^[a-f0-9]{64}$') 'W41_INSTALLED_SOURCE_OR_AUTHORITY_CHANGED'
 $selected=[IO.Path]::GetFullPath($receipt.candidate_directory)
 Require ($selected -ceq [IO.Path]::GetFullPath($candidate) -and
  $selected.StartsWith(([IO.Path]::GetFullPath($script:installedRoot)+'\'),[StringComparison]::OrdinalIgnoreCase)) 'W41_INSTALLED_DIRECTORY_UNTRUSTED'
 $exe=Join-Path $selected 'ktrade.exe'
 Ordinary $exe $false
 $shortcutDir=Join-Path $script:shortcuts ('KTRADE-'+$receipt.selection_digest.Substring(0,16))
 $shortcut=Join-Path $shortcutDir 'KTRADE.lnk'
 $proof=Join-Path $shortcutDir '.ktrade-shortcut-receipt.json'
 Ordinary $shortcut $false
 Ordinary $proof $false
 $owned=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
 Require ($owned.schema -ceq 'ktrade.windows-shortcut.v1' -and
  $owned.source_sha -ceq $NewSHA -and $owned.selection_digest -ceq $receipt.selection_digest -and
  $owned.root -ceq $script:installedRoot -and
  $owned.target -ceq $exe -and (Hash $shortcut) -ceq $owned.link_sha256) 'W41_INSTALLED_SHORTCUT_IDENTITY_INVALID'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_STALE_ACTIVE_LEASE'
 Start-Process -FilePath $shortcut
 $owner=$null
 $limit=(Get-Date).AddSeconds(48)
 do{
  if(Test-Path -LiteralPath $lease){
   try{$value=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json
    if($value.pid -gt 0){$owner=$value;break}}catch{}
  }
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $limit)
 Require ($null -ne $owner -and $owner.source_sha -ceq $NewSHA -and $owner.live_armed -eq $false) 'W41_NO_VERIFIED_INSTALLED_PROCESS_LEASE'
 $shell=Get-Process -Id ([int]$owner.pid) -ErrorAction Stop
 $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shell.Id)
 Require ([string]::Equals($cim.ExecutablePath,$exe,[StringComparison]::OrdinalIgnoreCase)) 'W41_FOREIGN_PROCESS_SOURCE'
 ClickUI $shell 'Desktop diagnostics'
 ClickUI $shell 'Verify chart UI'
 $null=FindUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.' $false 28
 $null=FindUI $shell 'Price chart drawing surface' $false 25
 $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|
  Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
 Require ($children.Count -eq 1) 'W41_INSTALLED_BACKEND_OWNER_CHANGED'
 $ports=@(Get-NetTCPConnection -OwningProcess $children[0].ProcessId -State Listen|
  Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W41_INSTALLED_LOOPBACK_AUTHORITY_CHANGED'
 $origin='http://127.0.0.1:'+$ports[0].LocalPort
 $cap=Invoke-RestMethod -Method Get -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and $cap.paper_orders_enabled -eq $false -and
  $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false -and
  $cap.requires_review -eq $true) 'W41_COLD_NATIVE_TRADING_NOT_DISARMED'
 $html=(Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/chart') -TimeoutSec 12).Content
 Require ($html.Contains('/static/chart_viewport_state.js') -and
  $html.Contains('scheduleViewportSave()')) 'W41_SHIPPING_CHART_NOT_SERVED'
 $js=Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/static/chart_viewport_state.js') -TimeoutSec 12
 Require ($js.StatusCode -eq 200 -and $js.Content.Contains('ktrade.chart-viewport.v2')) 'W41_VIEWPORT_MODULE_NOT_SERVED'
 return [pscustomobject]@{shell=$shell;enginePid=[int]$children[0].ProcessId;origin=$origin}
}
function W41-Stop([object]$run){
 Require ([W83Native]::PostMessage($run.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'W41_NATIVE_CLOSE_REFUSED'
 Require ($run.shell.WaitForExit(30000)) 'W41_NATIVE_SHELL_NOT_STOPPED'
 Require (!(Get-Process -Id $run.enginePid -ErrorAction SilentlyContinue)) 'W41_NATIVE_ENGINE_ORPHAN'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_LEASE_NOT_RELEASED_ON_COLD_STOP'
}
# Do not accept an unpainted time axis as a viewport result. Cold WebView2
# layout/render may lag behind the installed chart's DOM-ready handshake.
# Bound retries to transient missing label ink only. Any real geometry,
# process, layout, or viewport mismatch remains a hard failure.
# Bounded, read-only localStorage LevelDB marker observation on this runner's
# new synthetic installed profile. A hit indicates encoded key presence only;
# missing markers are diagnostic, never a standalone data-loss conclusion.
function W41-ObserveProfileKeys([string]$candidate,[object]$expected){
 $profile=Join-Path $candidate 'data/webview2-profile'
 if(!(Test-Path -LiteralPath $profile -PathType Container)){
  Write-Host 'W41_PROFILE_MARKER_SCAN=UNAVAILABLE_NO_PROFILE';return
 }
 Ordinary $profile $true
 $roots=@(
  (Join-Path $profile 'EBWebView/Default/Local Storage/leveldb'),
  (Join-Path $profile 'Default/Local Storage/leveldb')
 )
 $keys=@('ktrade_chart_viewport_v2:BTC-USD:1h','ktrade_chart_timeframe')
 $patterns=@()
 foreach($key in $keys){
  $patterns+=,[pscustomobject]@{
   ascii=[Text.Encoding]::Latin1.GetString([Text.Encoding]::UTF8.GetBytes($key));
   utf16=[Text.Encoding]::Latin1.GetString([Text.Encoding]::Unicode.GetBytes($key))
  }
 }
 $hit=@($false,$false);$scanned=0;$unreadable=0
 $records=0;$contextRecords=0;$sameHistory=0;$fractionalRecords=0;$parseFailures=0
 foreach($root in $roots){
  if(!(Test-Path -LiteralPath $root -PathType Container)){continue}
  Ordinary $root $true
  $files=@(Get-ChildItem -LiteralPath $root -File -ErrorAction Stop |
   Where-Object {$_.Extension -in @('.ldb','.sst','.log') -and
    $_.Length -le 16777216 -and
    !$_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)} |
   Sort-Object FullName | Select-Object -First 96)
  foreach($file in $files){
   if($scanned -ge 96){break}
   try{$text=[Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($file.FullName))}
   catch{$unreadable++;continue}
   $scanned++
   # Read-only scan of just the disposable test profile's tiny LevelDB log.
   # The original native installed witness never decrypts or migrates storage.
   # Do not publish raw JSON, prices, timestamps, ranges, profile paths or keys.
   if($file.Length -le 1048576){
    try{
     $raw=[IO.File]::ReadAllBytes($file.FullName)
     $views=@($text,[Text.Encoding]::Unicode.GetString($raw,0,($raw.Length-[int]($raw.Length%2))))
     foreach($view in $views){
      $found=[regex]::Matches($view,'\{"schema":"ktrade\.chart-viewport\.v2"[^{}]{0,480}\}')
      foreach($match in $found){
       $records++
       try{
        $row=$match.Value|ConvertFrom-Json
        if($row.schema -cne 'ktrade.chart-viewport.v2' -or
           $row.product -cne 'BTC-USD' -or $row.tf -cne '1h' -or
           [long]$row.count -ne [long]$expected.count -or
           [long]$row.first -ne [long]$expected.first -or
           [long]$row.last -ne [long]$expected.last){continue}
        $contextRecords++
        if([string]$row.history -ceq [string]$expected.history){$sameHistory++}
        $from=[double]$row.from;$to=[double]$row.to
        if([double]::IsFinite($from) -and [double]::IsFinite($to) -and
           $to-$from -ge .75 -and
           ([Math]::Abs($from-[Math]::Round($from)) -gt .02 -or
            [Math]::Abs($to-[Math]::Round($to)) -gt .02)){$fractionalRecords++}
       }catch{$parseFailures++}
      }
     }
    }catch{$parseFailures++}
   }
   for($i=0;$i -lt $keys.Count;$i++){
    if(!$hit[$i] -and ($text.Contains($patterns[$i].ascii) -or
      $text.Contains($patterns[$i].utf16))){$hit[$i]=$true}
   }
  }
 }
 Write-Host ('W41_COLD_PROFILE_V2_VALUE_PROBE='+(@{
  json_candidates=$records;bounded_context_matches=$contextRecords;
  matching_full_history=$sameHistory;fractional_records=$fractionalRecords;
  parse_failures=$parseFailures;
  semantic_proof=$false;scope='test_owned_LevelDB_log_heuristic_only_no_values_or_active_record_proof'
 }|ConvertTo-Json -Compress))
 Write-Host ('W41_COLD_PROFILE_STORAGE_MARKERS='+(@{
  scanned_files=$scanned;unreadable_files=$unreadable;
  viewport_key_present=$hit[0];timeframe_key_present=$hit[1];
  semantic_proof=$false;scope='test-owned profile, key bytes only, no values'
 }|ConvertTo-Json -Compress))
}
function W41-WaitColdAxis([object]$shell){
 $deadline=(Get-Date).AddSeconds(18)
 $attempt=0
 while($true){
  $attempt++
  try{
   $axis=ViewportStableAxis $shell 'COLD_REOPENED'
   Write-Host ('W41_INSTALLED_COLD_AXIS_RENDER_READY_ATTEMPTS='+$attempt)
   return $axis
  }catch{
   if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED' -or
      (Get-Date) -ge $deadline){throw}
   $shell.Refresh()
   Require (!$shell.HasExited) 'W41_SHELL_EXITED_BEFORE_COLD_AXIS_RENDER'
   Start-Sleep -Milliseconds 350
  }
 }
}
Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json'))) 'W41_EXISTING_INSTALLED_DATA_NOT_ALLOWED'
$distribution=Join-Path $QualificationRoot 'unsigned-distribution'
$null=New-Item -ItemType Directory -Path $distribution
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$distribution)
$null=Bundle $distribution $NewSHA
$installed=Setup (Join-Path $distribution 'KTRADE-Setup.ps1') 'Install'
Require ($installed.schema -ceq 'ktrade.fresh-installation.v1' -and
 $installed.source_sha -ceq $NewSHA -and $installed.root -ceq $script:installedRoot -and
 $installed.candidate_directory -cmatch '^[A-Za-z]:[\\/]' -and
 $installed.selection_digest -cmatch '^[a-f0-9]{64}$' -and
 $installed.fresh_only -eq $true -and $installed.app_launched -eq $false -and
 $installed.owner_data_imported -eq $false -and $installed.orders_enabled -eq $false -and
 $installed.live_armed -eq $false -and $installed.release_accepted -eq $false) 'W41_FRESH_INSTALL_NOT_DISARMED'
$active=$null
try{
 $active=W41-Start $installed.candidate_directory
 # 1h is supported end-to-end by the original Coinbase candle backend.
 # A 2h button exists but currently falls through to 1m backend granularity;
 # do not misrepresent that as a stable two-hour historical fixture.
 # If near an hour boundary, admit the next full-hour window so the sealed
 # candle identity cannot roll over during the physical restart check.
 $utc=[DateTime]::UtcNow
 if($utc.Minute -ge 58){
  $nextHour=$utc.AddHours(1)
  $after=[DateTime]::new($nextHour.Year,$nextHour.Month,$nextHour.Day,
   $nextHour.Hour,1,0,[DateTimeKind]::Utc)
  $wait=[int][Math]::Ceiling(($after-$utc).TotalSeconds)
  Require ($wait -gt 0 -and $wait -le 180) 'W41_COLD_HOURLY_WINDOW_ADMISSION_INVALID'
  Write-Host ('W41_HOURLY_CANDLE_ADMISSION_WAIT_SECONDS='+$wait)
  Start-Sleep -Seconds $wait
 }
 ClickUI $active.shell '1h'
 Write-Host 'W41_REAL_NATIVE_1H_TIMEFRAME_CLICKED=PASS'
 Start-Sleep -Milliseconds 1300
 $firstOrigin=$active.origin
 $firstCandles=W41-Candles $firstOrigin
 $baseline=ViewportStableAxis $active.shell 'COLD_BASELINE'
 $node=FindUI $active.shell 'Price chart drawing surface' $false 20
 $rect=$node.Current.BoundingRectangle
 [void][W83Native]::SetForegroundWindow($active.shell.MainWindowHandle)
 Require ([W83Native]::GetForegroundWindow() -eq $active.shell.MainWindowHandle) 'W41_CHART_NOT_FOREGROUND'
 $x=[int]($rect.Left+$rect.Width*0.45);$y=[int]($rect.Top+$rect.Height*0.40)
 Require ([W83Native]::SetCursorPos($x,$y)) 'W41_MOUSE_GEOMETRY_REFUSED'
 [W83Native]::mouse_event(0x0800,0,0,360,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 450
 [W83Native]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 try{
  for($i=1;$i -le 8;$i++){
   Require ([W83Native]::SetCursorPos(($x+[int]($rect.Width*0.22*$i/8)),$y)) 'W41_PHYSICAL_DRAG_REFUSED'
   Start-Sleep -Milliseconds 35
  }
 }finally{[W83Native]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)}
 Start-Sleep -Milliseconds 800
 $panned=ViewportStableAxis $active.shell 'COLD_PANNED'
 $pannedFrame=W41-ReadFrame $active.shell
 Require ($baseline.axis_sha256 -cne $panned.axis_sha256 -and
  !(ViewportAxisEquivalent $baseline $panned 'NEGATIVE_USER_NAVIGATION')) 'W41_NATIVE_CHART_NOT_CHANGED_BY_REAL_INPUT'
 $beforeClose=W41-Candles $firstOrigin
 Require ($beforeClose.count -eq $firstCandles.count -and
  $beforeClose.first -eq $firstCandles.first -and
  $beforeClose.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_DRIFTED_DURING_NAVIGATION'
 W41-Stop $active;$active=$null
 W41-ObserveProfileKeys $installed.candidate_directory $beforeClose
 $active=W41-Start $installed.candidate_directory
 # Read-only UIA metadata can distinguish a lost timeframe preference from
 # viewport-only restoration failure; it cannot substitute for the pixel oracle.
 $reopenTimeframe=FindUI $active.shell '1h' $true 15
 $pressed='UNAVAILABLE'
 try{
  $property=[System.Windows.Automation.AutomationElement]::AriaPropertiesProperty
  if($null -ne $property){
   $props=$reopenTimeframe.GetCurrentPropertyValue($property,$true)
   if($props -is [string]){
    if($props -match '(?:^|;)\\s*pressed=true(?:;|$)'){$pressed='TRUE'}
    elseif($props -match '(?:^|;)\\s*pressed=false(?:;|$)'){$pressed='FALSE'}
   }
  }
 }catch{}
 Write-Host ('W41_COLD_REOPEN_1H_ARIA_PRESSED='+$pressed)
 Require ($active.origin -ceq $firstOrigin) 'W41_INSTALLED_ORIGIN_NOT_STABLE_ACROSS_RESTART'
 $afterRestart=W41-Candles $active.origin
 Require ($afterRestart.count -eq $firstCandles.count -and
  $afterRestart.first -eq $firstCandles.first -and
  $afterRestart.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_CHANGED_SAFE_FALLBACK_NOT_COLD_RESTORE_CASE'
 Write-Host ('W41_INSTALLED_FULL_CANDLE_HISTORY_CUSTODY='+(@{
  initial_matches_preclose=($firstCandles.history -ceq $beforeClose.history);
  initial_matches_reopen=($firstCandles.history -ceq $afterRestart.history);
  preclose_matches_reopen=($beforeClose.history -ceq $afterRestart.history);
  scope='six_field_float64_be_sha256_no_candle_values'
 }|ConvertTo-Json -Compress))
 $chartNative=FindUI $active.shell 'Price chart drawing surface' $false 5
 $stage='UNAVAILABLE'
 try{
  $label=[string]$chartNative.Current.Name
  if($label -cmatch 'viewport:([a-z-]{3,40})'){$stage=$Matches[1]}
 }catch{}
 Write-Host ('W41_NATIVE_CHART_RESTORE_STAGE='+$stage)
 $restored=$null
 try{$restored=W41-WaitColdAxis $active.shell}
 catch{
  # Diagnostic is only entered on missing actual time-axis ink after the
  # bounded 18-second original render wait. A successful refresh cannot
  # retroactively turn the failed *cold restore* into acceptance.
  if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED'){throw}
  $nativeState=@{one_hour_button=$false;one_minute_button=$false;
    chart_surface=$false;data_unavailable=$false;loading_market_data=$false;
    one_hour_toggle='UNAVAILABLE';one_hour_aria='UNAVAILABLE'}
  try{
   $rootEl=[System.Windows.Automation.AutomationElement]::FromHandle($active.shell.MainWindowHandle)
   $nodes=$rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
   foreach($el in $nodes){
    try{
     $label=[string]$el.Current.Name
     if($label -ceq '1h'){$nativeState.one_hour_button=$true}
     if($label -ceq '1m'){$nativeState.one_minute_button=$true}
     if($label.Contains('Price chart drawing surface')){$nativeState.chart_surface=$true}
     if($label.Contains('Market data unavailable')){$nativeState.data_unavailable=$true}
     if($label.Contains('Loading market data')){$nativeState.loading_market_data=$true}
    }catch{}
   }
   $toggle=$null
   if($reopenTimeframe.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$toggle)){
    $nativeState.one_hour_toggle=[string]$toggle.Current.ToggleState
   }
   $aria=$reopenTimeframe.GetCurrentPropertyValue(
    [System.Windows.Automation.AutomationElement]::AriaPropertiesProperty,$true)
   if($aria -is [string]){
    if($aria -match '(?:^|;)\s*pressed=true(?:;|$)'){$nativeState.one_hour_aria='TRUE'}
    elseif($aria -match '(?:^|;)\s*pressed=false(?:;|$)'){$nativeState.one_hour_aria='FALSE'}
   }
  }catch{}
  Write-Host ('W41_COLD_NATIVE_UIA_CLASSIFICATION='+($nativeState|ConvertTo-Json -Compress))
  # Images remain on the disposable runner. Report only coarse palette
  # diversity, never UI text, prices, screenshots, or browser storage values.
  $surface=MarkerCaptureChart $active.shell 'REOPEN_DIAGNOSTIC_ONLY'
  try{
   $bins=@()
   foreach($frac in @(0.25,0.60,0.90)){
    $colors=[Collections.Generic.HashSet[string]]::new()
    $yy=[int][Math]::Floor($surface.bitmap.Height*$frac)
    for($xx=12;$xx -lt $surface.bitmap.Width-12;$xx+=8){
     $px=$surface.bitmap.GetPixel($xx,$yy)
     [void]$colors.Add(('{0}:{1}:{2}' -f ($px.R -shr 5),($px.G -shr 5),($px.B -shr 5)))
    }
    $bins+= $colors.Count
   }
   Write-Host ('W41_COLD_NATIVE_CHART_PALETTE='+(@{top_mid_bottom_distinct_bins=$bins;
     scope='coarse_native_pixel_palette_only_no_chart_data'}|ConvertTo-Json -Compress))
  }finally{$surface.bitmap.Dispose()}
  # One bounded physical 1h reselect distinguishes lost initial timeframe/
  # load/render from a cold-restoration defect. It changes ONLY the newly
  # installed disposable chart, after the cold acceptance has already failed.
  ClickUI $active.shell '1h'
  Start-Sleep -Milliseconds 1600
  try{
   $afterClick=ViewportStableAxis $active.shell 'DIAGNOSTIC_POST_CLICK_1H'
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$true;
    matches_saved_navigation=(ViewportAxisEquivalent $panned $afterClick 'DIAG_SAVED');
    matches_original_fit=(ViewportAxisEquivalent $baseline $afterClick 'DIAG_FIT');
    pass_authority=$false;scope='isolated_test_only_after_failed_cold_reopen'}|ConvertTo-Json -Compress))
  }catch{
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$false;failure_class='AXIS_NOT_AVAILABLE_AFTER_RESELECT';
    pass_authority=$false}|ConvertTo-Json -Compress))
  }
  throw 'W41_COLD_REOPEN_NATIVE_TIME_AXIS_ABSENT_NOT_ACCEPTED'
 }
 Require (!(ViewportAxisEquivalent $baseline $restored 'NEGATIVE_FIT_CONTENT')) 'W41_REOPEN_RESET_TO_FIT_CONTENT'
 $sameViewport=ViewportAxisEquivalent $panned $restored 'COLD_REOPENED_PRESERVES_FRACTIONAL_VIEWPORT'
 if(!$sameViewport){
  # After the already-failed native screenshot comparison, observe the
  # chart's categorical logical-range stage once more without repair.
  Start-Sleep -Milliseconds 1400
  $later=FindUI $active.shell 'Price chart drawing surface' $false 5
  $lateStage='UNAVAILABLE'
  try{
   $name=[string]$later.Current.Name
   if($name -cmatch 'viewport:([a-z-]{3,40})'){$lateStage=$Matches[1]}
  }catch{}
  Write-Host ('W41_NATIVE_CHART_POST_LAYOUT_STAGE='+$lateStage)
  W41-AxisDifference $panned $restored
  $coldFrame=W41-ReadFrame $active.shell
  $deltas=@()
  if($pannedFrame.available -and $coldFrame.available){
   for($i=0;$i -lt 3;$i++){
    $a=$pannedFrame.points[$i];$b=$coldFrame.points[$i]
    $dx=$null;$dy=$null
    if($null -ne $a.x -and $null -ne $b.x){$dx=$b.x-$a.x}
    if($null -ne $a.y -and $null -ne $b.y){$dy=$b.y-$a.y}
    $deltas+=@{sample=$i;index_equal=($a.index -eq $b.index);x_delta=$dx;y_delta=$dy}
   }
  }
  Write-Host ('W41_NATIVE_LOADED_FRAME_READBACK='+(@{
   before_available=$pannedFrame.available;after_available=$coldFrame.available;
   before_tf=$pannedFrame.tf;after_tf=$coldFrame.tf;
   before_count_matches_api=($pannedFrame.count -eq $firstCandles.count);
   after_count_matches_api=($coldFrame.count -eq $afterRestart.count);
   before_record=$pannedFrame.record;after_record=$coldFrame.record;
   before_live=$pannedFrame.live;after_live=$coldFrame.live;
   same_chart_dimensions=($pannedFrame.width -eq $coldFrame.width -and $pannedFrame.height -eq $coldFrame.height);
   candle_screen_coordinate_deltas=$deltas;pass_authority=$false;
   scope='disposable native UIA only, no OHLCV or digest export'
  }|ConvertTo-Json -Compress -Depth 5))
  $mapFit=W41-CandlePixelMap 'COLD_BASELINE'
  $mapSaved=W41-CandlePixelMap 'COLD_PANNED'
  $mapCold=W41-CandlePixelMap 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_XY_ANCHOR_DIAGNOSTIC='+(@{
   actual_physical_navigation_negative=(W41-CompareCandlePixels $mapFit $mapSaved);
   same_profile_cold_reopen_positive=(W41-CompareCandlePixels $mapSaved $mapCold);
   scope='original_native_candle_up_down_pixels_2d_disposable_profile_2px_window';
   no_acceptance_override=$true
  }|ConvertTo-Json -Compress -Depth 5))
  $columnsFit=W41-CandleColorColumns 'COLD_BASELINE'
  $columnsSaved=W41-CandleColorColumns 'COLD_PANNED'
  $columnsReopen=W41-CandleColorColumns 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_X_ANCHOR_DIAGNOSTIC='+(@{
   negative_fit_vs_saved=(W41-CompareCandleColumns $columnsFit $columnsSaved);
   positive_saved_vs_cold=(W41-CompareCandleColumns $columnsSaved $columnsReopen);
   no_pass_authority=$true;
   scope='original_native_pixels_same_candles_up_down_color_2px_alignment_no_DOM_injection'
  }|ConvertTo-Json -Compress -Depth 6))
 }
 Require $sameViewport 'W41_INSTALLED_COLD_REOPEN_TIME_AXIS_DID_NOT_RESTORE'
 $cap=Invoke-RestMethod -Method Get -Uri ($active.origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and
  $cap.live_orders_enabled -eq $false -and $cap.paper_orders_enabled -eq $false) 'W41_INSTALLED_REOPEN_CHANGED_TRADING_AUTHORITY'
 Write-Host ('W41_REAL_INSTALLED_COLD_AXIS_EVIDENCE='+(@{
  source_sha=$NewSHA;origin_stable=$true;exact_history_reused=$true;
  tf='1h';first=$firstCandles.first;last=$firstCandles.last;count=$firstCandles.count;
  baseline_axis_sha256=$baseline.axis_sha256;after_native_navigation_sha256=$panned.axis_sha256;
  cold_reopened_axis_sha256=$restored.axis_sha256;
  native_input=$true;restarted_selected_shortcut=$true;
  mode='PAPER_STOPPED';live_armed=$false;
  oracle='bounded six-glyph native time-axis matching, not exact DOM logical range';
  scope='ephemeral installed Wails/WebView2, no user profile, no broker'
 }|ConvertTo-Json -Compress))
 Write-Host '::notice::W41_INSTALLED_COLD_FRACTIONAL_CHART_VIEWPORT=PASS'
 W41-Stop $active;$active=$null
 Write-Host '::notice::W41_REAL_INSTALLED_WEBVIEW2_DISARMED_STOP_NO_ORPHANS=PASS'
}finally{
 if($null -ne $active){
  try{[void][W83Native]::PostMessage($active.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)}catch{}
  Write-Warning 'W41_ABORTED_WITH_OWNED_TEST_PROCESS; hosted ephemeral runner is discarded; no replay or owner takeover'
 }
}
){$x=[int]$p[1]}
   if($p[2] -match '^-?[0-9]+
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


# All screenshot pixels stay on this isolated runner. Log only measurement hashes.
Add-Type -AssemblyName System.Drawing
function W41-Candles([string]$origin){
 $data=Invoke-RestMethod -Method Get -Uri ($origin+'/api/candles?product=BTC-USD&tf=1h') -TimeoutSec 20
 $rows=@($data.candles)
 Require ($data.success -eq $true -and $rows.Count -ge 30 -and
  [long]$rows[0].time -gt 0 -and [long]$rows[$rows.Count-1].time -gt [long]$rows[0].time) 'W41_REAL_CANDLE_DATA_UNAVAILABLE'
 # The chart's v2 restore key hashes ALL six fields, not just time boundaries.
 # Match the original JS DataView float64 big-endian byte order without logging
 # source prices, sizes, private profile contents, or market records.
 $bytes=[Collections.Generic.List[byte]]::new()
 foreach($c in $rows){
  foreach($field in @('time','open','high','low','close','volume')){
   $value=[double]$c.$field
   Require (![double]::IsNaN($value) -and ![double]::IsInfinity($value)) 'W41_HISTORY_NONFINITE_FIELD'
   $part=[BitConverter]::GetBytes($value)
   if([BitConverter]::IsLittleEndian){[Array]::Reverse($part)}
   $bytes.AddRange([byte[]]$part)
  }
 }
 $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray())).ToLowerInvariant()
 return [pscustomobject]@{count=$rows.Count;first=[long]$rows[0].time;last=[long]$rows[$rows.Count-1].time;history=$digest}
}
function W41-Start([string]$candidate){
 $chosen=Join-Path $script:installedRoot '.ktrade-w29-install.json'
 Require (Test-Path -LiteralPath $chosen -PathType Leaf) 'W41_INSTALLED_SELECTION_ABSENT'
 $receipt=Get-Content -LiteralPath $chosen -Raw|ConvertFrom-Json
 Require ($receipt.source_sha -ceq $NewSHA -and $receipt.live_armed -eq $false -and
  $receipt.selection_digest -cmatch '^[a-f0-9]{64}$') 'W41_INSTALLED_SOURCE_OR_AUTHORITY_CHANGED'
 $selected=[IO.Path]::GetFullPath($receipt.candidate_directory)
 Require ($selected -ceq [IO.Path]::GetFullPath($candidate) -and
  $selected.StartsWith(([IO.Path]::GetFullPath($script:installedRoot)+'\'),[StringComparison]::OrdinalIgnoreCase)) 'W41_INSTALLED_DIRECTORY_UNTRUSTED'
 $exe=Join-Path $selected 'ktrade.exe'
 Ordinary $exe $false
 $shortcutDir=Join-Path $script:shortcuts ('KTRADE-'+$receipt.selection_digest.Substring(0,16))
 $shortcut=Join-Path $shortcutDir 'KTRADE.lnk'
 $proof=Join-Path $shortcutDir '.ktrade-shortcut-receipt.json'
 Ordinary $shortcut $false
 Ordinary $proof $false
 $owned=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
 Require ($owned.schema -ceq 'ktrade.windows-shortcut.v1' -and
  $owned.source_sha -ceq $NewSHA -and $owned.selection_digest -ceq $receipt.selection_digest -and
  $owned.root -ceq $script:installedRoot -and
  $owned.target -ceq $exe -and (Hash $shortcut) -ceq $owned.link_sha256) 'W41_INSTALLED_SHORTCUT_IDENTITY_INVALID'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_STALE_ACTIVE_LEASE'
 Start-Process -FilePath $shortcut
 $owner=$null
 $limit=(Get-Date).AddSeconds(48)
 do{
  if(Test-Path -LiteralPath $lease){
   try{$value=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json
    if($value.pid -gt 0){$owner=$value;break}}catch{}
  }
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $limit)
 Require ($null -ne $owner -and $owner.source_sha -ceq $NewSHA -and $owner.live_armed -eq $false) 'W41_NO_VERIFIED_INSTALLED_PROCESS_LEASE'
 $shell=Get-Process -Id ([int]$owner.pid) -ErrorAction Stop
 $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shell.Id)
 Require ([string]::Equals($cim.ExecutablePath,$exe,[StringComparison]::OrdinalIgnoreCase)) 'W41_FOREIGN_PROCESS_SOURCE'
 ClickUI $shell 'Desktop diagnostics'
 ClickUI $shell 'Verify chart UI'
 $null=FindUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.' $false 28
 $null=FindUI $shell 'Price chart drawing surface' $false 25
 $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|
  Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
 Require ($children.Count -eq 1) 'W41_INSTALLED_BACKEND_OWNER_CHANGED'
 $ports=@(Get-NetTCPConnection -OwningProcess $children[0].ProcessId -State Listen|
  Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W41_INSTALLED_LOOPBACK_AUTHORITY_CHANGED'
 $origin='http://127.0.0.1:'+$ports[0].LocalPort
 $cap=Invoke-RestMethod -Method Get -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and $cap.paper_orders_enabled -eq $false -and
  $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false -and
  $cap.requires_review -eq $true) 'W41_COLD_NATIVE_TRADING_NOT_DISARMED'
 $html=(Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/chart') -TimeoutSec 12).Content
 Require ($html.Contains('/static/chart_viewport_state.js') -and
  $html.Contains('scheduleViewportSave()')) 'W41_SHIPPING_CHART_NOT_SERVED'
 $js=Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/static/chart_viewport_state.js') -TimeoutSec 12
 Require ($js.StatusCode -eq 200 -and $js.Content.Contains('ktrade.chart-viewport.v2')) 'W41_VIEWPORT_MODULE_NOT_SERVED'
 return [pscustomobject]@{shell=$shell;enginePid=[int]$children[0].ProcessId;origin=$origin}
}
function W41-Stop([object]$run){
 Require ([W83Native]::PostMessage($run.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'W41_NATIVE_CLOSE_REFUSED'
 Require ($run.shell.WaitForExit(30000)) 'W41_NATIVE_SHELL_NOT_STOPPED'
 Require (!(Get-Process -Id $run.enginePid -ErrorAction SilentlyContinue)) 'W41_NATIVE_ENGINE_ORPHAN'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_LEASE_NOT_RELEASED_ON_COLD_STOP'
}
# Do not accept an unpainted time axis as a viewport result. Cold WebView2
# layout/render may lag behind the installed chart's DOM-ready handshake.
# Bound retries to transient missing label ink only. Any real geometry,
# process, layout, or viewport mismatch remains a hard failure.
# Bounded, read-only localStorage LevelDB marker observation on this runner's
# new synthetic installed profile. A hit indicates encoded key presence only;
# missing markers are diagnostic, never a standalone data-loss conclusion.
function W41-ObserveProfileKeys([string]$candidate,[object]$expected){
 $profile=Join-Path $candidate 'data/webview2-profile'
 if(!(Test-Path -LiteralPath $profile -PathType Container)){
  Write-Host 'W41_PROFILE_MARKER_SCAN=UNAVAILABLE_NO_PROFILE';return
 }
 Ordinary $profile $true
 $roots=@(
  (Join-Path $profile 'EBWebView/Default/Local Storage/leveldb'),
  (Join-Path $profile 'Default/Local Storage/leveldb')
 )
 $keys=@('ktrade_chart_viewport_v2:BTC-USD:1h','ktrade_chart_timeframe')
 $patterns=@()
 foreach($key in $keys){
  $patterns+=,[pscustomobject]@{
   ascii=[Text.Encoding]::Latin1.GetString([Text.Encoding]::UTF8.GetBytes($key));
   utf16=[Text.Encoding]::Latin1.GetString([Text.Encoding]::Unicode.GetBytes($key))
  }
 }
 $hit=@($false,$false);$scanned=0;$unreadable=0
 $records=0;$contextRecords=0;$sameHistory=0;$fractionalRecords=0;$parseFailures=0
 foreach($root in $roots){
  if(!(Test-Path -LiteralPath $root -PathType Container)){continue}
  Ordinary $root $true
  $files=@(Get-ChildItem -LiteralPath $root -File -ErrorAction Stop |
   Where-Object {$_.Extension -in @('.ldb','.sst','.log') -and
    $_.Length -le 16777216 -and
    !$_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)} |
   Sort-Object FullName | Select-Object -First 96)
  foreach($file in $files){
   if($scanned -ge 96){break}
   try{$text=[Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($file.FullName))}
   catch{$unreadable++;continue}
   $scanned++
   # Read-only scan of just the disposable test profile's tiny LevelDB log.
   # The original native installed witness never decrypts or migrates storage.
   # Do not publish raw JSON, prices, timestamps, ranges, profile paths or keys.
   if($file.Length -le 1048576){
    try{
     $raw=[IO.File]::ReadAllBytes($file.FullName)
     $views=@($text,[Text.Encoding]::Unicode.GetString($raw,0,($raw.Length-[int]($raw.Length%2))))
     foreach($view in $views){
      $found=[regex]::Matches($view,'\{"schema":"ktrade\.chart-viewport\.v2"[^{}]{0,480}\}')
      foreach($match in $found){
       $records++
       try{
        $row=$match.Value|ConvertFrom-Json
        if($row.schema -cne 'ktrade.chart-viewport.v2' -or
           $row.product -cne 'BTC-USD' -or $row.tf -cne '1h' -or
           [long]$row.count -ne [long]$expected.count -or
           [long]$row.first -ne [long]$expected.first -or
           [long]$row.last -ne [long]$expected.last){continue}
        $contextRecords++
        if([string]$row.history -ceq [string]$expected.history){$sameHistory++}
        $from=[double]$row.from;$to=[double]$row.to
        if([double]::IsFinite($from) -and [double]::IsFinite($to) -and
           $to-$from -ge .75 -and
           ([Math]::Abs($from-[Math]::Round($from)) -gt .02 -or
            [Math]::Abs($to-[Math]::Round($to)) -gt .02)){$fractionalRecords++}
       }catch{$parseFailures++}
      }
     }
    }catch{$parseFailures++}
   }
   for($i=0;$i -lt $keys.Count;$i++){
    if(!$hit[$i] -and ($text.Contains($patterns[$i].ascii) -or
      $text.Contains($patterns[$i].utf16))){$hit[$i]=$true}
   }
  }
 }
 Write-Host ('W41_COLD_PROFILE_V2_VALUE_PROBE='+(@{
  json_candidates=$records;bounded_context_matches=$contextRecords;
  matching_full_history=$sameHistory;fractional_records=$fractionalRecords;
  parse_failures=$parseFailures;
  semantic_proof=$false;scope='test_owned_LevelDB_log_heuristic_only_no_values_or_active_record_proof'
 }|ConvertTo-Json -Compress))
 Write-Host ('W41_COLD_PROFILE_STORAGE_MARKERS='+(@{
  scanned_files=$scanned;unreadable_files=$unreadable;
  viewport_key_present=$hit[0];timeframe_key_present=$hit[1];
  semantic_proof=$false;scope='test-owned profile, key bytes only, no values'
 }|ConvertTo-Json -Compress))
}
function W41-WaitColdAxis([object]$shell){
 $deadline=(Get-Date).AddSeconds(18)
 $attempt=0
 while($true){
  $attempt++
  try{
   $axis=ViewportStableAxis $shell 'COLD_REOPENED'
   Write-Host ('W41_INSTALLED_COLD_AXIS_RENDER_READY_ATTEMPTS='+$attempt)
   return $axis
  }catch{
   if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED' -or
      (Get-Date) -ge $deadline){throw}
   $shell.Refresh()
   Require (!$shell.HasExited) 'W41_SHELL_EXITED_BEFORE_COLD_AXIS_RENDER'
   Start-Sleep -Milliseconds 350
  }
 }
}
Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json'))) 'W41_EXISTING_INSTALLED_DATA_NOT_ALLOWED'
$distribution=Join-Path $QualificationRoot 'unsigned-distribution'
$null=New-Item -ItemType Directory -Path $distribution
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$distribution)
$null=Bundle $distribution $NewSHA
$installed=Setup (Join-Path $distribution 'KTRADE-Setup.ps1') 'Install'
Require ($installed.schema -ceq 'ktrade.fresh-installation.v1' -and
 $installed.source_sha -ceq $NewSHA -and $installed.root -ceq $script:installedRoot -and
 $installed.candidate_directory -cmatch '^[A-Za-z]:[\\/]' -and
 $installed.selection_digest -cmatch '^[a-f0-9]{64}$' -and
 $installed.fresh_only -eq $true -and $installed.app_launched -eq $false -and
 $installed.owner_data_imported -eq $false -and $installed.orders_enabled -eq $false -and
 $installed.live_armed -eq $false -and $installed.release_accepted -eq $false) 'W41_FRESH_INSTALL_NOT_DISARMED'
$active=$null
try{
 $active=W41-Start $installed.candidate_directory
 # 1h is supported end-to-end by the original Coinbase candle backend.
 # A 2h button exists but currently falls through to 1m backend granularity;
 # do not misrepresent that as a stable two-hour historical fixture.
 # If near an hour boundary, admit the next full-hour window so the sealed
 # candle identity cannot roll over during the physical restart check.
 $utc=[DateTime]::UtcNow
 if($utc.Minute -ge 58){
  $nextHour=$utc.AddHours(1)
  $after=[DateTime]::new($nextHour.Year,$nextHour.Month,$nextHour.Day,
   $nextHour.Hour,1,0,[DateTimeKind]::Utc)
  $wait=[int][Math]::Ceiling(($after-$utc).TotalSeconds)
  Require ($wait -gt 0 -and $wait -le 180) 'W41_COLD_HOURLY_WINDOW_ADMISSION_INVALID'
  Write-Host ('W41_HOURLY_CANDLE_ADMISSION_WAIT_SECONDS='+$wait)
  Start-Sleep -Seconds $wait
 }
 ClickUI $active.shell '1h'
 Write-Host 'W41_REAL_NATIVE_1H_TIMEFRAME_CLICKED=PASS'
 Start-Sleep -Milliseconds 1300
 $firstOrigin=$active.origin
 $firstCandles=W41-Candles $firstOrigin
 $baseline=ViewportStableAxis $active.shell 'COLD_BASELINE'
 $node=FindUI $active.shell 'Price chart drawing surface' $false 20
 $rect=$node.Current.BoundingRectangle
 [void][W83Native]::SetForegroundWindow($active.shell.MainWindowHandle)
 Require ([W83Native]::GetForegroundWindow() -eq $active.shell.MainWindowHandle) 'W41_CHART_NOT_FOREGROUND'
 $x=[int]($rect.Left+$rect.Width*0.45);$y=[int]($rect.Top+$rect.Height*0.40)
 Require ([W83Native]::SetCursorPos($x,$y)) 'W41_MOUSE_GEOMETRY_REFUSED'
 [W83Native]::mouse_event(0x0800,0,0,360,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 450
 [W83Native]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 try{
  for($i=1;$i -le 8;$i++){
   Require ([W83Native]::SetCursorPos(($x+[int]($rect.Width*0.22*$i/8)),$y)) 'W41_PHYSICAL_DRAG_REFUSED'
   Start-Sleep -Milliseconds 35
  }
 }finally{[W83Native]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)}
 Start-Sleep -Milliseconds 800
 $panned=ViewportStableAxis $active.shell 'COLD_PANNED'
 Require ($baseline.axis_sha256 -cne $panned.axis_sha256 -and
  !(ViewportAxisEquivalent $baseline $panned 'NEGATIVE_USER_NAVIGATION')) 'W41_NATIVE_CHART_NOT_CHANGED_BY_REAL_INPUT'
 $beforeClose=W41-Candles $firstOrigin
 Require ($beforeClose.count -eq $firstCandles.count -and
  $beforeClose.first -eq $firstCandles.first -and
  $beforeClose.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_DRIFTED_DURING_NAVIGATION'
 W41-Stop $active;$active=$null
 W41-ObserveProfileKeys $installed.candidate_directory $beforeClose
 $active=W41-Start $installed.candidate_directory
 # Read-only UIA metadata can distinguish a lost timeframe preference from
 # viewport-only restoration failure; it cannot substitute for the pixel oracle.
 $reopenTimeframe=FindUI $active.shell '1h' $true 15
 $pressed='UNAVAILABLE'
 try{
  $property=[System.Windows.Automation.AutomationElement]::AriaPropertiesProperty
  if($null -ne $property){
   $props=$reopenTimeframe.GetCurrentPropertyValue($property,$true)
   if($props -is [string]){
    if($props -match '(?:^|;)\\s*pressed=true(?:;|$)'){$pressed='TRUE'}
    elseif($props -match '(?:^|;)\\s*pressed=false(?:;|$)'){$pressed='FALSE'}
   }
  }
 }catch{}
 Write-Host ('W41_COLD_REOPEN_1H_ARIA_PRESSED='+$pressed)
 Require ($active.origin -ceq $firstOrigin) 'W41_INSTALLED_ORIGIN_NOT_STABLE_ACROSS_RESTART'
 $afterRestart=W41-Candles $active.origin
 Require ($afterRestart.count -eq $firstCandles.count -and
  $afterRestart.first -eq $firstCandles.first -and
  $afterRestart.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_CHANGED_SAFE_FALLBACK_NOT_COLD_RESTORE_CASE'
 Write-Host ('W41_INSTALLED_FULL_CANDLE_HISTORY_CUSTODY='+(@{
  initial_matches_preclose=($firstCandles.history -ceq $beforeClose.history);
  initial_matches_reopen=($firstCandles.history -ceq $afterRestart.history);
  preclose_matches_reopen=($beforeClose.history -ceq $afterRestart.history);
  scope='six_field_float64_be_sha256_no_candle_values'
 }|ConvertTo-Json -Compress))
 $chartNative=FindUI $active.shell 'Price chart drawing surface' $false 5
 $stage='UNAVAILABLE'
 try{
  $label=[string]$chartNative.Current.Name
  if($label -cmatch 'viewport:([a-z-]{3,40})'){$stage=$Matches[1]}
 }catch{}
 Write-Host ('W41_NATIVE_CHART_RESTORE_STAGE='+$stage)
 $restored=$null
 try{$restored=W41-WaitColdAxis $active.shell}
 catch{
  # Diagnostic is only entered on missing actual time-axis ink after the
  # bounded 18-second original render wait. A successful refresh cannot
  # retroactively turn the failed *cold restore* into acceptance.
  if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED'){throw}
  $nativeState=@{one_hour_button=$false;one_minute_button=$false;
    chart_surface=$false;data_unavailable=$false;loading_market_data=$false;
    one_hour_toggle='UNAVAILABLE';one_hour_aria='UNAVAILABLE'}
  try{
   $rootEl=[System.Windows.Automation.AutomationElement]::FromHandle($active.shell.MainWindowHandle)
   $nodes=$rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
   foreach($el in $nodes){
    try{
     $label=[string]$el.Current.Name
     if($label -ceq '1h'){$nativeState.one_hour_button=$true}
     if($label -ceq '1m'){$nativeState.one_minute_button=$true}
     if($label.Contains('Price chart drawing surface')){$nativeState.chart_surface=$true}
     if($label.Contains('Market data unavailable')){$nativeState.data_unavailable=$true}
     if($label.Contains('Loading market data')){$nativeState.loading_market_data=$true}
    }catch{}
   }
   $toggle=$null
   if($reopenTimeframe.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$toggle)){
    $nativeState.one_hour_toggle=[string]$toggle.Current.ToggleState
   }
   $aria=$reopenTimeframe.GetCurrentPropertyValue(
    [System.Windows.Automation.AutomationElement]::AriaPropertiesProperty,$true)
   if($aria -is [string]){
    if($aria -match '(?:^|;)\s*pressed=true(?:;|$)'){$nativeState.one_hour_aria='TRUE'}
    elseif($aria -match '(?:^|;)\s*pressed=false(?:;|$)'){$nativeState.one_hour_aria='FALSE'}
   }
  }catch{}
  Write-Host ('W41_COLD_NATIVE_UIA_CLASSIFICATION='+($nativeState|ConvertTo-Json -Compress))
  # Images remain on the disposable runner. Report only coarse palette
  # diversity, never UI text, prices, screenshots, or browser storage values.
  $surface=MarkerCaptureChart $active.shell 'REOPEN_DIAGNOSTIC_ONLY'
  try{
   $bins=@()
   foreach($frac in @(0.25,0.60,0.90)){
    $colors=[Collections.Generic.HashSet[string]]::new()
    $yy=[int][Math]::Floor($surface.bitmap.Height*$frac)
    for($xx=12;$xx -lt $surface.bitmap.Width-12;$xx+=8){
     $px=$surface.bitmap.GetPixel($xx,$yy)
     [void]$colors.Add(('{0}:{1}:{2}' -f ($px.R -shr 5),($px.G -shr 5),($px.B -shr 5)))
    }
    $bins+= $colors.Count
   }
   Write-Host ('W41_COLD_NATIVE_CHART_PALETTE='+(@{top_mid_bottom_distinct_bins=$bins;
     scope='coarse_native_pixel_palette_only_no_chart_data'}|ConvertTo-Json -Compress))
  }finally{$surface.bitmap.Dispose()}
  # One bounded physical 1h reselect distinguishes lost initial timeframe/
  # load/render from a cold-restoration defect. It changes ONLY the newly
  # installed disposable chart, after the cold acceptance has already failed.
  ClickUI $active.shell '1h'
  Start-Sleep -Milliseconds 1600
  try{
   $afterClick=ViewportStableAxis $active.shell 'DIAGNOSTIC_POST_CLICK_1H'
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$true;
    matches_saved_navigation=(ViewportAxisEquivalent $panned $afterClick 'DIAG_SAVED');
    matches_original_fit=(ViewportAxisEquivalent $baseline $afterClick 'DIAG_FIT');
    pass_authority=$false;scope='isolated_test_only_after_failed_cold_reopen'}|ConvertTo-Json -Compress))
  }catch{
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$false;failure_class='AXIS_NOT_AVAILABLE_AFTER_RESELECT';
    pass_authority=$false}|ConvertTo-Json -Compress))
  }
  throw 'W41_COLD_REOPEN_NATIVE_TIME_AXIS_ABSENT_NOT_ACCEPTED'
 }
 Require (!(ViewportAxisEquivalent $baseline $restored 'NEGATIVE_FIT_CONTENT')) 'W41_REOPEN_RESET_TO_FIT_CONTENT'
 $sameViewport=ViewportAxisEquivalent $panned $restored 'COLD_REOPENED_PRESERVES_FRACTIONAL_VIEWPORT'
 if(!$sameViewport){
  # After the already-failed native screenshot comparison, observe the
  # chart's categorical logical-range stage once more without repair.
  Start-Sleep -Milliseconds 1400
  $later=FindUI $active.shell 'Price chart drawing surface' $false 5
  $lateStage='UNAVAILABLE'
  try{
   $name=[string]$later.Current.Name
   if($name -cmatch 'viewport:([a-z-]{3,40})'){$lateStage=$Matches[1]}
  }catch{}
  Write-Host ('W41_NATIVE_CHART_POST_LAYOUT_STAGE='+$lateStage)
  W41-AxisDifference $panned $restored
  $mapFit=W41-CandlePixelMap 'COLD_BASELINE'
  $mapSaved=W41-CandlePixelMap 'COLD_PANNED'
  $mapCold=W41-CandlePixelMap 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_XY_ANCHOR_DIAGNOSTIC='+(@{
   actual_physical_navigation_negative=(W41-CompareCandlePixels $mapFit $mapSaved);
   same_profile_cold_reopen_positive=(W41-CompareCandlePixels $mapSaved $mapCold);
   scope='original_native_candle_up_down_pixels_2d_disposable_profile_2px_window';
   no_acceptance_override=$true
  }|ConvertTo-Json -Compress -Depth 5))
  $columnsFit=W41-CandleColorColumns 'COLD_BASELINE'
  $columnsSaved=W41-CandleColorColumns 'COLD_PANNED'
  $columnsReopen=W41-CandleColorColumns 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_X_ANCHOR_DIAGNOSTIC='+(@{
   negative_fit_vs_saved=(W41-CompareCandleColumns $columnsFit $columnsSaved);
   positive_saved_vs_cold=(W41-CompareCandleColumns $columnsSaved $columnsReopen);
   no_pass_authority=$true;
   scope='original_native_pixels_same_candles_up_down_color_2px_alignment_no_DOM_injection'
  }|ConvertTo-Json -Compress -Depth 6))
 }
 Require $sameViewport 'W41_INSTALLED_COLD_REOPEN_TIME_AXIS_DID_NOT_RESTORE'
 $cap=Invoke-RestMethod -Method Get -Uri ($active.origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and
  $cap.live_orders_enabled -eq $false -and $cap.paper_orders_enabled -eq $false) 'W41_INSTALLED_REOPEN_CHANGED_TRADING_AUTHORITY'
 Write-Host ('W41_REAL_INSTALLED_COLD_AXIS_EVIDENCE='+(@{
  source_sha=$NewSHA;origin_stable=$true;exact_history_reused=$true;
  tf='1h';first=$firstCandles.first;last=$firstCandles.last;count=$firstCandles.count;
  baseline_axis_sha256=$baseline.axis_sha256;after_native_navigation_sha256=$panned.axis_sha256;
  cold_reopened_axis_sha256=$restored.axis_sha256;
  native_input=$true;restarted_selected_shortcut=$true;
  mode='PAPER_STOPPED';live_armed=$false;
  oracle='bounded six-glyph native time-axis matching, not exact DOM logical range';
  scope='ephemeral installed Wails/WebView2, no user profile, no broker'
 }|ConvertTo-Json -Compress))
 Write-Host '::notice::W41_INSTALLED_COLD_FRACTIONAL_CHART_VIEWPORT=PASS'
 W41-Stop $active;$active=$null
 Write-Host '::notice::W41_REAL_INSTALLED_WEBVIEW2_DISARMED_STOP_NO_ORPHANS=PASS'
}finally{
 if($null -ne $active){
  try{[void][W83Native]::PostMessage($active.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)}catch{}
  Write-Warning 'W41_ABORTED_WITH_OWNED_TEST_PROCESS; hosted ephemeral runner is discarded; no replay or owner takeover'
 }
}
){$y=[int]$p[2]}
   $v+= [pscustomobject]@{index=[int]$p[0];x=$x;y=$y}
  }
  return [pscustomobject]@{
   available=($v.Count -eq 3);tf=$m.Groups[1].Value;count=[int]$m.Groups[2].Value;
   record=$m.Groups[3].Value;live=$m.Groups[4].Value;
   width=[int]$m.Groups[5].Value;height=[int]$m.Groups[6].Value;points=@($v)}
 }catch{return [pscustomobject]@{available=$false}}
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


# All screenshot pixels stay on this isolated runner. Log only measurement hashes.
Add-Type -AssemblyName System.Drawing
function W41-Candles([string]$origin){
 $data=Invoke-RestMethod -Method Get -Uri ($origin+'/api/candles?product=BTC-USD&tf=1h') -TimeoutSec 20
 $rows=@($data.candles)
 Require ($data.success -eq $true -and $rows.Count -ge 30 -and
  [long]$rows[0].time -gt 0 -and [long]$rows[$rows.Count-1].time -gt [long]$rows[0].time) 'W41_REAL_CANDLE_DATA_UNAVAILABLE'
 # The chart's v2 restore key hashes ALL six fields, not just time boundaries.
 # Match the original JS DataView float64 big-endian byte order without logging
 # source prices, sizes, private profile contents, or market records.
 $bytes=[Collections.Generic.List[byte]]::new()
 foreach($c in $rows){
  foreach($field in @('time','open','high','low','close','volume')){
   $value=[double]$c.$field
   Require (![double]::IsNaN($value) -and ![double]::IsInfinity($value)) 'W41_HISTORY_NONFINITE_FIELD'
   $part=[BitConverter]::GetBytes($value)
   if([BitConverter]::IsLittleEndian){[Array]::Reverse($part)}
   $bytes.AddRange([byte[]]$part)
  }
 }
 $digest=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray())).ToLowerInvariant()
 return [pscustomobject]@{count=$rows.Count;first=[long]$rows[0].time;last=[long]$rows[$rows.Count-1].time;history=$digest}
}
function W41-Start([string]$candidate){
 $chosen=Join-Path $script:installedRoot '.ktrade-w29-install.json'
 Require (Test-Path -LiteralPath $chosen -PathType Leaf) 'W41_INSTALLED_SELECTION_ABSENT'
 $receipt=Get-Content -LiteralPath $chosen -Raw|ConvertFrom-Json
 Require ($receipt.source_sha -ceq $NewSHA -and $receipt.live_armed -eq $false -and
  $receipt.selection_digest -cmatch '^[a-f0-9]{64}$') 'W41_INSTALLED_SOURCE_OR_AUTHORITY_CHANGED'
 $selected=[IO.Path]::GetFullPath($receipt.candidate_directory)
 Require ($selected -ceq [IO.Path]::GetFullPath($candidate) -and
  $selected.StartsWith(([IO.Path]::GetFullPath($script:installedRoot)+'\'),[StringComparison]::OrdinalIgnoreCase)) 'W41_INSTALLED_DIRECTORY_UNTRUSTED'
 $exe=Join-Path $selected 'ktrade.exe'
 Ordinary $exe $false
 $shortcutDir=Join-Path $script:shortcuts ('KTRADE-'+$receipt.selection_digest.Substring(0,16))
 $shortcut=Join-Path $shortcutDir 'KTRADE.lnk'
 $proof=Join-Path $shortcutDir '.ktrade-shortcut-receipt.json'
 Ordinary $shortcut $false
 Ordinary $proof $false
 $owned=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
 Require ($owned.schema -ceq 'ktrade.windows-shortcut.v1' -and
  $owned.source_sha -ceq $NewSHA -and $owned.selection_digest -ceq $receipt.selection_digest -and
  $owned.root -ceq $script:installedRoot -and
  $owned.target -ceq $exe -and (Hash $shortcut) -ceq $owned.link_sha256) 'W41_INSTALLED_SHORTCUT_IDENTITY_INVALID'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_STALE_ACTIVE_LEASE'
 Start-Process -FilePath $shortcut
 $owner=$null
 $limit=(Get-Date).AddSeconds(48)
 do{
  if(Test-Path -LiteralPath $lease){
   try{$value=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json
    if($value.pid -gt 0){$owner=$value;break}}catch{}
  }
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $limit)
 Require ($null -ne $owner -and $owner.source_sha -ceq $NewSHA -and $owner.live_armed -eq $false) 'W41_NO_VERIFIED_INSTALLED_PROCESS_LEASE'
 $shell=Get-Process -Id ([int]$owner.pid) -ErrorAction Stop
 $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shell.Id)
 Require ([string]::Equals($cim.ExecutablePath,$exe,[StringComparison]::OrdinalIgnoreCase)) 'W41_FOREIGN_PROCESS_SOURCE'
 ClickUI $shell 'Desktop diagnostics'
 ClickUI $shell 'Verify chart UI'
 $null=FindUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.' $false 28
 $null=FindUI $shell 'Price chart drawing surface' $false 25
 $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|
  Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
 Require ($children.Count -eq 1) 'W41_INSTALLED_BACKEND_OWNER_CHANGED'
 $ports=@(Get-NetTCPConnection -OwningProcess $children[0].ProcessId -State Listen|
  Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W41_INSTALLED_LOOPBACK_AUTHORITY_CHANGED'
 $origin='http://127.0.0.1:'+$ports[0].LocalPort
 $cap=Invoke-RestMethod -Method Get -Uri ($origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and $cap.paper_orders_enabled -eq $false -and
  $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false -and
  $cap.requires_review -eq $true) 'W41_COLD_NATIVE_TRADING_NOT_DISARMED'
 $html=(Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/chart') -TimeoutSec 12).Content
 Require ($html.Contains('/static/chart_viewport_state.js') -and
  $html.Contains('scheduleViewportSave()')) 'W41_SHIPPING_CHART_NOT_SERVED'
 $js=Invoke-WebRequest -UseBasicParsing -Uri ($origin+'/static/chart_viewport_state.js') -TimeoutSec 12
 Require ($js.StatusCode -eq 200 -and $js.Content.Contains('ktrade.chart-viewport.v2')) 'W41_VIEWPORT_MODULE_NOT_SERVED'
 return [pscustomobject]@{shell=$shell;enginePid=[int]$children[0].ProcessId;origin=$origin}
}
function W41-Stop([object]$run){
 Require ([W83Native]::PostMessage($run.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'W41_NATIVE_CLOSE_REFUSED'
 Require ($run.shell.WaitForExit(30000)) 'W41_NATIVE_SHELL_NOT_STOPPED'
 Require (!(Get-Process -Id $run.enginePid -ErrorAction SilentlyContinue)) 'W41_NATIVE_ENGINE_ORPHAN'
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 Require (!(Test-Path -LiteralPath $lease)) 'W41_LEASE_NOT_RELEASED_ON_COLD_STOP'
}
# Do not accept an unpainted time axis as a viewport result. Cold WebView2
# layout/render may lag behind the installed chart's DOM-ready handshake.
# Bound retries to transient missing label ink only. Any real geometry,
# process, layout, or viewport mismatch remains a hard failure.
# Bounded, read-only localStorage LevelDB marker observation on this runner's
# new synthetic installed profile. A hit indicates encoded key presence only;
# missing markers are diagnostic, never a standalone data-loss conclusion.
function W41-ObserveProfileKeys([string]$candidate,[object]$expected){
 $profile=Join-Path $candidate 'data/webview2-profile'
 if(!(Test-Path -LiteralPath $profile -PathType Container)){
  Write-Host 'W41_PROFILE_MARKER_SCAN=UNAVAILABLE_NO_PROFILE';return
 }
 Ordinary $profile $true
 $roots=@(
  (Join-Path $profile 'EBWebView/Default/Local Storage/leveldb'),
  (Join-Path $profile 'Default/Local Storage/leveldb')
 )
 $keys=@('ktrade_chart_viewport_v2:BTC-USD:1h','ktrade_chart_timeframe')
 $patterns=@()
 foreach($key in $keys){
  $patterns+=,[pscustomobject]@{
   ascii=[Text.Encoding]::Latin1.GetString([Text.Encoding]::UTF8.GetBytes($key));
   utf16=[Text.Encoding]::Latin1.GetString([Text.Encoding]::Unicode.GetBytes($key))
  }
 }
 $hit=@($false,$false);$scanned=0;$unreadable=0
 $records=0;$contextRecords=0;$sameHistory=0;$fractionalRecords=0;$parseFailures=0
 foreach($root in $roots){
  if(!(Test-Path -LiteralPath $root -PathType Container)){continue}
  Ordinary $root $true
  $files=@(Get-ChildItem -LiteralPath $root -File -ErrorAction Stop |
   Where-Object {$_.Extension -in @('.ldb','.sst','.log') -and
    $_.Length -le 16777216 -and
    !$_.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)} |
   Sort-Object FullName | Select-Object -First 96)
  foreach($file in $files){
   if($scanned -ge 96){break}
   try{$text=[Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($file.FullName))}
   catch{$unreadable++;continue}
   $scanned++
   # Read-only scan of just the disposable test profile's tiny LevelDB log.
   # The original native installed witness never decrypts or migrates storage.
   # Do not publish raw JSON, prices, timestamps, ranges, profile paths or keys.
   if($file.Length -le 1048576){
    try{
     $raw=[IO.File]::ReadAllBytes($file.FullName)
     $views=@($text,[Text.Encoding]::Unicode.GetString($raw,0,($raw.Length-[int]($raw.Length%2))))
     foreach($view in $views){
      $found=[regex]::Matches($view,'\{"schema":"ktrade\.chart-viewport\.v2"[^{}]{0,480}\}')
      foreach($match in $found){
       $records++
       try{
        $row=$match.Value|ConvertFrom-Json
        if($row.schema -cne 'ktrade.chart-viewport.v2' -or
           $row.product -cne 'BTC-USD' -or $row.tf -cne '1h' -or
           [long]$row.count -ne [long]$expected.count -or
           [long]$row.first -ne [long]$expected.first -or
           [long]$row.last -ne [long]$expected.last){continue}
        $contextRecords++
        if([string]$row.history -ceq [string]$expected.history){$sameHistory++}
        $from=[double]$row.from;$to=[double]$row.to
        if([double]::IsFinite($from) -and [double]::IsFinite($to) -and
           $to-$from -ge .75 -and
           ([Math]::Abs($from-[Math]::Round($from)) -gt .02 -or
            [Math]::Abs($to-[Math]::Round($to)) -gt .02)){$fractionalRecords++}
       }catch{$parseFailures++}
      }
     }
    }catch{$parseFailures++}
   }
   for($i=0;$i -lt $keys.Count;$i++){
    if(!$hit[$i] -and ($text.Contains($patterns[$i].ascii) -or
      $text.Contains($patterns[$i].utf16))){$hit[$i]=$true}
   }
  }
 }
 Write-Host ('W41_COLD_PROFILE_V2_VALUE_PROBE='+(@{
  json_candidates=$records;bounded_context_matches=$contextRecords;
  matching_full_history=$sameHistory;fractional_records=$fractionalRecords;
  parse_failures=$parseFailures;
  semantic_proof=$false;scope='test_owned_LevelDB_log_heuristic_only_no_values_or_active_record_proof'
 }|ConvertTo-Json -Compress))
 Write-Host ('W41_COLD_PROFILE_STORAGE_MARKERS='+(@{
  scanned_files=$scanned;unreadable_files=$unreadable;
  viewport_key_present=$hit[0];timeframe_key_present=$hit[1];
  semantic_proof=$false;scope='test-owned profile, key bytes only, no values'
 }|ConvertTo-Json -Compress))
}
function W41-WaitColdAxis([object]$shell){
 $deadline=(Get-Date).AddSeconds(18)
 $attempt=0
 while($true){
  $attempt++
  try{
   $axis=ViewportStableAxis $shell 'COLD_REOPENED'
   Write-Host ('W41_INSTALLED_COLD_AXIS_RENDER_READY_ATTEMPTS='+$attempt)
   return $axis
  }catch{
   if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED' -or
      (Get-Date) -ge $deadline){throw}
   $shell.Refresh()
   Require (!$shell.HasExited) 'W41_SHELL_EXITED_BEFORE_COLD_AXIS_RENDER'
   Start-Sleep -Milliseconds 350
  }
 }
}
Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w29-install.json'))) 'W41_EXISTING_INSTALLED_DATA_NOT_ALLOWED'
$distribution=Join-Path $QualificationRoot 'unsigned-distribution'
$null=New-Item -ItemType Directory -Path $distribution
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$distribution)
$null=Bundle $distribution $NewSHA
$installed=Setup (Join-Path $distribution 'KTRADE-Setup.ps1') 'Install'
Require ($installed.schema -ceq 'ktrade.fresh-installation.v1' -and
 $installed.source_sha -ceq $NewSHA -and $installed.root -ceq $script:installedRoot -and
 $installed.candidate_directory -cmatch '^[A-Za-z]:[\\/]' -and
 $installed.selection_digest -cmatch '^[a-f0-9]{64}$' -and
 $installed.fresh_only -eq $true -and $installed.app_launched -eq $false -and
 $installed.owner_data_imported -eq $false -and $installed.orders_enabled -eq $false -and
 $installed.live_armed -eq $false -and $installed.release_accepted -eq $false) 'W41_FRESH_INSTALL_NOT_DISARMED'
$active=$null
try{
 $active=W41-Start $installed.candidate_directory
 # 1h is supported end-to-end by the original Coinbase candle backend.
 # A 2h button exists but currently falls through to 1m backend granularity;
 # do not misrepresent that as a stable two-hour historical fixture.
 # If near an hour boundary, admit the next full-hour window so the sealed
 # candle identity cannot roll over during the physical restart check.
 $utc=[DateTime]::UtcNow
 if($utc.Minute -ge 58){
  $nextHour=$utc.AddHours(1)
  $after=[DateTime]::new($nextHour.Year,$nextHour.Month,$nextHour.Day,
   $nextHour.Hour,1,0,[DateTimeKind]::Utc)
  $wait=[int][Math]::Ceiling(($after-$utc).TotalSeconds)
  Require ($wait -gt 0 -and $wait -le 180) 'W41_COLD_HOURLY_WINDOW_ADMISSION_INVALID'
  Write-Host ('W41_HOURLY_CANDLE_ADMISSION_WAIT_SECONDS='+$wait)
  Start-Sleep -Seconds $wait
 }
 ClickUI $active.shell '1h'
 Write-Host 'W41_REAL_NATIVE_1H_TIMEFRAME_CLICKED=PASS'
 Start-Sleep -Milliseconds 1300
 $firstOrigin=$active.origin
 $firstCandles=W41-Candles $firstOrigin
 $baseline=ViewportStableAxis $active.shell 'COLD_BASELINE'
 $node=FindUI $active.shell 'Price chart drawing surface' $false 20
 $rect=$node.Current.BoundingRectangle
 [void][W83Native]::SetForegroundWindow($active.shell.MainWindowHandle)
 Require ([W83Native]::GetForegroundWindow() -eq $active.shell.MainWindowHandle) 'W41_CHART_NOT_FOREGROUND'
 $x=[int]($rect.Left+$rect.Width*0.45);$y=[int]($rect.Top+$rect.Height*0.40)
 Require ([W83Native]::SetCursorPos($x,$y)) 'W41_MOUSE_GEOMETRY_REFUSED'
 [W83Native]::mouse_event(0x0800,0,0,360,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 450
 [W83Native]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 try{
  for($i=1;$i -le 8;$i++){
   Require ([W83Native]::SetCursorPos(($x+[int]($rect.Width*0.22*$i/8)),$y)) 'W41_PHYSICAL_DRAG_REFUSED'
   Start-Sleep -Milliseconds 35
  }
 }finally{[W83Native]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)}
 Start-Sleep -Milliseconds 800
 $panned=ViewportStableAxis $active.shell 'COLD_PANNED'
 Require ($baseline.axis_sha256 -cne $panned.axis_sha256 -and
  !(ViewportAxisEquivalent $baseline $panned 'NEGATIVE_USER_NAVIGATION')) 'W41_NATIVE_CHART_NOT_CHANGED_BY_REAL_INPUT'
 $beforeClose=W41-Candles $firstOrigin
 Require ($beforeClose.count -eq $firstCandles.count -and
  $beforeClose.first -eq $firstCandles.first -and
  $beforeClose.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_DRIFTED_DURING_NAVIGATION'
 W41-Stop $active;$active=$null
 W41-ObserveProfileKeys $installed.candidate_directory $beforeClose
 $active=W41-Start $installed.candidate_directory
 # Read-only UIA metadata can distinguish a lost timeframe preference from
 # viewport-only restoration failure; it cannot substitute for the pixel oracle.
 $reopenTimeframe=FindUI $active.shell '1h' $true 15
 $pressed='UNAVAILABLE'
 try{
  $property=[System.Windows.Automation.AutomationElement]::AriaPropertiesProperty
  if($null -ne $property){
   $props=$reopenTimeframe.GetCurrentPropertyValue($property,$true)
   if($props -is [string]){
    if($props -match '(?:^|;)\\s*pressed=true(?:;|$)'){$pressed='TRUE'}
    elseif($props -match '(?:^|;)\\s*pressed=false(?:;|$)'){$pressed='FALSE'}
   }
  }
 }catch{}
 Write-Host ('W41_COLD_REOPEN_1H_ARIA_PRESSED='+$pressed)
 Require ($active.origin -ceq $firstOrigin) 'W41_INSTALLED_ORIGIN_NOT_STABLE_ACROSS_RESTART'
 $afterRestart=W41-Candles $active.origin
 Require ($afterRestart.count -eq $firstCandles.count -and
  $afterRestart.first -eq $firstCandles.first -and
  $afterRestart.last -eq $firstCandles.last) 'W41_CANDLE_HISTORY_CHANGED_SAFE_FALLBACK_NOT_COLD_RESTORE_CASE'
 Write-Host ('W41_INSTALLED_FULL_CANDLE_HISTORY_CUSTODY='+(@{
  initial_matches_preclose=($firstCandles.history -ceq $beforeClose.history);
  initial_matches_reopen=($firstCandles.history -ceq $afterRestart.history);
  preclose_matches_reopen=($beforeClose.history -ceq $afterRestart.history);
  scope='six_field_float64_be_sha256_no_candle_values'
 }|ConvertTo-Json -Compress))
 $chartNative=FindUI $active.shell 'Price chart drawing surface' $false 5
 $stage='UNAVAILABLE'
 try{
  $label=[string]$chartNative.Current.Name
  if($label -cmatch 'viewport:([a-z-]{3,40})'){$stage=$Matches[1]}
 }catch{}
 Write-Host ('W41_NATIVE_CHART_RESTORE_STAGE='+$stage)
 $restored=$null
 try{$restored=W41-WaitColdAxis $active.shell}
 catch{
  # Diagnostic is only entered on missing actual time-axis ink after the
  # bounded 18-second original render wait. A successful refresh cannot
  # retroactively turn the failed *cold restore* into acceptance.
  if($_.Exception.Message -cne 'VIEWPORT_AXIS_LABEL_PIXELS_NOT_OBSERVED'){throw}
  $nativeState=@{one_hour_button=$false;one_minute_button=$false;
    chart_surface=$false;data_unavailable=$false;loading_market_data=$false;
    one_hour_toggle='UNAVAILABLE';one_hour_aria='UNAVAILABLE'}
  try{
   $rootEl=[System.Windows.Automation.AutomationElement]::FromHandle($active.shell.MainWindowHandle)
   $nodes=$rootEl.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
   foreach($el in $nodes){
    try{
     $label=[string]$el.Current.Name
     if($label -ceq '1h'){$nativeState.one_hour_button=$true}
     if($label -ceq '1m'){$nativeState.one_minute_button=$true}
     if($label.Contains('Price chart drawing surface')){$nativeState.chart_surface=$true}
     if($label.Contains('Market data unavailable')){$nativeState.data_unavailable=$true}
     if($label.Contains('Loading market data')){$nativeState.loading_market_data=$true}
    }catch{}
   }
   $toggle=$null
   if($reopenTimeframe.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern,[ref]$toggle)){
    $nativeState.one_hour_toggle=[string]$toggle.Current.ToggleState
   }
   $aria=$reopenTimeframe.GetCurrentPropertyValue(
    [System.Windows.Automation.AutomationElement]::AriaPropertiesProperty,$true)
   if($aria -is [string]){
    if($aria -match '(?:^|;)\s*pressed=true(?:;|$)'){$nativeState.one_hour_aria='TRUE'}
    elseif($aria -match '(?:^|;)\s*pressed=false(?:;|$)'){$nativeState.one_hour_aria='FALSE'}
   }
  }catch{}
  Write-Host ('W41_COLD_NATIVE_UIA_CLASSIFICATION='+($nativeState|ConvertTo-Json -Compress))
  # Images remain on the disposable runner. Report only coarse palette
  # diversity, never UI text, prices, screenshots, or browser storage values.
  $surface=MarkerCaptureChart $active.shell 'REOPEN_DIAGNOSTIC_ONLY'
  try{
   $bins=@()
   foreach($frac in @(0.25,0.60,0.90)){
    $colors=[Collections.Generic.HashSet[string]]::new()
    $yy=[int][Math]::Floor($surface.bitmap.Height*$frac)
    for($xx=12;$xx -lt $surface.bitmap.Width-12;$xx+=8){
     $px=$surface.bitmap.GetPixel($xx,$yy)
     [void]$colors.Add(('{0}:{1}:{2}' -f ($px.R -shr 5),($px.G -shr 5),($px.B -shr 5)))
    }
    $bins+= $colors.Count
   }
   Write-Host ('W41_COLD_NATIVE_CHART_PALETTE='+(@{top_mid_bottom_distinct_bins=$bins;
     scope='coarse_native_pixel_palette_only_no_chart_data'}|ConvertTo-Json -Compress))
  }finally{$surface.bitmap.Dispose()}
  # One bounded physical 1h reselect distinguishes lost initial timeframe/
  # load/render from a cold-restoration defect. It changes ONLY the newly
  # installed disposable chart, after the cold acceptance has already failed.
  ClickUI $active.shell '1h'
  Start-Sleep -Milliseconds 1600
  try{
   $afterClick=ViewportStableAxis $active.shell 'DIAGNOSTIC_POST_CLICK_1H'
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$true;
    matches_saved_navigation=(ViewportAxisEquivalent $panned $afterClick 'DIAG_SAVED');
    matches_original_fit=(ViewportAxisEquivalent $baseline $afterClick 'DIAG_FIT');
    pass_authority=$false;scope='isolated_test_only_after_failed_cold_reopen'}|ConvertTo-Json -Compress))
  }catch{
   Write-Host ('W41_COLD_EXPLICIT_1H_REFRESH_DIAGNOSTIC='+(@{
    native_axis_visible=$false;failure_class='AXIS_NOT_AVAILABLE_AFTER_RESELECT';
    pass_authority=$false}|ConvertTo-Json -Compress))
  }
  throw 'W41_COLD_REOPEN_NATIVE_TIME_AXIS_ABSENT_NOT_ACCEPTED'
 }
 Require (!(ViewportAxisEquivalent $baseline $restored 'NEGATIVE_FIT_CONTENT')) 'W41_REOPEN_RESET_TO_FIT_CONTENT'
 $sameViewport=ViewportAxisEquivalent $panned $restored 'COLD_REOPENED_PRESERVES_FRACTIONAL_VIEWPORT'
 if(!$sameViewport){
  # After the already-failed native screenshot comparison, observe the
  # chart's categorical logical-range stage once more without repair.
  Start-Sleep -Milliseconds 1400
  $later=FindUI $active.shell 'Price chart drawing surface' $false 5
  $lateStage='UNAVAILABLE'
  try{
   $name=[string]$later.Current.Name
   if($name -cmatch 'viewport:([a-z-]{3,40})'){$lateStage=$Matches[1]}
  }catch{}
  Write-Host ('W41_NATIVE_CHART_POST_LAYOUT_STAGE='+$lateStage)
  W41-AxisDifference $panned $restored
  $mapFit=W41-CandlePixelMap 'COLD_BASELINE'
  $mapSaved=W41-CandlePixelMap 'COLD_PANNED'
  $mapCold=W41-CandlePixelMap 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_XY_ANCHOR_DIAGNOSTIC='+(@{
   actual_physical_navigation_negative=(W41-CompareCandlePixels $mapFit $mapSaved);
   same_profile_cold_reopen_positive=(W41-CompareCandlePixels $mapSaved $mapCold);
   scope='original_native_candle_up_down_pixels_2d_disposable_profile_2px_window';
   no_acceptance_override=$true
  }|ConvertTo-Json -Compress -Depth 5))
  $columnsFit=W41-CandleColorColumns 'COLD_BASELINE'
  $columnsSaved=W41-CandleColorColumns 'COLD_PANNED'
  $columnsReopen=W41-CandleColorColumns 'COLD_REOPENED'
  Write-Host ('W41_NATIVE_CANDLE_X_ANCHOR_DIAGNOSTIC='+(@{
   negative_fit_vs_saved=(W41-CompareCandleColumns $columnsFit $columnsSaved);
   positive_saved_vs_cold=(W41-CompareCandleColumns $columnsSaved $columnsReopen);
   no_pass_authority=$true;
   scope='original_native_pixels_same_candles_up_down_color_2px_alignment_no_DOM_injection'
  }|ConvertTo-Json -Compress -Depth 6))
 }
 Require $sameViewport 'W41_INSTALLED_COLD_REOPEN_TIME_AXIS_DID_NOT_RESTORE'
 $cap=Invoke-RestMethod -Method Get -Uri ($active.origin+'/api/operator/capabilities') -TimeoutSec 10
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and
  $cap.live_orders_enabled -eq $false -and $cap.paper_orders_enabled -eq $false) 'W41_INSTALLED_REOPEN_CHANGED_TRADING_AUTHORITY'
 Write-Host ('W41_REAL_INSTALLED_COLD_AXIS_EVIDENCE='+(@{
  source_sha=$NewSHA;origin_stable=$true;exact_history_reused=$true;
  tf='1h';first=$firstCandles.first;last=$firstCandles.last;count=$firstCandles.count;
  baseline_axis_sha256=$baseline.axis_sha256;after_native_navigation_sha256=$panned.axis_sha256;
  cold_reopened_axis_sha256=$restored.axis_sha256;
  native_input=$true;restarted_selected_shortcut=$true;
  mode='PAPER_STOPPED';live_armed=$false;
  oracle='bounded six-glyph native time-axis matching, not exact DOM logical range';
  scope='ephemeral installed Wails/WebView2, no user profile, no broker'
 }|ConvertTo-Json -Compress))
 Write-Host '::notice::W41_INSTALLED_COLD_FRACTIONAL_CHART_VIEWPORT=PASS'
 W41-Stop $active;$active=$null
 Write-Host '::notice::W41_REAL_INSTALLED_WEBVIEW2_DISARMED_STOP_NO_ORPHANS=PASS'
}finally{
 if($null -ne $active){
  try{[void][W83Native]::PostMessage($active.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)}catch{}
  Write-Warning 'W41_ABORTED_WITH_OWNED_TEST_PROCESS; hosted ephemeral runner is discarded; no replay or owner takeover'
 }
}
