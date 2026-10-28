Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W30Native {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint dx,uint dy,uint data,UIntPtr info);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd,System.Text.StringBuilder name,int count);
}
public static class W32BWindow { [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd,uint command); }
'@
$ps51=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
function W31-NativeClass([object]$element){
 $h=[IntPtr]$element.Current.NativeWindowHandle
 if($h -eq [IntPtr]::Zero){return ''}
 $name=New-Object Text.StringBuilder(512)
 if([W30Native]::GetClassName($h,$name,512) -le 0){return ''}
 return $name.ToString()
}
function Put-Clipboard([string]$text){
 $literal="'"+$text.Replace("'","''")+"'"
 $code="Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.Clipboard]::SetText("+$literal+");if([Windows.Forms.Clipboard]::GetText() -cne "+$literal+"){throw 'Clipboard fixture mismatch'}"
 & $ps51 -NoProfile -STA -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))
 if($LASTEXITCODE -ne 0){throw 'W32B_NATIVE_CLIPBOARD_FIXTURE_FAILED'}
}
function Owned-Roots([object]$process){
 $main=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
 $result=@($main)
 $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
 foreach($window in $windows){
  try{
   $h=[IntPtr]$window.Current.NativeWindowHandle
   if($h -eq [IntPtr]::Zero -or $h -eq $process.MainWindowHandle){continue}
   $owner=$h;$belongs=$false
   for($i=0;$i -lt 8;$i++){$owner=[W32BWindow]::GetWindow($owner,4);if($owner -eq $process.MainWindowHandle){$belongs=$true;break};if($owner -eq [IntPtr]::Zero){break}}
   if($belongs -or $window.Current.ProcessId -eq $process.Id){$result+=,$window}
  }catch{}
 }
 return $result
}
function Pine-Dialog([object]$process,[string]$message,[string]$answer,[string]$value=''){
 $until=(Get-Date).AddSeconds(15)
 $clicks=0
 :DialogSearch do{
  foreach($root in (Owned-Roots $process)){
   $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
   foreach($node in $nodes){
    if($node.Current.IsOffscreen -or !([string]$node.Current.Name).Contains($message)){continue}
    $scope=$node
    for($level=0;$level -lt 8 -and $null -ne $scope;$level++){
     $all=$scope.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
     $buttons=@($all|Where-Object {!$_.Current.IsOffscreen -and $_.Current.IsEnabled -and $_.Current.Name -ceq $answer -and ($_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button -or (W31-NativeClass $_) -match 'BUTTON')})
     $edits=@($all|Where-Object {!$_.Current.IsOffscreen -and $_.Current.IsEnabled -and ($_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit -or (W31-NativeClass $_) -match 'EDIT')})
     if($buttons.Count -eq 1 -and (!$value -or $edits.Count -eq 1)){
      $handle=[IntPtr]$root.Current.NativeWindowHandle
      if($handle -eq [IntPtr]::Zero){$handle=$process.MainWindowHandle}
      [void][W30Native]::SetForegroundWindow($handle);Start-Sleep -Milliseconds 150
      if($value){Put-Clipboard $value;[void][W30Native]::SetForegroundWindow($handle);$edits[0].SetFocus();[Windows.Forms.SendKeys]::SendWait('^a');[Windows.Forms.SendKeys]::SendWait('^v')}
      $rect=$buttons[0].Current.BoundingRectangle;$outer=$root.Current.BoundingRectangle
      if($rect.IsEmpty -or $rect.Left -lt $outer.Left -or $rect.Right -gt $outer.Right -or $rect.Top -lt $outer.Top -or $rect.Bottom -gt $outer.Bottom){throw 'W32B_FOREIGN_SCRIPT_DIALOG_CONTROL'}
      if([W30Native]::GetForegroundWindow() -ne $handle){throw 'W32B_FOREIGN_SCRIPT_DIALOG_FOCUS'}
      [void][W30Native]::SetCursorPos([int]($rect.Left+$rect.Width/2),[int]($rect.Top+$rect.Height/2))
      Write-Output ('W32B_OWNED_DIALOG_CLICK='+(@{message=$message;answer=$answer;nativeClass=(W31-NativeClass $buttons[0]);rootHandle=$handle.ToInt64();rectangle=$rect.ToString()}|ConvertTo-Json -Compress))
      [W30Native]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 100;[W30Native]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
      $clicks++
      $settle=(Get-Date).AddSeconds(2)
      $clearPasses=0
      do{
       $present=$false
       foreach($currentRoot in (Owned-Roots $process)){
        try{
         $currentNodes=$currentRoot.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
         foreach($currentNode in $currentNodes){if(!$currentNode.Current.IsOffscreen -and ([string]$currentNode.Current.Name).Contains($message)){$present=$true;break}}
        }catch [System.Windows.Automation.ElementNotAvailableException]{$present=$true}
       }
       if($present){$clearPasses=0}else{$clearPasses++}
       if($clearPasses -ge 2){Write-Output ('W32B_OWNED_DIALOG_DISMISSED='+$message);return}
       Start-Sleep -Milliseconds 150
      }while((Get-Date) -lt $settle)
      if($clicks -ge 3){throw ('W32B_OWNED_DIALOG_NOT_DISMISSED_'+$message)}
      continue DialogSearch
     }
     $scope=[System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($scope)
    }
   }
  }
  Start-Sleep -Milliseconds 200
 }while((Get-Date) -lt $until)
 throw ('W32B_SCRIPT_DIALOG_ABSENT_'+$message)
}
function W33-Field([object]$process,[string]$name,[string]$value){
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
 $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
 $matches=@($all|Where-Object {!$_.Current.IsOffscreen -and $_.Current.IsEnabled -and $_.Current.IsKeyboardFocusable -and $_.Current.Name -ceq $name})
 if($matches.Count -ne 1){throw ('W33_NATIVE_FIELD_UNVERIFIED_'+$name)}
 $el=$matches[0]
 Put-Clipboard $value
 $r=$el.Current.BoundingRectangle;$outer=$root.Current.BoundingRectangle
 if($r.IsEmpty -or $r.Left -lt $outer.Left -or $r.Right -gt $outer.Right -or $r.Top -lt $outer.Top -or $r.Bottom -gt $outer.Bottom){throw 'W33_NATIVE_FIELD_NOT_OWNED'}
 [void][W32ENativeInput]::SetForegroundWindow($process.MainWindowHandle)
 [void][W32ENativeInput]::SetCursorPos([int]($r.Left+$r.Width/2),[int]($r.Top+$r.Height/2))
 if([W32ENativeInput]::GetForegroundWindow() -ne $process.MainWindowHandle){throw 'W33_NATIVE_FIELD_FOREIGN_FOCUS'}
 [W32ENativeInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[W32ENativeInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 $el.SetFocus()
 Shortcut-W32E 0x41
 Shortcut-W32E 0x56
}
function W33-Get([string]$path){return Invoke-RestMethod -Uri ($uri+$path) -TimeoutSec 12}
function W33-CheckAccount([object]$account){
 if($account.schema -cne 'ktrade.paper.account.read-only.v1' -or $account.orders_enabled -ne $false -or $account.live_armed -ne $false -or @($account.products).Count -ne 1){throw 'W33_ORIGINAL_ACCOUNT_SCHEMA_UNVERIFIED'}
 $p=$account.products[0]
 if($p.product_id -cne 'BTC-USDC' -or $p.cash -cne '567.4275' -or $p.position_qty -cne '0.25' -or $p.cost_basis -cne '32.5725' -or $p.fees_paid -cne '0.3225' -or $p.realized_pnl -cne '0' -or $p.fill_count -ne 1){throw ('W33_ORIGINAL_FIFO_FEE_ACCOUNT_DIFFERS_'+($p|ConvertTo-Json -Compress))}
 return $p
}
function W33-Close([object]$process){
 $process.Refresh()
 if($process.HasExited){throw 'W33_NATIVE_SHELL_EXITED_BEFORE_CLOSE'}
 [void][W32EClose]::PostMessage($process.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)
 if(!$process.WaitForExit(15000) -or $process.ExitCode -ne 0){throw 'W33_NORMAL_NATIVE_CLOSE_FAILED'}
 $left=Get-Process -Id $engine.ProcessId -ErrorAction SilentlyContinue
 if($null -ne $left -and !$left.WaitForExit(10000)){throw 'W33_NATIVE_GO_CHILD_ORPHANED'}
}
function Run-W33NativePaper {
 $initial=W33-Get '/api/paper/session'
 if($initial.mode -cne 'PAPER_NOT_FUNDED' -or $initial.paper_orders_enabled -ne $false -or $initial.live_armed -ne $false){throw 'W33_INITIAL_FRESH_SESSION_NOT_DISARMED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'BTCUSD'
 Click-W32EUI $shell 'BTC-USDC'
 $null=Wait-W32EUI $shell 'BTCUSDC'
 Click-W32EUI $shell 'Pine Editor'
 $source="//@version=6`nstrategy(`"W33A native saved paper`", overlay=true)`nif bar_index == 29`n    strategy.entry(`"L`", strategy.long, qty=0.25)"
 Set-W32EPine $shell $source
 Click-W32EUI $shell 'Compile'
 $null=Wait-W32EUI $shell 'Compiled. Not applied or started.'
 Click-W32EUI $shell 'Save'
 Pine-Dialog $shell 'Save Pine script as' 'OK' 'W33A native saved paper'
 $null=Wait-W32EUI $shell 'Pine script durably saved; not automatically applied'
 $library=W33-Get '/api/pine-library'
 $saved=@($library.scripts|Where-Object {$_.display_name -ceq 'W33A native saved paper' -and $_.ownership -ceq 'user' -and $_.kind -ceq 'strategy'})
 if($saved.Count -ne 1){throw 'W33_NATIVE_SAVED_STRATEGY_NOT_DURABLE'}
 $stored=W33-Get ('/api/pine-library/'+$saved[0].id)
 if($stored.source.Replace("`r`n","`n") -cne $source){throw 'W33_NATIVE_SAVED_SOURCE_DIFFERS'}
 W33-Field $shell 'Paper USDC' '600'
 W33-Field $shell 'Simulated fee (bps)' '100'
 Click-W32EUI $shell 'Acknowledge simulated paper fees'
 $second=(Get-Date).Second
 if($second -ge 25){Start-Sleep -Seconds (65-$second)}
 $minute=[int64][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()/60)
 Click-W32EUI $shell 'Start isolated paper'
 $null=Wait-W32EUI $shell 'ISOLATED PAPER RUNNING' 15
 $running=W33-Get '/api/paper/session'
 $caps=W33-Get '/api/operator/capabilities'
 $runningCaps=$caps
 if($running.mode -cne 'PAPER_ISOLATED_RUNNING' -or $running.paper_orders_enabled -ne $true -or $running.durable_custody_enabled -ne $true -or $running.unattended_enabled -ne $true -or $caps.mode -cne $running.mode -or $caps.paper_orders_enabled -ne $true -or $caps.strategy_execution_enabled -ne $true -or $caps.paper_accounting_enabled -ne $true -or $caps.requires_review -ne $false -or $caps.live_orders_enabled -ne $false){throw 'W33_RUNNING_CAPABILITIES_DIVERGE_FROM_ORIGINAL_OWNER'}
 $firstArchive=W33-Get '/api/paper/session/archive'
 if($firstArchive.source_id -cnotmatch '^ktrade-reconcile-[a-z0-9]{12,48}$'){throw 'W33_INITIAL_SOURCE_ID_UNSAFE'}
 [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP 'w33-paper-source.txt'),$firstArchive.source_id)
 Click-W32EUI $shell 'Evaluate final bar'
 $null=Wait-W32EUI $shell 'fills 1' 15
 $first=W33-Get '/api/paper/session'
 $account=W33-Get '/api/paper/accounting'
 $product=W33-CheckAccount $account
 Click-W32EUI $shell 'Evaluate final bar'
 Start-Sleep -Milliseconds 500
 $secondState=W33-Get '/api/paper/session'
 if($secondState.fill_count -ne 1 -or $secondState.last_ledger_hash -cne $first.last_ledger_hash -or $secondState.evaluation_cycles -le $first.evaluation_cycles){throw 'W33_REPEATED_NATIVE_EVALUATION_DUPLICATED_OR_NOT_EXECUTED'}
 Click-W32EUI $shell 'Paper account'
 $null=Wait-W32EUI $shell 'Cash 567.4275 USDC' 10
 $null=Wait-W32EUI $shell 'Fees 0.3225' 10
 Click-W32EUI $shell 'Stop paper'
 $null=Wait-W32EUI $shell 'PAPER_STOPPED' 12
 $stopped=W33-Get '/api/paper/session'
 $caps=W33-Get '/api/operator/capabilities'
 if($stopped.stopped -ne $true -or $stopped.paper_orders_enabled -ne $false -or $stopped.unattended_enabled -ne $false -or $stopped.durable_custody_enabled -ne $false -or $caps.mode -cne 'PAPER_STOPPED' -or $caps.paper_orders_enabled -ne $false -or $caps.strategy_execution_enabled -ne $false -or $caps.paper_accounting_enabled -ne $false -or $caps.live_orders_enabled -ne $false){throw 'W33_NATIVE_STOP_NOT_DURABLY_DISARMED'}
 if([int64][Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()/60) -ne $minute){throw 'W33_DUPLICATE_CHECK_CROSSED_FIXTURE_MINUTE'}
 $archive=W33-Get '/api/paper/session/archive'
 if($archive.original_risk_proof_verified -ne $true -or $archive.execution_restore_eligible -ne $false -or $archive.account.stopped -ne $true -or $archive.orders_enabled -ne $false){throw 'W33_ORIGINAL_STOP_ARCHIVE_UNVERIFIED'}
 $null=W33-CheckAccount $archive.account
 if($archive.source_id -cnotmatch '^ktrade-reconcile-[a-z0-9]{12,48}$'){throw 'W33_SOURCE_ID_UNSAFE'}
 [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP 'w33-paper-source.txt'),$archive.source_id)
 Write-Output ('W33_NATIVE_PAPER_OWNER_PROOF='+(@{script_id=$saved[0].id;source_sha256=$running.source_sha256;mode_running=$running.mode;running_capabilities=$runningCaps;fill_count=$first.fill_count;duplicate_fill_count=$secondState.fill_count;ledger_hash=$first.last_ledger_hash;cash=$product.cash;position_qty=$product.position_qty;fifo_basis=$product.cost_basis;fees_paid=$product.fees_paid;realized_pnl=$product.realized_pnl;simulated_fee_bps=$running.simulated_fee_bps;source_id=$archive.source_id;snapshot_seal=$archive.snapshot_seal;original_risk_proof_verified=$archive.original_risk_proof_verified;stop_unattended_enabled=$stopped.unattended_enabled;live_orders_enabled=$caps.live_orders_enabled}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33_NATIVE_SAVE_START_ORIGINAL_GUARDED_FILL_FEE_FIFO_DEDUP_STOP=PASS'
 W33-Close $shell
 $script:shell=Start-Process -FilePath (Join-Path $stage 'ktrade.exe') -WorkingDirectory $stage -PassThru
 $null=$shell.Handle
 $deadline=(Get-Date).AddSeconds(45);$script:engine=$null
 do{
  $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
  if($children.Count -eq 1){
   $script:engine=$children[0]
   $ports=@(Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen -ErrorAction SilentlyContinue|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
   if($ports.Count -eq 1){$script:uri='http://127.0.0.1:'+$ports[0].LocalPort;break}
  }
  Start-Sleep -Milliseconds 400
 }while((Get-Date) -lt $deadline)
 if($null -eq $engine -or $ports.Count -ne 1){throw 'W33_COLD_NATIVE_ENGINE_NOT_OWNED'}
 $cold=W33-Get '/api/paper/session'
 $caps=W33-Get '/api/operator/capabilities'
 if($cold.paper_orders_enabled -ne $false -or $cold.unattended_enabled -ne $false -or $cold.fill_count -ne 0 -or $caps.mode -cne 'PAPER_STOPPED' -or $caps.paper_orders_enabled -ne $false -or $caps.live_orders_enabled -ne $false){throw 'W33_COLD_PROCESS_AUTO_REARMED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'Pine Editor'
 Click-W32EUI $shell 'Cold archive'
 $null=Wait-W32EUI $shell 'COLD ACCOUNT · READ ONLY' 15
 $null=Wait-W32EUI $shell '567.4275 USDC cash' 10
 $coldArchive=W33-Get '/api/paper/session/archive'
 if($coldArchive.snapshot_seal -cne $archive.snapshot_seal -or $coldArchive.source_id -cne $archive.source_id -or $coldArchive.execution_restore_eligible -ne $false -or $coldArchive.account.stopped -ne $true -or $coldArchive.orders_enabled -ne $false){throw 'W33_COLD_ORIGINAL_ARCHIVE_CHANGED_OR_REARMED'}
 $null=W33-CheckAccount $coldArchive.account
 Write-Output ('W33_NATIVE_COLD_REPLAY_PROOF='+(@{snapshot_seal=$coldArchive.snapshot_seal;source_id=$coldArchive.source_id;original_risk_proof_verified=$coldArchive.original_risk_proof_verified;old_account_stopped=$coldArchive.account.stopped;new_session_fill_count=$cold.fill_count;paper_orders_enabled=$cold.paper_orders_enabled;unattended_enabled=$cold.unattended_enabled;execution_restore_eligible=$coldArchive.execution_restore_eligible;ui_cold_archive_observed=$true}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33_NATIVE_COLD_READ_ONLY_ACCOUNT_NO_AUTO_REARM=PASS'
}
