package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

func TestDelayTimeoutIsBounded(t *testing.T) {
	if got, ok := delayTimeout(0); !ok || got != defaultDelayTimeout {
		t.Fatalf("default timeout = %v/%v", got, ok)
	}
	if got, ok := delayTimeout(maximumDelayTimeout.Milliseconds()); !ok || got != maximumDelayTimeout {
		t.Fatalf("maximum timeout = %v/%v", got, ok)
	}
	if _, ok := delayTimeout(maximumDelayTimeout.Milliseconds() + 1); ok {
		t.Fatal("timeout above maximum was accepted")
	}
	if _, ok := delayTimeout(-1); !ok {
		t.Fatal("non-positive timeout should use the default")
	}
}

func TestAcquireDelaySlotStopsWaitingAtContextDeadline(t *testing.T) {
	previousSlots := delaySlots
	delaySlots = make(chan struct{}, 1)
	delaySlots <- struct{}{}
	defer func() { delaySlots = previousSlots }()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	started := time.Now()
	if acquireDelaySlot(ctx) {
		t.Fatal("acquired an already full delay slot")
	}
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("slot acquisition remained blocked for %v", elapsed)
	}
}

func TestHandleValidateConfigRejectsBlankContent(t *testing.T) {
	home := prepareValidationTestHome(t)
	tests := map[string][]byte{
		"empty":          {},
		"whitespace":     []byte(" \t\r\n"),
		"BOM whitespace": {0xEF, 0xBB, 0xBF, 0x20, 0x09, 0x0D, 0x0A},
	}
	for name, content := range tests {
		t.Run(name, func(t *testing.T) {
			configPath := filepath.Join(home, name+".yaml")
			if err := os.WriteFile(configPath, content, 0o600); err != nil {
				t.Fatal(err)
			}
			if got := handleValidateConfig(configPath); got != "config is empty" {
				t.Fatalf("validation result = %q, want %q", got, "config is empty")
			}
		})
	}
}

func TestHandleValidateConfigKeepsEmptyMappingsCompatible(t *testing.T) {
	home := prepareValidationTestHome(t)
	for name, content := range map[string]string{
		"null": "null",
		"map":  "{}",
	} {
		t.Run(name, func(t *testing.T) {
			configPath := filepath.Join(home, name+".yaml")
			if err := os.WriteFile(configPath, []byte(content), 0o600); err != nil {
				t.Fatal(err)
			}
			if got := handleValidateConfig(configPath); got != "" {
				t.Fatalf("validation result = %q, want success", got)
			}
		})
	}
}

func prepareValidationTestHome(t *testing.T) string {
	t.Helper()
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
	constant.SetHomeDir(home)
	return home
}
