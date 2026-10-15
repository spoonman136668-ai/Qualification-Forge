#!/usr/bin/env python3
"""DIC-19: historical source-only parity inventory. Never executes application code."""
import argparse
import hashlib
import re
import subprocess
from pathlib import Path

OLD = "813f4b21de27606bbe6e52a94eec150b72408b80"
NEW = "7b5f641f7c37dcc643d79a24f9fefa49cd2469be"
HISTORICAL_ROOT_TREE = "ab5f06e4e4772dd3095010abf4e97f30544a5c8e"
CURRENT_ROOT_TREE = "a10018f29ecba0196eeb41d83edbe997f7f2e387"
EXPECTED_MISSING_PRODUCTION = {
    "pkg/tradeguard_continuity.go",
    "pkg/tradeguard_continuity_runtime.go",
    "pkg/transient_broker_authority_recovery_v1118_stage_a.go",
    "pkg/ktrade_donor_ui_migration_contract_v11110_stage_bi.go",
}
CRITICAL_METHODS = {
    "TradeGuardContinuity": (
        "SaveRiskContinuity",
        "RestoreRiskContinuity",
        "RequireRiskContinuityForLive",
    ),
    "TransientBrokerRecovery": (
        "IsTransientBrokerAuthorityFailure",
        "RecoverTransientBrokerAuthority",
    ),
}

def require(condition, code):
    if not condition:
        raise RuntimeError("DIC19_" + code)

def git(root, *args):
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, check=True)
    return result.stdout.decode("utf-8").strip()

def paths(root):
    raw = subprocess.run(["git", "ls-tree", "-r", "-z", "--name-only", "HEAD"],
                         cwd=root, capture_output=True, check=True).stdout
    return {x.decode("utf-8") for x in raw.split(b"\x00") if x}

def source_methods(root):
    found = set()
    for p in (root / "pkg").rglob("*.go"):
        if p.name.endswith("_test.go"):
            continue
        text = p.read_text(encoding="utf-8")
        for names in CRITICAL_METHODS.values():
            for name in names:
                if re.search(r"(?m)^func\s+(?:\([^\n]*?\)\s*)?" + re.escape(name) + r"\s*\(", text):
                    found.add(name)
    return found

def verify(old, new):
    for root, head, tree in ((old, OLD, HISTORICAL_ROOT_TREE), (new, NEW, CURRENT_ROOT_TREE)):
        require(git(root, "rev-parse", "HEAD") == head, "COMMIT_IDENTITY_DRIFT")
        require(git(root, "rev-parse", "HEAD^{tree}") == tree, "TREE_IDENTITY_DRIFT")
        require(not git(root, "status", "--porcelain", "--untracked-files=no"), "SOURCE_DIRTY")
    print("DIC19_TWO_IMMUTABLE_SOURCE_TREES=PASS", flush=True)

    historical, current = paths(old), paths(new)
    old_go = {p for p in historical if p.startswith("pkg/") and p.endswith(".go")}
    new_go = {p for p in current if p.startswith("pkg/") and p.endswith(".go")}
    missing_production = {p for p in old_go - new_go if not p.endswith("_test.go")}
    missing_tests = {p for p in old_go - new_go if p.endswith("_test.go")}
    require(missing_production == EXPECTED_MISSING_PRODUCTION, "PRODUCTION_GAP_INVENTORY_DRIFT")
    require(len(missing_tests) == 140, "HISTORICAL_TEST_COVERAGE_DRIFT")
    print("DIC19_HISTORICAL_PRODUCTION_PATH_GAPS_FOUR=PASS", flush=True)
    print("DIC19_HISTORICAL_TEST_PATH_GAPS_140=PASS", flush=True)

    old_methods = source_methods(old)
    new_methods = source_methods(new)
    for tag, names in CRITICAL_METHODS.items():
        require(set(names).issubset(old_methods), tag.upper() + "_OLD_SOURCE_CONTRACT_MISSING")
        require(not set(names).intersection(new_methods), tag.upper() + "_CURRENT_SOURCE_CLASSIFICATION_DRIFT")
        print("DIC19_" + tag.upper() + "_PUBLIC_API_ABSENCE_CONFIRMED=PASS", flush=True)

    # Non-matching trees alone do NOT prove runtime function non-equivalence.
    # No code is restored and no production/release promotion is authorized.
    print("DIC19_FUNCTIONAL_EQUIVALENCE=UNQUALIFIED", flush=True)
    print("DIC19_HISTORICAL_SIGNED_1_5_7=BLOCKED", flush=True)
    print("DIC19_RELEASE_PROMOTION=PROHIBITED", flush=True)
    print("DIC19_READONLY_SOURCE_PARITY_INVENTORY=PASS", flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--historical", required=True, type=Path)
    parser.add_argument("--current", required=True, type=Path)
    args = parser.parse_args()
    verify(args.historical.resolve(), args.current.resolve())
