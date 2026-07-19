//go:build !cgo

package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

type initialCountingProxyProvider struct {
	cp.ProxyProvider
	initialCalls atomic.Int32
}

type fakeConfigApplyTransaction struct {
	commit          func() error
	commitSuspended func() error
	rollback        func() error
}

func installPatchConfigStub(
	t *testing.T,
	result error,
	inspect func(*config.Config),
) {
	t.Helper()
	previous := patchCoreConfig
	patchCoreConfig = func(ctx context.Context, patch func(*config.Config)) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		general := *currentConfig.General
		controller := *currentConfig.Controller
		candidate := &config.Config{
			General:    &general,
			Controller: &controller,
		}
		patch(candidate)
		if inspect != nil {
			inspect(candidate)
		}
		if result == nil {
			currentConfig.General = candidate.General
			currentConfig.Controller = candidate.Controller
		}
		return result
	}
	t.Cleanup(func() { patchCoreConfig = previous })
}

func (tx *fakeConfigApplyTransaction) Commit() error {
	return tx.commit()
}

func (tx *fakeConfigApplyTransaction) CommitSuspended() error {
	if tx.commitSuspended != nil {
		return tx.commitSuspended()
	}
	return tx.commit()
}

func (tx *fakeConfigApplyTransaction) Rollback() error {
	return tx.rollback()
}

func (p *initialCountingProxyProvider) Initial() error {
	p.initialCalls.Add(1)
	return p.ProxyProvider.Initial()
}

func (p *initialCountingProxyProvider) Close() error {
	if closer, ok := p.ProxyProvider.(interface{ Close() error }); ok {
		return closer.Close()
	}
	return nil
}

func TestApplyConfigParseFailureKeepsCurrentConfig(t *testing.T) {
	home := t.TempDir()
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte("proxies: ["), 0o600); err != nil {
		t.Fatal(err)
	}
	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldConfig := currentConfig
	sentinel := &config.Config{}
	currentConfig = sentinel
	t.Cleanup(func() {
		currentConfig = oldConfig
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected invalid config to fail")
	}
	if currentConfig != sentinel {
		t.Fatal("parse failure replaced the current config")
	}
}

func TestConfigApplyOperationRegistrationIsExclusiveAndSelfClearing(t *testing.T) {
	if activeConfigApply.Load() != nil {
		t.Fatal("unexpected active config apply before test")
	}
	first, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(first) })
	if _, err := registerConfigApplyOperation(); !errors.Is(err, errConfigApplyBusy) {
		t.Fatalf("second registration error = %v, want busy", err)
	}
	finishConfigApplyOperation(first)
	finishConfigApplyOperation(first)
	select {
	case <-first.done:
	default:
		t.Fatal("finished operation did not close done")
	}
	if activeConfigApply.Load() != nil {
		t.Fatal("finished operation remained registered")
	}

	second, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	if second.generation <= first.generation {
		t.Fatalf("operation generation = %d, want greater than %d", second.generation, first.generation)
	}
	finishConfigApplyOperation(second)
}

func waitForDetachedConfigWorkers(t *testing.T, want int32) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for detachedConfigWork.Load() != want && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := detachedConfigWork.Load(); got != want {
		t.Fatalf("detached config workers = %d, want %d", got, want)
	}
}

func TestConfigParseWorkerPanicReturnsExplicitError(t *testing.T) {
	if activeConfigApply.Load() != nil || detachedConfigWork.Load() != 0 {
		t.Fatal("config apply worker state was not idle before panic test")
	}
	oldParse := parseCoreConfig
	parseCoreConfig = func(string, string) (*config.Config, error) {
		panic("injected parser panic")
	}
	t.Cleanup(func() { parseCoreConfig = oldParse })

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(operation) })
	_, parseErr := parseConfigBounded(operation, "unused", "")
	finishConfigApplyOperation(operation)
	if !errors.Is(parseErr, errConfigWorkerPanic) {
		t.Fatalf("parse error = %v, want worker panic", parseErr)
	}
	if activeConfigApply.Load() != nil || detachedConfigWork.Load() != 0 {
		t.Fatal("panicking parser retained an apply operation or worker slot")
	}
}

func TestDetachedParseBlocksRepeatedAdmissionUntilCleanup(t *testing.T) {
	if activeConfigApply.Load() != nil || detachedConfigWork.Load() != 0 {
		t.Fatal("config apply worker state was not idle before admission test")
	}
	candidate := &config.Config{}
	parseStarted := make(chan struct{})
	releaseParse := make(chan struct{})
	disposeDone := make(chan struct{})
	var releaseOnce sync.Once
	var parseCalls atomic.Int32
	var disposeCalls atomic.Int32
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldTimeout := configApplyParseTimeout
	parseCoreConfig = func(string, string) (*config.Config, error) {
		if parseCalls.Add(1) == 1 {
			close(parseStarted)
		}
		<-releaseParse
		return candidate, nil
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != candidate {
			return errors.New("disposed an unexpected config candidate")
		}
		if disposeCalls.Add(1) == 1 {
			close(disposeDone)
		}
		return nil
	}
	configApplyParseTimeout = 25 * time.Millisecond
	release := func() { releaseOnce.Do(func() { close(releaseParse) }) }
	t.Cleanup(func() {
		release()
		waitForDetachedConfigWorkers(t, 0)
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		configApplyParseTimeout = oldTimeout
	})

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(operation) })
	parseDone := make(chan error, 1)
	go func() {
		_, parseErr := parseConfigBounded(operation, "unused", "")
		parseDone <- parseErr
	}()
	select {
	case <-parseStarted:
	case <-time.After(time.Second):
		t.Fatal("config parse did not start")
	}
	var parseErr error
	select {
	case parseErr = <-parseDone:
	case <-time.After(time.Second):
		t.Fatal("bounded config parse did not return")
	}
	finishConfigApplyOperation(operation)
	if !errors.Is(parseErr, errConfigParseTimeout) {
		t.Fatalf("parse error = %v, want timeout", parseErr)
	}
	waitForDetachedConfigWorkers(t, 1)

	started := time.Now()
	for attempt := 0; attempt < 100; attempt++ {
		unexpected, registerErr := registerConfigApplyOperation()
		if unexpected != nil {
			finishConfigApplyOperation(unexpected)
			t.Fatalf("detached worker admitted attempt %d", attempt)
		}
		if !errors.Is(registerErr, errConfigApplyBusy) {
			t.Fatalf("attempt %d error = %v, want busy", attempt, registerErr)
		}
	}
	if elapsed := time.Since(started); elapsed > 2*time.Second {
		t.Fatalf("100 busy admissions took %v", elapsed)
	}
	if parseCalls.Load() != 1 {
		t.Fatalf("parse calls = %d, want 1", parseCalls.Load())
	}

	release()
	select {
	case <-disposeDone:
	case <-time.After(time.Second):
		t.Fatal("late config candidate was not disposed")
	}
	waitForDetachedConfigWorkers(t, 0)
	if disposeCalls.Load() != 1 {
		t.Fatalf("dispose calls = %d, want 1", disposeCalls.Load())
	}
	retry, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatalf("admission did not recover after cleanup: %v", err)
	}
	finishConfigApplyOperation(retry)
}

func TestConfigBeginWorkerPanicTransfersCandidateOwnership(t *testing.T) {
	candidate := &config.Config{}
	var disposeCalls atomic.Int32
	oldBegin, oldDispose := beginCoreConfigTransaction, disposeParsedConfig
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		panic("injected begin panic")
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != candidate {
			return errors.New("disposed an unexpected config candidate")
		}
		disposeCalls.Add(1)
		return nil
	}
	t.Cleanup(func() {
		beginCoreConfigTransaction = oldBegin
		disposeParsedConfig = oldDispose
	})

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(operation) })
	transaction, beginErr, rootOwnsCandidate := beginConfigTransactionBounded(operation, candidate, false)
	finishConfigApplyOperation(operation)
	if transaction != nil || !errors.Is(beginErr, errConfigWorkerPanic) || !rootOwnsCandidate {
		t.Fatalf("begin result = (%v, %v, %t), want panic with root ownership", transaction, beginErr, rootOwnsCandidate)
	}
	if rootOwnsCandidate {
		if err := disposeParsedConfig(candidate); err != nil {
			t.Fatal(err)
		}
	}
	if disposeCalls.Load() != 1 || detachedConfigWork.Load() != 0 {
		t.Fatalf("dispose calls/workers = %d/%d, want 1/0", disposeCalls.Load(), detachedConfigWork.Load())
	}
}

