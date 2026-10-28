# KTRADE RB3: read-only Git graph/source custody audit. NO merge or live operations.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$witness=Join-Path $env:GITHUB_WORKSPACE 'witness'
$repo=Join-Path $env:GITHUB_WORKSPACE 'candidate'
$manifestPath=Join-Path $witness 'integration-evidence/ktrade-rb3-main-to-p10-tail-20261028.json'
if(!(Test-Path -LiteralPath $manifestPath)){throw 'RB3_MANIFEST_MISSING'}
$m=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 30
if($m.schema -cne 'ktrade.rb3.integration-ancestry-readonly.v1' -or $m.repository -cne 'spoonman136668-ai/ktrade' -or
   $m.main.sha -cne 'a359e86d05e5ba24b71a1f4bdd8a5e36ebd31b58' -or
   $m.candidate.sha -cne '8881e7603facbcd761c66addf286b6a1f138e1d6' -or
   $m.verified_contiguous_open_draft_stack.count -ne 70 -or
   @($m.verified_contiguous_open_draft_stack.prs).Count -ne 70){throw 'RB3_PINNED_MANIFEST_IDENTITY_DRIFT'}
$head=(& git -C $repo rev-parse HEAD).Trim()
$tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
if($LASTEXITCODE -ne 0 -or $head -cne $m.candidate.sha -or $tree -cne $m.candidate.tree){throw 'RB3_TIP_SOURCE_OR_TREE_DRIFT'}
$main=(& git -C $repo rev-parse origin/main).Trim()
$mainTree=(& git -C $repo rev-parse 'origin/main^{tree}').Trim()
if($LASTEXITCODE -ne 0 -or $main -cne $m.main.sha -or $mainTree -cne $m.main.tree){throw 'RB3_MAIN_SOURCE_OR_TREE_DRIFT'}
$base=(& git -C $repo merge-base origin/main HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $base -cne $main){throw 'RB3_MAIN_NOT_EXACT_ANCESTOR'}
$ahead=[int]((& git -C $repo rev-list --count 'origin/main..HEAD').Trim())
$behind=[int]((& git -C $repo rev-list --count 'HEAD..origin/main').Trim())
if($LASTEXITCODE -ne 0 -or $ahead -ne 431 -or $behind -ne 0){throw "RB3_COMMIT_GAP_CHANGED: ahead=$ahead behind=$behind"}
$dirty=@(& git -C $repo status --porcelain)
if($dirty.Count -ne 0){throw 'RB3_SOURCE_CHECKOUT_DIRTY'}

$prs=@($m.verified_contiguous_open_draft_stack.prs)
$last=$null;$minCommitCount=0
foreach($p in $prs){
 if($p.stage -cne 'DRAFT_OPEN' -or [int]$p.pr -lt 111 -or [int]$p.pr -gt 183 -or
   $p.head -cnotmatch '^[a-f0-9]{40}$' -or $p.base -cnotmatch '^[a-f0-9]{40}$'){throw 'RB3_DRAFT_PR_MANIFEST_INVALID'}
 if($null -ne $last -and $last.head -cne $p.base){throw "RB3_DRAFT_CHAIN_DISCONTINUITY: $($p.pr)"}
 $baseType=(& git -C $repo cat-file -t $p.base).Trim()
 $headType=(& git -C $repo cat-file -t $p.head).Trim()
 if($LASTEXITCODE -ne 0 -or $baseType -cne 'commit' -or $headType -cne 'commit'){throw "RB3_DRAFT_HEAD_OBJECT_MISSING: $($p.pr)"}
 & git -C $repo merge-base --is-ancestor $p.base $p.head
 if($LASTEXITCODE -ne 0){throw "RB3_DRAFT_PR_ANCESTRY_FALSE: $($p.pr)"}
 & git -C $repo merge-base --is-ancestor $p.head $head
 if($LASTEXITCODE -ne 0){throw "RB3_DRAFT_PR_HEAD_NOT_IN_TIP: $($p.pr)"}
 $span=[int]((& git -C $repo rev-list --count "$($p.base)..$($p.head)").Trim())
 if($span -lt 1){throw "RB3_EMPTY_DRAFT_PR: $($p.pr)"}
 $minCommitCount+=$span
 $last=$p
}
if($prs[0].base -cne $m.verified_contiguous_open_draft_stack.base -or
   $last.head -cne $head){throw 'RB3_DRAFT_TAIL_NOT_ATTACHED_TO_TIP'}

