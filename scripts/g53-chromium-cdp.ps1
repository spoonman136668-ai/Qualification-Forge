param(
 [Parameter(Mandatory=$true)][string]$PrivateHtml,
 [Parameter(Mandatory=$true)][long]$PriorCpuMs,
 [Parameter(Mandatory=$true)][long]$PriorWallMs
)
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $PrivateHtml)){throw 'G53_AUTHENTIC_PRIVATE_HTML_MISSING'}
$qualifier=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$trustedHead=(git -C $qualifier rev-parse HEAD).Trim()
if($trustedHead -cne $env:GITHUB_SHA){throw 'G53_HARNESS_HEAD_IDENTITY_DRIFT'}
$binaries=@(
 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
 'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
 'C:\Program Files\Google\Chrome\Application\chrome.exe',
 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
)
$browserExe=$binaries|Where-Object {Test-Path -LiteralPath $_}|Select-Object -First 1
if(!$browserExe){throw 'G53_NO_INSTALLED_BROWSER_ENGINE_ON_HOSTED_WINDOWS'}
$profile=Join-Path $env:RUNNER_TEMP ('g53-profile-'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $profile){throw 'G53_PROFILE_COLLISION'}
New-Item -ItemType Directory -Path $profile -Force|Out-Null
$script:seq=0
$script:ws=$null
$browserProcess=$null
$job=[IntPtr]::Zero
$browserWatch=[System.Diagnostics.Stopwatch]::StartNew()
$token=[System.Threading.CancellationToken]::None
function Invoke-G53CDP([string]$method,[hashtable]$parameters=@{}){
 $script:seq++
 $packet=@{id=$script:seq;method=$method;params=$parameters}|ConvertTo-Json -Depth 15 -Compress
 $send=[System.Text.Encoding]::UTF8.GetBytes($packet)
 $script:ws.SendAsync([System.ArraySegment[byte]]::new($send),
  [System.Net.WebSockets.WebSocketMessageType]::Text,$true,$token).GetAwaiter().GetResult()
 for($i=0;$i -lt 20;$i++){
  $memory=[System.IO.MemoryStream]::new()
  try {
   do{
    $buffer=[byte[]]::new(65536)
    $guard=[System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(7))
    try{
     $res=$script:ws.ReceiveAsync([System.ArraySegment[byte]]::new($buffer),$guard.Token).GetAwaiter().GetResult()
    }finally{$guard.Dispose()}
    if($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close){throw 'G53_CDP_WEBSOCKET_CLOSED'}
    $memory.Write($buffer,0,$res.Count)
    if($memory.Length -gt 8388608){throw 'G53_CDP_MESSAGE_SIZE_LIMIT'}
   }while(-not $res.EndOfMessage)
   $text=[System.Text.Encoding]::UTF8.GetString($memory.ToArray())
   $obj=$text|ConvertFrom-Json
   if($obj.id -eq $script:seq){
    if($obj.error){throw ('G53_CDP_ERROR_'+$method+'_'+$obj.error.message)}
    if($obj.result.exceptionDetails){throw ('G53_BROWSER_SCRIPT_EXCEPTION_'+$obj.result.exceptionDetails.text)}
    return $obj.result
   }
  }finally{$memory.Dispose()}
 }
 throw ('G53_CDP_RESPONSE_NOT_OBSERVED_'+$method)
}
function Evaluate-G53([string]$expression){
 $result=Invoke-G53CDP 'Runtime.evaluate' @{expression=$expression;returnByValue=$true}
 if($result.exceptionDetails){throw ('G53_JAVASCRIPT_EXCEPTION_'+$result.exceptionDetails.text)}
 return $result.result.value
}
function Click-G53([string]$selector){
 $js='(()=>{const e=document.querySelector('+($selector|ConvertTo-Json -Compress)+');'+
  'if(!e)throw Error("ELEMENT_NOT_FOUND");e.scrollIntoView({block:"center",behavior:"instant"});'+
  'const r=e.getBoundingClientRect();if(r.width<=0||r.height<=0)throw Error("HIDDEN_TARGET");'+
  'return {x:r.left+r.width/2,y:r.top+r.height/2}})()'
 $xy=Evaluate-G53 $js
 [void](Invoke-G53CDP 'Input.dispatchMouseEvent' @{type='mouseMoved';x=[double]$xy.x;y=[double]$xy.y;button='none'})
 [void](Invoke-G53CDP 'Input.dispatchMouseEvent' @{type='mousePressed';x=[double]$xy.x;y=[double]$xy.y;button='left';clickCount=1})
 [void](Invoke-G53CDP 'Input.dispatchMouseEvent' @{type='mouseReleased';x=[double]$xy.x;y=[double]$xy.y;button='left';clickCount=1})
}
try {
 $info=[System.Diagnostics.ProcessStartInfo]::new($browserExe)
 $info.UseShellExecute=$false
 $info.WorkingDirectory=$env:RUNNER_TEMP
 foreach($arg in @(
  '--headless=new','--disable-gpu','--disable-extensions',
  '--disable-background-networking','--disable-component-update',
  '--disable-default-apps','--no-first-run','--no-default-browser-check',
  '--disable-sync','--no-proxy-server',
  '--host-resolver-rules=MAP * ~NOTFOUND,EXCLUDE localhost',
  '--remote-debugging-port=0',('--user-data-dir='+$profile),
  '--window-size=1500,1100','about:blank'
 )){[void]$info.ArgumentList.Add($arg)}
 $job=[G53ProcessTreeBudget]::Create([ulong]536870912)
 $browserProcess=[System.Diagnostics.Process]::Start($info)
 if(!$browserProcess){throw 'G53_BROWSER_START_FAILURE'}
 [G53ProcessTreeBudget]::Attach($job,$browserProcess.Handle)
 $activePort=Join-Path $profile 'DevToolsActivePort'
 while(!(Test-Path -LiteralPath $activePort)){
  if($browserProcess.HasExited){throw 'G53_BROWSER_EXITED_BEFORE_DEVTOOLS'}
  if($browserWatch.Elapsed.TotalSeconds -gt 35){throw 'G53_BROWSER_DEBUG_ENDPOINT_TIMEOUT'}
  Start-Sleep -Milliseconds 250
 }
 $lines=Get-Content -LiteralPath $activePort
 $port=[int]$lines[0]
 if($port -lt 1024 -or $port -gt 65535){throw 'G53_CDP_INVALID_EPHEMERAL_PORT'}
 $pageResult=Invoke-RestMethod -Uri ('http://127.0.0.1:'+ $port +'/json/list') -TimeoutSec 6
 $pages=@($pageResult)
 if($pages.Count -eq 1 -and $pages[0] -is [array]){$pages=@($pages[0])}
 $matches=@($pages|Where-Object {$_.type -eq 'page' -and $_.webSocketDebuggerUrl})
 if($matches.Count -lt 1){throw 'G53_CDP_PAGE_NOT_DISCOVERED'}
 $endpoint=[string](@($matches[0].webSocketDebuggerUrl)[0])
 if(!$endpoint){throw 'G53_BROWSER_PAGE_WEBSOCKET_ENDPOINT_EMPTY'}
 $wsUri=[Uri]::new($endpoint)
 if($wsUri.Scheme -cne 'ws' -or $wsUri.Host -cne '127.0.0.1' -or
   $wsUri.AbsolutePath -notlike '/devtools/page/*' -or $wsUri.Port -ne $port){
  throw 'G53_BROWSER_PAGE_WEBSOCKET_ENDPOINT_INVALID'
 }
 $script:ws=[System.Net.WebSockets.ClientWebSocket]::new()
 $script:ws.ConnectAsync($wsUri,$token).GetAwaiter().GetResult()
 [void](Invoke-G53CDP 'Page.enable')
 [void](Invoke-G53CDP 'Runtime.enable')
 $fileUri=([Uri]::new([System.IO.Path]::GetFullPath($PrivateHtml))).AbsoluteUri
 [void](Invoke-G53CDP 'Page.navigate' @{url=$fileUri})
 $ready=$false
 for($j=0;$j -lt 120;$j++){
  $state=Evaluate-G53 'document.readyState==="complete" && !!document.querySelector("#pairs button[data-pair-source]") && document.querySelectorAll("#edges tbody tr").length>1'
  if($state){$ready=$true;break}
  if($browserWatch.Elapsed.TotalSeconds -gt 75){break}
  Start-Sleep -Milliseconds 150
 }
 if(!$ready){throw 'G53_REAL_BROWSER_PRIVATE_PAGE_NOT_READY'}
 $identity=Evaluate-G53 '(()=>({browser:navigator.userAgent,source:location.protocol,pairs:document.querySelectorAll("#pairs button[data-pair-source]").length,rows:document.querySelectorAll("#edges tbody tr").length}))()'
 if($identity.source -cne 'file:' -or $identity.pairs -lt 1 -or $identity.rows -ne 552 -or
  $identity.browser -notmatch 'Chrome|Edg'){throw 'G53_CHROMIUM_OR_AUTHENTIC_ROW_IDENTITY_FAILURE'}
 $pair=Evaluate-G53 '(()=>{const b=document.querySelector("#pairs button[data-pair-source]");const a=[...document.querySelectorAll("#edges tbody tr")];return {source:b.dataset.pairSource,target:b.dataset.pairTarget,count:a.filter(e=>e.dataset.callerPackage===b.dataset.pairSource&&e.dataset.calleePackage===b.dataset.pairTarget).length}})()'
 if($pair.count -le 0){throw 'G53_SELECTED_PAIR_HAS_NO_STATIC_EDGE'}
 Click-G53 '#pairs button[data-pair-source]'
 $selected=Evaluate-G53 '(()=>({visible:[...document.querySelectorAll("#edges tbody tr")].filter(e=>!e.hidden).length,pressed:document.querySelector("#pairs button[data-pair-source]").getAttribute("aria-pressed"),status:document.querySelector("#pair-status").textContent,focus:document.activeElement.id}))()'
 if($selected.visible -ne $pair.count -or $selected.pressed -cne 'true' -or
  $selected.focus -cne 'edge-heading' -or
  !$selected.status.Contains($pair.source) -or !$selected.status.Contains($pair.target)){
  throw 'G53_REAL_MOUSE_SELECTION_STATUS_AND_FOCUS_FAILED'
 }
 Click-G53 '#q'
 [void](Invoke-G53CDP 'Input.insertText' @{text='g53_no_matching_dependency_a17bf9'})
 $searched=Evaluate-G53 '(()=>({visible:[...document.querySelectorAll("#edges tbody tr")].filter(e=>!e.hidden).length,query:document.querySelector("#q").value,status:document.querySelector("#pair-status").textContent,pressed:document.querySelector("#pairs button[data-pair-source]").getAttribute("aria-pressed")}))()'
 if($searched.visible -ne 0 -or $searched.query -cne 'g53_no_matching_dependency_a17bf9' -or
  $searched.pressed -cne 'true' -or !$searched.status.Contains('showing 0 of')){
  throw 'G53_REAL_KEYBOARD_TEXT_SEARCH_INTERSECTION_FAILED'
 }
 Click-G53 '#clear-pair'
 $reset=Evaluate-G53 '(()=>({visible:[...document.querySelectorAll("#edges tbody tr")].filter(e=>!e.hidden).length,query:document.querySelector("#q").value,status:document.querySelector("#pair-status").textContent,pressed:document.querySelector("#pairs button[data-pair-source]").getAttribute("aria-pressed"),focus:document.activeElement.id}))()'
 if($reset.visible -ne 552 -or $reset.query -cne '' -or
  $reset.status -cne 'All qualified edges shown.' -or
  $reset.pressed -cne 'false' -or $reset.focus -cne 'edge-heading'){
  throw 'G53_REAL_MOUSE_RESET_AND_FOCUS_FAILED'
 }
 Click-G53 '#pairs button[data-pair-source]'
 Click-G53 '#pairs button[data-pair-source]'
 $toggle=Evaluate-G53 '(()=>({visible:[...document.querySelectorAll("#edges tbody tr")].filter(e=>!e.hidden).length,pressed:document.querySelector("#pairs button[data-pair-source]").getAttribute("aria-pressed")}))()'
 if($toggle.visible -ne 552 -or $toggle.pressed -cne 'false'){
  throw 'G53_REAL_MOUSE_SECOND_CLICK_DESELECTION_FAILED'
 }
 $metrics=[G53ProcessTreeBudget]::Read($job)
 $cpu=[long][Math]::Ceiling($metrics[0]);$peak=[long]$metrics[1]
 $combined=$PriorCpuMs+$cpu
 if($cpu -lt 0 -or $combined -gt 120000 -or $peak -le 0 -or $peak -gt 536870912 -or
   ($PriorWallMs+$browserWatch.ElapsedMilliseconds) -gt 120000){
  throw 'G53_BROWSER_PROCESS_TREE_BUDGET_EXCEEDED'
 }
 Write-Host 'G53_AUTHENTIC_FILE_CHROMIUM_ENGINE=PASS'
 Write-Host 'G53_REAL_CDP_MOUSE_PAIR_SELECTION=PASS'
 Write-Host 'G53_REAL_CDP_KEYBOARD_TEXT_FILTER=PASS'
 Write-Host 'G53_REAL_CDP_RESET_AND_FOCUS=PASS'
 Write-Host 'G53_REAL_CDP_PAIR_TOGGLE=PASS'
 Write-Host ('G53_BROWSER_USER_AGENT_SHA256='+[Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity.browser))).ToLowerInvariant())
 Write-Host ('G53_CHROMIUM_PAIRED_STATIC_EDGES='+$pair.count)
 Write-Host ('G53_BROWSER_JOB_CPU_MS='+$cpu)
 Write-Host ('G53_BROWSER_JOB_PEAK_COMMITTED_BYTES='+$peak)
 Write-Host ('G53_TOTAL_JOB_CPU_MS='+$combined)
 Write-Host 'G53_PRIVATE_HTML_GRAPH_PROFILE_NOT_UPLOADED=PASS'
 return [pscustomobject]@{engine='Chromium';browser_job_cpu_ms=$cpu;browser_peak_committed_bytes=$peak;combined_cpu_ms=$combined;browser_wall_ms=$browserWatch.ElapsedMilliseconds;real_mouse_keyboard_pass=$true;authentic_static_rows=$identity.rows;qualified_pair_count=$identity.pairs;selected_pair_edges=$pair.count}
}finally{
 if($script:ws){try{$script:ws.Dispose()}catch{}}
 if($browserProcess){
  try{if(-not $browserProcess.HasExited){$browserProcess.Kill($true)}}catch{}
  try{$browserProcess.WaitForExit(10000)|Out-Null}catch{}
 }
 if($job -ne [IntPtr]::Zero){try{[G53ProcessTreeBudget]::Close($job)}catch{}}
 if(Test-Path -LiteralPath $profile){Remove-Item -LiteralPath $profile -Recurse -Force -ErrorAction SilentlyContinue}
 if(Test-Path -LiteralPath $profile){throw 'G53_BROWSER_PROFILE_CLEANUP_FAILED'}
}