func TestDetachedBeginPanicCleansCandidateAndReleasesAdmission(t *testing.T) {
	candidate := &config.Config{}
	beginStarted := make(chan struct{})
	releaseBegin := make(chan struct{})
	disposeDone := make(chan struct{})
	var releaseOnce sync.Once
	var disposeCalls atomic.Int32
	oldBegin, oldDispose := beginCoreConfigTransaction, disposeParsedConfig
	oldTimeout := configApplyBeginTimeout
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		close(beginStarted)
		<-releaseBegin
		panic("injected detached begin panic")
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != candidate {
			return errors.New("disposed an unexpected config candidate")
		}
		if disposeCalls.Add(1) == 1 {
			close(disposeDone)
		}
		return nil
	}
	configApplyBeginTimeout = 25 * time.Millisecond
	release := func() { releaseOnce.Do(func() { close(releaseBegin) }) }
	t.Cleanup(func() {
		release()
		waitForDetachedConfigWorkers(t, 0)
		beginCoreConfigTransaction = oldBegin
		disposeParsedConfig = oldDispose
		configApplyBeginTimeout = oldTimeout
	})

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(operation) })
	type beginResult struct {
		transaction       configApplyTransaction
		err               error
		rootOwnsCandidate bool
	}
	beginDone := make(chan beginResult, 1)
	go func() {
		transaction, beginErr, rootOwnsCandidate := beginConfigTransactionBounded(operation, candidate, false)
		beginDone <- beginResult{
			transaction:       transaction,
			err:               beginErr,
			rootOwnsCandidate: rootOwnsCandidate,
		}
	}()
	select {
	case <-beginStarted:
	case <-time.After(time.Second):
		t.Fatal("config begin did not start")
	}
	var result beginResult
	select {
	case result = <-beginDone:
	case <-time.After(time.Second):
		t.Fatal("bounded config begin did not return")
	}
	finishConfigApplyOperation(operation)
	if result.transaction != nil || !errors.Is(result.err, errConfigApplyTimeout) || result.rootOwnsCandidate {
		t.Fatalf(
			"begin result = (%v, %v, %t), want detached timeout",
			result.transaction,
			result.err,
			result.rootOwnsCandidate,
		)
	}
	waitForDetachedConfigWorkers(t, 1)
	release()
	select {
	case <-disposeDone:
	case <-time.After(time.Second):
		t.Fatal("panicking detached begin did not dispose its candidate")
	}
	waitForDetachedConfigWorkers(t, 0)
	if disposeCalls.Load() != 1 {
		t.Fatalf("dispose calls = %d, want 1", disposeCalls.Load())
	}
}

func TestBeginErrorTransactionRollbackRetainsAdmissionUntilFinished(t *testing.T) {
	rollbackStarted := make(chan struct{})
	releaseRollback := make(chan struct{})
	var releaseOnce sync.Once
	var rollbackCalls atomic.Int32
	transaction := &fakeConfigApplyTransaction{
		rollback: func() error {
			if rollbackCalls.Add(1) == 1 {
				close(rollbackStarted)
			}
			<-releaseRollback
			return errors.New("injected rollback cleanup failure")
		},
	}
	oldBegin := beginCoreConfigTransaction
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		return transaction, errors.New("injected begin failure")
	}
	release := func() { releaseOnce.Do(func() { close(releaseRollback) }) }
	t.Cleanup(func() {
		release()
		waitForDetachedConfigWorkers(t, 0)
		beginCoreConfigTransaction = oldBegin
	})

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { finishConfigApplyOperation(operation) })
	gotTransaction, beginErr, rootOwnsCandidate := beginConfigTransactionBounded(
		operation,
		&config.Config{},
		false,
	)
	finishConfigApplyOperation(operation)
	if gotTransaction != nil || beginErr == nil || rootOwnsCandidate {
		t.Fatalf(
			"begin result = (%v, %v, %t), want tracked transaction rollback",
			gotTransaction,
			beginErr,
			rootOwnsCandidate,
		)
	}
	select {
	case <-rollbackStarted:
	case <-time.After(time.Second):
		t.Fatal("transaction rollback did not start")
	}
	waitForDetachedConfigWorkers(t, 1)
	if retry, retryErr := registerConfigApplyOperation(); retry != nil || !errors.Is(retryErr, errConfigApplyBusy) {
		if retry != nil {
			finishConfigApplyOperation(retry)
		}
		t.Fatalf("admission during rollback = (%v, %v), want busy", retry, retryErr)
	}

	release()
	waitForDetachedConfigWorkers(t, 0)
	if rollbackCalls.Load() != 1 {
		t.Fatalf("rollback calls = %d, want 1", rollbackCalls.Load())
	}
	retry, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatalf("admission did not recover after rollback: %v", err)
	}
	finishConfigApplyOperation(retry)
}

