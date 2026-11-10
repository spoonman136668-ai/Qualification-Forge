# W120: one-shot, public-data-only feasibility of Coinbase Exchange MATCHES
# + HEARTBEAT + public REST trades as a possible alternate count-chart source.
# NO exact-execution acceptance here: matches can drop messages. Never infer
# certified bars from this probe. No credentials, broker, order, schedule,
# installed app or persistent data. At most one WS and one REST request.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$ok,[string]$why){if(!$ok){throw $why}}
Require ($env:RUNNER_OS -ceq 'Windows' -and
 $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
 $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
 $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108' -and
 $env:GITHUB_EVENT_NAME -ceq 'push' -and
 $env:KTRADE_LIVE_TRADING -ceq 'false' -and
 $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
 $env:KTRADE_CI_PROMOTION_ALLOWED -ceq '0' -and
 $env:W120_PUBLIC_MATCHES_PROBE_ONLY -ceq '1') 'W120_SCOPE_OR_FINANCIAL_GUARD_REFUSED'
$restStatus='UNAVAILABLE'
$restTradeShape='UNVERIFIED'
$handler=[Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect=$false
$http=[Net.Http.HttpClient]::new($handler)
$http.Timeout=[TimeSpan]::FromSeconds(10)
$response=$null
$request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,
 [uri]'https://api.exchange.coinbase.com/products/BTC-USD/trades')
