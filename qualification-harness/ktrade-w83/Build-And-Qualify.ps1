# W83 read-only exact-source/evidence preflight and two source-built packages.
# SOURCE ONLY. Run solely inside established authorized hosted Windows qualification.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$PreviousCheckout,
 [Parameter(Mandatory=$true)][string]$CandidateCheckout,
 [Parameter(Mandatory=$true)][string]$WitnessScript,
 [Parameter(Mandatory=$true)][string]$NativeInputsPath,
 [Parameter(Mandatory=$true)][string]$PaperScenarioPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
function Require([bool]$ok,[string]$name){if(!$ok){throw $name}}
Require ($env:OS -ceq 'Windows_NT' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted') 'W83_UNAUTHORIZED_EXECUTION_ENVIRONMENT'
Require ($env:RUNNER_TEMP -and (Test-Path -LiteralPath $env:RUNNER_TEMP -PathType Container)) 'W83_RUNNER_TEMP_REQUIRED'
$expected=@(
 @{name='PREVIOUS';root=$PreviousCheckout;sha='b03dd6e58b6120cae3ffd39a79c6965ab8e91b9a';tree='989020f81a7c731acf3bfa830c06e7e929805bcd'},
 @{name='CANDIDATE';root=$CandidateCheckout;sha='7ddea43a58e433de38244215b256d76988f5e9f6';tree='5dc9bfce99e5f97fa3c434542509763ee8f29294'}
)
foreach($entry in $expected){
 $actualSHA=(& git -C $entry.root rev-parse HEAD).Trim()
 $actualTree=(& git -C $entry.root rev-parse 'HEAD^{tree}').Trim()
 $gitExit=$LASTEXITCODE
 Write-Output ('W83_SOURCE_ACTUAL_'+$entry.name+' SHA='+$actualSHA+' TREE='+$actualTree+' GIT_EXIT='+$gitExit)
 Require ($gitExit -eq 0 -and $actualSHA -ceq $entry.sha -and $actualTree -ceq $entry.tree) ('W83_'+$entry.name+'_EXACT_IDENTITY_FAILED')
 $status=@(& git -C $entry.root status --porcelain --untracked-files=no)
 Require ($status.Count -eq 0) ('W83_'+$entry.name+'_DIRTY_TRACKED_SOURCE')
}
$unchanged=@(
 'tools/wails-pilot/backend/installed_update.go',
 'tools/wails-pilot/backend/installed_update_test.go',
 'tools/wails-pilot/backend/fresh_launch.go',
 'tools/wails-pilot/backend/setup_bundle.go',
 'tools/wails-pilot/backend/release_process_lease.go',
 'tools/wails-pilot/cmd/release-setup/main.go',
 'tools/wails-pilot/cmd/release-launch/main.go',
 'tools/wails-pilot/backend/fresh_uninstall.go',
 'windows/Install-KTRADE-Fresh.ps1'
)
foreach($path in $unchanged){
 $a=(& git -C $PreviousCheckout rev-parse ('HEAD:'+$path)).Trim()
 $b=(& git -C $CandidateCheckout rev-parse ('HEAD:'+$path)).Trim()
 Require ($LASTEXITCODE -eq 0 -and $a -ceq $b -and $a -cmatch '^[a-f0-9]{40}$') ('W83_INSTALLER_FOUNDATION_IDENTITY_DRIFT_'+$path)
}
Write-Output 'W83_SOURCE_AND_NINE_INSTALLER_BLOBS_IDENTICAL=PASS'
$foundations=@(
 @{id=40615926800;sha='5c2a6200f54b4a9e50c05e00ffe45f42a2b5b413'},
 @{id=40787692876;sha='858d21380e1e88c01555371c6e258dfab07f7446'}
)
foreach($proof in $foundations){
 $url='https://api.github.com/repos/spoonman136668-ai/Qualification-Forge/actions/runs/'+$proof.id
 $headers=@{Accept='application/vnd.github+json';'User-Agent'='KTRADE-W83-qualification'}
 if($env:GITHUB_TOKEN){$headers.Authorization='Bearer '+$env:GITHUB_TOKEN}
 $run=Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
 Require ($run.status -ceq 'completed' -and $run.conclusion -ceq 'success' -and $run.head_sha -ceq $proof.sha) ('W83_EXACT_FOUNDATION_NOT_SUCCESSFUL_'+$proof.id)
}
Write-Output 'W83_EXISTING_WINDOWS_QUALIFICATION_FOUNDATIONS=PASS'
$astTokens=$null;$astErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($WitnessScript,[ref]$astTokens,[ref]$astErrors)
Require ($astErrors.Count -eq 0) ('W83_NATIVE_WITNESS_POWERSHELL_SYNTAX_INVALID '+(($astErrors|ForEach-Object {$_.ToString()}) -join '; '))
$ps51=(Get-Command pwsh.exe -ErrorAction Stop).Source
Require ((& go env GOVERSION).Trim() -ceq 'go1.26.10') 'W83_PINNED_GO_REQUIRED'
Require (Test-Path -LiteralPath $ps51) 'W83_NATIVE_POWERSHELL_MISSING'
$packages=@{}
foreach($entry in $expected){
 Push-Location $entry.root
 try {
  & npm ci --ignore-scripts --no-audit --no-fund --silent
  Require ($LASTEXITCODE -eq 0) ('W83_'+$entry.name+'_NPM_STAGE_FAILED')
  & node scripts/stage_offline_vendor.cjs
  Require ($LASTEXITCODE -eq 0) ('W83_'+$entry.name+'_ORIGINAL_ASSET_STAGE_FAILED')
  $bundleRoot=Join-Path $env:RUNNER_TEMP ('ktrade-setup-package-'+[guid]::NewGuid().ToString('N'))
  & (Join-Path $entry.root 'windows/Build-KTRADE-FreshInstaller.ps1') -OutputRoot $bundleRoot -ExpectedSourceSha $entry.sha
  Require ($LASTEXITCODE -eq 0) ('W83_'+$entry.name+'_SOURCE_BUILD_FAILED')
  $zip=Join-Path $bundleRoot 'KTRADE-SetupBundle.zip'
  Require (Test-Path -LiteralPath $zip -PathType Leaf) ('W83_'+$entry.name+'_PACKAGE_NOT_CREATED')
  $distribution=Join-Path $env:RUNNER_TEMP ('W83-distribution-'+$entry.name+'-'+[guid]::NewGuid().ToString('N'))
  $null=New-Item -ItemType Directory -Path $distribution
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip,$distribution)
  $packages[$entry.name]=$distribution
  Write-Output ('W83_'+$entry.name+'_NATIVE_UNSIGNED_SETUP_BUILT=PASS')
 } finally { Pop-Location }
}
$gateRoot=Join-Path $env:RUNNER_TEMP ('W83-qualified-'+[guid]::NewGuid().ToString('N'))
& $ps51 -NoProfile -ExecutionPolicy Bypass -File $WitnessScript -PreviousBundle $packages['PREVIOUS'] -CandidateBundle $packages['CANDIDATE'] -QualificationRoot $gateRoot -NativeInputsPath $NativeInputsPath -PaperScenarioPath $PaperScenarioPath
Require ($LASTEXITCODE -eq 0) 'W83_NATIVE_CROSS_VERSION_ACCEPTANCE_FAILED'
Write-Output 'W83_FINAL_BOUNDARY_SUCCESS; no signing, release, LIVE, or owner-data access authorized'