func TestStopCancelsApplyWithoutWaitingForParse(t *testing.T) {
	candidate, err := executor.ParseWithBytes([]byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n"))
	if err != nil {
		t.Fatal(err)
	}
	previous := &config.Config{}
	parseStarted := make(chan struct{})
	parsedTestURL := make(chan string, 1)
	releaseParse := make(chan struct{})
	disposeDone := make(chan struct{})
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(releaseParse) }) }

	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin, oldStop := beginCoreConfigTransaction, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	beginCalls, stopCalls, disposeCalls := 0, 0, 0
	parseCoreConfig = func(_ string, testURL string) (*config.Config, error) {
		parsedTestURL <- testURL
		close(parseStarted)
		<-releaseParse
		return candidate, nil
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		disposeCalls++
		if cfg != candidate {
			t.Fatal("dispose received an unexpected candidate")
		}
		if disposeCalls == 1 {
			close(disposeDone)
		}
		return nil
	}
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		beginCalls++
		return nil, errors.New("begin should not run after canceled parse")
	}
	stopCoreRuntime = func() error {
		stopCalls++
		return nil
	}
	currentConfig = previous
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	t.Cleanup(func() {
		release()
		if operation := activeConfigApply.Load(); operation != nil {
			operation.cancel()
			select {
			case <-operation.done:
			case <-time.After(time.Second):
				t.Error("config apply did not finish during cleanup")
			}
		}
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	params := defaultSetupParams()
	applyDone := make(chan error, 1)
	go func() { applyDone <- applyConfig(params) }()
	select {
	case <-parseStarted:
	case <-time.After(time.Second):
		t.Fatal("config parse did not start")
	}
	if got := <-parsedTestURL; got != params.TestURL {
		t.Fatalf("parse test URL = %q, want %q", got, params.TestURL)
	}
	operation := activeConfigApply.Load()
	if operation == nil {
		t.Fatal("parsing config apply was not registered")
	}
	stopDone := make(chan bool, 1)
	go func() { stopDone <- handleStopListener() }()
	select {
	case stopped := <-stopDone:
		if !stopped {
			t.Fatal("stop was reported as unsuccessful")
		}
	case <-time.After(time.Second):
		t.Fatal("stop waited for config parse")
	}
	if stopCalls != 1 || isRunning.Load() {
		t.Fatalf("stop calls/running = %d/%t, want 1/false", stopCalls, isRunning.Load())
	}
	release()
	select {
	case applyErr := <-applyDone:
		if !errors.Is(applyErr, context.Canceled) {
			t.Fatalf("apply error = %v, want context canceled", applyErr)
		}
	case <-time.After(time.Second):
		t.Fatal("canceled parse did not return")
	}
	select {
	case <-disposeDone:
	case <-time.After(time.Second):
		t.Fatal("late parsed candidate was not disposed")
	}
	if beginCalls != 0 || disposeCalls != 1 || currentConfig != previous || activeConfigApply.Load() != nil {
		t.Fatalf(
			"begin/dispose calls/current config/active = %d/%d/%p/%v",
			beginCalls,
			disposeCalls,
			currentConfig,
			activeConfigApply.Load(),
		)
	}
	select {
	case <-operation.done:
	default:
		t.Fatal("canceled parse operation did not close done")
	}
}

func TestConfigApplyBeginTimeoutDetachesCandidateOwnership(t *testing.T) {
	previous := &config.Config{}
	candidate := &config.Config{}
	beginStarted := make(chan struct{})
	releaseBegin := make(chan struct{})
	disposeDone := make(chan struct{})
	var disposeCalls atomic.Int32
	var releaseOnce sync.Once
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin := beginCoreConfigTransaction
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldTimeout := configApplyBeginTimeout
	parseCoreConfig = func(string, string) (*config.Config, error) {
		return candidate, nil
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != candidate {
			t.Fatalf("dispose received an unexpected candidate")
		}
		if disposeCalls.Add(1) == 1 {
			close(disposeDone)
		}
		return nil
	}
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		close(beginStarted)
		<-releaseBegin
		return nil, errors.New("late begin failure")
	}
	configApplyBeginTimeout = 25 * time.Millisecond
	currentConfig = previous
	isRunning.Store(false)
	t.Cleanup(func() {
		releaseOnce.Do(func() { close(releaseBegin) })
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		configApplyBeginTimeout = oldTimeout
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	applyDone := make(chan error, 1)
	go func() { applyDone <- applyConfig(defaultSetupParams()) }()
	select {
	case <-beginStarted:
	case <-time.After(time.Second):
		t.Fatal("config begin did not start")
	}
	select {
	case err := <-applyDone:
		if !errors.Is(err, errConfigApplyTimeout) {
			t.Fatalf("apply error = %v, want bounded begin timeout", err)
		}
	case <-time.After(time.Second):
		t.Fatal("bounded begin did not return")
	}
	if activeConfigApply.Load() != nil {
		t.Fatal("timed out config apply remained registered")
	}
	if disposeCalls.Load() != 0 {
		t.Fatal("root disposed a candidate still owned by detached begin")
	}
	releaseOnce.Do(func() { close(releaseBegin) })
	select {
	case <-disposeDone:
	case <-time.After(time.Second):
		t.Fatal("detached begin did not dispose its candidate after returning")
	}
}

func TestConfigParseTimeoutAllowsRetryAndDisposesLateCandidate(t *testing.T) {
	previous := &config.Config{}
	lateCandidate := &config.Config{}
	retryCandidate := &config.Config{}
	firstParseStarted := make(chan struct{})
	releaseFirstParse := make(chan struct{})
	lateDisposeDone := make(chan struct{})
	var parseCalls atomic.Int32
	var disposeCalls atomic.Int32
	var releaseOnce sync.Once
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin := beginCoreConfigTransaction
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldTimeout := configApplyParseTimeout
	parseCoreConfig = func(string, string) (*config.Config, error) {
		if parseCalls.Add(1) == 1 {
			close(firstParseStarted)
			<-releaseFirstParse
			return lateCandidate, nil
		}
		return retryCandidate, nil
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != lateCandidate {
			return errors.New("disposed an unexpected candidate")
		}
		if disposeCalls.Add(1) == 1 {
			close(lateDisposeDone)
		}
		return nil
	}
	beginCoreConfigTransaction = func(_ context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
		if cfg != retryCandidate || running {
			return nil, errors.New("retry begin received unexpected state")
		}
		return &fakeConfigApplyTransaction{
			commitSuspended: func() error { return nil },
			rollback:        func() error { return nil },
		}, nil
	}
	configApplyParseTimeout = 25 * time.Millisecond
	currentConfig = previous
	isRunning.Store(false)
	t.Cleanup(func() {
		releaseOnce.Do(func() { close(releaseFirstParse) })
		waitForDetachedConfigWorkers(t, 0)
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		configApplyParseTimeout = oldTimeout
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	firstDone := make(chan error, 1)
	go func() { firstDone <- applyConfig(defaultSetupParams()) }()
	select {
	case <-firstParseStarted:
	case <-time.After(time.Second):
		t.Fatal("first config parse did not start")
	}
	select {
	case err := <-firstDone:
		if !errors.Is(err, errConfigParseTimeout) {
			t.Fatalf("first apply error = %v, want parse timeout", err)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out parse kept the root apply registered")
	}
	if activeConfigApply.Load() != nil {
		t.Fatal("timed out parse remained the active root operation")
	}
	if err := applyConfig(defaultSetupParams()); !errors.Is(err, errConfigApplyBusy) {
		t.Fatalf("retry while detached parser is active = %v, want busy", err)
	}
	if parseCalls.Load() != 1 || currentConfig != previous || isRunning.Load() {
		t.Fatal("busy retry parsed or changed the previous suspended config")
	}

	releaseOnce.Do(func() { close(releaseFirstParse) })
	select {
	case <-lateDisposeDone:
	case <-time.After(time.Second):
		t.Fatal("late parse candidate was not disposed")
	}
	waitForDetachedConfigWorkers(t, 0)
	if disposeCalls.Load() != 1 || currentConfig != previous {
		t.Fatal("late parse candidate was published or disposed more than once")
	}
	if err := applyConfig(defaultSetupParams()); err != nil {
		t.Fatalf("retry after detached cleanup failed: %v", err)
	}
	if parseCalls.Load() != 2 || currentConfig != retryCandidate || isRunning.Load() {
		t.Fatal("retry candidate was not committed in the suspended state")
	}
}

func TestStopKeepsRuntimeStoppedWhenLateBeginReturnsTransaction(t *testing.T) {
	previous := &config.Config{}
	candidate := &config.Config{}
	beginStarted := make(chan struct{})
	releaseBegin := make(chan struct{})
	rollbackDone := make(chan struct{})
	var releaseOnce sync.Once
	var rollbackCalls atomic.Int32
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin, oldStop := beginCoreConfigTransaction, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	oldTestURL := constant.GetDefaultTestURL()
	const previousURL = "https://stable.example/generate_204"
	const candidateURL = "https://late.example/generate_204"
	parseCoreConfig = func(string, string) (*config.Config, error) { return candidate, nil }
	disposeParsedConfig = func(*config.Config) error {
		t.Fatal("root disposed a candidate owned by late Begin")
		return nil
	}
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		close(beginStarted)
		<-releaseBegin
		return &fakeConfigApplyTransaction{
			commit:          func() error { return errors.New("late transaction committed unexpectedly") },
			commitSuspended: func() error { return errors.New("late transaction committed unexpectedly") },
			rollback: func() error {
				if rollbackCalls.Add(1) == 1 {
					close(rollbackDone)
				}
				return nil
			},
		}, nil
	}
	stopCoreRuntime = func() error { return nil }
	currentConfig = previous
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	constant.SetDefaultTestURL(previousURL)
	t.Cleanup(func() {
		releaseOnce.Do(func() { close(releaseBegin) })
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
		constant.SetDefaultTestURL(oldTestURL)
	})

	params := defaultSetupParams()
	params.TestURL = candidateURL
	applyDone := make(chan error, 1)
	go func() { applyDone <- applyConfig(params) }()
	select {
	case <-beginStarted:
	case <-time.After(time.Second):
		t.Fatal("late Begin did not start")
	}
	if !handleStopListener() || isRunning.Load() {
		t.Fatal("Stop did not leave runtime suspended")
	}
	if currentConfig != previous {
		t.Fatal("Stop changed root config ownership")
	}
	releaseOnce.Do(func() { close(releaseBegin) })
	select {
	case err := <-applyDone:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("late apply error = %v, want cancellation", err)
		}
	case <-time.After(time.Second):
		t.Fatal("late apply did not return")
	}
	select {
	case <-rollbackDone:
	case <-time.After(time.Second):
		t.Fatal("late transaction was not rolled back")
	}
	if rollbackCalls.Load() != 1 || currentConfig != previous || isRunning.Load() {
		t.Fatalf("late rollback calls/config/running = %d/%p/%t", rollbackCalls.Load(), currentConfig, isRunning.Load())
	}
	if got := constant.GetDefaultTestURL(); got != previousURL {
		t.Fatalf("default test URL = %q, want restored %q", got, previousURL)
	}
}

func TestStaleApplyDoesNotOverwriteNewerDefaultTestURL(t *testing.T) {
	previous := &config.Config{}
	candidate := &config.Config{}
	beginStarted := make(chan struct{})
	releaseBegin := make(chan struct{})
	var releaseOnce sync.Once
	var rollbackCalls atomic.Int32
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin := beginCoreConfigTransaction
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldTestURL := constant.GetDefaultTestURL()
	const previousURL = "https://previous.example/generate_204"
	const candidateURL = "https://candidate.example/generate_204"
	const newerURL = "https://newer.example/generate_204"
	parseCoreConfig = func(string, string) (*config.Config, error) { return candidate, nil }
	disposeParsedConfig = func(*config.Config) error {
		t.Fatal("transaction-owned candidate was disposed by root")
		return nil
	}
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		close(beginStarted)
		<-releaseBegin
		return &fakeConfigApplyTransaction{
			commit:          func() error { return errors.New("stale transaction committed unexpectedly") },
			commitSuspended: func() error { return errors.New("stale transaction committed unexpectedly") },
			rollback: func() error {
				rollbackCalls.Add(1)
				return nil
			},
		}, nil
	}
	constant.SetDefaultTestURL(previousURL)
	currentConfig = previous
	isRunning.Store(false)
	t.Cleanup(func() {
		releaseOnce.Do(func() { close(releaseBegin) })
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		constant.SetDefaultTestURL(oldTestURL)
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	params := defaultSetupParams()
	params.TestURL = candidateURL
	applyDone := make(chan error, 1)
	go func() { applyDone <- applyConfig(params) }()
	select {
	case <-beginStarted:
	case <-time.After(time.Second):
		t.Fatal("config Begin did not start")
	}
	runLock.Lock()
	constant.SetDefaultTestURL(newerURL)
	bumpRuntimeStateEpoch()
	runLock.Unlock()
	releaseOnce.Do(func() { close(releaseBegin) })
	select {
	case err := <-applyDone:
		if !errors.Is(err, errConfigApplyStale) {
			t.Fatalf("stale apply error = %v, want stale", err)
		}
	case <-time.After(time.Second):
		t.Fatal("stale apply did not return")
	}
	if got := constant.GetDefaultTestURL(); got != newerURL {
		t.Fatalf("default test URL = %q, want newer owner value %q", got, newerURL)
	}
	if rollbackCalls.Load() != 1 || currentConfig != previous || isRunning.Load() {
		t.Fatal("stale apply changed root runtime ownership")
	}
}

func TestApplyConfigBeginErrorDisposesRootOwnedCandidate(t *testing.T) {
	previous := &config.Config{}
	candidate := &config.Config{}
	oldParse, oldDispose := parseCoreConfig, disposeParsedConfig
	oldBegin := beginCoreConfigTransaction
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	disposeCalls := 0
	parseCoreConfig = func(string, string) (*config.Config, error) {
		return candidate, nil
	}
	disposeParsedConfig = func(cfg *config.Config) error {
		if cfg != candidate {
			t.Fatal("dispose received an unexpected candidate")
		}
		disposeCalls++
		return nil
	}
	beginCoreConfigTransaction = func(context.Context, *config.Config, bool) (configApplyTransaction, error) {
		return nil, &corehub.ApplyError{
			State: corehub.ApplyActiveUnchanged,
			Err:   errors.New("injected consumed candidate failure"),
		}
	}
	currentConfig = previous
	isRunning.Store(true)
	t.Cleanup(func() {
		parseCoreConfig = oldParse
		disposeParsedConfig = oldDispose
		beginCoreConfigTransaction = oldBegin
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected Begin failure")
	}
	if disposeCalls != 1 {
		t.Fatalf("root disposed candidate %d times, want 1", disposeCalls)
	}
	if currentConfig != previous || !isRunning.Load() {
		t.Fatal("typed Begin failure changed root bookkeeping")
	}
}

func TestStopDoesNotCancelCommittedApplyPhase(t *testing.T) {
	candidate, err := executor.ParseWithBytes([]byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n"))
	if err != nil {
		t.Fatal(err)
	}
	previous := &config.Config{}
	commitStarted := make(chan struct{})
	releaseCommit := make(chan struct{})
	var startOnce, releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(releaseCommit) }) }
	oldParse, oldBegin, oldStop := parseCoreConfig, beginCoreConfigTransaction, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	var beginContext context.Context
	commitCalls, rollbackCalls, stopCalls := 0, 0, 0
	parseCoreConfig = func(string, string) (*config.Config, error) { return candidate, nil }
	beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
		if cfg != candidate || !running {
			t.Fatal("unexpected running transaction candidate")
		}
		beginContext = ctx
		return &fakeConfigApplyTransaction{
			commit: func() error {
				commitCalls++
				startOnce.Do(func() { close(commitStarted) })
				<-releaseCommit
				return nil
			},
			rollback: func() error {
				rollbackCalls++
				return nil
			},
		}, nil
	}
	stopCoreRuntime = func() error {
		stopCalls++
		return nil
	}
	currentConfig = previous
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	t.Cleanup(func() {
		release()
		_ = corehub.StopRuntime()
		parseCoreConfig = oldParse
		beginCoreConfigTransaction = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	applyDone := make(chan error, 1)
	go func() { applyDone <- applyConfig(defaultSetupParams()) }()
	select {
	case <-commitStarted:
	case <-time.After(time.Second):
		t.Fatal("apply did not reach committing phase")
	}
	if beginContext == nil || beginContext.Err() != nil {
		t.Fatal("committing apply context was canceled")
	}
	stopDone := make(chan bool, 1)
	go func() { stopDone <- handleStopListener() }()
	select {
	case <-stopDone:
		t.Fatal("stop canceled or bypassed a committing apply")
	case <-time.After(100 * time.Millisecond):
	}
	if beginContext.Err() != nil {
		t.Fatal("stop canceled a committing apply context")
	}
	release()
	select {
	case applyErr := <-applyDone:
		if applyErr != nil {
			t.Fatal(applyErr)
		}
	case <-time.After(time.Second):
		t.Fatal("committing apply did not finish")
	}
	select {
	case stopped := <-stopDone:
		if !stopped {
			t.Fatal("stop after commit was reported as unsuccessful")
		}
	case <-time.After(time.Second):
		t.Fatal("stop did not resume after committing apply")
	}
	if commitCalls != 1 || rollbackCalls != 0 || stopCalls != 1 || currentConfig != candidate || isRunning.Load() {
		t.Fatalf(
			"commit/rollback/stop/config/running = %d/%d/%d/%p/%t",
			commitCalls,
			rollbackCalls,
			stopCalls,
			currentConfig,
			isRunning.Load(),
		)
	}
}

func TestRestoreAfterApplyFailureUsesTypedRuntimeState(t *testing.T) {
	tests := []struct {
		name       string
		err        error
		wasRunning bool
		wantReplay bool
		wantStop   bool
	}{
		{
			name: "active unchanged",
			err: &corehub.ApplyError{
				State: corehub.ApplyActiveUnchanged,
				Err:   errors.New("candidate rejected"),
			},
			wasRunning: true,
		},
		{
			name: "active restored wrapped",
			err: fmt.Errorf("apply failed: %w", &corehub.ApplyError{
				State: corehub.ApplyActiveRestored,
				Err:   errors.New("route rejected"),
			}),
			wasRunning: true,
		},
		{
			name: "no active runtime",
			err: &corehub.ApplyError{
				State: corehub.ApplyNoActive,
				Err:   errors.New("recovery failed"),
			},
			wantReplay: true,
			wantStop:   true,
		},
		{
			name:       "unknown error",
			err:        errors.New("untyped apply failure"),
			wantReplay: true,
			wantStop:   true,
		},
		{
			name:       "hub transaction already active",
			err:        corehub.ErrApplyTransactionActive,
			wasRunning: true,
		},
		{
			name: "wrapped executor transaction already active",
			err: &corehub.ApplyError{
				State: corehub.ApplyActiveUnchanged,
				Err:   executor.ErrApplyTransactionActive,
			},
			wasRunning: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			oldApply, oldStop := applyCoreConfig, stopCoreRuntime
			oldConfig, oldRunning := currentConfig, isRunning.Load()
			previous, err := executor.ParseWithBytes([]byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n"))
			if err != nil {
				t.Fatal(err)
			}
			providerInitialCalls := 1
			applyCoreConfig = func(cfg *config.Config) error {
				if cfg != previous {
					t.Fatal("rollback replayed an unexpected config")
				}
				providerInitialCalls++
				return nil
			}
			stopCalls := 0
			stopCoreRuntime = func() error {
				stopCalls++
				return nil
			}
			currentConfig = previous
			isRunning.Store(test.wasRunning)
			t.Cleanup(func() {
				applyCoreConfig = oldApply
				stopCoreRuntime = oldStop
				currentConfig = oldConfig
				isRunning.Store(oldRunning)
			})

			if err := restoreAfterApplyFailureLocked(test.err, previous, test.wasRunning); err != nil {
				t.Fatal(err)
			}
			wantInitialCalls := 1
			if test.wantReplay {
				wantInitialCalls++
			}
			if providerInitialCalls != wantInitialCalls {
				t.Fatalf("previous provider Initial calls = %d, want %d", providerInitialCalls, wantInitialCalls)
			}
			wantStopCalls := 0
			if test.wantStop {
				wantStopCalls = 1
			}
			if stopCalls != wantStopCalls {
				t.Fatalf("previous runtime stop calls = %d, want %d", stopCalls, wantStopCalls)
			}
			if isRunning.Load() != test.wasRunning {
				t.Fatalf("running state = %t, want %t", isRunning.Load(), test.wasRunning)
			}
		})
	}
}

func TestApplyConfigStoppedUsesSuspendedCommitWithoutStopping(t *testing.T) {
	home := t.TempDir()
	raw := []byte("mixed-port: 0\nproxies:\n  - name: candidate\n    type: direct\nrules:\n  - MATCH,candidate\n")
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), raw, 0o600); err != nil {
		t.Fatal(err)
	}
	previous, err := executor.ParseWithBytes([]byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n"))
	if err != nil {
		t.Fatal(err)
	}

	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldBegin, oldStop := beginCoreConfigTransaction, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = previous
	isRunning.Store(false)
	var candidate *config.Config
	commitCalls, suspendedCalls, rollbackCalls, stopCalls := 0, 0, 0, 0
	beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
		if err := ctx.Err(); err != nil {
			t.Fatalf("begin received canceled context: %v", err)
		}
		if running {
			t.Fatal("stopped apply used the running transaction entry point")
		}
		candidate = cfg
		return &fakeConfigApplyTransaction{
			commit: func() error {
				commitCalls++
				return nil
			},
			commitSuspended: func() error {
				suspendedCalls++
				return nil
			},
			rollback: func() error {
				rollbackCalls++
				return nil
			},
		}, nil
	}
	stopCoreRuntime = func() error {
		stopCalls++
		return nil
	}
	t.Cleanup(func() {
		beginCoreConfigTransaction = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	if err := applyConfig(defaultSetupParams()); err != nil {
		t.Fatal(err)
	}
	if commitCalls != 0 || suspendedCalls != 1 || rollbackCalls != 0 || stopCalls != 0 {
		t.Fatalf(
			"commit/suspended/rollback/stop calls = %d/%d/%d/%d, want 0/1/0/0",
			commitCalls,
			suspendedCalls,
			rollbackCalls,
			stopCalls,
		)
	}
	if candidate == nil || currentConfig != candidate || isRunning.Load() {
		t.Fatal("stopped candidate was not committed into root state")
	}
}

func TestApplyConfigFailuresDoNotReinitializePreviousProvider(t *testing.T) {
	home := t.TempDir()
	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldBegin := beginCoreConfigTransaction
	oldApply, oldStop := applyCoreConfig, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldAutoUpdate := updater.GeoAutoUpdate()
	beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
		if running {
			return corehub.BeginApplyConfigContext(ctx, cfg)
		}
		return corehub.BeginApplyConfigSuspendedContext(ctx, cfg)
	}
	applyCoreConfig = corehub.ApplyConfig
	stopCoreRuntime = corehub.StopRuntime
	currentConfig = nil
	isRunning.Store(false)
	if err := corehub.DiscardConfig(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = corehub.DiscardConfig()
		_ = cachefile.Cache().Close()
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
		if oldConfig != nil {
			_ = corehub.ApplyConfig(oldConfig)
			if !oldRunning {
				_ = corehub.StopRuntime()
			}
		}
		beginCoreConfigTransaction = oldBegin
		applyCoreConfig = oldApply
		stopCoreRuntime = oldStop
		updater.SetGeoAutoUpdate(oldAutoUpdate)
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	stableRaw := []byte(`
mixed-port: 0
proxy-providers:
  stable-provider:
    type: inline
    payload:
      - name: stable-proxy
        type: direct
proxy-groups:
  - name: stable-group
    type: select
    use:
      - stable-provider
rules:
  - MATCH,stable-group
`)
	stable, err := executor.ParseWithBytes(stableRaw)
	if err != nil {
		t.Fatal(err)
	}
	baseProvider := stable.Providers["stable-provider"]
	countingProvider := &initialCountingProxyProvider{ProxyProvider: baseProvider}
	stable.Providers["stable-provider"] = countingProvider
	if err := corehub.ApplyConfig(stable); err != nil {
		t.Fatal(err)
	}
	if err := verifyRuntimeListeners(stable); err != nil {
		t.Fatal(err)
	}
	currentConfig = stable
	isRunning.Store(true)
	if calls := countingProvider.initialCalls.Load(); calls != 1 {
		t.Fatalf("initial stable provider calls = %d, want 1", calls)
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "unavailable", http.StatusServiceUnavailable)
	}))
	defer server.Close()
	rejectedRaw := fmt.Sprintf(`
mixed-port: 0
proxy-providers:
  broken-provider:
    type: http
    url: %s
proxy-groups:
  - name: broken-group
    type: select
    use:
      - broken-provider
rules:
  - MATCH,broken-group
`, server.URL)
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(rejectedRaw), 0o600); err != nil {
		t.Fatal(err)
	}

	applyErr := applyConfig(defaultSetupParams())
	if applyErr == nil {
		t.Fatal("expected unavailable required provider to reject config")
	}
	var typedErr *corehub.ApplyError
	if !errors.As(applyErr, &typedErr) || typedErr.State != corehub.ApplyActiveUnchanged {
		t.Fatalf("apply error state = %v, want active unchanged", applyErr)
	}
	if calls := countingProvider.initialCalls.Load(); calls != 1 {
		t.Fatalf("stable provider Initial calls after rejection = %d, want 1", calls)
	}
	if currentConfig != stable || !isRunning.Load() {
		t.Fatal("stable runtime was not preserved after candidate rejection")
	}
	proxies := tunnel.AllProxies()
	if proxies["stable-group"] == nil || proxies["broken-group"] != nil {
		t.Fatalf("runtime proxies after rejection = %v", proxies)
	}

	blockedPort := reserveTCPPort(t)
	blocker, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", blockedPort))
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Close()
	postApplyRaw := fmt.Sprintf(`
mixed-port: %d
proxies:
  - name: rejected-after-apply
    type: direct
rules:
  - MATCH,rejected-after-apply
`, blockedPort)
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(postApplyRaw), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected occupied listener to reject applied candidate")
	}
	if calls := countingProvider.initialCalls.Load(); calls != 1 {
		t.Fatalf("stable provider Initial calls after transaction rollback = %d, want 1", calls)
	}
	if currentConfig != stable || !isRunning.Load() {
		t.Fatal("stable runtime was not restored after post-apply failure")
	}
	proxies = tunnel.AllProxies()
	if proxies["stable-group"] == nil || proxies["rejected-after-apply"] != nil {
		t.Fatalf("runtime proxies after transaction rollback = %v", proxies)
	}
}

