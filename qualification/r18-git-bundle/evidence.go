package bundlediag

import (
	"errors"
	"regexp"
	"strconv"
	"strings"
)

// LegacyFailure describes only what a previously captured Go test log attests.
// It never reports a root cause from an exit code alone.
type LegacyFailure struct {
	ObservedExitCode   int
	ObservedOperation  string
	Category           Category
	Decision           string
	Missing            []string
	SourceBound        bool
	RootCauseConfirmed bool
	RawStderrExported  bool
}

var legacyExitPattern = regexp.MustCompile(`^git bundle failed: exit status ([1-9][0-9]{0,2})$`)

func FromLegacyGoError(raw string) (LegacyFailure, error) {
	unknown := LegacyFailure{
		ObservedExitCode:   -1,
		ObservedOperation:  "UNKNOWN",
		Category:           Unknown,
		Decision:           "EVIDENCE_INCOMPLETE_NO_ROOT_CAUSE_CLAIM",
		Missing:            []string{"native_bundle_subcommand", "native_stderr", "source_bound_invocation"},
		SourceBound:        false,
		RootCauseConfirmed: false,
		RawStderrExported:  false,
	}
	if len(raw) == 0 || len(raw) > 512 {
		return unknown, errors.New("LEGACY_EVIDENCE_INVALID_BOUNDS")
	}
	matches := legacyExitPattern.FindStringSubmatch(strings.TrimSpace(raw))
	if matches == nil {
		return unknown, errors.New("LEGACY_EVIDENCE_NOT_A_SUPPORTED_BUNDLE_EXIT")
	}
	exit, e := strconv.Atoi(matches[1])
	if e != nil || exit <= 0 || exit > 255 {
		return unknown, errors.New("LEGACY_EVIDENCE_EXIT_OUT_OF_RANGE")
	}
	unknown.ObservedExitCode = exit
	return unknown, nil
}

// NativeRecord is strictly a test diagnostic input, not an admission credential.
// NativeStderr may contain paths, credentials or source identity, so the only
// exported value is its controlled category; raw bytes are never reflected.
type NativeRecord struct {
	Subcommand          string
	ExitCode            int
	NativeStderr        string
	NativeStderrComplete bool
	SourceIdentityBound bool
}

type ClassifiedRecord struct {
	Category           Category
	EvidenceDecision   string
	ObservedOperation  string
	ObservedExitCode   int
	RootCauseConfirmed bool
	RawStderrExported  bool
	Missing            []string
}

// ClassifyNativeRecord is intentionally incapable of promoting to a
// source-qualified root-cause verdict. External independent qualification is
// required even if a caller sets SourceIdentityBound=true.
func ClassifyNativeRecord(e NativeRecord) ClassifiedRecord {
	result := ClassifiedRecord{
		Category:           Unknown,
		EvidenceDecision:   "INCOMPLETE_OR_UNVERIFIED",
		ObservedOperation:  "UNKNOWN",
		ObservedExitCode:   e.ExitCode,
		RootCauseConfirmed: false,
		RawStderrExported:  false,
	}
	if e.Subcommand == "create" || e.Subcommand == "verify" || e.Subcommand == "list-heads" {
		result.ObservedOperation = e.Subcommand
	} else {
		result.Missing = append(result.Missing, "native_bundle_subcommand")
	}
	if e.ExitCode <= 0 || e.ExitCode > 255 {
		result.Missing = append(result.Missing, "native_failure_exit_code")
	}
	if e.NativeStderr == "" {
		result.Missing = append(result.Missing, "native_stderr")
	} else if !e.NativeStderrComplete {
		result.Missing = append(result.Missing, "complete_native_stderr")
	} else if len(e.NativeStderr) > 65536 {
		result.Missing = append(result.Missing, "bounded_native_stderr")
	} else {
		result.Category = classify(e.NativeStderr)
		if result.Category == Unknown {
			result.Missing = append(result.Missing, "recognized_native_failure_category")
		}
	}
	if !e.SourceIdentityBound {
		result.Missing = append(result.Missing, "independent_source_provenance")
	}
	if len(result.Missing) == 0 {
		// Classification is evidence for an investigation, not acceptance.
		result.EvidenceDecision = "CATEGORY_OBSERVED_REQUIRES_INDEPENDENT_QUALIFICATION"
	}
	return result
}
