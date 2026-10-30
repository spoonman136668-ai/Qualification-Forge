$ErrorActionPreference='Stop'
$env:TEMP=$env:RUNNER_TEMP;$env:TMP=$env:RUNNER_TEMP
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W32EDpi { [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd); }
public static class W32EClose { [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd,uint msg,IntPtr a,IntPtr b); }
public static class W32ENativeInput {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int X;public int Y;}
 [DllImport("user32.dll")] public static extern bool GetPhysicalCursorPos(out POINT point);
 [DllImport("user32.dll")] public static extern void mouse_event(uint f,uint a,uint b,uint c,UIntPtr d);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
}
'@
# Interact solely via owned Windows screen/UIA/OS keyboard.
# No JavaScript, inspector, DOM hooks or renderer mutation.
# Both Pine and volume coordinates use exact UIA and LWC formulas; default price guides do not imply extra bars.
function Report-W32EUI([object]$proc,[string]$phase){
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
  $elements=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $items=[Collections.Generic.List[object]]::new()
  foreach($e in $elements){try{
    $v=$e.Current
    if(!$v.IsOffscreen -and $v.Name -match '(BTC|USD|Coinbase|symbol|Search|Pine|chart)' -and $items.Count -lt 40){
      $items.Add([pscustomobject]@{name=$v.Name;type=[string]$v.ControlType.ProgrammaticName;rect=[string]$v.BoundingRectangle})
    }
  }catch{}}
  Write-Output ('W32E_UIA_STATE_'+$phase+'='+($items|ConvertTo-Json -Compress -Depth 4))
}
function Wait-W32EUI([object]$proc,[string]$name,[int]$seconds=22){
  $until=(Get-Date).AddSeconds($seconds)
  do{
    $proc.Refresh();if($proc.HasExited){throw ('W32E_BROWSER_EXITED_'+$name)}
    if($proc.MainWindowHandle -ne [IntPtr]::Zero){
      $root=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
      $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
      foreach($el in $all){try{
        $exact=([string]$el.Current.Name) -ceq $name
        $matching=if($name -ceq 'BTC-USDC'){$exact}else{$exact -or ([string]$el.Current.Name).Contains($name)}
        if(!$el.Current.IsOffscreen -and $matching -and !$el.Current.BoundingRectangle.IsEmpty){return $el}
      }catch{}}
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $until)
  throw ('W32E_UI_NOT_FOUND_'+$name)
}
function Click-W32EUI([object]$proc,[string]$name){
  $el=Wait-W32EUI $proc $name
  $rect=$el.Current.BoundingRectangle
  $outer=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle).Current.BoundingRectangle
  if($rect.IsEmpty -or $rect.Width -lt 5 -or $rect.Height -lt 5 -or $rect.Left -lt $outer.Left -or $rect.Right -gt $outer.Right -or $rect.Top -lt $outer.Top -or $rect.Bottom -gt $outer.Bottom){throw ('W32E_UI_CONTROL_NOT_OWNED_'+$name)}
  [void][W32ENativeInput]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 150
  if([W32ENativeInput]::GetForegroundWindow() -ne $proc.MainWindowHandle){throw 'W32E_FOREIGN_FOCUS'}
  $targetX=[int]($rect.Left+$rect.Width/2);$targetY=[int]($rect.Top+$rect.Height/2)
  $inputX=$targetX;$inputY=$targetY
  $pos=[W32ENativeInput+POINT]::new()
  for($attempt=0;$attempt -lt 4;$attempt++){
    if(![W32ENativeInput]::SetCursorPos($inputX,$inputY)){throw 'W32E_NATIVE_CURSOR_REFUSED'}
    Start-Sleep -Milliseconds 180
    if(![W32ENativeInput]::GetPhysicalCursorPos([ref]$pos)){throw 'W32E_NATIVE_PHYSICAL_CURSOR_UNAVAILABLE'}
    if([Math]::Abs($pos.X-$targetX) -le 3 -and [Math]::Abs($pos.Y-$targetY) -le 3){break}
    $inputX=[int][Math]::Round($inputX*[double]$targetX/[Math]::Max(1,$pos.X))
    $inputY=[int][Math]::Round($inputY*[double]$targetY/[Math]::Max(1,$pos.Y))
  }
  Write-Output ('W32E_PHYSICAL_POINTER_'+$name+'='+(@{target_x=$targetX;target_y=$targetY;physical_x=$pos.X;physical_y=$pos.Y;logical_input_x=$inputX;logical_input_y=$inputY}|ConvertTo-Json -Compress))
  if([Math]::Abs($pos.X-$targetX) -gt 5 -or [Math]::Abs($pos.Y-$targetY) -gt 5){throw ('W32E_CLICK_COORDINATES_NOT_PHYSICAL_'+$name)}
  $point=[System.Windows.Point]::new([double]$pos.X,[double]$pos.Y)
  $actual=[System.Windows.Automation.AutomationElement]::FromPoint($point)
  Write-Output ('W32E_HIT_TEST_'+$name+'='+$actual.Current.Name)
  [W32ENativeInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 85
  [W32ENativeInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 220
}
function Shortcut-W32E([byte]$key){
  [W32ENativeInput]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 45
  [W32ENativeInput]::keybd_event($key,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 45
  [W32ENativeInput]::keybd_event($key,0,2,[UIntPtr]::Zero)
  [W32ENativeInput]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 170
}
function Set-W32EPine([object]$proc,[string]$source){
  $editor=Wait-W32EUI $proc 'Pine source editor'
  if($editor.Current.ControlType -ne [System.Windows.Automation.ControlType]::Edit){throw 'W32E_REAL_MONACO_NOT_EDIT'}
  $r=$editor.Current.BoundingRectangle;$outer=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle).Current.BoundingRectangle
  $x=[int]($r.Left+12);$y=[int]($r.Top+9)
  if($x -lt $outer.Left -or $x -ge $outer.Right -or $y -lt $outer.Top -or $y -ge $outer.Bottom){throw 'W32E_MONACO_OUTSIDE_OWNED_WINDOW'}
  $quoted="'"+$source.Replace("'","''")+"'"
  $code="Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.Clipboard]::SetText("+$quoted+")"
  $ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  & $ps51 -NoProfile -STA -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))
  if($LASTEXITCODE -ne 0){throw 'W32E_SYNTHETIC_PINE_CLIPBOARD_FAILED'}
  [void][W32ENativeInput]::SetForegroundWindow($proc.MainWindowHandle)
  [void][W32ENativeInput]::SetCursorPos($x,$y)
  [W32ENativeInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[W32ENativeInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
  if([W32ENativeInput]::GetForegroundWindow() -ne $proc.MainWindowHandle){throw 'W32E_MONACO_FOCUS_CHANGED'}
  $focused=[System.Windows.Automation.AutomationElement]::FocusedElement
  if(!$focused.Equals($editor)){throw 'W32E_MONACO_EDIT_FOCUS_NOT_CONFIRMED'}
  Shortcut-W32E 0x41
  Shortcut-W32E 0x56
  $null=Wait-W32EUI $proc 'Editor changed. Compile again.'
}
