function P8-UnfundedWarningProbe {
 $state=W33-Get '/api/paper/session'
 if($state.mode -cne 'PAPER_NOT_FUNDED' -or $state.paper_orders_enabled -ne $false){throw 'P8_WARNING_PREFLIGHT_NOT_UNFUNDED'}
 $handle=Get-Process -Id $engine.ProcessId;$null=$handle.Handle
 Stop-Process -Id $handle.Id -Force
 if(!$handle.WaitForExit(10000)){throw 'P8_WARNING_PREFLIGHT_ENGINE_NOT_DEAD'}
 Start-Sleep -Milliseconds 800
 P8-DumpOwnedNativeWindows
 $dialog=P8-FindEngineWarning
 P8-AcknowledgeWarning $dialog
 if(!$shell.WaitForExit(15000) -or $shell.ExitCode -ne 0){throw 'P8_WARNING_PREFLIGHT_ACK_EXIT_FAILED'}
 Write-Output '::notice::W33C_P8_UNFUNDED_NATIVE_ENGINE_WARNING_PREFLIGHT=PASS'
 $script:shell=Start-Process -FilePath (Join-Path $stage 'ktrade.exe') -WorkingDirectory $stage -PassThru
 $null=$shell.Handle;W33B-OwnEngine
}
function P8-DumpOwnedNativeWindows {
 foreach($root in (Owned-Roots $shell)){
  try{
   Write-Output ('P8_NATIVE_DIAG_ROOT='+(@{name=$root.Current.Name;pid=$root.Current.ProcessId;handle=$root.Current.NativeWindowHandle;class=$root.Current.ClassName;offscreen=$root.Current.IsOffscreen}|ConvertTo-Json -Compress))
   $nodes=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
   $items=@();$count=0
   foreach($node in $nodes){
    if(!$node.Current.IsOffscreen -and $node.Current.Name){
     $items+=@{name=([string]$node.Current.Name).Substring(0,[Math]::Min(400,([string]$node.Current.Name).Length));type=$node.Current.ControlType.ProgrammaticName;pid=$node.Current.ProcessId;class=$node.Current.ClassName;handle=$node.Current.NativeWindowHandle}
     $count++;if($count -ge 100){break}
    }
   }
   Write-Output ('P8_NATIVE_DIAG_OWNED_NODES='+($items|ConvertTo-Json -Compress -Depth 4))
  }catch{Write-Output ('P8_NATIVE_DIAG_READ_ERROR='+$_.Exception.Message)}
 }
}
function P8-FindEngineWarning {
  $deadline=(Get-Date).AddSeconds(15)
  do{
    $shell.Refresh();if($shell.HasExited){throw 'P8_SHELL_EXITED_WITHOUT_NATIVE_ENGINE_WARNING'}
    foreach($root in (Owned-Roots $shell)){
      # Native Windows MessageDialog may be a Win32-owned #32770
      # descendant of Wails main, *not* its own UIA RootElement child.
      # Bind the actual dialog HWND to this exact shell PID and to the
      # already-confirmed Wails-owned subtree; do not accept a page DOM
      # text or an unrelated system dialog as a crash witness.
      $desc=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
      $dialogCandidates=@($desc|Where-Object {
        try{
          $_.Current.Name -ceq 'KTRADE engine stopped' -and
          $_.Current.ProcessId -eq $shell.Id -and
          $_.Current.ClassName -ceq '#32770' -and
          $_.Current.NativeWindowHandle -ne 0 -and
          !$_.Current.IsOffscreen
        }catch{$false}
      })
      foreach($dialog in $dialogCandidates){
        $content=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
        $body=@($content|Where-Object {
          try{
            $_.Current.ProcessId -eq $shell.Id -and
            !$_.Current.IsOffscreen -and
            ([string]$_.Current.Name).Contains('The trading engine stopped unexpectedly.') -and
            ([string]$_.Current.Name).Contains('Trading was not resumed.')
          }catch{$false}
        })
        # Native Win32 Button sometimes advertises UIA ControlType.Pane.
        # Match actual Win32 class instead, with same process/owned HWND.
        $buttons=@($content|Where-Object {
          try{
            $_.Current.ProcessId -eq $shell.Id -and
            $_.Current.IsEnabled -and !$_.Current.IsOffscreen -and
            $_.Current.Name -ceq 'OK' -and
            (W31-NativeClass $_) -ceq 'Button' -and
            $_.Current.NativeWindowHandle -ne 0
          }catch{$false}
        })
        if($body.Count -eq 1 -and $buttons.Count -eq 1){
          $r=$buttons[0].Current.BoundingRectangle;$d=$dialog.Current.BoundingRectangle
          if($r.IsEmpty -or $d.IsEmpty -or $r.Left -lt $d.Left -or $r.Right -gt $d.Right -or $r.Top -lt $d.Top -or $r.Bottom -gt $d.Bottom){continue}
          Write-Output ('P8_NATIVE_OWNED_ENGINE_WARNING='+(@{
             root_name=$root.Current.Name;dialog_name=$dialog.Current.Name;
             owner_pid=$dialog.Current.ProcessId;dialog_class=$dialog.Current.ClassName;
             dialog_hwnd=$dialog.Current.NativeWindowHandle;
             message=$body[0].Current.Name;button=$buttons[0].Current.Name;
             native_button_class=(W31-NativeClass $buttons[0])
          }|ConvertTo-Json -Compress))
          return @{root=$dialog;button=$buttons[0]}
        }
      }
    }
    Start-Sleep -Milliseconds 200
  }while((Get-Date) -lt $deadline)
  P8-DumpOwnedNativeWindows
  throw 'P8_NATIVE_ENGINE_STOPPED_WARNING_NOT_OBSERVED'
}
function P8-AcknowledgeWarning([object]$dialog){
 $root=$dialog.root;$button=$dialog.button
 $handle=[IntPtr]$root.Current.NativeWindowHandle
 [void][W30Native]::SetForegroundWindow($handle);Start-Sleep -Milliseconds 150
 $r=$button.Current.BoundingRectangle;$outer=$root.Current.BoundingRectangle
 if($r.IsEmpty -or $r.Left -lt $outer.Left -or $r.Right -gt $outer.Right -or $r.Top -lt $outer.Top -or $r.Bottom -gt $outer.Bottom -or [W30Native]::GetForegroundWindow() -ne $handle){throw 'P8_WARNING_CLICK_NOT_OWNED'}
 [void][W30Native]::SetCursorPos([int]($r.Left+$r.Width/2),[int]($r.Top+$r.Height/2))
 [W30Native]::mouse_event(2,0,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 100;[W30Native]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}
function W33B-History {
 $history=Join-Path $stage 'data/paper-history'
 $map=[ordered]@{}
 foreach($file in @(Get-ChildItem -LiteralPath $history -File -Recurse|Sort-Object FullName)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'W33B_UNSAFE_HISTORY_FILE'}
  $key=[IO.Path]::GetRelativePath($history,$file.FullName)
  # Match Go's observational reader sharing: Get-FileHash disallows an
  # existing Windows writer handle even when the writer permits reads.
  $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
  $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
  try{$map[$key]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()}
  finally{$stream.Dispose()}
 }
 return ($map|ConvertTo-Json -Compress)
}
function P7-ReadValuation([object]$account,[string]$phase){
 $before=W33-Get '/api/paper/session/archive'
 $value=W33-Get '/api/paper/session/valuation'
 $after=W33-Get '/api/paper/session/archive'
 $p=$account.products[0];$s=$value.value.state
 if($value.schema -cne 'ktrade.paper.valuation.read-only.v1' -or $value.product_id -cne 'BTC-USDC' -or $value.paper_source_sha256 -cne $script:p5SourceHash -or $value.market_source_sha256 -cnotmatch '^[a-f0-9]{64}$' -or $value.market_price_verified -ne $true -or $value.unrealized_pnl_available -ne $true -or $value.orders_enabled -ne $false -or $value.live_armed -ne $false -or $value.risk_verified -ne $false -or $value.requires_review -ne $true -or $value.account_stopped -ne $account.stopped -or $s.broker_access -ne $false -or $s.last_hash -cne $p.ledger_hash -or $s.fill_count -ne $p.fill_count -or $before.snapshot_seal -cne $after.snapshot_seal){throw 'P7_MARK_SOURCE_LEDGER_OR_AUTHORITY_DIFFERS'}
 foreach($key in @('cash','position_qty','cost_basis','fees_paid','realized_pnl')){if($s.$key -cne $p.$key){throw 'P7_VALUATION_CHANGED_ORIGINAL_ACCOUNT'}}
 $bars=W33-Get '/api/candles?product=BTC-USDC&tf=1m'
 Assert-W32EProductionBars $bars;Assert-W32EIndependentProvider $bars
 if(([DateTimeOffset]$value.mark_confirmed_at).ToUnixTimeSeconds() -ne [long]$bars.candles[-1].time+60 -or [decimal]$value.value.mark_price -ne [decimal]$bars.candles[-1].close){throw 'P7_VALUATION_NOT_CURRENT_PUBLIC_FINALIZED_PRICE'}
 $market=[Math]::Round([decimal]$p.position_qty*[decimal]$value.value.mark_price,8,[MidpointRounding]::AwayFromZero)
 $unrealized=$market-[decimal]$p.cost_basis;$equity=[decimal]$p.cash+$market
 if([decimal]$value.value.position_market_value -ne $market -or [decimal]$value.value.unrealized_pnl -ne $unrealized -or [decimal]$value.value.equity -ne $equity){throw 'P7_INDEPENDENT_FIXED_POINT_VALUATION_DIFFERS'}
 Click-W32EUI $shell 'Paper account'
 $null=Wait-W32EUI $shell ('Unrealized '+$value.value.unrealized_pnl+' USDC') 10
 $null=Wait-W32EUI $shell ('Equity '+$value.value.equity+' USDC') 10
 $null=Wait-W32EUI $shell 'Before exit fees' 10
 Write-Output ('P7_NATIVE_'+$phase+'_VALUATION='+(@{phase=$phase;source_sha256=$value.paper_source_sha256;market_sha256=$value.market_source_sha256;mark_confirmed_at=$value.mark_confirmed_at;mark_price=$value.value.mark_price;ledger_hash=$s.last_hash;cash=$s.cash;position_qty=$s.position_qty;basis=$s.cost_basis;fees=$s.fees_paid;realized_pnl=$s.realized_pnl;fill_count=$s.fill_count;position_value=$value.value.position_market_value;unrealized_pnl=$value.value.unrealized_pnl;equity=$value.value.equity;snapshot_seal=$after.snapshot_seal;native_estimate_observed=$true;live_armed=$value.live_armed}|ConvertTo-Json -Compress))
}
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
function P5-WaitUntil([long]$epoch,[string]$phase){
 $deadline=[DateTimeOffset]::UtcNow.AddMinutes(6)
 while([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $epoch){
  $shell.Refresh();if($shell.HasExited){throw ('P5_SHELL_EXITED_'+$phase)}
  if([DateTimeOffset]::UtcNow -gt $deadline){throw ('P5_CLOCK_WAIT_EXCEEDED_'+$phase)}
  Start-Sleep -Milliseconds 250
 }
}
function P5-Account([object]$account,[int]$fills,[object]$expected){
 if($account.schema -cne 'ktrade.paper.account.read-only.v1' -or $account.orders_enabled -ne $false -or $account.live_armed -ne $false -or @($account.products).Count -ne 1 -or @($account.recent_entries).Count -ne $fills){throw 'P5_ACCOUNT_SCHEMA_OR_COUNT'}
 $p=$account.products[0]
 if($p.product_id -cne 'BTC-USDC' -or $p.fill_count -ne $fills){throw 'P5_ACCOUNT_IDENTITY'}
 foreach($key in @('cash','position_qty','cost_basis','fees_paid','realized_pnl')){
  if([decimal]$p.$key -ne [decimal]$expected.$key){throw ('P5_FIXED_POINT_'+$key+'_'+$p.$key)}
 }
 for($i=0;$i -lt $fills;$i++){
  $entry=$account.recent_entries[$i];$want=$expected.entries[$i]
  if($entry.product_id -cne 'BTC-USDC' -or $entry.order_id -cne $want.id -or $entry.side -cne $want.side -or $entry.qty -cne '0.00025' -or $entry.fee_bps -ne 100 -or $entry.status -cne 'SETTLED' -or [decimal]$entry.price -ne [decimal]$want.price){throw ('P5_ENTRY_IDENTITY_'+($entry|ConvertTo-Json -Compress))}
 }
 return $p
}
function P5-Checkpoint([object]$archive,[bool]$stopped,[decimal]$cash,[decimal]$pnl){
 if($archive.source_id -cnotmatch '^ktrade-reconcile-[a-z0-9]{12,48}$' -or $archive.snapshot_seal -cnotmatch '^[a-f0-9]{64}$' -or $archive.original_risk_proof_verified -ne $true -or $archive.execution_restore_eligible -ne $false){throw 'P5_ARCHIVE_NOT_ORIGINAL_RISK_BOUND'}
 $dir=Join-Path $stage ('data/paper-history/'+$archive.source_id)
 $files=@(Get-ChildItem -LiteralPath $dir -File|Where-Object {$_.Name -match ('^checkpoint-[0-9]{19}-'+$archive.snapshot_seal.Substring(0,24)+'\.json$')})
 if($files.Count -ne 1 -or ($files[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'P5_CHECKPOINT_FILE_AMBIGUOUS'}
 $proof=Get-Content -LiteralPath $files[0].FullName -Raw|ConvertFrom-Json -Depth 30
 $risk=$proof.original_risk.observed
 if($proof.seal -cne $archive.snapshot_seal -or $proof.source_id -cne $archive.source_id -or $proof.source_sha256 -cne $script:p5SourceHash -or $proof.simulated_fee_bps -ne 100 -or $proof.live_armed -ne $false -or $risk.killed -ne $stopped -or $risk.open_orders -ne 0 -or @($risk.reservations).Count -ne 0 -or [double]$risk.product_exposure.'BTC-USDC' -ne 0 -or [Math]::Abs([double]$risk.current_equity-[double]$cash) -gt 1e-8 -or [Math]::Abs([double]$risk.daily_pnl-[double]$pnl) -gt 1e-8){throw 'P5_ORIGINAL_FLAT_RISK_CHECKPOINT_DIFFERS'}
 return @{seal=$proof.seal;file_sha256=(Get-FileHash -LiteralPath $files[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant();killed=$risk.killed;open_orders=$risk.open_orders;exposure=$risk.product_exposure.'BTC-USDC';equity=$risk.current_equity;daily_pnl=$risk.daily_pnl}
}
function P5-Close([object]$process){
 $process.Refresh();if($process.HasExited){throw 'P5_NATIVE_SHELL_EXITED_BEFORE_CLOSE'}
 [void][W32EClose]::PostMessage($process.MainWindowHandle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)
 if(!$process.WaitForExit(15000) -or $process.ExitCode -ne 0){throw 'P5_NATIVE_NORMAL_CLOSE_FAILED'}
 $left=Get-Process -Id $engine.ProcessId -ErrorAction SilentlyContinue
 if($null -ne $left -and !$left.WaitForExit(10000)){throw 'P5_ORIGINAL_ENGINE_ORPHANED'}
}
function Run-P8NativeEngineCrash {
 P8-UnfundedWarningProbe
 $initial=W33-Get '/api/paper/session'
 if($initial.mode -cne 'PAPER_NOT_FUNDED' -or $initial.paper_orders_enabled -ne $false -or $initial.live_armed -ne $false){throw 'P5_FRESH_OWNER_NOT_UNFUNDED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'BTCUSD';Click-W32EUI $shell 'BTC-USDC'
 $null=Wait-W32EUI $shell 'BTCUSDC'
 Click-W32EUI $shell 'Pine Editor'
 $entryOpen=[long]([Math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()/60)*60)+120
 $exitOpen=$entryOpen+60
 $entryClose=$entryOpen+60;$exitClose=$exitOpen+60
 $source="//@version=6`nstrategy(`"W33C P8 engine crash open position`", overlay=true)`nif time == $($entryOpen*1000)`n    strategy.entry(`"L`", strategy.long, qty=0.00025)`nif time == $($exitOpen*1000)`n    strategy.close(`"L`")"
 $script:p5SourceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source))).ToLowerInvariant()
 Write-Output ('P5_TIMED_SAVED_STRATEGY='+(@{entry_open=$entryOpen;exit_open=$exitOpen;entry_close=$entryClose;exit_close=$exitClose;source_sha256=$script:p5SourceHash;source=$source}|ConvertTo-Json -Compress))
 Set-W32EPine $shell $source
 Click-W32EUI $shell 'Compile'
 $null=Wait-W32EUI $shell 'Compiled. Not applied or started.'
 Click-W32EUI $shell 'Save'
 Pine-Dialog $shell 'Save Pine script as' 'OK' 'W33C P8 engine crash open position'
 $null=Wait-W32EUI $shell 'Pine script durably saved; not automatically applied'
 $saved=@((W33-Get '/api/pine-library').scripts|Where-Object {$_.display_name -ceq 'W33C P8 engine crash open position' -and $_.ownership -ceq 'user' -and $_.kind -ceq 'strategy'})
 if($saved.Count -ne 1){throw 'P5_CANONICAL_NATIVE_SAVE_MISSING'}
 $stored=W33-Get ('/api/pine-library/'+$saved[0].id)
 if($stored.source.Replace("`r`n","`n") -cne $source){throw 'P5_DURABLE_SOURCE_CHANGED'}
 W33-Field $shell 'Paper USDC' '600'
 W33-Field $shell 'Simulated fee (bps)' '100'
 Click-W32EUI $shell 'Acknowledge simulated paper fees'
 if([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -gt $entryClose-15){throw 'P5_NATIVE_SETUP_MISSED_PROSPECTIVE_WINDOW'}
 P5-WaitUntil ($entryClose-4) 'native-start'
 Click-W32EUI $shell 'Start isolated paper'
 $null=Wait-W32EUI $shell 'ISOLATED PAPER RUNNING' 15
 $running=W33-Get '/api/paper/session';$caps=W33-Get '/api/operator/capabilities'
 if($running.source_sha256 -cne $script:p5SourceHash -or $running.fill_count -ne 0 -or $running.durable_custody_enabled -ne $true -or $running.unattended_enabled -ne $true -or $caps.paper_orders_enabled -ne $true -or $caps.live_orders_enabled -ne $false){throw 'P5_NATIVE_START_CUSTODY_OR_SOURCE'}
 $firstArchive=W33-Get '/api/paper/session/archive'
 if($firstArchive.source_id -cnotmatch '^ktrade-reconcile-[a-z0-9]{12,48}$'){throw 'P5_SOURCE_ID_INVALID'}
 [IO.File]::WriteAllText((Join-Path $env:RUNNER_TEMP 'w33-paper-source.txt'),$firstArchive.source_id)
 $request=@{script_id=$saved[0].id;product_id='BTC-USDC';timeframe='1m'}|ConvertTo-Json -Compress
 P5-WaitUntil ($entryClose+3) 'entry-finality'
 $buyBars=W33-Get '/api/candles?product=BTC-USDC&tf=1m'
 Assert-W32EProductionBars $buyBars;Assert-W32EIndependentProvider $buyBars
 if([long]$buyBars.candles[-1].time -ne $entryOpen){throw 'P5_ENTRY_SOURCE_NOT_SELECTED_CURRENT_BAR'}
 $preview=Invoke-RestMethod -Uri ($uri+'/api/paper/strategy/preview') -Method Post -Headers @{Origin=$uri} -ContentType 'application/json' -Body $request -TimeoutSec 15
 if($preview.status -cne 'REVIEW_ONLY' -or $preview.source_sha256 -cne $script:p5SourceHash -or ([DateTimeOffset]$preview.final_bar_at).ToUnixTimeSeconds() -ne $entryClose -or $preview.review_proposal.paper_order.qty -cne '0.00025' -or [decimal]$preview.review_proposal.paper_order.price -ne [decimal]$buyBars.candles[-1].close){throw 'P5_ENTRY_NATIVE_PREVIEW_NOT_CURRENT_SOURCE'}
 $buyPrice=[decimal]$preview.review_proposal.paper_order.price
 $buyGross=[Math]::Round($buyPrice*[decimal]'0.00025',8,[MidpointRounding]::AwayFromZero)
 $buyFee=[Math]::Round($buyGross/100,8,[MidpointRounding]::AwayFromZero)
 $buyExpected=@{cash=600-$buyGross-$buyFee;position_qty='0.00025';cost_basis=$buyGross+$buyFee;fees_paid=$buyFee;realized_pnl=0;entries=@(@{id=$preview.review_proposal.paper_order.id;side='BUY';price=$buyPrice})}
 $before=W33-Get '/api/paper/session'
 if($before.fill_count -ne 0){throw 'P5_ENTRY_FILLED_BEFORE_NATIVE_EVALUATE'}
 Click-W32EUI $shell 'Evaluate final bar'
 $null=Wait-W32EUI $shell 'fills 1' 12
 $bought=W33-Get '/api/paper/session'
 if($bought.fill_count -ne 1 -or $bought.evaluation_cycles -ne $before.evaluation_cycles+1 -or ([DateTimeOffset]$bought.last_final_bar_at).ToUnixTimeSeconds() -ne $entryClose){throw 'P5_NATIVE_ENTRY_NOT_EXACTLY_ONE_CYCLE'}
 $buyAccount=W33-Get '/api/paper/accounting'
 $buyProduct=P5-Account $buyAccount 1 $buyExpected
 Write-Output ('P5_NATIVE_BUY='+(@{source_id=$firstArchive.source_id;price=$buyPrice;qty=$buyProduct.position_qty;gross=$buyGross;cash=$buyProduct.cash;fees=$buyProduct.fees_paid;basis=$buyProduct.cost_basis;order_id=$buyExpected.entries[0].id;ledger_hash=$bought.last_ledger_hash;final_bar_hash=$preview.final_bar_sha256;final_bar_time=$entryClose}|ConvertTo-Json -Compress))
 P7-ReadValuation $buyAccount 'OPEN_POSITION'
 # The position is still open; crash the exact funded original engine.
 $archive=W33-Get '/api/paper/session/archive'
 $null=P5-Account $archive.account 1 $buyExpected
 if($archive.account.stopped -ne $false -or $archive.original_risk_proof_verified -ne $true -or $archive.execution_restore_eligible -ne $false){throw 'P8_OPEN_POSITION_NOT_IN_ORIGINAL_ACTIVE_CHECKPOINT'}
 $beforeHistory=W33B-History
 $prekill=W33-Get '/api/paper/session'
 if($prekill.fill_count -ne 1 -or $prekill.paper_orders_enabled -ne $true -or $prekill.unattended_enabled -ne $true -or $prekill.durable_custody_enabled -ne $true){throw 'P8_OPEN_POSITION_OWNER_NOT_ACTIVE_BEFORE_ENGINE_CRASH'}
 $owned=Get-CimInstance Win32_Process -Filter ('ProcessId='+$engine.ProcessId)
 if($owned.ParentProcessId -ne $shell.Id -or ![string]::Equals($owned.ExecutablePath,(Join-Path $stage 'ktrade-engine.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'P8_ENGINE_CRASH_TARGET_UNOWNED'}
 $oldShell=$shell.Id;$oldPort=([uri]$uri).Port
 $handle=Get-Process -Id $engine.ProcessId;$null=$handle.Handle
 $profile=Join-Path $stage 'data/webview2-profile'
 $views=@(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'"|Where-Object {$_.CommandLine -and $_.CommandLine.Contains($profile)})
 if($views.Count -lt 1){throw 'P8_OWNED_PROFILE_PROCESS_ABSENT'}
 $viewHandles=@($views|ForEach-Object {$p=Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue;if($p){$null=$p.Handle;$p}})
 Stop-Process -Id $handle.Id -Force
 if(!$handle.WaitForExit(10000)){throw 'P8_ORIGINAL_ENGINE_CRASH_NOT_OBSERVED'}
 $warning=P8-FindEngineWarning
 # Leave the warning open across the strategy's next SELL bar: neither the
 # shell nor its old worker may respawn or settle that future exit.
 $deadline=[DateTimeOffset]::UtcNow.AddSeconds(90)
 while([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $exitClose+5){
  if(@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$oldShell)|Where-Object {$_.Name -ceq 'ktrade-engine.exe'}).Count -ne 0){throw 'P8_ENGINE_RESPAWNED_DURING_WARNING'}
  if([DateTimeOffset]::UtcNow -gt $deadline){throw 'P8_POSTCRASH_FINAL_BAR_WAIT_EXCEEDED'}
  Start-Sleep -Milliseconds 500
 }
 if(@(Get-NetTCPConnection -State Listen -LocalPort $oldPort -ErrorAction SilentlyContinue).Count -ne 0 -or (W33B-History) -cne $beforeHistory){throw 'P8_CRASH_LEFT_LISTENER_OR_MUTATED_OPEN_POSITION_HISTORY'}
 P8-AcknowledgeWarning $warning
 if(!$shell.WaitForExit(15000) -or $shell.ExitCode -ne 0){throw 'P8_NATIVE_WARNING_ACK_DID_NOT_CLOSE_SHELL_CLEANLY'}
 foreach($p in $viewHandles){if(!$p.WaitForExit(10000)){throw 'P8_WEBVIEW_PROFILE_PROCESS_ORPHANED'}}
 Write-Output ('P8_NATIVE_OPEN_POSITION_ENGINE_CRASH='+(@{source_id=$archive.source_id;source_sha256=$script:p5SourceHash;snapshot_seal=$archive.snapshot_seal;cash=$buyProduct.cash;qty=$buyProduct.position_qty;fifo_basis=$buyProduct.cost_basis;fees=$buyProduct.fees_paid;realized_pnl=$buyProduct.realized_pnl;fill_count=$prekill.fill_count;ledger_hash=$prekill.last_ledger_hash;engine_pid=$handle.Id;shell_pid=$oldShell;owned_webview_processes=$viewHandles.Count;prekill_worker=$prekill.unattended_enabled;prekill_writer=$prekill.durable_custody_enabled;native_warning_observed=$true;acknowledged_shell_exit_code=$shell.ExitCode;future_sell_not_settled=$true;history_byte_identical=$true;stop_injected=$false;engine_respawned=$false}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33C_P8_NATIVE_OPEN_POSITION_ENGINE_KILL_WARNING_ACK_SHELL_CLOSE_NO_RESPAWN=PASS'
 $script:shell=Start-Process -FilePath (Join-Path $stage 'ktrade.exe') -WorkingDirectory $stage -PassThru
 $null=$shell.Handle;W33B-OwnEngine
 $cold=W33-Get '/api/paper/session';$caps=W33-Get '/api/operator/capabilities'
 if($cold.mode -cne 'PAPER_NOT_FUNDED' -or $cold.fill_count -ne 0 -or $cold.paper_orders_enabled -ne $false -or $cold.unattended_enabled -ne $false -or $cold.durable_custody_enabled -ne $false -or $caps.paper_orders_enabled -ne $false -or $caps.strategy_execution_enabled -ne $false -or $caps.live_orders_enabled -ne $false){throw 'P8_COLD_EXECUTION_REARMED'}
 Click-W32EUI $shell 'Verify chart UI'
 $null=Wait-W32EUI $shell 'Original chart DOM, Monaco editor and preferences controls observed.'
 Click-W32EUI $shell 'Pine Editor';Click-W32EUI $shell 'Cold archive'
 $null=Wait-W32EUI $shell 'COLD ACCOUNT · READ ONLY' 15
 $null=Wait-W32EUI $shell ($buyProduct.cash+' USDC cash') 10
 $null=Wait-W32EUI $shell ($buyProduct.position_qty+' positions') 10
 $coldArchive=W33-Get '/api/paper/session/archive'
 if($coldArchive.snapshot_seal -cne $archive.snapshot_seal -or $coldArchive.source_id -cne $archive.source_id -or $coldArchive.original_risk_proof_verified -ne $true -or $coldArchive.account.stopped -ne $false -or $coldArchive.original_source_comparison.state -cne 'OWNER_LEASE_UNRESOLVED' -or $coldArchive.original_source_comparison.trading_resume_eligible -ne $false -or $coldArchive.execution_restore_eligible -ne $false -or (W33B-History) -cne $beforeHistory){throw 'P8_COLD_OPEN_POSITION_ARCHIVE_OR_ABANDONED_LEASE_CHANGED'}
 $null=P5-Account $coldArchive.account 1 $buyExpected
 $noColdMark=Invoke-WebRequest -Uri ($uri+'/api/paper/session/valuation') -SkipHttpErrorCheck -TimeoutSec 12
 if($noColdMark.StatusCode -ne 409){throw 'P8_COLD_OWNER_FABRICATED_CURRENT_VALUATION'}
 P5-WaitUntil ($exitClose+63) 'cold-post-exit-admission'
 $admissionBars=W33-Get '/api/candles?product=BTC-USDC&tf=1m'
 Assert-W32EProductionBars $admissionBars;Assert-W32EIndependentProvider $admissionBars
 if([long]$admissionBars.candles[-1].time -le $exitOpen){throw 'P8_ADMISSION_STILL_ON_UNSUPPORTED_EXIT_BAR'}
 $start=@{script_id=$saved[0].id;product_id='BTC-USDC';timeframe='1m';initial_cash='600';simulated_fee_bps=100;fee_model_acknowledged=$true}|ConvertTo-Json -Compress
 $refused=Invoke-WebRequest -Uri ($uri+'/api/paper/session/start') -Method Post -Headers @{Origin=$uri} -ContentType 'application/json' -Body $start -TimeoutSec 15 -SkipHttpErrorCheck
 if($refused.StatusCode -ne 409 -or !$refused.Content.Contains('durable paper writer blocked or previously interrupted')){throw ('P8_COLD_START_NOT_REFUSED_BY_ORIGINAL_LEASE_'+$refused.StatusCode)}
 $after=W33-Get '/api/paper/session';$sources=W33-Get '/api/paper/session/archive-sources';$selected=W33-Get '/api/paper/session/archive'
 if($after.mode -cne 'PAPER_NOT_FUNDED' -or $after.fill_count -ne 0 -or $after.paper_orders_enabled -ne $false -or $after.unattended_enabled -ne $false -or $after.durable_custody_enabled -ne $false -or @($sources.sources).Count -ne 1 -or $sources.sources[0] -cne $archive.source_id -or $selected.snapshot_seal -cne $archive.snapshot_seal -or (W33B-History) -cne $beforeHistory){throw 'P8_REFUSED_START_CHANGED_HISTORY_OR_FUNDS'}
 Write-Output ('P8_NATIVE_COLD_OPEN_POSITION='+(@{source_id=$coldArchive.source_id;snapshot_seal=$coldArchive.snapshot_seal;cash=$buyProduct.cash;position_qty=$buyProduct.position_qty;fifo_basis=$buyProduct.cost_basis;fees=$buyProduct.fees_paid;realized_pnl=$buyProduct.realized_pnl;fill_count=$buyProduct.fill_count;historical_stopped=$coldArchive.account.stopped;lease_state=$coldArchive.original_source_comparison.state;new_owner_fill_count=$after.fill_count;new_owner_paper_enabled=$after.paper_orders_enabled;new_owner_worker=$after.unattended_enabled;new_owner_writer=$after.durable_custody_enabled;cold_valuation_http=$noColdMark.StatusCode;cold_start_http=$refused.StatusCode;history_byte_identical=$true;native_cash_and_position_observed=$true;live_orders_enabled=$caps.live_orders_enabled}|ConvertTo-Json -Compress))
 Write-Output '::notice::W33C_P8_COLD_OPEN_POSITION_FEES_FIFO_NO_CURRENT_MARK_NO_REARM_NO_PHANTOM_HISTORY=PASS'
}
