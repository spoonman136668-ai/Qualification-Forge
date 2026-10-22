package bundlediag

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1")
	raw, e := cmd.CombinedOutput()
	if e != nil {
		t.Fatalf("synthetic Git fixture setup failed: verb=%s: %s", args[0], strings.TrimSpace(string(raw)))
	}
	return strings.TrimSpace(string(raw))
}
func syntheticRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	git(t, dir, "init", "-b", "main")
	git(t, dir, "config", "user.email", "fixture@example.invalid")
	git(t, dir, "config", "user.name", "QForge Fixture")
	git(t, dir, "config", "commit.gpgsign", "false")
	return dir
}
func commit(t *testing.T, dir string) string {
	t.Helper()
	if e := os.WriteFile(filepath.Join(dir, "fixture.txt"), []byte("frozen fixture\n"), 0600); e != nil {
		t.Fatal(e)
	}
	git(t, dir, "add", "fixture.txt")
	git(t, dir, "commit", "-m", "fixture")
	return git(t, dir, "rev-parse", "HEAD")
}
func probe(t *testing.T, dir string, want Category, args ...string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	result, err := Probe(ctx, dir, args...)
	if result.Category != want {
		t.Fatalf("category=%s want=%s (exit=%d)", result.Category, want, result.ExitCode)
	}
	if want == OK {
		if err != nil || result.ExitCode != 0 {
			t.Fatalf("unexpected success error: %v", err)
		}
	}
	if want != OK {
		if err == nil || result.ExitCode == 0 {
			t.Fatal("failure misclassified as success")
		}
	}
	if strings.Contains(errText(err), dir) {
		t.Fatal("private path emitted in error")
	}
}
func errText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func Test01ValidBundle(t *testing.T) {
	dir := syntheticRepo(t)
	commit(t, dir)
	path := filepath.Join(t.TempDir(), "valid.bundle")
	probe(t, dir, OK, "bundle", "create", path, "refs/heads/main")
	probe(t, dir, OK, "bundle", "verify", path)
}
func Test02EmptyUnbornRef(t *testing.T) {
	dir := syntheticRepo(t)
	probe(t, dir, EmptyHistory, "bundle", "create", filepath.Join(t.TempDir(), "empty.bundle"), "--all")
}
func Test03MissingBranch(t *testing.T) {
	dir := syntheticRepo(t)
	commit(t, dir)
	probe(t, dir, InvalidReference, "bundle", "create", filepath.Join(t.TempDir(), "unknown.bundle"), "refs/heads/this-branch-does-not-exist")
}
func Test04UnresolvedRawSha(t *testing.T) {
	dir := syntheticRepo(t)
	commit(t, dir)
	probe(t, dir, InvalidReference, "bundle", "create", filepath.Join(t.TempDir(), "bad.bundle"), "deadbeef00000000000000000000000000000000")
}
func Test05MissingOutputParent(t *testing.T) {
	dir := syntheticRepo(t)
	commit(t, dir)
	probe(t, dir, MissingParent, "bundle", "create", filepath.Join(t.TempDir(), "absent-parent", "bad.bundle"), "--all")
}
func Test06NotRepository(t *testing.T) {
	dir := t.TempDir()
	probe(t, dir, NotRepository, "bundle", "create", filepath.Join(t.TempDir(), "bad.bundle"), "--all")
}
func Test07IncrementalRequiresPrerequisites(t *testing.T) {
	dir := syntheticRepo(t)
	base := commit(t, dir)
	if e := os.WriteFile(filepath.Join(dir, "new.txt"), []byte("new\n"), 0600); e != nil {
		t.Fatal(e)
	}
	git(t, dir, "add", "new.txt")
	git(t, dir, "commit", "-m", "new")
	path := filepath.Join(t.TempDir(), "incremental.bundle")
	probe(t, dir, OK, "bundle", "create", path, "refs/heads/main", "^"+base)
	empty := syntheticRepo(t)
	probe(t, empty, MissingPrerequisite, "bundle", "verify", path)
}
func Test08UnsupportedOperationDenied(t *testing.T) {
	dir := syntheticRepo(t)
	probe(t, dir, InvalidRequest, "status", "--short")
}
func Test09SensitivePathNeverInResultOrError(t *testing.T) {
	dir := syntheticRepo(t)
	commit(t, dir)
	secret := "confidential-qforge-never-emit"
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()
	r, e := Probe(ctx, dir, "bundle", "create", filepath.Join(dir, "missing", secret, "fixture.bundle"), "--all")
	if e == nil || r.Category != MissingParent {
		t.Fatalf("category=%s", r.Category)
	}
	if strings.Contains(e.Error(), secret) || strings.Contains(string(r.Category), secret) {
		t.Fatal("private path leaked")
	}
}
func Test10UnrecognizedStderrFailsClosed(t *testing.T) {
	if classify("fatal: deliberately unusual error") != Unknown {
		t.Fatal("unknown stderr was accepted")
	}
}
func Test11BoundedOutput(t *testing.T) {
	b := &boundedBuffer{limit: 5}
	n, e := b.Write([]byte("123456789"))
	if n != 9 || e != nil || b.body.String() != "12345" || !b.truncated {
		t.Fatal("output bounds bypassed")
	}
}
