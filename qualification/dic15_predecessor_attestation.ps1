# DIC-15: read-only historical predecessor admission. FAIL CLOSED.
# Only an independently sourced, offline, signed ckb.exe may be admitted.
# No real installation/profile paths, network download, or promotion.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ExecutablePath,
  [Parameter(Mandatory=$true)][string]$ExpectedSHA256,
  [Parameter(Mandatory=$true)][string]$ExpectedSignerThumbprint,
  [string]$ExpectedVersion='1.5.7'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Deny([string]$Code){ throw ('DIC15_'+$Code) }
if($env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){Deny 'RUNNER_NOT_INDEPENDENT_WINDOWS'}
if($env:KTRADE_CI_SOURCE_ONLY -cne '1' -or $env:KTRADE_CI_LIVE_AUTHORITY -cne '0' -or
   $env:KTRADE_CI_COINBASE_ALLOWED -cne '0' -or $env:KTRADE_CI_PROMOTION_ALLOWED -cne '0'){
  Deny 'AUTHORITY_ENV_UNSAFE'
}
if($ExpectedSHA256 -cnotmatch '^[a-fA-F0-9]{64}$'){Deny 'INDEPENDENT_HASH_NOT_PINNED'}
if($ExpectedSignerThumbprint -cnotmatch '^[a-fA-F0-9]{40,64}$'){Deny 'INDEPENDENT_SIGNER_NOT_PINNED'}
if($ExpectedVersion -cne '1.5.7'){Deny 'PREDECESSOR_VERSION_NOT_ALLOWED'}
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
$path=[IO.Path]::GetFullPath($ExecutablePath)
if(-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){Deny 'NOT_EPHEMERAL_EVIDENCE'}
if([IO.Path]::GetFileName($path) -cne 'ckb.exe'){Deny 'HISTORICAL_EXECUTABLE_NAME_DRIFT'}
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Deny 'HISTORICAL_EXECUTABLE_UNAVAILABLE'}
$probe=$path
while($probe.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){
  $entry=Get-Item -LiteralPath $probe -Force
  if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){Deny 'REPARSE_POINT_IN_EVIDENCE_PATH'}
  $probe=Split-Path -Parent $probe
}
$file=Get-Item -LiteralPath $path -Force
if($file.Length -lt 4096){Deny 'PREDECESSOR_NOT_REAL_PE_SIZE'}
$bytes=[IO.File]::OpenRead($path)
try{
  if($bytes.ReadByte() -ne 77 -or $bytes.ReadByte() -ne 90){Deny 'PREDECESSOR_NOT_PE'}
}finally{$bytes.Dispose()}
$sha=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
if($sha -cne $ExpectedSHA256.ToLowerInvariant()){Deny 'PREDECESSOR_HASH_MISMATCH'}
Write-Host 'DIC15_INDEPENDENT_FILE_HASH=PASS'
$signature=Get-AuthenticodeSignature -LiteralPath $path
if($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate){Deny 'AUTHENTICODE_NOT_VALID'}
if($signature.SignerCertificate.Thumbprint.ToLowerInvariant() -cne $ExpectedSignerThumbprint.ToLowerInvariant()){Deny 'SIGNER_IDENTITY_MISMATCH'}
Write-Host 'DIC15_AUTHENTICATED_SIGNER=PASS'
$vi=[Diagnostics.FileVersionInfo]::GetVersionInfo($path)
$v=([string]$vi.ProductVersion).Trim()
$f=([string]$vi.FileVersion).Trim()
$allowed=@($ExpectedVersion,($ExpectedVersion+'.0'))
if(($v -cnotin $allowed) -and ($f -cnotin $allowed)){Deny 'PREDECESSOR_VERSION_MISMATCH'}
Write-Host 'DIC15_PREDECESSOR_1_5_7_IDENTITY=PASS'
Write-Host 'DIC15_PREDECESSOR_AUTHENTICATED=PASS'
# A valid predecessor alone still cannot authorize migration: require separately
# qualified actual install paths, signed target, updater, and version policy.
Write-Host 'DIC15_REAL_INSTALL_OR_UPGRADE_AUTHORIZED=FALSE'
