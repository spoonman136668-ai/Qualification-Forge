# W122: first real public 100T session match/heartbeat acceptance.
# Hosted Windows, exact W121; no owner workstation, credentials, broker/order,
# paid service, retry, scheduled monitor, installation, or state persistence.
param([Parameter(Mandatory=$true)][string]$ExpectedSourceSha,
      [Parameter(Mandatory=$true)][string]$ExpectedTreeSha)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$ok,[string]$reason){if(!$ok){throw $reason}}
Require ($ExpectedSourceSha -ceq 'c44bb75345b48385f784b9500f49ffb127c4411c' -and
  $ExpectedTreeSha -ceq 'c04d67b9e3b1c1a9472e0fcbb8215330f89b25cb' -and
  $env:RUNNER_OS -ceq 'Windows' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
  $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
  $env:GITHUB_EVENT_NAME -ceq 'push' -and
  $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108' -and
  $env:KTRADE_LIVE_TRADING -ceq 'false' -and
  $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
  $env:KTRADE_CI_PROMOTION_ALLOWED -ceq '0' -and
  $env:W122_PUBLIC_READONLY_ONESHOT -ceq '1') 'W122_SCOPE_OR_FINANCIAL_GUARD_REFUSED'
$p=Join-Path $env:GITHUB_WORKSPACE 'product'
$q=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$source=Join-Path $q 'qualification-harness/ktrade-w122-public-readonly/public_probe_test.go'
$destination=Join-Path $p 'internal/tickchart/w122_public_matches_test.go'
$log=Join-Path $env:RUNNER_TEMP 'w122-public-matches-private.log'
Require ((Test-Path -LiteralPath $source -PathType Leaf) -and
 !(Test-Path -LiteralPath $destination) -and
 !(Test-Path -LiteralPath (Join-Path $p '.env'))) 'W122_UNSAFE_TEST_STAGING'
Require ((& git -C $q hash-object -- $source).Trim() -ceq '4987486561e85d560cfe043da1ae4b280db0a1b0') 'W122_TEST_HASH_MISMATCH'
Require ((& git -C $p rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
 (& git -C $p rev-parse 'HEAD^{tree}').Trim() -ceq $ExpectedTreeSha -and
 @(& git -C $p status --porcelain).Count -eq 0) 'W122_EXACT_QUALIFIED_KTRADE_REQUIRED'
try{
 Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
 Push-Location -LiteralPath $p
 try{
  & go test -mod=readonly -count=1 -tags w122_public_matches_heartbeat_probe -timeout 90s -v ./internal/tickchart -run '^TestW122GenuinePublicSessionHundredTrades$' *> $log
  $exit=$LASTEXITCODE
  $output=[IO.File]::ReadAllText($log)
  $pass=[regex]::IsMatch($output,'W122_REAL_PUBLIC_MATCHES_HEARTBEAT_100T=PASS;source=W121;product=BTC-USD;count=100;complete_bars=1;elapsed=[A-Za-z0-9.]+;heartbeats=REQUIRED;gap_free=TRUE;orders=ZERO;credentials=ZERO;retries=ZERO')
  $failure=[regex]::Match($output,'W122_PUBLIC_FEED_RESULT=UNVERIFIED;class=([A-Z_]+);complete_bars=[0-9]+;elapsed=[A-Za-z0-9.]+;orders=ZERO;retries=ZERO')
  if($exit -eq 0 -and $pass){
   Write-Host ('QFORGE_W122_GENUINE_PUBLIC_100T=PASS;source='+$ExpectedSourceSha+';rest_backfill=none;orders=0;credentials=0;retries=0')
  }else{
   $class=if($failure.Success){$failure.Groups[1].Value}else{'RUNTIME_OR_HARNESS_UNVERIFIED'}
   Write-Host ('QFORGE_W122_GENUINE_PUBLIC_100T=UNVERIFIED;class='+$class+';source='+$ExpectedSourceSha)
   throw 'W122_NO_PROVEN_GENUINE_PUBLIC_100T'
  }
 }finally{Pop-Location}
}finally{
 Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
Require ((& git -C $p rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
 (& git -C $p rev-parse 'HEAD^{tree}').Trim() -ceq $ExpectedTreeSha -and
 @(& git -C $p status --porcelain).Count -eq 0) 'W122_PRIVATE_SOURCE_MUTATION_REFUSED'
