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
 Start-Sleep -Milliseconds 200
 [void][W32ENativeInput]::SetCursorPos([int]($r.Left+$r.Width/2),[int]($r.Top+$r.Height/2))
 if([W32ENativeInput]::GetForegroundWindow() -ne $process.MainWindowHandle){throw 'W33_NATIVE_FIELD_FOREIGN_FOCUS'}
 [W32ENativeInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 85
 [W32ENativeInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 300
 $focused=[System.Windows.Automation.AutomationElement]::FocusedElement
 Write-Output ('W33_NATIVE_FIELD_FOCUS='+(@{name=$name;target_type=$el.Current.ControlType.ProgrammaticName;focused_name=$focused.Current.Name;focused_type=$focused.Current.ControlType.ProgrammaticName;rect=$r.ToString()}|ConvertTo-Json -Compress))
 if($focused.Current.Name -cne $name -or [W32ENativeInput]::GetForegroundWindow() -ne $process.MainWindowHandle){throw 'W33_NATIVE_FIELD_INPUT_FOCUS_UNCONFIRMED'}
 [Windows.Forms.SendKeys]::SendWait('^a')
 [Windows.Forms.SendKeys]::SendWait($value)
 Start-Sleep -Milliseconds 200
 $actual=$null
 try{$actual=$el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value}catch{}
 if($null -eq $actual){try{$actual=$el.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value}catch{}}
 Write-Output ('W33_NATIVE_FIELD_READBACK='+(@{name=$name;expected=$value;actual=$actual}|ConvertTo-Json -Compress))
 if($null -eq $actual -or [decimal]$actual -ne [decimal]$value){throw 'W33_NATIVE_FIELD_VALUE_NOT_CONFIRMED'}
}
function W33-Get([string]$path){return Invoke-RestMethod -Uri ($uri+$path) -TimeoutSec 12}
function Assert-W32EProductionBars([object]$response){
  if($response.success -ne $true -or $response.source -cne 'coinbase_advanced_public_rest' -or $response.finalized -ne $true -or $response.stale -ne $false){throw 'W32E_P2_CURRENT_FINALIZED_SOURCE_REQUIRED'}
  $rows=@($response.candles)
  if($rows.Count -lt 250 -or $rows.Count -gt 300){throw ('W32E_P2_CURRENT_HISTORY_COUNT_'+$rows.Count)}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $last=0L
  foreach($row in $rows){
    $t=[long]$row.time
    if($t -le $last -or $t%60 -ne 0 -or $t+62 -gt $now -or $row.product_id -cne 'BTC-USDC'){throw 'W32E_P2_BAR_IDENTITY_OR_FINALITY_INVALID'}
    foreach($value in @($row.open,$row.high,$row.low,$row.close,$row.volume)){
      if($null -eq $value -or [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value)){throw 'W32E_P2_NONFINITE_BAR'}
    }
    if($row.low -le 0 -or $row.high -lt $row.low -or $row.open -lt $row.low -or $row.open -gt $row.high -or $row.close -lt $row.low -or $row.close -gt $row.high -or $row.volume -lt 0){throw 'W32E_P2_OHLCV_INCONSISTENT'}
    $last=$t
  }
  $age=$now-($last+60)
  if($age -lt 2 -or $age -gt 120){throw ('W32E_P2_CURRENT_FINALIZED_AGE_'+$age)}
  $reported=[DateTimeOffset]::Parse($response.last_finalized_at).ToUnixTimeSeconds()
  if($reported -ne $last+60){throw 'W32E_P2_FINALIZED_METADATA_DIFFERS'}
  Write-Host ('W32E_P2_CURRENT_SOURCE_PROOF='+(@{rows=$rows.Count;product='BTC-USDC';timeframe='1m';source=$response.source;first_bar=$rows[0].time;last_bar=$last;last_close_age_seconds=$age;last_close=$rows[-1].close;last_volume=$rows[-1].volume;finalized=$response.finalized;stale=$response.stale}|ConvertTo-Json -Compress))
}
function Assert-W32EIndependentProvider([object]$bars){
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $url='https://api.coinbase.com/api/v3/brokerage/market/products/BTC-USDC/candles?start='+($now-304*60)+'&end='+$now+'&granularity=ONE_MINUTE&limit=350'
  $provider=Invoke-RestMethod -Uri $url -TimeoutSec 12 -MaximumRedirection 0 -Headers @{Accept='application/json';'User-Agent'='KTRADE-ReadOnly-Independent-Qualification/1.0'}
  $byTime=@{}
  foreach($row in @($provider.candles)){
    if($byTime.ContainsKey([string]$row.start)){throw 'W32E_P2_INDEPENDENT_PROVIDER_DUPLICATE'}
    $byTime[[string]$row.start]=$row
  }
  $matched=0
  foreach($row in @($bars.candles)){
    $raw=$byTime[[string]$row.time]
    if($null -eq $raw){throw 'W32E_P2_INDEPENDENT_PROVIDER_BAR_ABSENT'}
    foreach($name in @('open','high','low','close','volume')){
      $a=[double]$row.$name;$b=[double]::Parse([string]$raw.$name,[Globalization.CultureInfo]::InvariantCulture)
      if([Math]::Abs($a-$b) -gt [Math]::Max(1e-9,[Math]::Abs($a)*1e-11)){throw ('W32E_P2_INDEPENDENT_PROVIDER_OHLCV_DIFFERS_'+$name)}
    }
    $matched++
  }
  Write-Host ('W32E_P2_INDEPENDENT_PUBLIC_PROVIDER_PROOF='+(@{endpoint='https://api.coinbase.com/api/v3/brokerage/market/products/BTC-USDC/candles';matched_current_finalized_ohlcv_rows=$matched;raw_rows=@($provider.candles).Count;authentication='none';redirects_allowed=$false;transport='independent PowerShell HTTPS request, no source override'}|ConvertTo-Json -Compress))
}
function W33B-Account([object]$account,[object]$expected){
 if($account.schema -cne 'ktrade.paper.account.read-only.v1' -or $account.orders_enabled -ne $false -or $account.live_armed -ne $false -or @($account.products).Count -ne 1 -or @($account.recent_entries).Count -ne 1){throw 'W33B_ACCOUNT_SCHEMA_OR_ENTRY_COUNT'}
 $p=$account.products[0];$e=$account.recent_entries[0]
 if($p.product_id -cne 'BTC-USDC' -or $p.fill_count -ne 1 -or $p.position_qty -cne '0.00025' -or $p.realized_pnl -cne '0' -or $e.product_id -cne 'BTC-USDC' -or $e.side -cne 'BUY' -or $e.qty -cne '0.00025' -or $e.fee_bps -ne 100 -or $e.status -cne 'SETTLED' -or $e.order_id -cne $expected.id -or [decimal]$e.price -ne $expected.price){throw ('W33B_SOURCE_BOUND_ORIGINAL_ENTRY_DIFFERS_'+($e|ConvertTo-Json -Compress))}
 foreach($key in @('cash','cost_basis','fees_paid')){if([decimal]$p.$key -ne [decimal]$expected.$key){throw ('W33B_INDEPENDENT_FIXED_POINT_'+$key+'_'+$p.$key)}}
 return $p
}
function W33B-History {
 $history=Join-Path $stage 'data/paper-history'
 $map=[ordered]@{}
 foreach($file in @(Get-ChildItem -LiteralPath $history -File -Recurse|Sort-Object FullName)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'W33B_UNSAFE_HISTORY_FILE'}
  $key=[IO.Path]::GetRelativePath($history,$file.FullName)
  $map[$key]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
 }
 return ($map|ConvertTo-Json -Compress)
}
function W33B-OwnEngine {
 $deadline=(Get-Date).AddSeconds(45);$script:engine=$null
 do{
  $shell.Refresh();if($shell.HasExited){throw 'W33B_SHELL_EXITED_DURING_START'}
  $children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'})
  if($children.Count -eq 1){
   $script:engine=$children[0]
   if(![string]::Equals($engine.ExecutablePath,(Join-Path $stage 'ktrade-engine.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'W33B_ENGINE_PATH_UNOWNED'}
   $ports=@(Get-NetTCPConnection -OwningProcess $engine.ProcessId -State Listen -ErrorAction SilentlyContinue|Where-Object {$_.LocalAddress -ceq '127.0.0.1'})
   if($ports.Count -eq 1){$script:uri='http://127.0.0.1:'+$ports[0].LocalPort;return}
  }
  Start-Sleep -Milliseconds 400
 }while((Get-Date) -lt $deadline)
 throw 'W33B_COLD_NATIVE_ENGINE_NOT_OWNED'
}
function Run-W33BNativePaper {
 $initial=W33-Get '/api/paper/session'
 if($initial.mode -cne 'PAPER_NOT_FUNDED' -or $initial.paper_orders_enabled -ne $false -or $initial.live_armed -ne $false){throw 'W33B_FRESH_OWNER_NOT_DISARMED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'BTCUSD'
 Click-W32EUI $shell 'BTC-USDC'
 $null=Wait-W32EUI $shell 'BTCUSDC'
 Click-W32EUI $shell 'Pine Editor'
 $source="//@version=6`nstrategy(`"W33B current paper crash`", overlay=true)`nif bar_index == 299`n    strategy.entry(`"L`", strategy.long, qty=0.00025)"
 Set-W32EPine $shell $source
 Click-W32EUI $shell 'Compile'
 $null=Wait-W32EUI $shell 'Compiled. Not applied or started.'
 Click-W32EUI $shell 'Save'
 Pine-Dialog $shell 'Save Pine script as' 'OK' 'W33B current paper crash'
 $null=Wait-W32EUI $shell 'Pine script durably saved; not automatically applied'
 $saved=@((W33-Get '/api/pine-library').scripts|Where-Object {$_.display_name -ceq 'W33B current paper crash' -and $_.ownership -ceq 'user' -and $_.kind -ceq 'strategy'})
 if($saved.Count -ne 1){throw 'W33B_NATIVE_SAVE_NOT_DURABLE'}
 $stored=W33-Get ('/api/pine-library/'+$saved[0].id)
 if($stored.source.Replace("`r`n","`n") -cne $source){throw 'W33B_SAVED_SOURCE_CHANGED'}
 W33-Field $shell 'Paper USDC' '600'
 W33-Field $shell 'Simulated fee (bps)' '100'
 Click-W32EUI $shell 'Acknowledge simulated paper fees'
 # All independent price checks and execution must stay on the same finalized bar.
 $sec=(Get-Date).Second
 if($sec -ge 15){Start-Sleep -Seconds (68-$sec)}
 $bars=W33-Get '/api/candles?product=BTC-USDC&tf=1m'
 Assert-W32EProductionBars $bars
 if(@($bars.candles).Count -ne 300){throw 'W33B_EXACT_NATIVE_PINE_HISTORY_REQUIRED'}
 Assert-W32EIndependentProvider $bars
 $previewBody=@{script_id=$saved[0].id;product_id='BTC-USDC';timeframe='1m'}|ConvertTo-Json -Compress
 $preview=Invoke-RestMethod -Uri ($uri+'/api/paper/strategy/preview') -Method Post -Headers @{Origin=$uri} -ContentType 'application/json' -Body $previewBody -TimeoutSec 15
 $row=$bars.candles[-1]
 $closeAt=[DateTimeOffset]::FromUnixTimeSeconds([long]$row.time+60).ToString('yyyy-MM-ddTHH:mm:ssZ')
 if($preview.status -cne 'REVIEW_ONLY' -or $preview.final_bar_at -cne $closeAt -or $preview.orders_enabled -ne $false -or $preview.live_armed -ne $false -or $preview.review_proposal.order.qty -cne '0.00025' -or [decimal]$preview.review_proposal.order.price -ne [decimal]$row.close){throw 'W33B_CURRENT_NATIVE_PREVIEW_NOT_SAME_PUBLIC_BAR'}
 $price=[decimal]$preview.review_proposal.order.price
 $gross=[Math]::Round($price*[decimal]'0.00025',8,[MidpointRounding]::AwayFromZero)
 $fees=[Math]::Round($gross/100,8,[MidpointRounding]::AwayFromZero)
 if($gross -le 0 -or $gross -gt 100){throw 'W33B_PROSPECTIVE_ORIGINAL_RISK_LIMIT'}
 $expected=@{price=$price;id=$preview.review_proposal.order.id;cash=600-$gross-$fees;cost_basis=$gross+$fees;fees_paid=$fees}
 Click-W32EUI $shell 'Start isolated paper'
 $null=Wait-W32EUI $shell 'ISOLATED PAPER RUNNING' 15
 $running=W33-Get '/api/paper/session';$caps=W33-Get '/api/operator/capabilities'
 if($running.source_sha256 -cne $preview.source_sha256 -or $running.durable_custody_enabled -ne $true -or $running.unattended_enabled -ne $true -or $caps.paper_orders_enabled -ne $true -or $caps.strategy_execution_enabled -ne $true -or $caps.paper_accounting_enabled -ne $true -or $caps.requires_review -ne $false -or $caps.live_orders_enabled -ne $false){throw 'W33B_NATIVE_START_SAME_OWNER_REQUIRED'}
 $firstArchive=W33-Get '/api/paper/session/archive'
 if($firstArchive.source_id -cnotmatch '^ktrade-reconcile-[a-z0-9]{12,48}$'){throw 'W33B_INVALID_SOURCE_ID'}
 [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP 'w33-paper-source.txt'),$firstArchive.source_id)
 Click-W32EUI $shell 'Evaluate final bar'
 $null=Wait-W32EUI $shell 'fills 1' 15
 $first=W33-Get '/api/paper/session'
 $product=W33B-Account (W33-Get '/api/paper/accounting') $expected
 Click-W32EUI $shell 'Evaluate final bar'
 $null=Wait-W32EUI $shell 'Final bar already evaluated. No additional fill placed.' 10
 $second=W33-Get '/api/paper/session'
 if($second.fill_count -ne 1 -or $second.last_ledger_hash -cne $first.last_ledger_hash -or $second.evaluation_cycles -le $first.evaluation_cycles -or $second.last_final_bar_at -cne $preview.final_bar_at){throw 'W33B_CURRENT_BAR_DUPLICATED_OR_ROLLED'}
 $archive=W33-Get '/api/paper/session/archive'
 if($archive.original_risk_proof_verified -ne $true -or $archive.account.stopped -ne $false -or $archive.execution_restore_eligible -ne $false -or $archive.source_id -cne $firstArchive.source_id){throw 'W33B_PRECRASH_DURABLE_ACCOUNT_NOT_RUNNING_OR_VERIFIED'}
 $null=W33B-Account $archive.account $expected
 $beforeHistory=W33B-History
 $lease=Join-Path $stage 'data/paper-history/application-owner.lock'
 if(!(Test-Path -LiteralPath $lease)){throw 'W33B_ACTIVE_LEASE_MISSING'}
 $prekill=W33-Get '/api/paper/session'
 if($prekill.paper_orders_enabled -ne $true -or $prekill.unattended_enabled -ne $true -or $prekill.durable_custody_enabled -ne $true -or $prekill.fill_count -ne 1){throw 'W33B_ENGINE_NOT_ACTIVE_AT_CRASH'}
 $owned=Get-CimInstance Win32_Process -Filter ('ProcessId='+$engine.ProcessId)
 if($owned.ParentProcessId -ne $shell.Id -or ![string]::Equals($owned.ExecutablePath,(Join-Path $stage 'ktrade-engine.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'W33B_CRASH_TARGET_NOT_OWNED'}
 $crashedPID=[int]$engine.ProcessId;$oldPort=([uri]$uri).Port
 $handle=Get-Process -Id $crashedPID
 $null=$handle.Handle
 Stop-Process -Id $crashedPID -Force
 if(!$handle.WaitForExit(10000)){throw 'W33B_ENGINE_CRASH_NOT_OBSERVED'}
 for($i=0;$i -lt 20;$i++){
  if(@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$shell.Id)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'}).Count -ne 0){throw 'W33B_ENGINE_AUTO_RESPAWNED'}
  Start-Sleep -Seconds 1
 }
 if(@(Get-NetTCPConnection -State Listen -LocalPort $oldPort -ErrorAction SilentlyContinue).Count -ne 0 -or (W33B-History) -cne $beforeHistory){throw 'W33B_CRASH_LEFT_LISTENER_OR_MUTATED_HISTORY'}
 Write-Output ('W33B_CURRENT_PAPER_AND_ACTIVE_CRASH='+(@{script_id=$saved[0].id;source_sha256=$running.source_sha256;final_bar_at=$preview.final_bar_at;final_bar_sha256=$preview.final_bar_sha256;public_candle_count=300;price=$price;qty=$product.position_qty;gross=$gross;cash=$product.cash;fees_paid=$product.fees_paid;fifo_basis=$product.cost_basis;realized_pnl=$product.realized_pnl;fill_count=$first.fill_count;duplicate_fill_count=$second.fill_count;ledger_hash=$first.last_ledger_hash;source_id=$archive.source_id;snapshot_seal=$archive.snapshot_seal;crashed_pid=$crashedPID;prekill_worker=$prekill.unattended_enabled;prekill_writer=$prekill.durable_custody_enabled;historical_account_stopped=$archive.account.stopped;engine_respawned=$false;no_stop_injected=$true;live_orders_enabled=$caps.live_orders_enabled}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33B_PRODUCTION_CURRENT_MARKET_NATIVE_PAPER_FILL_DEDUP_ACTIVE_ENGINE_KILL=PASS'
 $shell.Refresh()
 if(!$shell.HasExited){[void][W32EClose]::PostMessage($shell.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)}
 if(!$shell.WaitForExit(15000) -or $shell.ExitCode -ne 0){throw 'W33B_POSTCRASH_SHELL_CLOSE_FAILED'}
 $script:shell=Start-Process -FilePath (Join-Path $stage 'ktrade.exe') -WorkingDirectory $stage -PassThru
 $null=$shell.Handle
 W33B-OwnEngine
 $cold=W33-Get '/api/paper/session';$caps=W33-Get '/api/operator/capabilities'
 if($cold.mode -cne 'PAPER_NOT_FUNDED' -or $cold.fill_count -ne 0 -or $cold.paper_orders_enabled -ne $false -or $cold.unattended_enabled -ne $false -or $cold.durable_custody_enabled -ne $false -or $caps.mode -cne 'PAPER_STOPPED' -or $caps.paper_orders_enabled -ne $false -or $caps.strategy_execution_enabled -ne $false -or $caps.live_orders_enabled -ne $false){throw 'W33B_COLD_EXECUTION_REARMED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'Pine Editor'
 Click-W32EUI $shell 'Cold archive'
 $null=Wait-W32EUI $shell 'COLD ACCOUNT · READ ONLY' 15
 $null=Wait-W32EUI $shell ($product.cash+' USDC cash') 10
 $coldArchive=W33-Get '/api/paper/session/archive'
 if($coldArchive.snapshot_seal -cne $archive.snapshot_seal -or $coldArchive.source_id -cne $archive.source_id -or $coldArchive.original_risk_proof_verified -ne $true -or $coldArchive.account.stopped -ne $false -or $coldArchive.original_source_comparison.state -cne 'OWNER_LEASE_UNRESOLVED' -or $coldArchive.original_source_comparison.trading_resume_eligible -ne $false -or $coldArchive.execution_restore_eligible -ne $false -or (W33B-History) -cne $beforeHistory){throw 'W33B_COLD_ARCHIVE_OR_ABANDONED_LEASE_CHANGED'}
 $null=W33B-Account $coldArchive.account $expected
 # Negative admission probe: exactly the same saved source; lease must refuse BEFORE funding.
 $start=@{script_id=$saved[0].id;product_id='BTC-USDC';timeframe='1m';initial_cash='600';simulated_fee_bps=100;fee_model_acknowledged=$true}|ConvertTo-Json -Compress
 $refused=Invoke-WebRequest -Uri ($uri+'/api/paper/session/start') -Method Post -Headers @{Origin=$uri} -ContentType 'application/json' -Body $start -TimeoutSec 15 -SkipHttpErrorCheck
 if($refused.StatusCode -ne 409 -or !$refused.Content.Contains('durable paper writer blocked or previously interrupted')){throw ('W33B_COLD_START_NOT_REFUSED_BY_CRASH_CUSTODY_'+$refused.StatusCode)}
 $after=W33-Get '/api/paper/session'
 $sources=W33-Get '/api/paper/session/archive-sources'
 $selected=W33-Get '/api/paper/session/archive'
 if($after.mode -cne 'PAPER_NOT_FUNDED' -or $after.fill_count -ne 0 -or $after.paper_orders_enabled -ne $false -or $after.unattended_enabled -ne $false -or $after.durable_custody_enabled -ne $false -or @($sources.sources).Count -ne 1 -or $sources.sources[0] -cne $archive.source_id -or $selected.snapshot_seal -cne $archive.snapshot_seal -or (W33B-History) -cne $beforeHistory){throw 'W33B_REFUSED_START_CREATED_HISTORY_OR_CHANGED_FUNDS'}
 Write-Output ('W33B_COLD_CRASH_CUSTODY='+(@{source_id=$coldArchive.source_id;snapshot_seal=$coldArchive.snapshot_seal;original_risk_proof_verified=$coldArchive.original_risk_proof_verified;historical_account_stopped=$coldArchive.account.stopped;lease_state=$coldArchive.original_source_comparison.state;execution_restore_eligible=$false;new_fill_count=$after.fill_count;paper_orders_enabled=$after.paper_orders_enabled;unattended_enabled=$after.unattended_enabled;durable_custody_enabled=$after.durable_custody_enabled;cold_start_http=$refused.StatusCode;source_count=@($sources.sources).Count;history_byte_identical=$true;native_cash_observed=$true}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33B_COLD_NATIVE_ACCOUNT_REPLAY_ABANDONED_LEASE_PRESERVED_NO_REARM_NO_PHANTOM_HISTORY=PASS'
}
