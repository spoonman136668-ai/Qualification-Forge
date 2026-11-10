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
# W119: one request per level, no retries, redirects or body logging.
# Levels 1/2 distinguish a bad path/network from level-3-only rejection.
$handler=[Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect=$false
$client=[Net.Http.HttpClient]::new($handler)
$client.Timeout=[TimeSpan]::FromSeconds(12)
[void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept','application/json')
$httpStatus='REQUEST_FAILED'
$httpClass='NOT_CLASSIFIED'
$levels=@{}
try{
 foreach($level in @(1,2,3)){
   $response=$null
   $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,
      ('https://api.exchange.coinbase.com/products/BTC-USD/book?level='+$level))
   try{
     $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
     $status=[string][int]$response.StatusCode
     $levels[$level]=$status
     if($level -eq 3){
       $httpStatus=$status
       if($status -ne '200'){
         $httpClass='HTTP_'+$status+'_UNCLASSIFIED'
         $length=$response.Content.Headers.ContentLength
         if($null -ne $length -and $length -gt 2048){$httpClass='ERROR_BODY_OVERSIZED'}
         else{
           try{
             $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
             $buf=New-Object byte[] 2048
             $bytes=$stream.Read($buf,0,$buf.Length)
             if($bytes -gt 0){
               $body=[Text.Encoding]::UTF8.GetString($buf,0,$bytes)
               if($body -match 'auth|api.key|permission|forbidden'){$httpClass='ACCESS_OR_AUTH_REQUIRED'}
               elseif($body -match 'rate.limit|too.many'){$httpClass='RATE_LIMITED'}
               elseif($body -match 'invalid|level|unsupported|bad.request'){$httpClass='INVALID_REQUEST_OR_LEVEL'}
               elseif($body -match 'cloudflare|challenge|proxy|denied'){$httpClass='EDGE_OR_PROXY_REJECTION'}
             }
           }catch{$httpClass='ERROR_BODY_UNAVAILABLE'}
         }
       }
     }
   }catch{
     $levels[$level]='TRANSPORT_UNAVAILABLE'
     if($level -eq 3){$httpStatus='TRANSPORT_UNAVAILABLE'}
   }finally{
     if($response){$response.Dispose()}
     $request.Dispose()
   }
 }
}finally{$client.Dispose()}
foreach($level in @(1,2,3)){
 Write-Host ('W119_PUBLIC_BOOK_LEVEL_'+$level+'_STATUS='+$levels[$level])
}
Write-Host ('W119_PUBLIC_LEVEL3_ERROR_CLASS='+$httpClass)
$wsStatus='CONNECT_UNAVAILABLE'
$ackStatus='NOT_ATTEMPTED'
$firstType='NONE'
$errorClass='NONE'
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
     $receiveSegment=[ArraySegment[byte]]::new($buf)
     $received=$ws.ReceiveAsync($receiveSegment,$cancel.Token).GetAwaiter().GetResult()
     if($received.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Text -and $received.EndOfMessage -and $received.Count -gt 0){
       $msg=[Text.Encoding]::UTF8.GetString($buf,0,$received.Count)|ConvertFrom-Json -AsHashtable
       if($msg -isnot [System.Collections.IDictionary]){
         $firstType='NON_OBJECT';$ackStatus='UNEXPECTED_ENVELOPE'
       }else{
         $type=if($msg.Contains('type')){[string]$msg['type']}else{''}
         $firstType=switch($type) {
           'subscriptions' {'SUBSCRIPTIONS';break}
           'error' {'ERROR';break}
           'heartbeat' {'HEARTBEAT';break}
           'match' {'MATCH';break}
           default {'OTHER_OR_MISSING';break}
         }
         if($type -ceq 'subscriptions' -and $msg.Contains('channels')){
           $channels=@($msg['channels'])
           if($channels.Count -eq 1 -and $channels[0] -is [System.Collections.IDictionary] -and
              $channels[0].Contains('name') -and $channels[0]['name'] -ceq 'full' -and
              $channels[0].Contains('product_ids') -and
              @($channels[0]['product_ids']).Count -eq 1 -and
              @($channels[0]['product_ids'])[0] -ceq 'BTC-USD'){$ackStatus='FULL_BTC_USD'}
           else{$ackStatus='WRONG_CHANNEL_OR_PRODUCT'}
         }elseif($type -ceq 'error'){
           $ackStatus='SERVER_ERROR'
           $message=if($msg.Contains('message')){[string]$msg['message']}else{''}
           $errorClass=if($message -match 'auth|credential|permission|api.?key'){'ACCESS_OR_AUTH'}
             elseif($message -match 'limit|too.many|quota'){'LIMIT_OR_QUOTA'}
             elseif($message -match 'full|channel|unknown|unsupported'){'CHANNEL_REFUSED'}
             elseif($message -match 'product|currency'){'PRODUCT_REFUSED'}
             else{'ERROR_UNCLASSIFIED'}
         }else{$ackStatus='UNEXPECTED_FIRST_MESSAGE'}
       }
     }else{$ackStatus='NO_COMPLETE_TEXT_ACK'}
   }
 }catch{
   $kind=$_.Exception.GetType().Name -replace '[^A-Za-z]',''
   if($wsStatus -eq 'CONNECTED'){$ackStatus='CLIENT_OR_CHANNEL_ERROR_'+$kind}
   else{$wsStatus='CONNECT_ERROR_'+$kind}
 }
}finally{
 try{$ws.Dispose()}catch{}
 $cancel.Dispose()
}
Write-Host ('W119_PUBLIC_WEBSOCKET_STATUS='+$wsStatus)
Write-Host ('W119_PUBLIC_FIRST_MESSAGE_TYPE='+$firstType)
Write-Host ('W119_PUBLIC_SUBSCRIPTION_ACK='+$ackStatus)
Write-Host ('W119_PUBLIC_ERROR_CLASS='+$errorClass)
Require ($okDNS -and $httpStatus -ceq '200' -and
 $wsStatus -ceq 'CONNECTED' -and $ackStatus -ceq 'FULL_BTC_USD') 'W119_PUBLIC_EXCHANGE_CONNECTIVITY_UNVERIFIED'
Write-Host 'W119_PUBLIC_CONNECTIVITY_AND_ACK=PASS;ORDER_CALLS=0;KEYS=0;SYNTHETIC_BARS=0'