func TestBlockedProviderApplyIsCanceledByLifecycle(t *testing.T) {
	tests := []struct {
		name     string
		shutdown bool
	}{
		{name: "stop"},
		{name: "shutdown", shutdown: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			requestStarted := make(chan struct{})
			requestCanceled := make(chan struct{})
			var startOnce, cancelOnce sync.Once
			server := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, request *http.Request) {
				startOnce.Do(func() { close(requestStarted) })
				<-request.Context().Done()
				cancelOnce.Do(func() { close(requestCanceled) })
			}))
			t.Cleanup(server.Close)

			home := t.TempDir()
			oldHome := constant.Path.HomeDir()
			homeLock.Lock()
			oldTrustedHome := trustedHomeDir
			trustedHomeDir = home
			homeLock.Unlock()
			constant.SetHomeDir(home)
			oldBegin := beginCoreConfigTransaction
			oldStop, oldDiscard, oldShutdown := stopCoreRuntime, discardCoreConfig, shutdownCore
			oldConfig, oldRunning := currentConfig, isRunning.Load()
			oldInit := isInit.Load()
			oldCleanupPending := runtimeCleanupPending.Load()
			oldAutoUpdate := updater.GeoAutoUpdate()
			beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
				if running {
					return corehub.BeginApplyConfigContext(ctx, cfg)
				}
				return corehub.BeginApplyConfigSuspendedContext(ctx, cfg)
			}
			stopCoreRuntime = corehub.StopRuntime
			discardCoreConfig = corehub.DiscardConfig
			shutdownCore = func() {}
			currentConfig = nil
			isRunning.Store(false)
			isInit.Store(true)
			runtimeCleanupPending.Store(false)
			if activeConfigApply.Load() != nil {
				t.Fatal("unexpected active apply before cancellation test")
			}
			if err := corehub.DiscardConfig(); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				if operation := activeConfigApply.Load(); operation != nil {
					operation.cancel()
				}
				_ = corehub.DiscardConfig()
				_ = cachefile.Cache().Close()
				constant.SetHomeDir(oldHome)
				homeLock.Lock()
				trustedHomeDir = oldTrustedHome
				homeLock.Unlock()
				if oldConfig != nil {
					_ = corehub.ApplyConfig(oldConfig)
					if !oldRunning {
						_ = corehub.StopRuntime()
					}
				}
				beginCoreConfigTransaction = oldBegin
				stopCoreRuntime = oldStop
				discardCoreConfig = oldDiscard
				shutdownCore = oldShutdown
				updater.SetGeoAutoUpdate(oldAutoUpdate)
				currentConfig = oldConfig
				isRunning.Store(oldRunning)
				isInit.Store(oldInit)
				runtimeCleanupPending.Store(oldCleanupPending)
			})

			stableRaw := []byte(`
mixed-port: 0
proxies:
  - name: stable-proxy
    type: direct
rules:
  - MATCH,stable-proxy
`)
			stable, err := executor.ParseWithBytes(stableRaw)
			if err != nil {
				t.Fatal(err)
			}
			if err := corehub.ApplyConfig(stable); err != nil {
				t.Fatal(err)
			}
			currentConfig = stable
			isRunning.Store(true)

			candidateRaw := fmt.Sprintf(`
mixed-port: 0
proxy-providers:
  blocked-provider:
    type: http
    url: %s
proxy-groups:
  - name: blocked-group
    type: select
    use:
      - blocked-provider
rules:
  - MATCH,blocked-group
`, server.URL)
			if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(candidateRaw), 0o600); err != nil {
				t.Fatal(err)
			}
			applyDone := make(chan error, 1)
			go func() { applyDone <- applyConfig(defaultSetupParams()) }()
			select {
			case <-requestStarted:
			case <-time.After(3 * time.Second):
				t.Fatal("provider request did not start")
			}

			lifecycleDone := make(chan bool, 1)
			go func() {
				if test.shutdown {
					lifecycleDone <- handleShutdown()
					return
				}
				lifecycleDone <- handleStopListener()
			}()
			select {
			case result := <-lifecycleDone:
				if !result {
					t.Fatal("lifecycle cancellation was reported as unsuccessful")
				}
			case <-time.After(3 * time.Second):
				t.Fatal("lifecycle cancellation blocked behind config apply")
			}
			select {
			case <-requestCanceled:
			case <-time.After(3 * time.Second):
				t.Fatal("provider server did not observe request cancellation")
			}
			select {
			case applyErr := <-applyDone:
				if !errors.Is(applyErr, context.Canceled) {
					t.Fatalf("apply error = %v, want context canceled", applyErr)
				}
			case <-time.After(3 * time.Second):
				t.Fatal("canceled config apply did not return")
			}
			if activeConfigApply.Load() != nil {
				t.Fatal("canceled config apply remained registered")
			}
			proxies := tunnel.AllProxies()
			if proxies["blocked-group"] != nil {
				t.Fatal("canceled candidate was published")
			}
			if test.shutdown {
				if currentConfig != nil || isRunning.Load() || isInit.Load() {
					t.Fatal("shutdown cancellation retained root runtime state")
				}
			} else if currentConfig != stable || isRunning.Load() || proxies["stable-proxy"] == nil {
				t.Fatal("stop cancellation did not retain the suspended stable config")
			}
		})
	}
}

