# W107 real WinForms setup UI acceptance. Runs only in a disposable
# GitHub-hosted Windows session, with a test-owned LocalAppData collision.
# Never installs, invokes an updater, deletes an owner root or arms trading.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PackageDir)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Need([bool]$v,[string]$why){if(!$v){throw $why}}
Need ($env:OS -ceq 'Windows_NT' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
 $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
 $env:KTRADE_LIVE_TRADING -ceq 'false') 'W107_GITHUB_HOSTED_WINDOWS_DISARMED_ONLY'
$source='4b0bb1cf12d72d09ba16142a8334884b7655df6c'
$expectedShort=$source.Substring(0,8)
$local=[Environment]::GetFolderPath('LocalApplicationData')
Need (![string]::IsNullOrWhiteSpace($local) -and $local -cmatch '^[A-Za-z]:[\\/]' -and
 $local -notmatch 'OneDrive|Dropbox|Documents' -and
 $local -like '*AppData*Local*') 'W107_TEST_LOCAL_APPDATA_NOT_ORDINARY'
$original=Join-Path $local 'KTRADE-Application'
Need (!(Test-Path -LiteralPath $original)) 'W107_PREEXISTING_INSTALL_ROOT_REFUSED'
$sentinel='W107 hosted ephemeral owner-byte preservation sentinel'
[void][IO.Directory]::CreateDirectory($original)
[IO.File]::WriteAllText((Join-Path $original 'w107-test-owned-sentinel.txt'),$sentinel,[Text.UTF8Encoding]::new($false))
# The GUI may only propose a sibling; it must not create that sibling.
$expected=Join-Path $local ('KTRADE-Application-Preview-'+$expectedShort)
Need (!(Test-Path -LiteralPath $expected)) 'W107_EXPECTED_SIBLING_ALREADY_EXISTS'
$exe=Join-Path $PackageDir 'KTRADE-Setup.exe'
Need (Test-Path -LiteralPath $exe -PathType Leaf) 'W107_BOUND_GUI_EXE_MISSING'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$script:launcher=$null;$script:window=$null
function UI([System.Windows.Automation.AutomationElement]$root,[string]$name,[System.Windows.Automation.ControlType]$type){
 $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
 foreach($node in $nodes){try{
  if($node.Current.Name -ceq $name -and $node.Current.ControlType -eq $type -and
    !$node.Current.IsOffscreen){return $node}
 }catch{}}
 return $null
}
# Native handles are a separate check from UIA roles. Some hosted WinForms
# automation providers expose only ControlType.Pane. Use Win32 message
# marshalling exclusively for exact test-owned controls; no process injection.
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class W107Native {
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]
 public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")]
 public static extern bool IsChild(IntPtr parent, IntPtr child);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)]
 public static extern IntPtr Read(IntPtr h,uint msg,IntPtr w,[Out]StringBuilder value,uint flags,uint ms,out IntPtr result);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)]
 public static extern IntPtr Write(IntPtr h,uint msg,IntPtr w,[MarshalAs(UnmanagedType.LPWStr)]string value,uint flags,uint ms,out IntPtr result);
 [DllImport("user32.dll",EntryPoint="SendMessageTimeoutW",CharSet=CharSet.Unicode)]
 public static extern IntPtr Click(IntPtr h,uint msg,IntPtr w,IntPtr value,uint flags,uint ms,out IntPtr result);
 public static string ClassName(IntPtr h){
  var s=new StringBuilder(256);
  return GetClassName(h,s,s.Capacity)>0?s.ToString():String.Empty;
 }
 public static string Caption(IntPtr h){
  var s=new StringBuilder(1024);IntPtr result;
  return Read(h,13,(IntPtr)s.Capacity,s,2,1000,out result)!=IntPtr.Zero?s.ToString():String.Empty;
 }
 public static bool ChangeText(IntPtr h,string value){
  IntPtr result;
  return Write(h,12,IntPtr.Zero,value,2,1000,out result)!=IntPtr.Zero && result!=IntPtr.Zero;
 }
 public static bool Invoke(IntPtr h){
  IntPtr result;
  return Click(h,245,IntPtr.Zero,IntPtr.Zero,2,1000,out result)!=IntPtr.Zero;
 }
}
'@
function NativeControls([System.Windows.Automation.AutomationElement]$root){
 $parent=[IntPtr]$root.Current.NativeWindowHandle
 Need ($parent -ne [IntPtr]::Zero) 'W107_NATIVE_WINDOW_HANDLE_REQUIRED'
 $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  [System.Windows.Automation.Condition]::TrueCondition)
 $out=@();$seen=@{}
 foreach($node in $nodes){try{
  $h=[IntPtr]$node.Current.NativeWindowHandle
  if($h -eq [IntPtr]::Zero -or $seen.ContainsKey($h.ToInt64())){continue}
  if(![W107Native]::IsChild($parent,$h)){continue}
  $seen[$h.ToInt64()]=$true
  $out+=@{h=$h;class=[W107Native]::ClassName($h)}
 }catch{}}
 return $out
}
try{
 $script:launcher=Start-Process -FilePath $exe -WorkingDirectory $PackageDir -PassThru
 Need ($script:launcher.Id -gt 0) 'W107_NATIVE_LAUNCHER_NOT_STARTED'
 $until=(Get-Date).AddSeconds(35)
 do{
  $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId = '+$script:launcher.Id) -ErrorAction SilentlyContinue)
  $ids=@($children|ForEach-Object {[int]$_.ProcessId})
  $all=[System.Windows.Automation.AutomationElement]::RootElement.FindAll(
   [System.Windows.Automation.TreeScope]::Children,
   [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window))
  foreach($item in $all){try{
   if($item.Current.Name -ceq 'KTRADE Setup' -and $ids -contains [int]$item.Current.ProcessId){
    $script:window=$item;break
   }
  }catch{}}
  if($null -ne $script:window){break}
  $script:launcher.Refresh()
  Need (!$script:launcher.HasExited) 'W107_NATIVE_GUI_LAUNCHER_EXITED_EARLY'
  Start-Sleep -Milliseconds 300
 }while((Get-Date) -lt $until)
 Need ($null -ne $script:window) 'W107_REAL_HOSTED_WINFORMS_WINDOW_NOT_OBSERVED'
 # Wait for genuine WinForms controls to become accessible after the native
 # window is created. The bare top-level window can exist before its children.
 # Require controls to settle. WinForms may expose all children as Pane
 # rather than Edit/Button/ComboBox through hosted UIAutomation.
 $edit=$null;$lastTypes=@{};$lastVisible=0;$uiElements=@()
 $readyUntil=(Get-Date).AddSeconds(20)
 do{
  $nodes=$script:window.FindAll([System.Windows.Automation.TreeScope]::Descendants,
   [System.Windows.Automation.Condition]::TrueCondition)
  $edits=@();$lastTypes=@{};$lastVisible=0
  foreach($node in $nodes){try{
   $state=$node.Current;$type=$state.ControlType.ProgrammaticName
   if(!$lastTypes.ContainsKey($type)){$lastTypes[$type]=0}
   $lastTypes[$type]++
   if(!$state.IsOffscreen){$lastVisible++}
   if($state.ControlType -eq [System.Windows.Automation.ControlType]::Edit -and
    !$state.IsOffscreen -and $state.IsEnabled){$edits+=,$node}
  }catch{}}
  if($edits.Count -eq 1){$edit=$edits[0];break}
  Start-Sleep -Milliseconds 350
 }while((Get-Date) -lt $readyUntil)
 $nativeMode=$false
 if($null -eq $edit){
  $nativeMode=$true
  $nativeControls=@(NativeControls $script:window)
  $nativeEdit=@($nativeControls|Where-Object {$_.class -match '(^|\.)EDIT(\.|$)'})
  $nativeCombo=@($nativeControls|Where-Object {$_.class -match '(^|\.)COMBOBOX(\.|$)'})
  $nativeButton=@($nativeControls|Where-Object {
   $_.class -match '(^|\.)BUTTON(\.|$)' -and [W107Native]::Caption($_.h) -ceq 'Install'
  })
  if($nativeEdit.Count -ne 1 -or $nativeCombo.Count -ne 1 -or $nativeButton.Count -ne 1){
   # Only counts and window class names are output; no input or account values.
   $classes=@{};foreach($el in $nativeControls){
    if(!$classes.ContainsKey($el.class)){$classes[$el.class]=0};$classes[$el.class]++
   }
   Write-Host ('W107_WINDOWS_NATIVE_CONTROL_DIAGNOSTIC='+(@{
    uia_total_nodes=$nodes.Count;uia_types=$lastTypes;
    child_hwnd_count=$nativeControls.Count;native_class_counts=$classes;
    edit_count=$nativeEdit.Count;combo_count=$nativeCombo.Count;
    install_button_count=$nativeButton.Count
   }|ConvertTo-Json -Compress -Depth 5))
   throw 'W107_WINFORMS_NATIVE_CONTROL_OWNERSHIP_NOT_PROVABLE'
  }
  $actual=[W107Native]::Caption($nativeEdit[0].h)
  Need ($actual -ceq $expected) 'W107_NATIVE_OCCUPIED_DEFAULT_NOT_SAFELY_REPLACED'
 }else{
  $value=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
  Need ($value.Current.Value -ceq $expected) 'W107_OCCUPIED_DEFAULT_NOT_SAFELY_REPLACED'
  $mode=UI $script:window 'Setup operation' ([System.Windows.Automation.ControlType]::ComboBox)
  Need ($null -ne $mode) 'W107_SETUP_MODE_NOT_VISIBLE'
  $button=UI $script:window 'Install' ([System.Windows.Automation.ControlType]::Button)
  Need ($null -ne $button -and $button.Current.IsEnabled) 'W107_NATIVE_INSTALL_CONTROL_MISSING'
 }
 Need (!(Test-Path -LiteralPath $expected)) 'W107_SUGGESTION_UNEXPECTEDLY_CREATED_FOLDER'
 Write-Host '::notice::W107_REAL_NATIVE_SETUP_SUGGESTS_UNUSED_SOURCE_BOUND_SIBLING=PASS'
 # Test-owned existing root only. A click must refuse without invoking
 # release-setup.exe or creating any installation receipt.
 if($nativeMode){
  Need ([W107Native]::ChangeText($nativeEdit[0].h,$original)) 'W107_WIN32_SET_TEXT_FAILED'
  Need ([W107Native]::Caption($nativeEdit[0].h) -ceq $original) 'W107_WIN32_TEXT_NOT_CHANGED'
  Need ([W107Native]::Invoke($nativeButton[0].h)) 'W107_WIN32_EXACT_INSTALL_BUTTON_INVOKE_FAILED'
 }else{
  $value.SetValue($original)
  Need ($value.Current.Value -ceq $original) 'W107_NATIVE_INPUT_OVERRIDE_REFUSED'
  $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
  $invoke.Invoke()
 }
 $seen=$false
 $limit=(Get-Date).AddSeconds(12)
 do{
  if($nativeMode){
   foreach($el in $nativeControls){
    if([W107Native]::Caption($el.h) -ceq 'This folder already exists. Choose an unused folder for a new installation.'){$seen=$true;break}
   }
  }else{
   $msg=UI $script:window 'This folder already exists. Choose an unused folder for a new installation.' ([System.Windows.Automation.ControlType]::Text)
   if($null -ne $msg){$seen=$true}
  }
  if($seen){break}
  Start-Sleep -Milliseconds 250
 }while((Get-Date) -lt $limit)
 Need $seen 'W107_REAL_NATIVE_EXISTING_ROOT_ERROR_NOT_SHOWN'
 Need (([IO.File]::ReadAllText((Join-Path $original 'w107-test-owned-sentinel.txt')) -ceq $sentinel) -and
  !(Test-Path -LiteralPath (Join-Path $original '.ktrade-w29-install.json')) -and
  !(Test-Path -LiteralPath (Join-Path $original '.ktrade-w29-install-incomplete')) -and
  !(Test-Path -LiteralPath $expected)) 'W107_OCCUPIED_ROOT_OR_SUGGESTED_ROOT_MUTATED'
 Write-Host '::notice::W107_REAL_NATIVE_CLICK_REFUSES_OCCUPIED_ROOT_WITHOUT_INSTALL=PASS'
}finally{
 if($null -ne $script:window){try{
  $windowPattern=$script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
  $windowPattern.Close()
 }catch{}}
 if($null -ne $script:launcher){
  try{if(!$script:launcher.HasExited){
   Need ($script:launcher.WaitForExit(15000)) 'W107_GUI_FAILED_TO_CLOSE_NORMALLY'
  }}finally{$script:launcher.Dispose()}
 }
}
Need (([IO.File]::ReadAllText((Join-Path $original 'w107-test-owned-sentinel.txt')) -ceq $sentinel)) 'W107_TEST_ROOT_CHANGED_ON_EXIT'
Write-Host ('W107_NATIVE_UI_EVIDENCE='+(@{
 source_sha=$source;gui='KTRADE-Setup.exe';default_was_occupied=$true;
 proposed_unused_sibling=$true;actual_occupied_root_click_refused=$true;
 owner_data_accessed=$false;installation_performed=$false;live_armed=$false
}|ConvertTo-Json -Compress))
Write-Host '::notice::W107_EXACT_UNSIGNED_INSTALLER_REAL_WINFORMS_UI=PASS'
