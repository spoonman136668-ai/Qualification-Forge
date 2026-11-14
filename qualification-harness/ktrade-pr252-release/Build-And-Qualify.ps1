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
 @{name='CANDIDATE';root=$CandidateCheckout;sha='98783a8b509d355c3d75ca9fe665517f13c9dc75';tree='32cba5d0679afcfe8348243ece0d870823ab55b2'}
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
 'tools/wails-pilot/backend/fresh_uninstall.go'
)
foreach($path in $unchanged){
 $a=(& git -C $PreviousCheckout rev-parse ('HEAD:'+$path)).Trim()
 $b=(& git -C $CandidateCheckout rev-parse ('HEAD:'+$path)).Trim()
 Require ($LASTEXITCODE -eq 0 -and $a -ceq $b -and $a -cmatch '^[a-f0-9]{40}$') ('W83_INSTALLER_FOUNDATION_IDENTITY_DRIFT_'+$path)
}
# W106 is an explicit, narrowly reviewed safety-UI delta, never called
# source-identical. The W29 exclusive root-claim implementation stays identical.
$setupPath='windows/Install-KTRADE-Fresh.ps1'
$priorSetup=(& git -C $PreviousCheckout rev-parse ('HEAD:'+$setupPath)).Trim()
$newSetup=(& git -C $CandidateCheckout rev-parse ('HEAD:'+$setupPath)).Trim()
$newTest=(& git -C $CandidateCheckout rev-parse 'HEAD:tests/w106_installer_preflight.test.cjs').Trim()
Require ($priorSetup -ceq 'e65062ac026403fb57ebdc8a1c15ff16ae6630e9' -and
 $newSetup -ceq '7612bd5fdf9e163bcb14ca0bced4477f2c7d75b6' -and
 $newTest -ceq 'bf53f640c14c8284a01e2df329305764090a35ba') 'W106_EXACT_GUI_DELTA_AND_NEGATIVE_TEST_REQUIRED'
$w29Old=(& git -C $PreviousCheckout rev-parse 'HEAD:tools/wails-pilot/backend/fresh_install.go').Trim()
$w29New=(& git -C $CandidateCheckout rev-parse 'HEAD:tools/wails-pilot/backend/fresh_install.go').Trim()
Require ($w29Old -ceq $w29New -and $w29Old -cmatch '^[a-f0-9]{40}$') 'W106_W29_EXCLUSIVE_ROOT_CLAIM_DRIFT'
Write-Output 'W106_EIGHT_UNCHANGED_INSTALLER_BLOBS_EXACT_GUI_DELTA_AND_W29_CLAIM=PASS'
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
Require ((& go env GOVERSION).Trim() -ceq 'go1.26.11') 'W83_PINNED_GO_REQUIRED'
Require (Test-Path -LiteralPath $ps51) 'W83_NATIVE_POWERSHELL_MISSING'
$packages=@{}
foreach($entry in $expected){
 Push-Location $entry.root
 try {
  # Build each immutable source with its independently pinned Go patch release.
  $savedToolchain=$env:GOTOOLCHAIN
  $required=if($entry.name -ceq 'PREVIOUS'){'go1.26.10'}else{'go1.26.11'}
  Require (([IO.File]::ReadAllText((Join-Path $entry.root 'windows/Go-Toolchain.version')).Trim()) -ceq $required) ('W83_'+$entry.name+'_REVIEWED_TOOLCHAIN_PIN_DRIFT')
  $env:GOTOOLCHAIN=$required
  Require ((& go env GOVERSION).Trim() -ceq $required) ('W83_'+$entry.name+'_COMPILER_PIN_DRIFT')
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
 } finally { $env:GOTOOLCHAIN=$savedToolchain; Pop-Location }
}
$gateRoot=Join-Path $env:RUNNER_TEMP ('W83-qualified-'+[guid]::NewGuid().ToString('N'))
& $ps51 -NoProfile -ExecutionPolicy Bypass -File $WitnessScript -PreviousBundle $packages['PREVIOUS'] -CandidateBundle $packages['CANDIDATE'] -QualificationRoot $gateRoot -NativeInputsPath $NativeInputsPath -PaperScenarioPath $PaperScenarioPath
Require ($LASTEXITCODE -eq 0) 'W83_NATIVE_CROSS_VERSION_ACCEPTANCE_FAILED'
Write-Output 'W83_FINAL_BOUNDARY_SUCCESS; no signing, release, LIVE, or owner-data access authorized'