func TestApplyConfigStoppedPublishesCandidateWithoutStartingIt(t *testing.T) {
	home := t.TempDir()
	mixedPort := reserveTCPPort(t)
	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldBegin := beginCoreConfigTransaction
	oldApply, oldStop := applyCoreConfig, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldAutoUpdate := updater.GeoAutoUpdate()
	beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
		if running {
			return corehub.BeginApplyConfigContext(ctx, cfg)
		}
		return corehub.BeginApplyConfigSuspendedContext(ctx, cfg)
	}
	applyCoreConfig = corehub.ApplyConfig
	stopCoreRuntime = corehub.StopRuntime
	currentConfig = nil
	isRunning.Store(false)
	if err := corehub.DiscardConfig(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = corehub.DiscardConfig()
		_ = cachefile.Cache().Close()
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
		if oldConfig != nil {
			_ = corehub.ApplyConfig(oldConfig)
			if !oldRunning {
				_ = corehub.StopRuntime()
			}
		}
		beginCoreConfigTransaction = oldBegin
		applyCoreConfig = oldApply
		stopCoreRuntime = oldStop
		updater.SetGeoAutoUpdate(oldAutoUpdate)
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	stableRaw := []byte(`
mixed-port: 0
proxy-providers:
  stable-provider:
    type: inline
    payload:
      - name: stable-proxy
        type: direct
proxy-groups:
  - name: stable-group
    type: select
    use:
      - stable-provider
rules:
  - MATCH,stable-group
`)
	stable, err := executor.ParseWithBytes(stableRaw)
	if err != nil {
		t.Fatal(err)
	}
	countingProvider := &initialCountingProxyProvider{ProxyProvider: stable.Providers["stable-provider"]}
	stable.Providers["stable-provider"] = countingProvider
	if err := corehub.ApplyConfig(stable); err != nil {
		t.Fatal(err)
	}
	if err := corehub.StopRuntime(); err != nil {
		t.Fatal(err)
	}
	currentConfig = stable
	isRunning.Store(false)
	if calls := countingProvider.initialCalls.Load(); calls != 1 {
		t.Fatalf("initial stable provider calls = %d, want 1", calls)
	}

	candidateRaw := fmt.Sprintf(`
mixed-port: %d
proxies:
  - name: candidate-proxy
    type: direct
rules:
  - MATCH,candidate-proxy
`, mixedPort)
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(candidateRaw), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(defaultSetupParams()); err != nil {
		t.Fatal(err)
	}
	if isRunning.Load() || tunnel.Status() != tunnel.Suspend {
		t.Fatalf("candidate runtime state = running %t/status %s, want false/suspend", isRunning.Load(), tunnel.Status())
	}
	if currentConfig == nil || currentConfig == stable {
		t.Fatal("candidate config was not published while stopped")
	}
	proxies := tunnel.AllProxies()
	if proxies["candidate-proxy"] == nil || proxies["stable-group"] != nil {
		t.Fatalf("stopped candidate proxies = %v", proxies)
	}
	if calls := countingProvider.initialCalls.Load(); calls != 1 {
		t.Fatalf("stable provider Initial calls after replacement = %d, want 1", calls)
	}
	assertTCPPortFree(t, mixedPort)

	if !handleStartListener() {
		t.Fatal("failed to start the committed candidate")
	}
	assertRuntimeReady(t, mixedPort)
	if !isRunning.Load() || tunnel.Status() != tunnel.Running {
		t.Fatalf("started candidate state = running %t/status %s", isRunning.Load(), tunnel.Status())
	}
	if !handleStopListener() {
		t.Fatal("failed to stop the committed candidate")
	}
	assertTCPPortFree(t, mixedPort)

	blockedControllerPort := reserveTCPPort(t)
	controllerBlocker, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", blockedControllerPort))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = controllerBlocker.Close() })
	failedStartMixedPort := reserveTCPPort(t)
	startFailureRaw := fmt.Sprintf(`
mixed-port: %d
external-controller: 127.0.0.1:%d
proxies:
  - name: start-failure-proxy
    type: direct
rules:
  - MATCH,start-failure-proxy
`, failedStartMixedPort, blockedControllerPort)
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(startFailureRaw), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(defaultSetupParams()); err != nil {
		t.Fatalf("stopped apply bound the occupied controller before commit: %v", err)
	}
	if isRunning.Load() || tunnel.Status() != tunnel.Suspend {
		t.Fatal("controller candidate did not remain suspended")
	}
	proxies = tunnel.AllProxies()
	if proxies["start-failure-proxy"] == nil || proxies["candidate-proxy"] != nil {
		t.Fatalf("controller candidate proxies = %v", proxies)
	}
	assertTCPPortFree(t, failedStartMixedPort)
	if handleStartListener() {
		t.Fatal("expected occupied controller to reject runtime start")
	}
	if isRunning.Load() || tunnel.Status() != tunnel.Suspend {
		t.Fatal("failed core start did not leave the candidate suspended")
	}
	if tunnel.AllProxies()["start-failure-proxy"] == nil {
		t.Fatal("failed start discarded the committed candidate")
	}
	assertTCPPortFree(t, failedStartMixedPort)
	if err := controllerBlocker.Close(); err != nil {
		t.Fatal(err)
	}
	if !handleStartListener() {
		t.Fatal("candidate did not start after the controller port was released")
	}
	assertRuntimeReady(t, failedStartMixedPort, blockedControllerPort)
	if !handleStopListener() {
		t.Fatal("failed to stop the recovered candidate")
	}
	assertTCPPortFree(t, failedStartMixedPort)
	assertTCPPortFree(t, blockedControllerPort)
}

