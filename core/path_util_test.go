//go:build !cgo

package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"net"
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
	if !samePath(got, filepath.Clean(inside)) {
		t.Fatalf("got %q want %q", got, filepath.Clean(inside))
	}

	// Relative path that resolves under home.
	rel := filepath.Join(home, "config.yaml")
	got, err = resolveSafePath(rel)
	if err != nil {
		t.Fatalf("expected home-relative ok: %v", err)
	}
	if !samePath(got, filepath.Clean(rel)) {
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

	outsideDir := t.TempDir()
	symlink := filepath.Join(home, "outside-link")
	if err := os.Symlink(outsideDir, symlink); err == nil {
		if _, err := resolveSafePath(filepath.Join(symlink, "secret")); err == nil {
			t.Fatal("expected symlink escape outside home to fail")
		}
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
	frame := make([]byte, 4)
	binary.LittleEndian.PutUint32(frame, maxIPCFrameSize+1)
	if _, err := readFrame(bytes.NewReader(frame)); err == nil {
		t.Fatal("expected oversized frame to fail before allocation")
	}
}

func TestInitializeHomeDirCannotChange(t *testing.T) {
	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = ""
	homeLock.Unlock()
	t.Cleanup(func() {
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
		constant.SetHomeDir(oldHome)
	})

	home := t.TempDir()
	if err := initializeHomeDir(home); err != nil {
		t.Fatalf("initialize home: %v", err)
	}
	if err := initializeHomeDir(home); err != nil {
		t.Fatalf("reusing home must succeed: %v", err)
	}
	if err := initializeHomeDir(t.TempDir()); err == nil {
		t.Fatal("expected changing home to fail")
	}
}

func TestAuthenticateIPCMutualProof(t *testing.T) {
	const token = "0123456789abcdef0123456789abcdef"
	t.Setenv(ipcTokenEnvironment, token)
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	done := make(chan error, 1)
	go func() {
		if err := writeFrame(server, ipcProof(token, ipcServerLabel)); err != nil {
			done <- err
			return
		}
		proof, err := readFrame(server)
		if err == nil && !bytes.Equal(proof, ipcProof(token, ipcCoreLabel)) {
			err = errors.New("invalid core proof")
		}
		done <- err
	}()
	if err := authenticateIPC(client); err != nil {
		t.Fatalf("authenticate IPC: %v", err)
	}
	if err := <-done; err != nil {
		t.Fatalf("server handshake: %v", err)
	}
}

func TestHomeRootOperationsDoNotEscapeThroughSymlink(t *testing.T) {
	home := t.TempDir()
	outside := t.TempDir()
	constant.SetHomeDir(home)
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = ""
	homeLock.Unlock()
	t.Cleanup(func() {
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	outsideFile := filepath.Join(outside, "keep.txt")
	if err := os.WriteFile(outsideFile, []byte("secret"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(home, "outside")
	if err := os.Symlink(outside, link); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	if _, err := readFile(filepath.Join(link, "keep.txt")); err == nil {
		t.Fatal("expected rooted read through outside symlink to fail")
	}
	root, rel, err := openHomePath(link)
	if err != nil {
		t.Fatal(err)
	}
	if err := root.RemoveAll(rel); err != nil {
		root.Close()
		t.Fatal(err)
	}
	if err := root.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(outsideFile); err != nil {
		t.Fatalf("outside target was affected: %v", err)
	}
}
