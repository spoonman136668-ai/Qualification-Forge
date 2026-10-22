package bundlediag

import (
	"encoding/json"
	"strings"
	"testing"
)

func Test12LegacyGoExitIsUnderdetermined(t *testing.T) {
	r, err := FromLegacyGoError("git bundle failed: exit status 1")
	if err != nil || r.ObservedExitCode != 1 || r.Category != Unknown ||
		r.ObservedOperation != "UNKNOWN" ||
		r.Decision != "EVIDENCE_INCOMPLETE_NO_ROOT_CAUSE_CLAIM" ||
		r.RootCauseConfirmed || r.RawStderrExported || r.SourceBound {
		t.Fatalf("legacy error assigned unsupported cause: %+v %v", r, err)
	}
	if strings.Join(r.Missing, ",") != "native_bundle_subcommand,native_stderr,source_bound_invocation" {
		t.Fatal("original failure evidence gaps not preserved")
	}
}

func Test13LegacyUnsupportedAndInjectedEvidenceRejected(t *testing.T) {
	for _, candidate := range []string{
		"", "git bundle failed: exit status 0", "git bundle failed: exit status 9999",
		"git bundle failed: exit status 1\nfatal: secret-path",
		"git bundle failed: exit status 1; root cause=unknown",
		strings.Repeat("A", 513),
	} {
		_, e := FromLegacyGoError(candidate)
		if e == nil {
			t.Fatal("unsupported or injected log entry accepted")
		}
	}
}

func Test14NativeErrorEvidenceNeverPromotesToAcceptedRootCause(t *testing.T) {
	r := ClassifyNativeRecord(NativeRecord{
		Subcommand: "create", ExitCode: 128,
		NativeStderr: "fatal: bad revision 'refs/heads/not-there'",
		NativeStderrComplete: true, SourceIdentityBound: true,
	})
	if r.Category != InvalidReference ||
		r.EvidenceDecision != "CATEGORY_OBSERVED_REQUIRES_INDEPENDENT_QUALIFICATION" ||
		r.RootCauseConfirmed || r.RawStderrExported || len(r.Missing) != 0 {
		t.Fatalf("native input did not preserve verification boundary: %+v", r)
	}
}

func Test15UnverifiedProvenanceCannotBePromoted(t *testing.T) {
	r := ClassifyNativeRecord(NativeRecord{
		Subcommand: "verify", ExitCode: 1,
		NativeStderr: "error: Repository lacks these prerequisite commits",
		NativeStderrComplete: true, SourceIdentityBound: false,
	})
	if r.Category != MissingPrerequisite || r.EvidenceDecision != "INCOMPLETE_OR_UNVERIFIED" ||
		r.RootCauseConfirmed || len(r.Missing) != 1 ||
		r.Missing[0] != "independent_source_provenance" {
		t.Fatalf("unverified source was promoted or misclassified: %+v", r)
	}
}

func Test16NoRawPrivatePathInReceipt(t *testing.T) {
	sensitive := "SECRET_VALUE_PRIVATE_EVIDENCE_PATH_DO_NOT_EMIT"
	r := ClassifyNativeRecord(NativeRecord{
		Subcommand: "create", ExitCode: 128,
		NativeStderr: "fatal: bad revision '" + sensitive + "'",
		NativeStderrComplete: true, SourceIdentityBound: true,
	})
	b, e := json.Marshal(r)
	if e != nil {
		t.Fatal(e)
	}
	if strings.Contains(string(b), sensitive) || r.RawStderrExported {
		t.Fatal("private stderr was reflected in output")
	}
}

func Test17IncompleteStderrFailsClosed(t *testing.T) {
	r := ClassifyNativeRecord(NativeRecord{
		Subcommand: "create", ExitCode: 128,
		NativeStderr: "fatal: bad revision 'truncated'",
		NativeStderrComplete: false, SourceIdentityBound: true,
	})
	if r.Category != Unknown || r.EvidenceDecision != "INCOMPLETE_OR_UNVERIFIED" {
		t.Fatalf("truncated evidence classified as full proof: %+v", r)
	}
}

func Test18UnknownErrorAndUnsupportedOperationFailClosed(t *testing.T) {
	r := ClassifyNativeRecord(NativeRecord{
		Subcommand: "push", ExitCode: 42,
		NativeStderr: "fatal: unexpected new vendor error",
		NativeStderrComplete: true, SourceIdentityBound: true,
	})
	if r.EvidenceDecision != "INCOMPLETE_OR_UNVERIFIED" ||
		r.Category != Unknown || r.RootCauseConfirmed || len(r.Missing) < 2 {
		t.Fatalf("unknown evidence silently admitted: %+v", r)
	}
}