func TestApplyConfigCommitFailureRollsBackWithoutReplayingPreviousConfig(t *testing.T) {
	home := t.TempDir()
	raw := []byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n")
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), raw, 0o600); err != nil {
		t.Fatal(err)
	}
	previous, err := executor.ParseWithBytes(raw)
	if err != nil {
		t.Fatal(err)
	}

	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldBegin := beginCoreConfigTransaction
	oldApply, oldStop := applyCoreConfig, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = previous
	isRunning.Store(true)
	beginCalls, commitCalls, rollbackCalls := 0, 0, 0
	providerInitialCalls := 1
	beginCoreConfigTransaction = func(ctx context.Context, _ *config.Config, running bool) (configApplyTransaction, error) {
		if err := ctx.Err(); err != nil {
			t.Fatalf("begin received canceled context: %v", err)
		}
		if !running {
			t.Fatal("running apply used the suspended transaction entry point")
		}
		beginCalls++
		return &fakeConfigApplyTransaction{
			commit: func() error {
				commitCalls++
				return errors.New("injected candidate geo updater failure")
			},
			rollback: func() error {
				rollbackCalls++
				return nil
			},
		}, nil
	}
	applyCoreConfig = func(cfg *config.Config) error {
		providerInitialCalls++
		return nil
	}
	stopCoreRuntime = func() error { return nil }
	t.Cleanup(func() {
		_ = corehub.StopRuntime()
		beginCoreConfigTransaction = oldBegin
		applyCoreConfig = oldApply
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected candidate geo updater commit failure")
	}
	if beginCalls != 1 || commitCalls != 1 || rollbackCalls != 1 {
		t.Fatalf("begin/commit/rollback calls = %d/%d/%d, want 1/1/1", beginCalls, commitCalls, rollbackCalls)
	}
	if providerInitialCalls != 1 {
		t.Fatalf("previous provider Initial calls = %d, want 1", providerInitialCalls)
	}
	if currentConfig != previous || !isRunning.Load() {
		t.Fatal("previous root runtime state was not restored")
	}
}

