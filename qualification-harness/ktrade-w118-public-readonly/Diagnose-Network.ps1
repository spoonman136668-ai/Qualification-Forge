# W118B: one-shot PUBLIC market-data endpoint diagnostics on hosted Windows.
# This is NOT product qualification, a Coinbase account connection, an order,
# a historical feed reconstruction, or a standing monitor. Zero credentials.
# No retries; classify independently at DNS, HTTPS L3 headers, and WS subscribe.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$x,[string]$code){if(!$x){throw $code}}
Require ($env:RUNNER_OS -ceq 'Windows' -and
 $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
 $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
 $env:GITHUB_EVENT_NAME -ceq 'push' -and
 $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108' -and
 $env:KTRADE_LIVE_TRADING -ceq 'false' -and
 $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
 $env:W118B_PUBLIC_MARKET_DIAGNOSTIC_ONLY -ceq '1') 'W118B_UNAUTHORIZED_OR_ARMED'
$okDNS=$true
foreach($hostname in @('api.exchange.coinbase.com','ws-feed.exchange.coinbase.com')){
 try{
  $addresses=[Net.Dns]::GetHostAddresses($hostname)
  if(!$addresses -or $addresses.Length -lt 1){throw 'NO_HOST_ADDRESS'}
  Write-Host ('W118B_DNS_'+($hostname -replace '[^a-zA-Z]','_')+'=PASS')
 }catch{
  Write-Host ('W118B_DNS_'+($hostname -replace '[^a-zA-Z]','_')+'=UNAVAILABLE')
  $okDNS=$false
 }
}
$client=[Net.Http.HttpClient]::new()
$client.Timeout=[TimeSpan]::FromSeconds(14)
$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept','application/json')|Out-Null
$httpStatus='REQUEST_FAILED'
$response=$null
try{
 $uri='https://api.exchange.coinbase.com/products/BTC-USD/book?level=3'
 $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$uri)
 try{
   $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
   $httpStatus=[string][int]$response.StatusCode
 }finally{$request.Dispose()}
}catch{$httpStatus='TRANSPORT_UNAVAILABLE'}
finally{
 if($response){$response.Dispose()}
 $client.Dispose()
}
Write-Host ('W118B_PUBLIC_LEVEL3_HTTPS_STATUS='+$httpStatus)
$wsStatus='CONNECT_UNAVAILABLE'
$ackStatus='NOT_ATTEMPTED'
$ws=[Net.WebSockets.ClientWebSocket]::new()
$cancel=[Threading.CancellationTokenSource]::new()
try{
 $cancel.CancelAfter([TimeSpan]::FromSeconds(12))
 try{
   $ws.ConnectAsync([uri]'wss://ws-feed.exchange.coinbase.com',$cancel.Token).GetAwaiter().GetResult()
   if($ws.State -eq [Net.WebSockets.WebSocketState]::Open){
     $wsStatus='CONNECTED'
     $sub='{"type":"subscribe","product_ids":["BTC-USD"],"channels":["full"]}'
     $raw=[Text.Encoding]::UTF8.GetBytes($sub)
     $segment=[ArraySegment[byte]]::new($raw)
     $ws.SendAsync($segment,[Net.WebSockets.WebSocketMessageType]::Text,$true,$cancel.Token).GetAwaiter().GetResult()
     $buf=New-Object byte[] 8192
     $received=$ws.ReceiveAsync([ArraySegment[byte]]::new($buf),$cancel.Token).GetAwaiter().GetResult()
     if($received.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Text -and $received.EndOfMessage -and $received.Count -gt 0){
       $msg=[Text.Encoding]::UTF8.GetString($buf,0,$received.Count)|ConvertFrom-Json
       $channels=@($msg.channels)
       if($msg.type -ceq 'subscriptions' -and
        $channels.Count -eq 1 -and
        $channels[0].name -ceq 'full' -and
        @($channels[0].product_ids).Count -eq 1 -and
        $channels[0].product_ids[0] -ceq 'BTC-USD'){
         $ackStatus='FULL_BTC_USD'
       }else{$ackStatus='UNEXPECTED_FIRST_MESSAGE'}
     }else{$ackStatus='NO_COMPLETE_TEXT_ACK'}
   }
 }catch{
   if($wsStatus -eq 'CONNECTED'){$ackStatus='ACK_TIMEOUT_OR_RECEIVE_FAILED'}
 }
}finally{
 try{$ws.Dispose()}catch{}
 $cancel.Dispose()
}
Write-Host ('W118B_PUBLIC_WEBSOCKET_STATUS='+$wsStatus)
Write-Host ('W118B_PUBLIC_SUBSCRIPTION_ACK='+$ackStatus)
Require ($okDNS -and $httpStatus -ceq '200' -and
 $wsStatus -ceq 'CONNECTED' -and $ackStatus -ceq 'FULL_BTC_USD') 'W118B_PUBLIC_EXCHANGE_CONNECTIVITY_UNVERIFIED'
Write-Host 'W118B_PUBLIC_CONNECTIVITY_AND_ACK=PASS;ORDER_CALLS=0;KEYS=0;SYNTHETIC_BARS=0'
