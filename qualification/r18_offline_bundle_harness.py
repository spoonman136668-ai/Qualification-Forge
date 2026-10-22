#!/usr/bin/env python3
"""R18 offline qualification-worker diagnostic. No private source, controller, network or secrets.

This tests the Windows Git-bundle primitive separately from the unavailable private
CKB-plane roadmap test. Passing it is NOT full R18 source qualification.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCHEMA = "qualification-forge.r18-offline-git-bundle-harness.v1"


class GitFixture(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="QForge-R18-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.env = dict(os.environ)
        self.env["GIT_CONFIG_NOSYSTEM"] = "1"
        self.env["GIT_CONFIG_GLOBAL"] = os.devnull
        self.env["GIT_TERMINAL_PROMPT"] = "0"
        self.env["GIT_ALLOW_PROTOCOL"] = "file"
        self.env["GIT_LFS_SKIP_SMUDGE"] = "1"
        self.assertIsNotNone(shutil.which("git"), "Git executable missing")

    def git(self, cwd, *args, ok=True):
        result = subprocess.run(
            ["git", *args], cwd=str(cwd), env=self.env,
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=25,
        )
        if ok and result.returncode != 0:
            self.fail(
                "Git failed for %r with exit %d; stdout=%r; stderr=%r"
                % (args, result.returncode, result.stdout[-800:], result.stderr[-800:])
            )
        if not ok:
            self.assertNotEqual(result.returncode, 0, "unexpected Git negative-control success: %r" % (args,))
        return result

    def repository(self, name="source"):
        directory = self.root / name
        directory.mkdir(parents=True)
        self.git(directory, "init", "-b", "main")
        self.git(directory, "config", "user.name", "Offline QForge Fixture")
        self.git(directory, "config", "user.email", "fixture@invalid.example")
        self.git(directory, "config", "commit.gpgsign", "false")
        return directory

    def commit(self, repository, name="first", data=b"frozen fixture bytes\n"):
        (repository / (name + ".txt")).write_bytes(data)
        self.git(repository, "add", "--all")
        self.git(repository, "commit", "-m", "fixture " + name)
        sha = self.git(repository, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(len(sha), 40)
        return sha

    def test_bundle_01_unborn_history_is_not_accepted(self):
        repository = self.repository()
        bundle = self.root / "unborn.bundle"
        self.git(repository, "bundle", "create", str(bundle), "--all", ok=False)

    def test_bundle_02_missing_ref_is_not_accepted(self):
        repository = self.repository()
        self.commit(repository)
        bundle = self.root / "nonexistent.bundle"
        self.git(repository, "bundle", "create", str(bundle),
                 "refs/heads/never-existed", ok=False)

    def test_bundle_03_pinned_head_round_trip(self):
        repository = self.repository()
        frozen = self.commit(repository, "first")
        bundle = self.root / "pinned.bundle"
        self.git(repository, "bundle", "create", str(bundle), "refs/heads/main")
        self.git(repository, "bundle", "verify", str(bundle))
        clone = self.root / "clone"
        self.git(self.root, "clone", "--quiet", "--branch", "main", str(bundle), str(clone))
        observed = self.git(clone, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(observed, frozen, "bundle clone failed to preserve frozen parent")
        self.assertEqual((clone / "first.txt").read_bytes(), b"frozen fixture bytes\n")
        self.git(clone, "fsck", "--no-reflogs", "--full")

    def test_bundle_04_long_original_style_fixture_path(self):
        # Original failed test had a long Go generated test-directory name.
        # This is a synthetic path-shape control, not its private test body.
        label = "TestRoadmapCurrentFrontierPostBTVMaterializesBTV03"
        repository = self.repository(label + "12345678")
        first = self.commit(repository, "one")
        self.commit(repository, "two")
        bundle = self.root / "long-fixture.bundle"
        self.git(repository, "bundle", "create", str(bundle), "--all")
        self.git(repository, "bundle", "verify", str(bundle))
        clone = self.root / "long-clone"
        self.git(self.root, "clone", "--quiet", "--branch", "main", str(bundle), str(clone))
        self.assertNotEqual(self.git(clone, "rev-parse", "HEAD").stdout.strip(), first)
        self.git(clone, "fsck", "--no-reflogs", "--full")

    def test_bundle_05_git_worktree_bundle(self):
        repository = self.repository()
        sha = self.commit(repository)
        secondary = self.root / "fixture-worktree"
        self.git(repository, "worktree", "add", "--detach", str(secondary), sha)
        bundle = self.root / "worktree.bundle"
        self.git(secondary, "bundle", "create", str(bundle), "--all")
        self.git(secondary, "bundle", "verify", str(bundle))
        clone = self.root / "worktree-clone"
        self.git(self.root, "clone", "--quiet", "--branch", "main", str(bundle), str(clone))
        self.assertEqual(self.git(clone, "rev-parse", "HEAD").stdout.strip(), sha)

    def test_bundle_06_changed_contract_receipt_is_not_a_pass(self):
        # A portable negative-control of the qualification invariant, not
        # a replacement for the actual private Engine.contract implementation.
        config_a = b'{"paused":true,"authority":"plane"}'
        config_b = b'{"paused":false,"authority":"plane"}'
        tool_a = hashlib.sha256(b"tool-A").digest()
        tool_b = hashlib.sha256(b"tool-B").digest()
        current = lambda c, t: hashlib.sha256(c + b"\x00" + t).hexdigest()
        sealed = current(config_a, tool_a)
        receipt = {"passed": True, "config_and_tool_digest": sealed}
        allowed = lambda c, t: receipt["passed"] and receipt["config_and_tool_digest"] == current(c, t)
        self.assertTrue(allowed(config_a, tool_a))
        self.assertFalse(allowed(config_b, tool_a))
        self.assertFalse(allowed(config_a, tool_b))
        receipt["passed"] = False
        self.assertFalse(allowed(config_a, tool_a))


if __name__ == "__main__":
    if os.environ.get("RUNNER_OS") not in {"Windows", "Linux"}:
        raise SystemExit("R18_QFORGE_REQUIRES_NATIVE_QUALIFIER_RUNNER")
    if os.environ.get("GITHUB_REPOSITORY") != "spoonman136668-ai/Qualification-Forge":
        raise SystemExit("R18_QFORGE_REPOSITORY_BOUNDARY_INVALID")
    result = unittest.TextTestRunner(verbosity=2).run(
        unittest.defaultTestLoader.loadTestsFromTestCase(GitFixture)
    )
    receipt = {
        "schema": SCHEMA,
        "result": "PASS" if result.wasSuccessful() and result.testsRun == 6 else "FAIL",
        "cases": result.testsRun,
        "runner_os": os.environ["RUNNER_OS"],
        "private_ckb_plane_source_used": False,
        "live_controller_connected": False,
        "scientific_dispatch": False,
        "private_source_acceptance": False,
    }
    print("R18_QFORGE_OFFLINE_RECEIPT=" + json.dumps(receipt, sort_keys=True, separators=(",", ":")))
    sys.exit(0 if receipt["result"] == "PASS" else 1)
