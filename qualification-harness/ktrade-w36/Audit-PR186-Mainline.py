#!/usr/bin/env python3
"""Read-only W36 full-file Git/PR/receipt custody audit. No build, merge or release."""
import collections
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.request

BASE="a359e86d05e5ba24b71a1f4bdd8a5e36ebd31b58"
HEAD="0059d4b794552818b3f32798da7df27c75e21c5c"
TREE="9f1e559560ac14f4e6fc823dac9150e3a95f2c4d"
QF_RUNS=((40787692876,"858d21380e1e88c01555371c6e258dfab07f7446"),
         (40796601906,"85948ad3188f15a8ea9d4c83481418cade29d278"))

def require(condition,label):
    if not condition:
        raise RuntimeError("W36_BLOCKED_"+label)

def git(root,*args):
    p=subprocess.run(["git","-C",str(root),*args],text=True,stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE,check=False)
    require(p.returncode==0,"GIT_"+args[0]+"_"+p.stderr[-120:].strip())
    return p.stdout.strip()

def get_json(path,token):
    require(bool(token),"MISSING_READ_ONLY_TOKEN")
    req=urllib.request.Request("https://api.github.com/repos/"+path,
        headers={"Authorization":"Bearer "+token,"Accept":"application/vnd.github+json",
                 "User-Agent":"KTRADE-W36-source-audit"})
    with urllib.request.urlopen(req,timeout=25) as response:
        return json.load(response)

def main():
    require(os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted","EPHEMERAL_HOST_REQUIRED")
    require(len(sys.argv)==3,"EXPECTED_CANDIDATE_AND_MANIFEST")
    source=pathlib.Path(sys.argv[1]).resolve(strict=True)
    manifest_path=pathlib.Path(sys.argv[2]).resolve(strict=True)
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    require(manifest["schema"]=="ktrade.w36.mainline-scope.v1","MANIFEST_SCHEMA")
    require(manifest["main_sha"]==BASE and manifest["head_sha"]==HEAD and
            manifest["head_tree"]==TREE and manifest["source_pr"]==186,
            "MANIFEST_SOURCE_IDENTITY")
    actual_sha=git(source,"rev-parse","HEAD")
    actual_tree=git(source,"rev-parse","HEAD^{tree}")
    require(actual_sha==HEAD and actual_tree==TREE,"CANDIDATE_SOURCE_OR_TREE_MISMATCH")
    require(not git(source,"status","--porcelain","--untracked-files=no"),
            "CANDIDATE_TRACKED_WORKTREE_DIRTY")
    require(git(source,"rev-parse",BASE+"^{commit}")==BASE,
            "BASE_COMMIT_NOT_FETCHED")
    require(git(source,"merge-base",BASE,HEAD)==BASE,"MAIN_NOT_ANCESTOR")
    require(len(git(source,"rev-list","--count",BASE+".."+HEAD))>0,"EMPTY_REV_LIST")
    ahead=int(git(source,"rev-list","--count",BASE+".."+HEAD))
    require(ahead==434,"COMMIT_COUNT_DRIFT")
    require(int(git(source,"rev-list","--count",HEAD+".."+BASE))==0,"BEHIND_MAIN")
    rows=git(source,"diff","--name-status","--no-renames",BASE,HEAD).splitlines()
    actual={}
    for row in rows:
        bits=row.split("\t",1)
        require(len(bits)==2 and bits[0] in ("A","M"),"UNEXPECTED_FILE_STATUS")
        status={"A":"added","M":"modified"}[bits[0]]
        require(bits[1] not in actual,"DUPLICATE_DIFF_PATH")
        actual[bits[1]]={"status":status}
    numrows=git(source,"diff","--numstat","--no-renames",BASE,HEAD).splitlines()
    for row in numrows:
        parts=row.split("\t",2)
        require(len(parts)==3 and parts[2] in actual,"BAD_NUMSTAT_PATH")
        require(parts[0].isdigit() and parts[1].isdigit(),"BINARY_OR_BAD_NUMSTAT")
        actual[parts[2]]["additions"]=int(parts[0])
        actual[parts[2]]["deletions"]=int(parts[1])
    listed=manifest["files"]
    require(len(listed)==310 and len(actual)==310,"FILE_COUNT")
    expected={}
    for record in listed:
        path=record["path"]
        require(path not in expected,"DUPLICATE_MANIFEST_PATH")
        require(not re.search(r"(^|/)\.env($|[./])|(^|/)node_modules/|"
                 r"\.(exe|dll|p12|pfx|pem|key|zip)$",path,re.I),
                 "RESTRICTED_COMMITTED_ASSET")
        expected[path]={k:record[k] for k in ("status","additions","deletions")}
    require(expected==actual,"COMPLETE_310_PATH_OR_LINE_DELTA_DRIFT")
    count=collections.Counter(v["status"] for v in actual.values())
    require(count=={"added":272,"modified":38},"ADDED_MODIFIED_DELETED_DRIFT")
    require(sum(v["additions"] for v in actual.values())==29446 and
            sum(v["deletions"] for v in actual.values())==977,
            "SOURCE_CHANGE_VOLUME_DRIFT")
    for path in actual:
        mode=git(source,"ls-tree",HEAD,"--",path).split(" ",1)[0]
        require(mode in ("100644","100755"),"SYMLINK_SUBMODULE_OR_BAD_FILE_MODE")
    print("W36_ALL_310_GIT_PATHS_NUMSTAT_AND_MODES=PASS")
    print("W36_MAINLINE_BASE_434_COMMITS_ZERO_BEHIND=PASS")
    read_token=os.environ.get("KTRADE_SOURCE_READ_TOKEN","")
    runs_token=os.environ.get("GITHUB_TOKEN","")
    ref=get_json("spoonman136668-ai/ktrade/git/ref/heads/main",read_token)
    require(ref["object"]["sha"]==BASE,"MAIN_MOVED")
    pr=get_json("spoonman136668-ai/ktrade/pulls/186",read_token)
    require(pr["head"]["sha"]==HEAD and pr["base"]["sha"]==BASE and
            pr["draft"] is True and pr["merged"] is False and
            pr["changed_files"]==310 and pr["commits"]==434,
            "W36_PR_CHANGED_OR_PROMOTED")
    require(pr["mergeable"] is True and pr["mergeable_state"]=="clean",
            "W36_MAINLINE_CONFLICT_OR_UNKNOWN")
    print("W36_DRAFT_PR_HEAD_BASE_MERGE_CUSTODY=PASS")
    for run_id,witness_sha in QF_RUNS:
        run=get_json("spoonman136668-ai/Qualification-Forge/actions/runs/"+str(run_id),runs_token)
        require(run["status"]=="completed" and run["conclusion"]=="success" and
                run["head_sha"]==witness_sha,"W34_OR_W35B_RECEIPT_IDENTITY")
    print("W36_EXACT_W34_AND_W35B_WINDOWS_FOUNDATIONS=PASS")
    print("W36_SCOPE_ONLY_PASS_NO_RELEASE_NO_MERGE_NO_LIVE=TRUE")

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(1)