func TestApplyConfigPrepublishCommitErrorRollsBackCandidate(t *testing.T) {
	home := t.TempDir()
	raw := []byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n")
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), raw, 0o600); err != nil {
		t.Fatal(err)
	}
	previous, err := executor.ParseWithBytes(raw)
	if err != nil {
		t.Fatal(err)
	}

	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldBegin := beginCoreConfigTransaction
	oldApply, oldStop := applyCoreConfig, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = previous
	isRunning.Store(false)
	commitCalls, rollbackCalls, replayCalls := 0, 0, 0
	beginCoreConfigTransaction = func(ctx context.Context, _ *config.Config, running bool) (configApplyTransaction, error) {
		if err := ctx.Err(); err != nil {
			t.Fatalf("begin received canceled context: %v", err)
		}
		if running {
			t.Fatal("stopped apply used the running transaction entry point")
		}
		return &fakeConfigApplyTransaction{
			commit: func() error {
				commitCalls++
				return errors.New("injected prepublish commit failure")
			},
			rollback: func() error {
				rollbackCalls++
				return nil
			},
		}, nil
	}
	applyCoreConfig = func(*config.Config) error {
		replayCalls++
		return nil
	}
	stopCoreRuntime = func() error { return nil }
	t.Cleanup(func() {
		beginCoreConfigTransaction = oldBegin
		applyCoreConfig = oldApply
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected prepublish commit failure")
	}
	if commitCalls != 1 || rollbackCalls != 1 || replayCalls != 0 {
		t.Fatalf("commit/rollback/replay calls = %d/%d/%d, want 1/1/0", commitCalls, rollbackCalls, replayCalls)
	}
	if currentConfig != previous || isRunning.Load() {
		t.Fatal("previous stopped config was not retained after commit failure")
	}
}

