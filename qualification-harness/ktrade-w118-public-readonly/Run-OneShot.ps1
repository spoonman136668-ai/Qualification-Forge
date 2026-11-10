# W118: one-shot, public Coinbase Exchange market-data-only engineering probe.
# Run solely on the qualified exact-source hosted Windows runner. Product
# checkout remains tracked-clean. No credentials/accounts/broker, orders,
# retries, installs, persistent state, scheduled jobs, or payment APIs.
param([Parameter(Mandatory=$true)][string]$ExpectedSourceSha,
      [Parameter(Mandatory=$true)][string]$ExpectedTreeSha)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$pass,[string]$reason){if(!$pass){throw $reason}}
Require ($ExpectedSourceSha -ceq 'ef7c7105879025d8e8e04d2b26900b19886804b0' -and
  $ExpectedTreeSha -ceq '13e0e6330512293b118f767d48fda0759bf98bfe' -and
  $env:RUNNER_OS -ceq 'Windows' -and
  $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
  $env:GITHUB_REPOSITORY -ceq 'spoonman136668-ai/Qualification-Forge' -and
  $env:GITHUB_EVENT_NAME -ceq 'push' -and
  $env:GITHUB_REF -ceq 'refs/heads/qualification/ktrade-ui-workstation-refresh-20261108') 'W118_RUNNER_OR_SCOPE_REFUSED'
Require ($env:KTRADE_LIVE_TRADING -ceq 'false' -and
  $env:KTRADE_CI_LIVE_AUTHORITY -ceq '0' -and
  $env:KTRADE_CI_PROMOTION_ALLOWED -ceq '0' -and
  $env:W118_PUBLIC_MARKET_DATA_ONLY -ceq '1' -and
  $env:KTRADE_PAPER_SESSION_ROOT -ceq '' -and
  $env:KTRADE_PAPER_CUSTODY_REVIEW_ROOT -ceq '') 'W118_TRADING_AUTHORITY_REFUSED'
$p=Join-Path $env:GITHUB_WORKSPACE 'product'
$q=Join-Path $env:GITHUB_WORKSPACE 'qualifier'
$src=Join-Path $q 'qualification-harness/ktrade-w118-public-readonly/public_probe_test.go'
$dst=Join-Path $p 'internal/tickchart/w118_public_readonly_probe_test.go'
$log=Join-Path $env:RUNNER_TEMP 'w118-public-market-data-private.log'
Require (!(Test-Path -LiteralPath $dst) -and
  (Test-Path -LiteralPath $src -PathType Leaf) -and
  !(Test-Path -LiteralPath (Join-Path $p '.env'))) 'W118_PROBE_SOURCE_OR_ENVIRONMENT_UNSAFE'
Require ((& git -C $p rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
  (& git -C $p rev-parse 'HEAD^{tree}').Trim() -ceq $ExpectedTreeSha -and
  @(& git -C $p status --porcelain).Count -eq 0) 'W118_PRODUCT_SOURCE_CUSTODY_REFUSED'
Require ((& git -C $q hash-object -- $src).Trim() -ceq 'b59876f0f6bbb349802d5fb03ea81dc8cae08fde') 'W118_PROBE_HASH_MISMATCH'
try{
  Copy-Item -LiteralPath $src -Destination $dst -ErrorAction Stop
  Require ((& git -C $p hash-object -- $dst).Trim() -ceq 'b59876f0f6bbb349802d5fb03ea81dc8cae08fde') 'W118_TEST_STAGING_DRIFT'
  Push-Location -LiteralPath $p
  try{
    & go test -mod=readonly -count=1 -tags w118_public_readonly_probe -timeout 90s -v ./internal/tickchart -run '^TestW118PublicCoinbaseFullReadOnlyHundredTrades$' *> $log
    $exit=$LASTEXITCODE
    $raw=[IO.File]::ReadAllText($log)
    $pass=[regex]::Match($raw,'W118_PUBLIC_MARKET_TLS_WS_L3_SESSION_100T=PASS;duration=[0-9a-zA-Z.]+;product=BTC-USD;completed_bars=1;trade_count=100;execution_mode=READ_ONLY;auth=NONE;orders=ZERO;retries=ZERO')
    $fail=[regex]::Match($raw,'W118_PUBLIC_MARKET_RESULT=UNVERIFIED;class=([A-Z_]+);elapsed=[0-9a-zA-Z.]+;completed_bars=[0-9]+;orders=ZERO;retries=ZERO')
    if($exit -eq 0 -and $pass.Success){
      Write-Host ('QFORGE_W118_PUBLIC_EXCHANGE_FULL_REAL_100T=PASS;source='+$ExpectedSourceSha+';orders=0;accounts=0;credentials=0')
    }else{
      $class=if($fail.Success){$fail.Groups[1].Value}else{'RUNNER_OR_RUNTIME_UNVERIFIED'}
      Write-Host ('QFORGE_W118_PUBLIC_DATA_ACCEPTANCE=UNVERIFIED;class='+$class+';source='+$ExpectedSourceSha)
      throw 'W118_NO_VERIFIED_REAL_PUBLIC_COMPLETED_BAR'
    }
  }finally{Pop-Location}
}finally{
  Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
Require ((& git -C $p rev-parse HEAD).Trim() -ceq $ExpectedSourceSha -and
  (& git -C $p rev-parse 'HEAD^{tree}').Trim() -ceq $ExpectedTreeSha -and
  @(& git -C $p status --porcelain).Count -eq 0) 'W118_PRODUCT_WORKTREE_CHANGED'