$changed=@(& git -C $repo diff --name-only origin/main HEAD)
if($LASTEXITCODE -ne 0 -or $changed.Count -lt 300){throw 'RB3_CUMULATIVE_DIFF_INCOMPLETE'}
$scopes=@{}
foreach($scope in @('cmd/','internal/','pkg/','tools/','windows/','static/','templates/','tests/','docs/','.github/')){
 $scopes[$scope]=@($changed | Where-Object {$_.StartsWith($scope,[StringComparison]::Ordinal)}).Count
}
foreach($path in @('AGENTS.md','docs/rebuild/RB1_SINGLE_TRACK_CONTRACT.md','docs/rebuild/RB2_PRODUCT_COMPLETION_AND_COMPETITIVE_ACCEPTANCE.md','docs/rebuild/RB3_WAILS_CODEX_WEB_OWNER_DECISION_20261024.md')){
 if(!(Test-Path -LiteralPath (Join-Path $repo $path))){throw "RB3_OWNER_CONTRACT_MISSING: $path"}
}
$rb3=Get-Content -LiteralPath (Join-Path $repo 'docs/rebuild/RB3_WAILS_CODEX_WEB_OWNER_DECISION_20261024.md') -Raw
if(!$rb3.Contains('Wails v2 + WebView2') -or !$rb3.Contains('LIVE_READY_DISARMED') -or !$rb3.Contains('No broker orders')){
 throw 'RB3_OWNER_PRODUCT_AND_FINANCIAL_CONTRACT_UNRECOGNIZED'
}

# Authenticate current main branch protection. The credential used for the
# private source checkout is used read-only here, never displayed.
$token=$env:KTRADE_READ_TOKEN
if([string]::IsNullOrWhiteSpace($token)){throw 'RB3_REPO_READ_CREDENTIAL_MISSING'}
$headers=@{Accept='application/vnd.github+json';Authorization=('Bearer '+$token)}
$branch=Invoke-RestMethod -Uri 'https://api.github.com/repos/spoonman136668-ai/ktrade/branches/main' -Headers $headers -TimeoutSec 20
if($branch.commit.sha -cne $main){throw 'RB3_CURRENT_MAIN_DRIFT_DURING_GUARD_READ'}
$mainProtected=($branch.protected -eq $true)
$decision='HOLD_FULL_PRODUCT_RELEASE_AND_INDEPENDENT_INTEGRATION_NOT_QUALIFIED'
if(!$mainProtected){$decision='HOLD_MAIN_UNPROTECTED_AND_FULL_PRODUCT_RELEASE_NOT_QUALIFIED'}
$signal=@{
 schema='ktrade.rb3.integration-boundary-observation.v1'
 observed_main_sha=$main
 observed_main_tree=$mainTree
 observed_main_protected=$mainProtected
 candidate_sha=$head
 candidate_tree=$tree
 behind=$behind
 ahead=$ahead
 exact_changed_paths=$changed.Count
 verified_contiguous_draft_tail=@{from=111;to=183;count=$prs.Count;sha=$last.head;commit_span=$minCommitCount}
 changed_scopes=$scopes
 outcome=$decision
 financial_execution_activated=$false
 merged_or_released=$false
}
Write-Output ('RB3_INTEGRATION_BOUNDARY='+($signal|ConvertTo-Json -Compress -Depth 8))
Write-Output '::notice::RB3_MAIN_CANDIDATE_431_COMMIT_GRAPH_AND_70_DRAFT_TAIL_VERIFIED=PASS'
Write-Output ('::warning::RB3_INTEGRATION_READINESS='+$decision)
@(
 '## KTRADE RB3 independent cumulative-source integration audit'
 ''
 ('- **Result: '+$decision+'**')
 ('- main SHA: '+$main+' (protected='+$mainProtected+')')
 ('- candidate SHA: '+$head)
 ('- source ancestry ahead='+$ahead+', behind='+$behind)
 ('- exact cumulative changed paths='+$changed.Count+' (no 300-path API truncation)')
 ('- verified contiguous DRAFT PRs #111–#183: '+$prs.Count)
 ('- LIVE broker/orders: no operations performed')
 '- This is **not** release approval, PR merge, signing or installed-data migration.'
) | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
