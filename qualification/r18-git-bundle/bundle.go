// Package bundlediag classifies Git bundle failures without disclosing raw
// stderr, source paths, repository identity, or secrets. No CKB-plane coupling.
package bundlediag

import (
	"bytes"
	"context"
	"errors"
	"os"
	"os/exec"
	"strings"
)

type Category string

const (
	OK                  Category = "PASS"
	EmptyHistory        Category = "EMPTY_OR_UNBORN_HISTORY"
	InvalidReference    Category = "UNRESOLVED_REFERENCE"
	MissingParent       Category = "OUTPUT_PARENT_MISSING"
	MissingPrerequisite Category = "PREREQUISITE_COMMITS_MISSING"
	NotRepository       Category = "NOT_GIT_REPOSITORY"
	InvalidBundle       Category = "INVALID_BUNDLE"
	Unknown             Category = "UNCLASSIFIED_FAIL_CLOSED"
	InvalidRequest      Category = "UNSUPPORTED_GIT_OPERATION"
)

type Result struct {
	Category        Category
	ExitCode        int
	Operation       string
	StdoutTruncated bool
	StderrTruncated bool
}

type boundedBuffer struct {
	body      bytes.Buffer
	limit     int
	truncated bool
}

func (b *boundedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	remain := b.limit - b.body.Len()
	if remain > 0 {
		if remain > n {
			remain = n
		}
		if _, e := b.body.Write(p[:remain]); e != nil {
			return 0, e
		}
	}
	if remain < n {
		b.truncated = true
	}
	return n, nil
}

func classify(stderr string) Category {
	s := strings.ToLower(stderr)
	switch {
	case strings.Contains(s, "not a git repository"),
		strings.Contains(s, "need a repository to create a bundle"):
		return NotRepository
	case strings.Contains(s, "refusing to create empty bundle"):
		return EmptyHistory
	case strings.Contains(s, "ambiguous argument"), strings.Contains(s, "unknown revision"),
		strings.Contains(s, "not a valid ref"), strings.Contains(s, "bad revision"),
		strings.Contains(s, "bad object"):
		return InvalidReference
	case strings.Contains(s, "prerequisite commit"):
		return MissingPrerequisite
	case strings.Contains(s, "no such file or directory") &&
		(strings.Contains(s, "unable to create") || strings.Contains(s, "cannot create")):
		return MissingParent
	case strings.Contains(s, "not a git bundle"), strings.Contains(s, "unrecognized bundle"):
		return InvalidBundle
	default:
		return Unknown
	}
}

// Probe permits only Git bundle create/verify/list-heads. It never uses a shell,
// returns no raw output and does not grant source or production authorization.
// Callers must supply their own authorized working directory.
func Probe(ctx context.Context, dir string, args ...string) (Result, error) {
	operation := ""
	if len(args) >= 2 {
		operation = args[1]
	}
	result := Result{Category: InvalidRequest, ExitCode: -1, Operation: operation}
	if len(args) < 3 || args[0] != "bundle" ||
		(operation != "create" && operation != "verify" && operation != "list-heads") ||
		dir == "" {
		return result, errors.New("UNSUPPORTED_GIT_OPERATION")
	}
	stdout := &boundedBuffer{limit: 16384}
	stderr := &boundedBuffer{limit: 65536}
	cmd := exec.CommandContext(ctx, "git", args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_LFS_SKIP_SMUDGE=1", "GIT_CONFIG_NOSYSTEM=1")
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	err := cmd.Run()
	result.StdoutTruncated = stdout.truncated
	result.StderrTruncated = stderr.truncated
	if err == nil {
		result.Category = OK
		result.ExitCode = 0
		return result, nil
	}
	result.Category = classify(stderr.body.String())
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		result.ExitCode = exitErr.ExitCode()
	}
	// Do not report exec's raw error: it can contain filesystem paths.
	return result, errors.New("GIT_BUNDLE_" + string(result.Category))
}
