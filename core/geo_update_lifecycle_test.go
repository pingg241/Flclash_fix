package main

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
)

func prepareGeoUpdateLifecycleTest(t *testing.T) {
	t.Helper()
	oldConfig := currentConfig
	oldInit := isInit.Load()
	oldRunning := isRunning.Load()
	oldUpdate := updateGeoResource
	oldInvalidate := invalidateGeoUpdates
	oldDiscard := discardCoreConfig
	oldShutdown := shutdownCore
	oldOperation := activeGeoUpdate.Load()
	currentConfig = &config.Config{}
	isInit.Store(true)
	isRunning.Store(false)
	activeGeoUpdate.Store(nil)
	t.Cleanup(func() {
		if operation := activeGeoUpdate.Swap(nil); operation != nil {
			operation.cancel()
		}
		currentConfig = oldConfig
		isInit.Store(oldInit)
		isRunning.Store(oldRunning)
		updateGeoResource = oldUpdate
		invalidateGeoUpdates = oldInvalidate
		discardCoreConfig = oldDiscard
		shutdownCore = oldShutdown
		activeGeoUpdate.Store(oldOperation)
	})
}

func TestHandleUpdateGeoDataDoesNotHoldRunLock(t *testing.T) {
	prepareGeoUpdateLifecycleTest(t)
	started := make(chan struct{})
	release := make(chan struct{})
	updateGeoResource = func(context.Context, string) error {
		close(started)
		<-release
		return nil
	}

	result := make(chan error, 1)
	go func() { result <- handleUpdateGeoData("GEOSITE") }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("GEO update did not start")
	}
	lockAcquired := make(chan struct{})
	go func() {
		runLock.Lock()
		close(lockAcquired)
		runLock.Unlock()
	}()
	select {
	case <-lockAcquired:
	case <-time.After(time.Second):
		t.Fatal("GEO update held the root runtime lock")
	}
	close(release)
	if err := <-result; err != nil {
		t.Fatal(err)
	}
}

func TestHandleUpdateGeoDataRejectsConcurrentAndStaleResult(t *testing.T) {
	prepareGeoUpdateLifecycleTest(t)
	started := make(chan struct{})
	release := make(chan struct{})
	updateGeoResource = func(context.Context, string) error {
		close(started)
		<-release
		return nil
	}

	result := make(chan error, 1)
	go func() { result <- handleUpdateGeoData("GEOSITE") }()
	<-started
	if err := handleUpdateGeoData("GEOSITE"); !errors.Is(err, errRuntimeResourceBusy) {
		t.Fatalf("concurrent update error = %v", err)
	}
	runLock.Lock()
	currentConfig = &config.Config{}
	runLock.Unlock()
	close(release)
	if err := <-result; !errors.Is(err, errConfigApplyStale) {
		t.Fatalf("stale update error = %v", err)
	}
}

func TestShutdownCancelsManualGeoUpdateBeforeCleanup(t *testing.T) {
	prepareGeoUpdateLifecycleTest(t)
	started := make(chan struct{})
	canceled := make(chan struct{})
	updateGeoResource = func(ctx context.Context, _ string) error {
		close(started)
		<-ctx.Done()
		close(canceled)
		return ctx.Err()
	}
	var invalidations atomic.Int32
	invalidateGeoUpdates = func() { invalidations.Add(1) }
	var cleanupCalls atomic.Int32
	discardCoreConfig = func() error {
		cleanupCalls.Add(1)
		return nil
	}
	shutdownCore = func() { cleanupCalls.Add(1) }

	result := make(chan error, 1)
	go func() { result <- handleUpdateGeoData("GEOSITE") }()
	<-started
	if !handleShutdown() {
		t.Fatal("shutdown failed")
	}
	select {
	case <-canceled:
	case <-time.After(time.Second):
		t.Fatal("shutdown did not cancel the GEO update")
	}
	if err := <-result; !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled update error = %v", err)
	}
	if invalidations.Load() != 1 {
		t.Fatalf("publication invalidations = %d, want 1", invalidations.Load())
	}
	if cleanupCalls.Load() != 2 {
		t.Fatalf("shutdown cleanup calls = %d, want 2", cleanupCalls.Load())
	}
}

func TestCancelActiveGeoUpdateIsIdempotent(t *testing.T) {
	prepareGeoUpdateLifecycleTest(t)
	var invalidations atomic.Int32
	invalidateGeoUpdates = func() { invalidations.Add(1) }
	ctx, cancel := context.WithCancel(context.Background())
	operation := &geoUpdateOperation{context: ctx, cancel: cancel}
	activeGeoUpdate.Store(operation)

	var wait sync.WaitGroup
	for index := 0; index < 8; index++ {
		wait.Add(1)
		go func() {
			defer wait.Done()
			cancelActiveGeoUpdate()
		}()
	}
	wait.Wait()
	if ctx.Err() == nil {
		t.Fatal("active GEO operation was not canceled")
	}
	if invalidations.Load() != 8 {
		t.Fatalf("publication invalidations = %d, want 8", invalidations.Load())
	}
}
