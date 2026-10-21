#requires -Version 7.2
<#
R25-C75D3B2D read-only, non-executing donor foundation preflight.
Invoke only through the existing authorized KTRADE/CKB-plane qualification path.
Does not clone, fetch, stage, test, dispatch, promote, or mutate a checkout.
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$DonorCheckout,
 [Parameter(Mandatory=$true)][string]$CandidateCheckout,
 [Parameter(Mandatory=$true)][string]$ReceiptPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expected=@{
 donor=@{
  commit='520cfe124fdd7e8dcbf16b6a6f38229b43db7dbc'
  tree='b74808f35e798b1b72e8fb31a49a5f4664ca87b5'
  paths=@('go.mod','pkg/strategy_engine.go','pkg/strategy_types.go',
   'pkg/risk.go','pkg/tradeguard_continuity.go',
   'pkg/tradeguard_continuity_runtime.go','pkg/candle-builder.go')
 }
 candidate=@{
  commit='94c7fdb6944ac8a30681101ffa8fb25ac2ced1c0'
  tree='5435e444f133ba2d386eaac648889de2ea6a0f5e'
  paths=@('go.mod','internal/paperlifecycle/authority.go',
   'internal/paperlifecycle/native_source_binding.go',
   'internal/paperlifecycle/native_risk_restore_review.go',
   'tests/donor-shadow/c75d3b2_native_bound_lifecycle_test.go',
   'tests/donor-native-vwap/native_vwap_bridge_c74f2.go')
 }
}
if(!(Get-Command git -ErrorAction SilentlyContinue)){throw 'D3B2D_GIT_NOT_AVAILABLE'}
function GitRead([string]$root,[string[]]$argsList){
 $result=@(& git -C $root @argsList 2>&1)
 if($LASTEXITCODE -ne 0){throw 'D3B2D_GIT_READ_FAILED'}
 return $result
}
function VerifyRoot([string]$role,[string]$supplied){
 $info=$expected[$role]
 $path=[IO.Path]::GetFullPath($supplied).TrimEnd('\','/')
 if(!(Test-Path -LiteralPath $path -PathType Container)){
  throw ('D3B2D_'+$role+'_CHECKOUT_MISSING')
 }
 if(((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw ('D3B2D_'+$role+'_REPARSE_ROOT')
 }
 $top=[string](@(GitRead $path @('rev-parse','--show-toplevel'))[-1])
 if([IO.Path]::GetFullPath($top).TrimEnd('\','/') -ine $path){
  throw ('D3B2D_'+$role+'_NOT_REPO_ROOT')
 }
 $sha=[string](@(GitRead $path @('rev-parse','--verify','HEAD'))[-1])
 $tree=[string](@(GitRead $path @('rev-parse','HEAD^{tree}'))[-1])
 if($sha -cne $info.commit -or $tree -cne $info.tree){
  throw ('D3B2D_'+$role+'_SHA_OR_TREE_DRIFT')
 }
 if(@(GitRead $path @('status','--porcelain=v1','--untracked-files=all')).Count -ne 0){
  throw ('D3B2D_'+$role+'_DIRTY_WORKTREE')
 }
 foreach($rel in $info.paths){
  $obj=@(GitRead $path @('ls-tree','HEAD','--',$rel))
  if($obj.Count -ne 1 -or $obj[0] -notmatch '^[0-9]{6} blob [a-f0-9]{40}\s+'){
   throw ('D3B2D_'+$role+'_REQUIRED_ORIGINAL_BLOB_MISSING')
  }
  $full=Join-Path $path $rel.Replace('/',[IO.Path]::DirectorySeparatorChar)
  if(!(Test-Path -LiteralPath $full -PathType Leaf)){
   throw ('D3B2D_'+$role+'_MATERIALIZATION_MISSING')
  }
  if(((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw ('D3B2D_'+$role+'_REPARSE_BLOB')
  }
 }
 return @{role=$role;sha=$sha;tree=$tree;clean=$true;blobs=$info.paths.Count}
}
$donor=VerifyRoot 'donor' $DonorCheckout
$candidate=VerifyRoot 'candidate' $CandidateCheckout
$donorRoot=[IO.Path]::GetFullPath($DonorCheckout).TrimEnd('\','/')
$candidateRoot=[IO.Path]::GetFullPath($CandidateCheckout).TrimEnd('\','/')
if($donorRoot -ieq $candidateRoot){throw 'D3B2D_COLLIDING_ROOTS'}
$receipt=[IO.Path]::GetFullPath($ReceiptPath)
foreach($root in @($donorRoot,$candidateRoot)){
 if($receipt.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
  throw 'D3B2D_RECEIPT_INSIDE_SOURCE'
 }
}
if(!(Test-Path -LiteralPath (Split-Path -Parent $receipt) -PathType Container) -or
   (Test-Path -LiteralPath $receipt)){
 throw 'D3B2D_RECEIPT_DESTINATION_INVALID'
}
$record=[ordered]@{
 schema='ktrade.r25-c75d3b2d.exact-source-foundation.v1'
 observed_utc=[DateTime]::UtcNow.ToString('o')
 status='FOUNDATION_IDENTITY_ONLY'
 donor=$donor
 candidate=$candidate
 fresh_checkout_created=$false
 original_source_mutated=$false
 native_tests_executed=$false
 final_windows_regression_executed=$false
 trade_authority=$false
 accepted_ref_mutation=$false
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receipt -Encoding utf8NoBOM -NoNewline
Write-Host 'C75D3B2D_EXACT_DONOR_PERSISTENT_FOUNDATION=PASS'
Write-Host 'C75D3B2D_EXACT_KTRADE_PERSISTENT_FOUNDATION=PASS'
Write-Host 'C75D3B2D_NATIVE_EXECUTION_QUALIFICATION=PENDING'
