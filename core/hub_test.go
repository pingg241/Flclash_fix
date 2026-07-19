package main

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
)

type manualUpdateProvider struct {
	name    string
	started chan struct{}
	release chan struct{}
	once    sync.Once
}

func (p *manualUpdateProvider) Name() string                { return p.name }
func (p *manualUpdateProvider) VehicleType() cp.VehicleType { return cp.HTTP }
func (p *manualUpdateProvider) Type() cp.ProviderType       { return cp.Rule }
func (p *manualUpdateProvider) Initial() error              { return nil }
func (p *manualUpdateProvider) Update() error {
	if p.started != nil {
		p.once.Do(func() { close(p.started) })
	}
	if p.release != nil {
		<-p.release
	}
	return nil
}

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

func TestManualProviderUpdateDoesNotBlockRuntimeChanges(t *testing.T) {
	provider := &manualUpdateProvider{
		name:    "blocking",
		started: make(chan struct{}),
		release: make(chan struct{}),
	}
	previousLookup := providerForUpdate
	previousGeneration := providerRuntimeGen.Load()
	providerForUpdate = func(string) (cp.Provider, bool) { return provider, true }
	t.Cleanup(func() {
		providerForUpdate = previousLookup
		providerRuntimeGen.Store(previousGeneration)
	})

	result := make(chan string, 1)
	go handleUpdateExternalProvider(provider.name, func(value string) { result <- value })
	select {
	case <-provider.started:
	case <-time.After(time.Second):
		t.Fatal("provider update did not start")
	}

	lockAcquired := make(chan struct{}, 1)
	go func() {
		runLock.Lock()
		providerRuntimeGen.Add(1)
		lockAcquired <- struct{}{}
		runLock.Unlock()
	}()
	select {
	case <-lockAcquired:
	case <-time.After(time.Second):
		t.Fatal("slow provider update blocked the runtime lock")
	}
	close(provider.release)
	select {
	case value := <-result:
		if value != "runtime changed while updating external provider" {
			t.Fatalf("stale provider update result = %q", value)
		}
	case <-time.After(time.Second):
		t.Fatal("provider update did not finish")
	}
}

func TestManualProviderUpdateRejectsReplacedGeneration(t *testing.T) {
	oldProvider := &manualUpdateProvider{name: "replaced"}
	newProvider := &manualUpdateProvider{name: "replaced"}
	previousLookup := providerForUpdate
	lookupCount := 0
	providerForUpdate = func(string) (cp.Provider, bool) {
		lookupCount++
		if lookupCount == 1 {
			return oldProvider, true
		}
		return newProvider, true
	}
	t.Cleanup(func() { providerForUpdate = previousLookup })

	var result string
	handleUpdateExternalProvider(oldProvider.name, func(value string) { result = value })
	if result != "external provider changed while updating" {
		t.Fatalf("provider update result = %q", result)
	}
}

func TestSideLoadProviderDoesNotBlockRuntimeChanges(t *testing.T) {
	provider := &manualUpdateProvider{name: "side-load"}
	started := make(chan struct{})
	release := make(chan struct{})
	var releaseOnce sync.Once
	releaseUpdate := func() { releaseOnce.Do(func() { close(release) }) }
	previousLookup := providerForUpdate
	previousSideUpdate := sideUpdateProvider
	previousGeneration := providerRuntimeGen.Load()
	providerForUpdate = func(string) (cp.Provider, bool) { return provider, true }
	sideUpdateProvider = func(cp.Provider, []byte) error {
		close(started)
		<-release
		return nil
	}
	t.Cleanup(func() {
		releaseUpdate()
		deadline := time.Now().Add(time.Second)
		for activeProviderUpdates.Load() != 0 && time.Now().Before(deadline) {
			time.Sleep(time.Millisecond)
		}
		providerForUpdate = previousLookup
		sideUpdateProvider = previousSideUpdate
		providerRuntimeGen.Store(previousGeneration)
	})

	result := make(chan string, 1)
	go handleSideLoadExternalProvider(provider.name, []byte("payload"), func(value string) {
		result <- value
	})
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("provider side-load did not start")
	}

	lockAcquired := make(chan struct{}, 1)
	go func() {
		runLock.Lock()
		providerRuntimeGen.Add(1)
		lockAcquired <- struct{}{}
		runLock.Unlock()
	}()
	select {
	case <-lockAcquired:
	case <-time.After(time.Second):
		t.Fatal("provider side-load blocked the runtime lock")
	}
	releaseUpdate()
	select {
	case value := <-result:
		if value != "runtime changed while side-loading external provider" {
			t.Fatalf("stale provider side-load result = %q", value)
		}
	case <-time.After(time.Second):
		t.Fatal("provider side-load did not finish")
	}
	deadline := time.Now().Add(time.Second)
	for activeProviderUpdates.Load() != 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if activeProviderUpdates.Load() != 0 {
		t.Fatalf("active provider updates = %d, want 0", activeProviderUpdates.Load())
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
