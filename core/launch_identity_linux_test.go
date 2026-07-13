//go:build linux && !cgo

package main

import (
	"os"
	"testing"
)

func TestReadLinuxProcessIdentityReadsCurrentProcess(t *testing.T) {
	startTime, pgid, err := readLinuxProcessIdentity(os.Getpid())
	if err != nil {
		t.Fatal(err)
	}
	if startTime == "" {
		t.Fatal("start time is empty")
	}
	if pgid <= 0 {
		t.Fatalf("invalid process group %d", pgid)
	}
}

func TestVerifyLinuxProcessRejectsNonceMismatch(t *testing.T) {
	metadata, err := currentLaunchMetadata("not-the-process-nonce-but-long-enough-123456")
	if err != nil {
		t.Fatal(err)
	}
	if err := verifyLinuxProcess(metadata); err == nil {
		t.Fatal("expected nonce mismatch")
	}
}
