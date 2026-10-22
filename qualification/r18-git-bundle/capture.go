package bundlediag

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// CaptureReceipt describes a *local source-free diagnostic*, not a private
// R18 qualification or an independently attested source/witness record.
type CaptureReceipt struct {
	Schema                   string
	Category                 Category
	ExitCode                 int
	Operation                string
	HeadMatchedLocally       bool
	RefSelectorSHA256        string
	NativeStderrTruncated    bool
	RawStderrExported        bool
	SourceIndependentlyProven bool
	ProductionAccepted       bool
}

var safeHexSHA = regexp.MustCompile("^(?:[a-f0-9]{40}|[a-f0-9]{64})$")
var safeGitRef = regexp.MustCompile("^(refs/(?:heads|tags)/[a-zA-Z0-9][a-zA-Z0-9._/-]{0,180}|--all)$")

func sandboxFailure(label string) (CaptureReceipt, error) {
	return CaptureReceipt{
		Schema: "qualification-forge.r18-sandbox-git-capture.v1",
		Category: InvalidRequest, ExitCode: -1,
		Operation: "create",
	}, errors.New("R18_SANDBOX_" + label)
}

// CaptureSandboxBundle captures the native bundle outcome without publishing
// paths, repository IDs, stderr, output contents, or secrets. Only a caller-
// supplied authorized working tree can be used; qualification itself is not
// conferred by this helper. The output path is fixed under a separate scratch
// directory; refs are a strict allowlist. HEAD must match the caller's pin.
func CaptureSandboxBundle(ctx context.Context, repoRoot, scratchRoot, expectedHead, ref string) (CaptureReceipt, error) {
	if !safeHexSHA.MatchString(expectedHead) || !safeGitRef.MatchString(ref) ||
		strings.Contains(ref, "..") || strings.Contains(ref, "//") || strings.HasSuffix(ref, "/") {
		return sandboxFailure("UNSAFE_SOURCE_PIN_OR_REFERENCE")
	}
	if !filepath.IsAbs(repoRoot) || !filepath.IsAbs(scratchRoot) {
		return sandboxFailure("ROOT_NOT_ABSOLUTE")
	}
	repoReal, err := filepath.EvalSymlinks(repoRoot)
	if err != nil {
		return sandboxFailure("REPOSITORY_ROOT_INVALID")
	}
	scratchReal, err := filepath.EvalSymlinks(scratchRoot)
	if err != nil {
		return sandboxFailure("SCRATCH_ROOT_INVALID")
	}
	repoInfo, err := os.Stat(repoReal)
	if err != nil || !repoInfo.IsDir() {
		return sandboxFailure("REPOSITORY_NOT_A_DIRECTORY")
	}
	scratchInfo, err := os.Lstat(scratchRoot)
	if err != nil || !scratchInfo.IsDir() || scratchInfo.Mode()&os.ModeSymlink != 0 {
		return sandboxFailure("SCRATCH_DIRECTORY_INVALID")
	}
	relRepo, err := filepath.Rel(repoReal, scratchReal)
	if err != nil {
		return sandboxFailure("UNRELATED_ROOTS")
	}
	relScratch, err := filepath.Rel(scratchReal, repoReal)
	if err != nil {
		return sandboxFailure("UNRELATED_ROOTS")
	}
	inTree := func(relative string) bool {
		return relative == "." || relative == "" || (relative != ".." &&
			!strings.HasPrefix(relative, ".."+string(filepath.Separator)) &&
			!filepath.IsAbs(relative))
	}
	if inTree(relRepo) || inTree(relScratch) {
		return sandboxFailure("SCRATCH_AND_SOURCE_NOT_SEPARATE")
	}
	head := exec.CommandContext(ctx, "git", "rev-parse", "--verify", "HEAD")
	head.Dir = repoReal
	head.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1")
	var out boundedBuffer
	out.limit = 128
	var stderr boundedBuffer
	stderr.limit = 512
	head.Stdout = &out
	head.Stderr = &stderr
	if err := head.Run(); err != nil || out.truncated || stderr.truncated ||
		strings.TrimSpace(out.body.String()) != expectedHead {
		return sandboxFailure("HEAD_IDENTITY_NOT_PROVEN")
	}
	bundle := filepath.Join(scratchReal, "r18-sandbox-capture.bundle")
	if _, err := os.Lstat(bundle); err == nil {
		return sandboxFailure("OUTPUT_DESTINATION_ALREADY_EXISTS")
	} else if !errors.Is(err, os.ErrNotExist) {
		return sandboxFailure("OUTPUT_DESTINATION_INVALID")
	}
	hash := sha256.Sum256([]byte("git\x00bundle\x00create\x00" + ref))
	result := CaptureReceipt{
		Schema: "qualification-forge.r18-sandbox-git-capture.v1",
		Category: Unknown, ExitCode: -1, Operation: "create",
		HeadMatchedLocally: true,
		RefSelectorSHA256: hex.EncodeToString(hash[:]),
		RawStderrExported: false,
		SourceIndependentlyProven: false,
		ProductionAccepted: false,
	}
	native, nativeErr := Probe(ctx, repoReal, "bundle", "create", bundle, ref)
	result.Category = native.Category
	result.ExitCode = native.ExitCode
	result.NativeStderrTruncated = native.StderrTruncated
	if native.StderrTruncated || native.StdoutTruncated {
		result.Category = Unknown
		return result, errors.New("R18_SANDBOX_NATIVE_OUTPUT_INCOMPLETE")
	}
	if nativeErr != nil {
		return result, errors.New("R18_SANDBOX_GIT_" + string(native.Category))
	}
	if info, e := os.Lstat(bundle); e != nil || !info.Mode().IsRegular() || info.Size() == 0 {
		result.Category = Unknown
		return result, errors.New("R18_SANDBOX_BUNDLE_OUTPUT_UNVERIFIED")
	}
	return result, nil
}
