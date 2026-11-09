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
 $edit=UI $script:window 'Installation folder' ([System.Windows.Automation.ControlType]::Edit)
 Need ($null -ne $edit) 'W107_NATIVE_DESTINATION_INPUT_MISSING'
 $value=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
 Need ($value.Current.Value -ceq $expected) 'W107_OCCUPIED_DEFAULT_NOT_SAFELY_REPLACED'
 $mode=UI $script:window 'Setup operation' ([System.Windows.Automation.ControlType]::ComboBox)
 Need ($null -ne $mode) 'W107_SETUP_MODE_NOT_VISIBLE'
 $button=UI $script:window 'Install' ([System.Windows.Automation.ControlType]::Button)
 Need ($null -ne $button -and $button.Current.IsEnabled) 'W107_NATIVE_INSTALL_CONTROL_MISSING'
 Need (!(Test-Path -LiteralPath $expected)) 'W107_SUGGESTION_UNEXPECTEDLY_CREATED_FOLDER'
 Write-Host '::notice::W107_REAL_NATIVE_SETUP_SUGGESTS_UNUSED_SOURCE_BOUND_SIBLING=PASS'
 # Explicitly override with a test-owned existing directory. The GUI must
 # refuse locally before creating an installation receipt or starting W29.
 $value.SetValue($original)
 Need ($value.Current.Value -ceq $original) 'W107_NATIVE_INPUT_OVERRIDE_REFUSED'
 $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
 $invoke.Invoke()
 $seen=$false
 $limit=(Get-Date).AddSeconds(12)
 do{
  $msg=UI $script:window 'This folder already exists. Choose an unused folder for a new installation.' ([System.Windows.Automation.ControlType]::Text)
  if($null -ne $msg){$seen=$true;break}
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
