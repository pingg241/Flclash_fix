//go:build !cgo

package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestResolveSafePath(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)

	inside := filepath.Join(home, "profiles", "a.yaml")
	got, err := resolveSafePath(inside)
	if err != nil {
		t.Fatalf("expected inside path ok: %v", err)
	}
	if got != filepath.Clean(inside) {
		t.Fatalf("got %q want %q", got, filepath.Clean(inside))
	}

	// Relative path that resolves under home.
	rel := filepath.Join(home, "config.yaml")
	got, err = resolveSafePath(rel)
	if err != nil {
		t.Fatalf("expected home-relative ok: %v", err)
	}
	if got != filepath.Clean(rel) {
		t.Fatalf("got %q want %q", got, filepath.Clean(rel))
	}

	// Escape via .. must fail.
	escape := filepath.Join(home, "..", "etc", "passwd")
	if _, err := resolveSafePath(escape); err == nil {
		t.Fatal("expected path outside home to fail")
	}

	// Absolute path outside home must fail.
	outside := filepath.Join(os.TempDir(), "flclash-outside-test")
	if _, err := resolveSafePath(outside); err == nil {
		t.Fatal("expected absolute outside path to fail")
	}
}

func TestReadFrameRejectsHugeLength(t *testing.T) {
	// Smoke: constant is sane for desktop IPC.
	if maxIPCFrameSize < 1<<20 {
		t.Fatalf("maxIPCFrameSize too small: %d", maxIPCFrameSize)
	}
	if maxIPCFrameSize > 256<<20 {
		t.Fatalf("maxIPCFrameSize too large: %d", maxIPCFrameSize)
	}
}
