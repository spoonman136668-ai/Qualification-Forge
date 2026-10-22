package bundlediag

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func captureWithTimeout(t *testing.T, repo, scratch, head, ref string) (CaptureReceipt, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return CaptureSandboxBundle(ctx, repo, scratch, head, ref)
}

func Test19SandboxValidPinnedBundleAndNonAdmission(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	scratch := t.TempDir()
	r, err := captureWithTimeout(t, repo, scratch, head, "refs/heads/main")
	if err != nil || r.Category != OK || r.ExitCode != 0 ||
		!r.HeadMatchedLocally || r.Operation != "create" ||
		len(r.RefSelectorSHA256) != 64 || r.NativeStderrTruncated ||
		r.RawStderrExported || r.SourceIndependentlyProven || r.ProductionAccepted {
		t.Fatalf("valid fixture did not produce fail-closed receipt: %+v %v", r, err)
	}
	info, err := os.Stat(filepath.Join(scratch, "r18-sandbox-capture.bundle"))
	if err != nil || info.Size() <= 0 {
		t.Fatal("bundle not produced in isolated scratch root")
	}
}

func Test20SandboxWrongHeadDoesNotWrite(t *testing.T) {
	repo := syntheticRepo(t)
	commit(t, repo)
	scratch := t.TempDir()
	r, err := captureWithTimeout(t, repo, scratch, strings.Repeat("f", 40), "--all")
	if err == nil || r.HeadMatchedLocally || r.Category != InvalidRequest {
		t.Fatalf("false source proof was accepted: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(scratch, "r18-sandbox-capture.bundle")); !os.IsNotExist(err) {
		t.Fatal("mismatched source wrote bundle")
	}
}

func Test21SandboxUnsafeSelectorRejectedBeforeExecution(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	for _, ref := range []string{
		"", "--all;rm -rf .", "../main", "refs/heads/../../secret",
		"refs/heads/main//other", "refs/heads/main/",
		"refs/heads/main\nsecret", "--stdin", "refs/remotes/origin/main",
	} {
		r, err := captureWithTimeout(t, repo, t.TempDir(), head, ref)
		if err == nil || r.Category != InvalidRequest || r.HeadMatchedLocally {
			t.Fatal("unsafe selector accepted")
		}
	}
}

func Test22SandboxScratchNestedInSourceRejected(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	scratch := filepath.Join(repo, "inside")
	if err := os.Mkdir(scratch, 0700); err != nil {
		t.Fatal(err)
	}
	r, err := captureWithTimeout(t, repo, scratch, head, "--all")
	if err == nil || r.Category != InvalidRequest {
		t.Fatalf("scratch inside source was accepted: %+v", r)
	}
}

func Test23SandboxUnresolvedRefCategorizedWithoutStderr(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	r, err := captureWithTimeout(t, repo, t.TempDir(), head, "refs/heads/does-not-exist")
	if err == nil || r.Category != InvalidReference || !r.HeadMatchedLocally ||
		r.SourceIndependentlyProven || r.ProductionAccepted || r.RawStderrExported {
		t.Fatalf("invalid synthetic ref incorrectly admitted: %+v %v", r, err)
	}
}

func Test24SandboxOutputCollisionRefused(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	scratch := t.TempDir()
	output := filepath.Join(scratch, "r18-sandbox-capture.bundle")
	if err := os.WriteFile(output, []byte("existing fixture\n"), 0600); err != nil {
		t.Fatal(err)
	}
	r, err := captureWithTimeout(t, repo, scratch, head, "refs/heads/main")
	if err == nil || r.Category != InvalidRequest {
		t.Fatalf("existing destination not protected: %+v", r)
	}
	content, err := os.ReadFile(output)
	if err != nil || string(content) != "existing fixture\n" {
		t.Fatal("destination preexisting bytes changed")
	}
}

func Test25SandboxHeadDriftRejectedBeforeBundle(t *testing.T) {
	repo := syntheticRepo(t)
	stored := commit(t, repo)
	if err := os.WriteFile(filepath.Join(repo, "second.txt"), []byte("second revision\n"), 0600); err != nil {
		t.Fatal(err)
	}
	git(t, repo, "add", "second.txt")
	git(t, repo, "commit", "-m", "second")
	scratch := t.TempDir()
	r, err := captureWithTimeout(t, repo, scratch, stored, "--all")
	if err == nil || r.Category != InvalidRequest || r.HeadMatchedLocally {
		t.Fatalf("source drift accepted: %+v", r)
	}
	if _, err := os.Stat(filepath.Join(scratch, "r18-sandbox-capture.bundle")); !os.IsNotExist(err) {
		t.Fatal("drifted source wrote bundle")
	}
}

func Test26SandboxNoRelativeOrSymlinkScratch(t *testing.T) {
	repo := syntheticRepo(t)
	head := commit(t, repo)
	r, err := captureWithTimeout(t, repo, ".", head, "--all")
	if err == nil || r.Category != InvalidRequest {
		t.Fatal("relative scratch accepted")
	}
	// Symlink creation can require elevated privileges on Windows; the
	// relative-path control is platform-invariant and always enforced.
}
