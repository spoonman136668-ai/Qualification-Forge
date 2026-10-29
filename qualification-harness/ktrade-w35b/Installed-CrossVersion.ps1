# KTRADE W35B: original native Windows W31 -> W34 installed lifecycle.
# SOURCE-ONLY witness. No broker, owner installation, release or authority changes.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$PreviousBundle,
 [Parameter(Mandatory=$true)][string]$CandidateBundle,
 [Parameter(Mandatory=$true)][string]$QualificationRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$OldSHA='e51e03c22f906704295a24138ac1ceba5d9ea0d4'
$NewSHA='0059d4b794552818b3f32798da7df27c75e21c5c'
function Require([bool]$ok,[string]$name){if(!$ok){throw $name}}
function Hash([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()}
function Ordinary([string]$f,[bool]$dir){
 $obj=Get-Item -LiteralPath $f -Force -ErrorAction Stop
 Require ($obj.PSIsContainer -eq $dir -and !$obj.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) 'W35B_NONORDINARY_ASSET'
}
function Bundle([string]$root,[string]$sha){
 Ordinary $root $true
 $path=Join-Path $root 'installer-manifest.json'
 Ordinary $path $false
 Require ((Get-Item -LiteralPath $path).Length -le 16384) 'W35B_MANIFEST_SIZE_INVALID'
 $m=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 Require ($m.schema -ceq 'ktrade.setup-bundle.v2' -and $m.source_sha -ceq $sha -and
  $m.live_armed -eq $false -and $m.release_authority -ceq 'none' -and
  $m.signature_status -ceq 'unsigned') 'W35B_BUNDLE_AUTHORITY_MISMATCH'
 $wanted=@('KTRADE-Setup.ps1','Manage-KTRADE-FreshInstall.ps1','release-setup.exe',
  'release-launch.exe','release-maintain.exe','KTRADE-Setup.exe','KTRADE-Payload.zip')
 Require (@($m.files).Count -eq $wanted.Count) 'W35B_BUNDLE_FILE_COUNT_CHANGED'
 $seen=@{}
 foreach($row in @($m.files)){
  Require ($wanted -ccontains $row.name -and !$seen.ContainsKey($row.name) -and
   $row.sha256 -cmatch '^[a-f0-9]{64}$' -and $row.size -gt 0) 'W35B_BUNDLE_ITEM_INVALID'
  $seen[$row.name]=$true
  $p=Join-Path $root $row.name
  Ordinary $p $false
  Require ((Get-Item -LiteralPath $p).Length -eq $row.size -and (Hash $p) -ceq $row.sha256) 'W35B_BUNDLE_BYTES_CHANGED'
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
 $proc=Start-Process -FilePath $script:ps51 -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError $errors
 $output=Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
 $errorText=Get-Content -LiteralPath $errors -Raw -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $log,$errors -Force -ErrorAction SilentlyContinue
 if(!$shouldPass){Require ($proc.ExitCode -ne 0) ('W35B_EXPECTED_'+$action+'_REFUSAL_MISSING');return $null}
 Require ($proc.ExitCode -eq 0) ('W35B_'+$action+'_FAILED_'+$errorText)
 try{return ($output|ConvertFrom-Json)}catch{throw ('W35B_'+$action+'_INVALID_RECEIPT')}
}
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
function StartInstalled([string]$maintenance,[object]$receipt,[string]$phase){
 $launch=Join-Path $maintenance 'release-launch.exe'
 Ordinary $launch $false
 $out=Join-Path $QualificationRoot ('app-'+$phase+'.out')
 $err=Join-Path $QualificationRoot ('app-'+$phase+'.err')
 $launcher=Start-Process -FilePath $launch -ArgumentList ('"'+$script:installedRoot+'"') -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
 $lease=Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'
 $until=(Get-Date).AddSeconds(45)
 do{
  $launcher.Refresh()
  Require (!$launcher.HasExited) ('W35B_'+$phase+'_LAUNCH_PREMATURE_EXIT')
  if(Test-Path -LiteralPath $lease){try{$owner=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json;if($owner.pid -gt 0){break}}catch{}}
  Start-Sleep -Milliseconds 300
 }while((Get-Date) -lt $until)
 Require (Test-Path -LiteralPath $lease) ('W35B_'+$phase+'_NO_OWNER_LEASE')
 $owner=Get-Content -LiteralPath $lease -Raw|ConvertFrom-Json
 Require ($owner.source_sha -ceq $receipt.source_sha -and $owner.live_armed -eq $false) 'W35B_SOURCE_OR_DISARM_DRIFT'
 $shell=Get-Process -Id $owner.pid
 $cim=Get-CimInstance Win32_Process -Filter ('ProcessId='+$shell.Id)
 Require ([string]::Equals($cim.ExecutablePath,(Join-Path $receipt.candidate_directory 'ktrade.exe'),[StringComparison]::OrdinalIgnoreCase)) 'W35B_SHELL_EXE_DRIFT'
 $verified=$false
 for($attempt=1;$attempt -le 3;$attempt++){
  ClickUI $shell 'Verify chart UI'
  try{
   $null=FindUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.' $false 12
   $verified=$true
   break
  }catch{
   if($attempt -eq 3){throw ('W35B_'+$phase+'_NATIVE_WEBVIEW2_NOT_VERIFIED')}
   Start-Sleep -Seconds 2
  }
 }
 Require $verified 'W35B_WEBVIEW2_NOT_VERIFIED'
 $engine=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
 Require ($engine.Count -eq 1) 'W35B_NATIVE_ENGINE_OWNERSHIP_DRIFT'
 $ports=@(Get-NetTCPConnection -OwningProcess $engine[0].ProcessId -State Listen|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
 Require ($ports.Count -eq 1) 'W35B_UNEXPECTED_LOOPBACK'
 $cap=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$ports[0].LocalPort+'/api/operator/capabilities') -TimeoutSec 5
 Require ($cap.mode -ceq 'PAPER_STOPPED' -and $cap.paper_orders_enabled -eq $false -and
  $cap.live_orders_enabled -eq $false -and $cap.strategy_execution_enabled -eq $false -and
  $cap.paper_accounting_enabled -eq $false -and $cap.requires_review -eq $true) 'W35B_OPERATOR_CAPABILITIES_DRIFT'
 Write-Output ('::notice::W35B_NATIVE_'+$phase+'_WEBVIEW2_AND_PAPER_STOPPED=PASS')
 return [pscustomobject]@{shell=$shell;launcher=$launcher;enginePid=[int]$engine[0].ProcessId}
}
function StopInstalled([object]$run){
 Require ([W35BNative]::PostMessage($run.shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)) 'W35B_NORMAL_CLOSE_FAILED'
 Require ($run.shell.WaitForExit(30000) -and $run.launcher.WaitForExit(30000) -and $run.launcher.ExitCode -eq 0) 'W35B_PROCESS_SHUTDOWN_FAILED'
 Require (!(Get-Process -Id $run.enginePid -ErrorAction SilentlyContinue)) 'W35B_ORPHAN_ENGINE'
 Require (!(Test-Path -LiteralPath (Join-Path $script:installedRoot '.ktrade-w28c-active-process.lock'))) 'W35B_LEASE_NOT_RELEASED'
 Start-Sleep -Seconds 2
}
Require ($env:OS -ceq 'Windows_NT' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted') 'W35B_EPHEMERAL_WINDOWS_ONLY'
$script:ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
Require (Test-Path -LiteralPath $script:ps51) 'W35B_POWERSHELL_51_MISSING'
$QualificationRoot=[IO.Path]::GetFullPath($QualificationRoot)
$runnerTemp=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
Require (([IO.Path]::GetDirectoryName($QualificationRoot)).TrimEnd('\') -ieq $runnerTemp.TrimEnd('\')) 'W35B_NOT_EPHEMERAL_TEMP_CHILD'
Require (!(Test-Path -LiteralPath $QualificationRoot)) 'W35B_ROOT_ALREADY_EXISTS'
$null=New-Item -ItemType Directory -Path $QualificationRoot
$script:installedRoot=Join-Path $QualificationRoot 'KTRADE-W35B installed with spaces'
$script:shortcuts=Join-Path $QualificationRoot 'Shortcuts'
$null=New-Item -ItemType Directory -Path $script:shortcuts
$null=Bundle $PreviousBundle $OldSHA
$null=Bundle $CandidateBundle $NewSHA
$oldSetup=Join-Path $PreviousBundle 'KTRADE-Setup.ps1'
$newSetup=Join-Path $CandidateBundle 'KTRADE-Setup.ps1'
$script:active=$null
$savedPath=$env:PATH
$env:PATH=(Join-Path $env:WINDIR 'System32')+';'+(Split-Path -Parent $script:ps51)+';'+$env:WINDIR
Require (@(Get-Command go.exe,node.exe -ErrorAction SilentlyContinue).Count -eq 0) 'W35B_BUILD_TOOLS_ON_RUNTIME_PATH'
try{
 $old=Setup $oldSetup 'Install'
 Require ($old.source_sha -ceq $OldSHA -and $old.app_launched -eq $false -and $old.live_armed -eq $false) 'W35B_OLD_INSTALL_DRIFT'
 $oldMaint=Join-Path $script:installedRoot 'maintenance'
 $oldReceiptPath=Join-Path $script:installedRoot '.ktrade-w29-install.json'
 $oldReceiptHash=Hash $oldReceiptPath
 $unknown=Join-Path $script:installedRoot 'unknown-owner-file.bin'
 [IO.File]::WriteAllBytes($unknown,[byte[]](0,255,3,19,73,254))
 $unknownHash=Hash $unknown
 $script:active=StartInstalled $oldMaint $old 'PREVIOUS'
 $null=Setup $newSetup 'Update' $false
 Require ((Hash $oldReceiptPath) -ceq $oldReceiptHash) 'W35B_ACTIVE_UPDATE_MUTATED_RECEIPT'
 StopInstalled $script:active;$script:active=$null
 foreach($item in @(@{path='pine-library/w35b-retained.pine';body='//@version=6 indicator W35B'},
                  @{path='strategies/w35b-retained.pine';body='//@version=6 strategy W35B'},
                  @{path='unknown/w35b-local-state';body='DO_NOT_MIGRATE_THIS_UNKNOWN_STATE'})){
  $path=Join-Path $old.candidate_directory ('data/'+$item.path)
  $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
  [IO.File]::WriteAllText($path,$item.body,[Text.UTF8Encoding]::new($false))
 }
 $oldHashes=Hashes (Join-Path $old.candidate_directory 'data')
 $updated=Setup $newSetup 'Update'
 Require ($updated.schema -ceq 'ktrade.installed-transition.v1' -and $updated.action -ceq 'select' -and
  $updated.before.source_sha -ceq $OldSHA -and $updated.after.source_sha -ceq $NewSHA -and
  $updated.live_armed -eq $false) 'W35B_UPDATE_IDENTITY_INVALID'
 $new=$updated.after
 $newMaint=Join-Path $script:installedRoot ('maintenance-'+(Split-Path -Leaf (Split-Path -Parent $new.candidate_directory)))
 $newSetupInstalled=Join-Path $newMaint 'KTRADE-Setup.ps1'
 $newInspect=Setup $newSetupInstalled 'Inspect'
 Require ($newInspect.source_sha -ceq $NewSHA) 'W35B_UPDATED_MAINTENANCE_MISMATCH'
 AssertHashes $oldHashes (Hashes (Join-Path $old.candidate_directory 'data')) 'W35B_OLD_DATA'
 Require ((Hash (Join-Path $script:installedRoot '.ktrade-w30-before-000002.json')) -ceq $oldReceiptHash) 'W35B_OLD_RECEIPT_BACKUP_DRIFT'
 foreach($rel in @('pine-library/w35b-retained.pine','strategies/w35b-retained.pine')){
  Require ((Hash (Join-Path $old.candidate_directory ('data/'+$rel))) -ceq
   (Hash (Join-Path $new.candidate_directory ('data/'+$rel)))) 'W35B_SUPPORTED_BYTES_CHANGED'
 }
 Require (!(Test-Path -LiteralPath (Join-Path $new.candidate_directory 'data/unknown/w35b-local-state'))) 'W35B_UNSUPPORTED_STATE_MIGRATED'
 Require ((Hash $unknown) -ceq $unknownHash) 'W35B_UNKNOWN_ROOT_BYTES_CHANGED'
 $script:active=StartInstalled $newMaint $new 'UPDATED'
 $null=Setup $newSetupInstalled 'Rollback' $false
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
  $rolled.live_armed -eq $false) 'W35B_ROLLBACK_IDENTITY_INVALID'
 AssertHashes $oldHashes (Hashes (Join-Path $old.candidate_directory 'data')) 'W35B_ROLLBACK_OLD_DATA'
 AssertHashes $newHashes (Hashes (Join-Path $new.candidate_directory 'data')) 'W35B_ROLLBACK_NEW_DATA'
 Require ((Hash $unknown) -ceq $unknownHash) 'W35B_UNKNOWN_ROOT_BYTES_AFTER_ROLLBACK'
 $oldAgain=Setup (Join-Path $oldMaint 'KTRADE-Setup.ps1') 'Inspect'
 Require ($oldAgain.source_sha -ceq $OldSHA) 'W35B_ROLLED_BACK_MAINTENANCE_INVALID'
 $script:active=StartInstalled $oldMaint $oldAgain 'ROLLED_BACK'
 StopInstalled $script:active;$script:active=$null
 AssertHashes $newHashes (Hashes (Join-Path $new.candidate_directory 'data')) 'W35B_RETAINED_NEW_DATA'
 Write-Output '::notice::W35B_W31_TO_W34_REAL_INSTALLED_UPDATE_ROLLBACK=PASS'
 Write-Output '::notice::W35B_NO_OWNER_DATA_NO_LIVE_NO_RELEASE=PASS'
}finally{
 $env:PATH=$savedPath
 if($null -ne $script:active){Write-Warning 'W35B_ABORTED_WITH_OWNED_PROCESS: fail-closed ephemeral runner required; no automatic retry or takeover'}
}