try{
 try{
  $response=$http.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
  $restStatus=[string][int]$response.StatusCode
  if($restStatus -ceq '200'){
    $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $buf=New-Object byte[] 8192
    $n=$stream.Read($buf,0,$buf.Length)
    $sample=[Text.Encoding]::UTF8.GetString($buf,0,$n)
    if($sample.TrimStart().StartsWith('[') -and
       $sample -match '"trade_id"\s*:\s*[0-9]+' -and
       $sample -match '"price"\s*:\s*"' -and
       $sample -match '"size"\s*:\s*"'){$restTradeShape='PUBLIC_TRADE_FIELDS'}
  }
 }catch{$restStatus='TRANSPORT_UNAVAILABLE'}
}finally{
 if($response){$response.Dispose()}
 $request.Dispose();$http.Dispose()
}
Write-Host ('W120_PUBLIC_REST_TRADES_STATUS='+$restStatus)
Write-Host ('W120_PUBLIC_REST_TRADE_SHAPE='+$restTradeShape)
$wsState='CONNECT_UNAVAILABLE'
$ackMatches=$false;$ackHeartbeat=$false
$seenMatch=$false;$seenHeartbeat=$false
$wsClass='NO_SERVER_ERROR'
$ws=[Net.WebSockets.ClientWebSocket]::new()
$cancel=[Threading.CancellationTokenSource]::new()
$start=[Diagnostics.Stopwatch]::StartNew()
try{
 $cancel.CancelAfter([TimeSpan]::FromSeconds(24))
 try{
  $ws.ConnectAsync([uri]'wss://ws-feed.exchange.coinbase.com',$cancel.Token).GetAwaiter().GetResult()
  Require ($ws.State -eq [Net.WebSockets.WebSocketState]::Open) 'W120_WEBSOCKET_NOT_OPEN'
  $wsState='CONNECTED'
  $subscription='{"type":"subscribe","product_ids":["BTC-USD"],"channels":["matches","heartbeat"]}'
  $raw=[Text.Encoding]::UTF8.GetBytes($subscription)
  $ws.SendAsync([ArraySegment[byte]]::new($raw),
    [Net.WebSockets.WebSocketMessageType]::Text,$true,$cancel.Token).GetAwaiter().GetResult()
  for($i=0;$i -lt 64 -and $start.Elapsed.TotalSeconds -lt 22;$i++){
    $buf=New-Object byte[] 8192
    $rec=$ws.ReceiveAsync([ArraySegment[byte]]::new($buf),$cancel.Token).GetAwaiter().GetResult()
    if($rec.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text -or
       !$rec.EndOfMessage -or $rec.Count -lt 1){
      $wsClass='NON_JSON_OR_FRAGMENTED';break
    }
    try{
      $msg=([Text.Encoding]::UTF8.GetString($buf,0,$rec.Count)|ConvertFrom-Json -AsHashtable)
    }catch{$wsClass='INVALID_JSON';break}
    if($msg -isnot [Collections.IDictionary] -or !$msg.Contains('type')){
      $wsClass='UNEXPECTED_FRAME_SHAPE';break
    }
    $type=[string]$msg['type']
    if($type -ceq 'error'){
      $reason=if($msg.Contains('message')){[string]$msg['message']}else{''}
      $wsClass=if($reason -match 'auth|key|credential|permission'){'AUTH_OR_PERMISSION'}
        elseif($reason -match 'limit|quota|many'){'RATE_OR_SUBSCRIPTION_LIMIT'}
        elseif($reason -match 'channel|unknown|unsupported|match'){'CHANNEL_UNAVAILABLE'}
        elseif($reason -match 'product'){'PRODUCT_UNAVAILABLE'}
        else{'SERVER_ERROR_OTHER'}
      break
    }
    if($type -ceq 'subscriptions' -and $msg.Contains('channels')){
      foreach($c in @($msg['channels'])){
        if($c -is [Collections.IDictionary] -and $c.Contains('name') -and
           $c.Contains('product_ids') -and
           (@($c['product_ids']) -contains 'BTC-USD')){
           if($c['name'] -ceq 'matches'){$ackMatches=$true}
           if($c['name'] -ceq 'heartbeat'){$ackHeartbeat=$true}
        }
      }
    }
    if(($type -ceq 'last_match' -or $type -ceq 'match') -and
       $msg.Contains('product_id') -and $msg['product_id'] -ceq 'BTC-USD' -and
       $msg.Contains('trade_id') -and [string]$msg['trade_id'] -match '^[0-9]+$'){$seenMatch=$true}
    if($type -ceq 'heartbeat' -and $msg.Contains('product_id') -and
       $msg['product_id'] -ceq 'BTC-USD' -and
       $msg.Contains('last_trade_id') -and
       [string]$msg['last_trade_id'] -match '^[0-9]+$'){$seenHeartbeat=$true}
    if($ackMatches -and $ackHeartbeat -and $seenMatch -and $seenHeartbeat){break}
  }
 }catch{
  if($wsClass -eq 'NO_SERVER_ERROR'){
   $e=$_.Exception.GetType().Name
   $wsClass=if($e -match 'OperationCanceled'){'TIME_BUDGET_OR_CANCEL'}
     elseif($e -match 'WebSocket'){'WEBSOCKET_TRANSPORT'}
     else{'CLIENT_EXCEPTION'}
  }
 }
}finally{
 $ws.Dispose();$cancel.Dispose()
}
Write-Host ('W120_WS_TRANSPORT='+$wsState)
Write-Host ('W120_WS_SERVER_CLASS='+$wsClass)
Write-Host ('W120_MATCHES_ACK='+$(if($ackMatches){'PASS'}else{'UNVERIFIED'}))
Write-Host ('W120_HEARTBEAT_ACK='+$(if($ackHeartbeat){'PASS'}else{'UNVERIFIED'}))
Write-Host ('W120_MATCH_MESSAGE_SEEN='+$(if($seenMatch){'PASS'}else{'UNVERIFIED'}))
Write-Host ('W120_HEARTBEAT_TRADE_ID_SEEN='+$(if($seenHeartbeat){'PASS'}else{'UNVERIFIED'}))
Require ($restStatus -ceq '200' -and $restTradeShape -ceq 'PUBLIC_TRADE_FIELDS' -and
 $wsState -ceq 'CONNECTED' -and $ackMatches -and $ackHeartbeat -and
 $seenMatch -and $seenHeartbeat) 'W120_PUBLIC_ALTERNATIVE_FEED_FEASIBILITY_UNVERIFIED'
Write-Host 'W120_PUBLIC_MATCH_HEARTBEAT_REST_FEASIBILITY=PASS;NO_COVERAGE_CERTIFICATION=TRUE;ORDERS=ZERO;RETRIES=ZERO'