func TestUpdateConfigAppliesAllowLan(t *testing.T) {
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = &config.Config{
		General:    &config.General{Inbound: config.Inbound{AllowLan: false}},
		Controller: &config.Controller{},
		TLS:        &config.TLS{},
	}
	isRunning.Store(false)
	patchCalls := 0
	installPatchConfigStub(t, nil, func(candidate *config.Config) {
		patchCalls++
		if !candidate.General.AllowLan {
			t.Fatal("delegated candidate did not contain allow-lan")
		}
	})
	t.Cleanup(func() {
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	allowLan := true
	if err := updateConfig(&UpdateParams{AllowLan: &allowLan}); err != nil {
		t.Fatal(err)
	}
	if !currentConfig.General.AllowLan {
		t.Fatal("allow-lan was not applied")
	}
	if patchCalls != 1 {
		t.Fatalf("patch calls = %d, want 1", patchCalls)
	}
}

func TestUpdateConfigDelegatesIPv6(t *testing.T) {
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = &config.Config{
		General:    &config.General{IPv6: false},
		Controller: &config.Controller{},
		TLS:        &config.TLS{},
	}
	isRunning.Store(false)
	installPatchConfigStub(t, nil, func(candidate *config.Config) {
		if !candidate.General.IPv6 {
			t.Fatal("delegated candidate did not contain IPv6")
		}
	})
	t.Cleanup(func() {
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	enabled := true
	if err := updateConfig(&UpdateParams{IPv6: &enabled}); err != nil {
		t.Fatal(err)
	}
	if !currentConfig.General.IPv6 {
		t.Fatal("IPv6 hot update was not published by the delegated patch")
	}
}

func TestUpdateConfigDoesNotPublishFailedDelegatedPatch(t *testing.T) {
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldAutoUpdate := updater.GeoAutoUpdate()
	oldDisableIPv6 := resolver.RuntimeSnapshot().DisableIPv6
	currentConfig = &config.Config{
		General:    &config.General{},
		Controller: &config.Controller{},
		TLS:        &config.TLS{},
	}
	isRunning.Store(false)
	updater.SetGeoAutoUpdate(false)
	tunnel.SetDisableIPv6(true)
	patchErr := errors.New("patch updater transition failed")
	installPatchConfigStub(t, patchErr, func(candidate *config.Config) {
		if !candidate.General.GeoAutoUpdate || !candidate.General.IPv6 {
			t.Fatal("failed delegated candidate omitted requested settings")
		}
	})
	t.Cleanup(func() {
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		updater.SetGeoAutoUpdate(oldAutoUpdate)
		tunnel.SetDisableIPv6(oldDisableIPv6)
	})

	enabled := true
	if err := updateConfig(&UpdateParams{GeoAutoUpdate: &enabled, IPv6: &enabled}); !errors.Is(err, patchErr) {
		t.Fatalf("update error = %v, want %v", err, patchErr)
	}
	if currentConfig.General.GeoAutoUpdate || updater.GeoAutoUpdate() || currentConfig.General.IPv6 || !resolver.RuntimeSnapshot().DisableIPv6 {
		t.Fatal("failed delegated patch leaked into Root or runtime state")
	}
}

func TestUpdateConfigRollsBackExternalControllerBindFailure(t *testing.T) {
	controllerPort := reserveTCPPort(t)
	blockedPort := reserveTCPPort(t)
	raw := fmt.Sprintf(`
mixed-port: 0
external-controller: 127.0.0.1:%d
rules:
  - MATCH,DIRECT
`, controllerPort)
	cfg, err := executor.ParseWithBytes([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	if err := corehub.ApplyConfig(cfg); err != nil {
		t.Fatal(err)
	}

	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = cfg
	isRunning.Store(true)
	t.Cleanup(func() {
		_ = corehub.StopRuntime()
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})
	assertRuntimeReady(t, controllerPort)

	blocker, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", blockedPort))
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Close()
	nextController := fmt.Sprintf("127.0.0.1:%d", blockedPort)
	if err := updateConfig(&UpdateParams{ExternalController: &nextController}); err == nil {
		t.Fatal("expected occupied controller port to fail")
	}
	if cfg.Controller.ExternalController != fmt.Sprintf("127.0.0.1:%d", controllerPort) {
		t.Fatalf("controller config was not rolled back: %s", cfg.Controller.ExternalController)
	}
	if !isRunning.Load() {
		t.Fatal("runtime should remain running after successful rollback")
	}
	assertRuntimeReady(t, controllerPort)
}

func TestUpdateConfigDelegatesMixedPortCommitAndRollback(t *testing.T) {
	portA := reserveTCPUDPPort(t)
	portB := reserveTCPUDPPort(t)
	for portB == portA {
		portB = reserveTCPUDPPort(t)
	}
	portC := reserveTCPUDPPort(t)
	for portC == portA || portC == portB {
		portC = reserveTCPUDPPort(t)
	}
	stable, err := executor.ParseWithBytes([]byte(fmt.Sprintf(`
mixed-port: %d
rules:
  - MATCH,DIRECT
`, portA)))
	if err != nil {
		t.Fatal(err)
	}
	if err := corehub.ApplyConfig(stable); err != nil {
		t.Fatal(err)
	}

	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = stable
	isRunning.Store(true)
	t.Cleanup(func() {
		_ = corehub.StopRuntime()
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})
	assertRuntimeReady(t, portA)

	if err := updateConfig(&UpdateParams{MixedPort: &portB}); err != nil {
		t.Fatalf("commit mixed-port B: %v", err)
	}
	if currentConfig.General.MixedPort != portB || listener.GetRuntimeState().Ports.MixedPort != portB {
		t.Fatalf("mixed-port B was not published: config=%d runtime=%d", currentConfig.General.MixedPort, listener.GetRuntimeState().Ports.MixedPort)
	}
	assertTCPPortFree(t, portA)
	assertRuntimeReady(t, portB)

	blocker, err := net.ListenPacket("udp", fmt.Sprintf("127.0.0.1:%d", portC))
	if err != nil {
		t.Fatal(err)
	}
	defer blocker.Close()
	if err := updateConfig(&UpdateParams{MixedPort: &portC}); err == nil {
		t.Fatal("occupied mixed-port C unexpectedly committed")
	}
	state := listener.GetRuntimeState()
	if currentConfig.General.MixedPort != portB || state.Ports.MixedPort != portB || !isRunning.Load() {
		t.Fatalf(
			"failed mixed-port patch did not retain B: config=%d runtime=%d running=%t",
			currentConfig.General.MixedPort,
			state.Ports.MixedPort,
			isRunning.Load(),
		)
	}
	assertRuntimeReady(t, portB)
}

func TestInitialListenerFailureDiscardsRejectedConfig(t *testing.T) {
	home := t.TempDir()
	dnsPort := reserveTCPUDPPort(t)
	mixedPort := reserveTCPPort(t)
	mixedBlocker, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort))
	if err != nil {
		t.Fatal(err)
	}
	defer mixedBlocker.Close()

	initial := fmt.Sprintf(`
mixed-port: %d
dns:
  enable: true
  listen: 127.0.0.1:%d
  nameserver:
    - 1.1.1.1
proxies:
  - name: rejected-proxy
    type: direct
rules:
  - MATCH,rejected-proxy
`, mixedPort, dnsPort)
	configPath := filepath.Join(home, "config.yaml")
	if err := os.WriteFile(configPath, []byte(initial), 0o600); err != nil {
		t.Fatal(err)
	}

	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = nil
	isRunning.Store(true)
	if err := corehub.DiscardConfig(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = corehub.DiscardConfig()
		_ = cachefile.Cache().Close()
		if oldConfig != nil {
			_ = corehub.ApplyConfig(oldConfig)
			if !oldRunning {
				_ = corehub.StopRuntime()
			}
		}
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected occupied mixed port to reject initial config")
	}
	if currentConfig != nil || isRunning.Load() {
		t.Fatal("rejected initial config remained active")
	}
	if tunnel.AllProxies()["rejected-proxy"] != nil {
		t.Fatal("rejected initial proxy leaked after rollback")
	}
	assertTCPUnavailable(t, dnsPort)

	failedDNSPort := reserveTCPUDPPort(t)
	dnsBlocker, err := net.ListenPacket("udp", fmt.Sprintf("127.0.0.1:%d", failedDNSPort))
	if err != nil {
		t.Fatal(err)
	}
	defer dnsBlocker.Close()
	second := fmt.Sprintf(`
mixed-port: 0
dns:
  enable: true
  listen: 127.0.0.1:%d
  nameserver:
    - 1.1.1.1
proxies:
  - name: suspended-proxy
    type: direct
rules:
  - MATCH,suspended-proxy
`, failedDNSPort)
	if err := os.WriteFile(configPath, []byte(second), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(defaultSetupParams()); err != nil {
		t.Fatalf("stopped apply should not start the occupied DNS listener: %v", err)
	}
	if currentConfig == nil || isRunning.Load() || tunnel.Status() != tunnel.Suspend {
		t.Fatal("stopped config was not retained in suspended state")
	}
	proxies := tunnel.AllProxies()
	if proxies["rejected-proxy"] != nil || proxies["suspended-proxy"] == nil {
		t.Fatal("stopped candidate did not replace the rejected proxy set")
	}
	if handleStartListener() {
		t.Fatal("expected occupied DNS port to reject runtime start")
	}
	if isRunning.Load() || tunnel.Status() != tunnel.Suspend {
		t.Fatal("failed runtime start did not remain suspended")
	}
	assertTCPUnavailable(t, dnsPort)
	assertTCPUnavailable(t, failedDNSPort)
}

func TestApplyConfigRejectsInvalidLegacyServerWithoutAcceptingOldListener(t *testing.T) {
	tests := []struct {
		name       string
		configKey  string
		validValue func(*testing.T) string
		setValue   func(*config.General, string)
		actual     func(listener.RuntimeState) string
		running    func(listener.RuntimeState) bool
	}{
		{
			name:      "shadowsocks",
			configKey: "ss-config",
			validValue: func(t *testing.T) string {
				return fmt.Sprintf(
					`{"Enable":true,"Listen":"127.0.0.1:%d","Password":"password","Cipher":"aes-128-gcm","Udp":true}`,
					reserveTCPUDPPort(t),
				)
			},
			setValue: func(general *config.General, value string) {
				general.ShadowSocksConfig = value
			},
			actual:  func(state listener.RuntimeState) string { return state.Ports.ShadowSocksConfig },
			running: func(state listener.RuntimeState) bool { return state.ShadowSocks },
		},
		{
			name:      "vmess",
			configKey: "vmess-config",
			validValue: func(t *testing.T) string {
				return fmt.Sprintf(
					`{"Enable":true,"Listen":"127.0.0.1:%d","Users":[{"Username":"user","UUID":"00000000-0000-0000-0000-000000000001","AlterID":0}]}`,
					reserveTCPPort(t),
				)
			},
			setValue: func(general *config.General, value string) {
				general.VmessConfig = value
			},
			actual:  func(state listener.RuntimeState) string { return state.Ports.VmessConfig },
			running: func(state listener.RuntimeState) bool { return state.Vmess },
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			home := t.TempDir()
			oldHome := constant.Path.HomeDir()
			homeLock.Lock()
			oldTrustedHome := trustedHomeDir
			trustedHomeDir = home
			homeLock.Unlock()
			constant.SetHomeDir(home)
			oldConfig, oldRunning := currentConfig, isRunning.Load()
			currentConfig = nil
			isRunning.Store(false)
			if err := corehub.DiscardConfig(); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() {
				_ = corehub.DiscardConfig()
				_ = cachefile.Cache().Close()
				if oldConfig != nil {
					_ = corehub.ApplyConfig(oldConfig)
					if !oldRunning {
						_ = corehub.StopRuntime()
					}
				}
				currentConfig = oldConfig
				isRunning.Store(oldRunning)
				constant.SetHomeDir(oldHome)
				homeLock.Lock()
				trustedHomeDir = oldTrustedHome
				homeLock.Unlock()
			})

			stable, err := executor.ParseWithBytes([]byte("mixed-port: 0\nrules:\n  - MATCH,DIRECT\n"))
			if err != nil {
				t.Fatal(err)
			}
			test.setValue(stable.General, test.validValue(t))
			if err := corehub.ApplyConfig(stable); err != nil {
				t.Fatalf("start stable %s listener: %v", test.name, err)
			}
			currentConfig = stable
			isRunning.Store(true)
			before := listener.GetRuntimeState()
			if !test.running(before) || test.actual(before) == "" {
				t.Fatalf("stable %s listener did not start: %+v", test.name, before)
			}

			candidate := fmt.Sprintf(
				"%s: definitely-not-a-valid-server-config\nrules:\n  - MATCH,DIRECT\n",
				test.configKey,
			)
			if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(candidate), 0o600); err != nil {
				t.Fatal(err)
			}
			if err := applyConfig(defaultSetupParams()); err == nil {
				t.Fatalf("invalid %s config unexpectedly committed", test.name)
			}
			after := listener.GetRuntimeState()
			if currentConfig != stable || !isRunning.Load() {
				t.Fatalf("invalid %s config replaced the stable runtime", test.name)
			}
			if !test.running(after) || test.actual(after) != test.actual(before) {
				t.Fatalf("stable %s listener changed after rejection: before=%+v after=%+v", test.name, before, after)
			}
		})
	}
}

func assertTCPUnavailable(t *testing.T, port int) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 100*time.Millisecond)
	if err == nil {
		_ = conn.Close()
		t.Fatalf("TCP port %d is still listening", port)
	}
}
