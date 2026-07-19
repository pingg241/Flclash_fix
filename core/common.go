package main

import (
	b "bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	currentConfig           *config.Config
	version                 atomic.Int64
	isRunning               atomic.Bool
	runtimeStartGen         atomic.Uint64
	providerRuntimeGen      atomic.Uint64
	runtimeStateEpoch       atomic.Uint64
	configApplyGen          atomic.Uint64
	activeConfigApply       atomic.Pointer[configApplyOperation]
	detachedConfigWork      atomic.Int32
	activeProviderUpdates   atomic.Int32
	geoUpdateCancelGen      atomic.Uint64
	activeGeoUpdate         atomic.Pointer[geoUpdateOperation]
	runLock                 sync.Mutex
	configApplyGate         sync.Mutex
	homeLock                sync.Mutex
	trustedHomeDir          string
	debugError              = false
	updateGeoResource       = updater.UpdateGeoResourceContext
	invalidateGeoUpdates    = updater.InvalidateGeoUpdates
	applyCoreConfig         = hub.ApplyConfig
	patchCoreConfig         = hub.PatchConfigContext
	stopCoreRuntime         = hub.StopRuntime
	discardCoreConfig       = hub.DiscardConfig
	shutdownCore            = executor.Shutdown
	parseCoreConfig         = executor.ParseWithPathAndDefaultTestURL
	disposeParsedConfig     = hub.DisposeParsedConfig
	errPathOutsideHome      = errors.New("path outside home directory")
	errConfigApplyBusy      = errors.New("a root config apply is already active")
	errConfigApplyStale     = errors.New("runtime changed during config apply")
	errConfigParseTimeout   = errors.New("config parsing timed out")
	errConfigApplyTimeout   = errors.New("config apply preparation timed out")
	errConfigWorkerPanic    = errors.New("config preparation worker panicked")
	errRuntimeResourceBusy  = errors.New("runtime resources are busy")
	configApplyParseTimeout = 15 * time.Second
	configApplyBeginTimeout = 45 * time.Second
)

const maxDetachedConfigWorkers int32 = 1

// bumpRuntimeStateEpoch invalidates in-flight config preparations. Call it
// while runLock is held whenever a lifecycle or runtime-owned configuration
// mutation is about to become observable.
func bumpRuntimeStateEpoch() uint64 {
	return runtimeStateEpoch.Add(1)
}

type configApplyOperation struct {
	generation uint64
	context    context.Context
	cancel     context.CancelFunc
	done       chan struct{}
	doneOnce   sync.Once
	phase      atomic.Uint32
}

type geoUpdateOperation struct {
	generation uint64
	context    context.Context
	cancel     context.CancelFunc
}

func registerGeoUpdateOperation() (*geoUpdateOperation, error) {
	ctx, cancel := context.WithCancel(context.Background())
	operation := &geoUpdateOperation{
		generation: geoUpdateCancelGen.Load(),
		context:    ctx,
		cancel:     cancel,
	}
	if !activeGeoUpdate.CompareAndSwap(nil, operation) {
		cancel()
		return nil, errRuntimeResourceBusy
	}
	return operation, nil
}

func finishGeoUpdateOperation(operation *geoUpdateOperation) {
	if operation == nil {
		return
	}
	activeGeoUpdate.CompareAndSwap(operation, nil)
	operation.cancel()
}

func cancelActiveGeoUpdate() {
	geoUpdateCancelGen.Add(1)
	if operation := activeGeoUpdate.Load(); operation != nil {
		operation.cancel()
	}
	invalidateGeoUpdates()
}

const (
	configApplyPreparing uint32 = iota
	configApplyCommitting
	configApplyCanceled
	configApplyDone
)

type configApplyTransaction interface {
	Commit() error
	CommitSuspended() error
	Rollback() error
}

type runtimeStartTransaction interface {
	Commit() error
	Rollback() error
}

func isRuntimeStartFinalizedError(err error) bool {
	return errors.Is(err, hub.ErrApplyTransactionFinalized) ||
		errors.Is(err, executor.ErrRuntimeStartFinalized)
}

var beginCoreConfigTransaction = func(ctx context.Context, cfg *config.Config, running bool) (configApplyTransaction, error) {
	if running {
		transaction, err := hub.BeginApplyConfigContext(ctx, cfg)
		if transaction == nil {
			return nil, err
		}
		return transaction, err
	}
	transaction, err := hub.BeginApplyConfigSuspendedContext(ctx, cfg)
	if transaction == nil {
		return nil, err
	}
	return transaction, err
}

var beginCoreRuntimeStart = func(cfg *config.Config) (runtimeStartTransaction, error) {
	return hub.BeginRuntimeStart(cfg)
}

func registerConfigApplyOperation() (*configApplyOperation, error) {
	ctx, cancel := context.WithCancel(context.Background())
	operation := &configApplyOperation{
		generation: configApplyGen.Add(1),
		context:    ctx,
		cancel:     cancel,
		done:       make(chan struct{}),
	}
	configApplyGate.Lock()
	defer configApplyGate.Unlock()
	if detachedConfigWork.Load() >= maxDetachedConfigWorkers {
		finishConfigApplyOperation(operation)
		return nil, fmt.Errorf("%w: previous config preparation is still stopping", errConfigApplyBusy)
	}
	if !activeConfigApply.CompareAndSwap(nil, operation) {
		finishConfigApplyOperation(operation)
		return nil, errConfigApplyBusy
	}
	return operation, nil
}

func finishConfigApplyOperation(operation *configApplyOperation) {
	if operation == nil {
		return
	}
	operation.phase.Store(configApplyDone)
	activeConfigApply.CompareAndSwap(operation, nil)
	operation.cancel()
	operation.doneOnce.Do(func() { close(operation.done) })
}

func runtimeStateChangedSince(epoch uint64, previous *config.Config, wasRunning bool) bool {
	return runtimeStateEpoch.Load() != epoch || currentConfig != previous || isRunning.Load() != wasRunning
}

func cancelConfigApplyOperation(operation *configApplyOperation) {
	if operation == nil {
		return
	}
	if operation.phase.CompareAndSwap(configApplyPreparing, configApplyCanceled) {
		operation.cancel()
	}
}

type configBeginResult struct {
	transaction configApplyTransaction
	err         error
}

type configParseResult struct {
	config *config.Config
	err    error
}

func configApplyTransactionIsNil(transaction configApplyTransaction) bool {
	if transaction == nil {
		return true
	}
	value := reflect.ValueOf(transaction)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}

func disposeDetachedConfigCandidate(cfg *config.Config, dispose func(*config.Config) error) {
	if cfg == nil {
		return
	}
	defer func() {
		if recover() != nil {
			logError("detached config candidate disposal panicked")
		}
	}()
	if err := dispose(cfg); err != nil {
		logError("detached config candidate disposal failed: %v", err)
	}
}

func rollbackDetachedConfigTransaction(transaction configApplyTransaction) {
	if configApplyTransactionIsNil(transaction) {
		return
	}
	defer func() {
		if recover() != nil {
			logError("detached config apply rollback panicked")
		}
	}()
	if err := transaction.Rollback(); err != nil &&
		!errors.Is(err, hub.ErrApplyTransactionFinalized) &&
		!errors.Is(err, executor.ErrApplyTransactionFinalized) {
		logError("detached config apply rollback failed: %v", err)
	}
}

func configWorkerPanicError(stage string) error {
	logError("config %s worker panicked", stage)
	return fmt.Errorf("%w during %s", errConfigWorkerPanic, stage)
}

func runConfigParseWorker(parse func(string, string) (*config.Config, error), path, defaultTestURL string) (result configParseResult) {
	defer func() {
		if recover() != nil {
			result = configParseResult{err: configWorkerPanicError("parsing")}
		}
	}()
	result.config, result.err = parse(path, defaultTestURL)
	return result
}

func runConfigBeginWorker(
	begin func(context.Context, *config.Config, bool) (configApplyTransaction, error),
	ctx context.Context,
	cfg *config.Config,
	running bool,
) (result configBeginResult) {
	defer func() {
		if recover() != nil {
			result = configBeginResult{err: configWorkerPanicError("apply preparation")}
		}
	}()
	result.transaction, result.err = begin(ctx, cfg, running)
	if configApplyTransactionIsNil(result.transaction) {
		result.transaction = nil
	}
	return result
}

func rollbackConfigTransactionDetached(transaction configApplyTransaction) {
	detachedConfigWork.Add(1)
	go func() {
		defer detachedConfigWork.Add(-1)
		rollbackDetachedConfigTransaction(transaction)
	}()
}

// parseConfigBounded detaches an uncooperative parser without leaving the
// root operation registered forever. A late config remains worker-owned and
// is disposed before the worker exits.
func parseConfigBounded(operation *configApplyOperation, path, defaultTestURL string) (*config.Config, error) {
	parse := parseCoreConfig
	dispose := disposeParsedConfig
	resultCh := make(chan configParseResult)
	detached := make(chan struct{})
	go func() {
		result := runConfigParseWorker(parse, path, defaultTestURL)
		select {
		case resultCh <- result:
		case <-detached:
			defer detachedConfigWork.Add(-1)
			disposeDetachedConfigCandidate(result.config, dispose)
		}
	}()

	timer := time.NewTimer(configApplyParseTimeout)
	defer timer.Stop()
	select {
	case result := <-resultCh:
		if result.err != nil && result.config != nil {
			return nil, errors.Join(result.err, dispose(result.config))
		}
		if result.config == nil && result.err == nil {
			return nil, errors.New("config parser returned no config")
		}
		return result.config, result.err
	case <-operation.context.Done():
		detachedConfigWork.Add(1)
		close(detached)
		return nil, operation.context.Err()
	case <-timer.C:
		cancelConfigApplyOperation(operation)
		detachedConfigWork.Add(1)
		close(detached)
		return nil, errors.Join(errConfigParseTimeout, context.Canceled)
	}
}

// beginConfigTransactionBounded keeps the root lifecycle responsive when a
// custom provider ignores context cancellation during preparation. Once the
// call is detached, the worker owns cfg and finalizes that ownership when Meta
// eventually returns; the caller must not dispose cfg in that case.
func beginConfigTransactionBounded(
	operation *configApplyOperation,
	cfg *config.Config,
	running bool,
) (transaction configApplyTransaction, err error, rootOwnsCandidate bool) {
	begin := beginCoreConfigTransaction
	dispose := disposeParsedConfig
	resultCh := make(chan configBeginResult)
	detached := make(chan struct{})
	go func() {
		result := runConfigBeginWorker(begin, operation.context, cfg, running)
		select {
		case resultCh <- result:
		case <-detached:
			defer detachedConfigWork.Add(-1)
			if result.transaction != nil {
				rollbackDetachedConfigTransaction(result.transaction)
				return
			}
			if errors.Is(result.err, hub.ErrPreparationDetached) {
				return
			}
			disposeDetachedConfigCandidate(cfg, dispose)
		}
	}()

	timer := time.NewTimer(configApplyBeginTimeout)
	defer timer.Stop()
	select {
	case result := <-resultCh:
		if result.transaction != nil && result.err != nil {
			rollbackConfigTransactionDetached(result.transaction)
			return nil, result.err, false
		}
		if result.transaction == nil && errors.Is(result.err, hub.ErrPreparationDetached) {
			return nil, result.err, false
		}
		if result.transaction == nil && result.err == nil {
			return nil, errors.New("config transaction begin returned no transaction"), true
		}
		return result.transaction, result.err, result.transaction == nil
	case <-operation.context.Done():
		detachedConfigWork.Add(1)
		close(detached)
		return nil, operation.context.Err(), false
	case <-timer.C:
		cancelConfigApplyOperation(operation)
		detachedConfigWork.Add(1)
		close(detached)
		return nil, errors.Join(errConfigApplyTimeout, context.Canceled), false
	}
}

// lockRunAfterCancelingConfigApply closes the registration window before it
// cancels an active provider load and waits for that operation to release runLock.
func lockRunAfterCancelingConfigApply() {
	configApplyGate.Lock()
	if operation := activeConfigApply.Load(); operation != nil {
		cancelConfigApplyOperation(operation)
	}
	runLock.Lock()
	configApplyGate.Unlock()
}

func getExternalProvidersRaw() map[string]cp.Provider {
	eps := make(map[string]cp.Provider)
	for n, p := range tunnel.Providers() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	for n, p := range tunnel.RuleProviders() {
		if p.VehicleType() != cp.Compatible {
			eps[n] = p
		}
	}
	return eps
}

// lookupExternalProvider always reads the live provider map (no stale cache).
func lookupExternalProvider(name string) (cp.Provider, bool) {
	if p, ok := tunnel.Providers()[name]; ok && p.VehicleType() != cp.Compatible {
		return p, true
	}
	if p, ok := tunnel.RuleProviders()[name]; ok && p.VehicleType() != cp.Compatible {
		return p, true
	}
	return nil, false
}

func toExternalProvider(p cp.Provider) (*ExternalProvider, error) {
	switch psp := p.(type) {
	case *provider.ProxySetProvider:
		return &ExternalProvider{
			Name:             psp.Name(),
			Type:             psp.Type().String(),
			VehicleType:      psp.VehicleType().String(),
			Count:            psp.Count(),
			UpdateAt:         psp.UpdatedAt(),
			Path:             psp.Vehicle().Path(),
			SubscriptionInfo: psp.GetSubscriptionInfo(),
		}, nil
	case *rp.RuleSetProvider:
		return &ExternalProvider{
			Name:        psp.Name(),
			Type:        psp.Type().String(),
			VehicleType: psp.VehicleType().String(),
			Count:       psp.Count(),
			UpdateAt:    psp.UpdatedAt(),
			Path:        psp.Vehicle().Path(),
		}, nil
	default:
		return nil, errors.New("not external provider")
	}
}

func sideUpdateExternalProvider(p cp.Provider, bytes []byte) error {
	switch psp := p.(type) {
	case *provider.ProxySetProvider:
		_, _, err := psp.SideUpdate(bytes)
		return err
	case *rp.RuleSetProvider:
		_, _, err := psp.SideUpdate(bytes)
		return err
	default:
		return errors.New("not external provider")
	}
}

func canonicalizePath(path string) (string, error) {
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	absPath = filepath.Clean(absPath)
	current := absPath
	missing := make([]string, 0, 2)
	for {
		resolved, resolveErr := filepath.EvalSymlinks(current)
		if resolveErr == nil {
			for i := len(missing) - 1; i >= 0; i-- {
				resolved = filepath.Join(resolved, missing[i])
			}
			return filepath.Clean(resolved), nil
		}
		if !os.IsNotExist(resolveErr) {
			return "", resolveErr
		}
		parent := filepath.Dir(current)
		if parent == current {
			return "", resolveErr
		}
		missing = append(missing, filepath.Base(current))
		current = parent
	}
}

func initializeHomeDir(path string) error {
	if path == "" || !filepath.IsAbs(path) {
		return errors.New("home dir must be an absolute path")
	}
	canonical, err := canonicalizePath(path)
	if err != nil {
		return fmt.Errorf("resolve home dir: %w", err)
	}
	if filepath.Dir(canonical) == canonical {
		return errors.New("home dir must not be a filesystem root")
	}
	info, err := os.Stat(canonical)
	if err != nil {
		return fmt.Errorf("stat home dir: %w", err)
	}
	if !info.IsDir() {
		return errors.New("home dir is not a directory")
	}
	homeLock.Lock()
	defer homeLock.Unlock()
	if trustedHomeDir != "" && !samePath(trustedHomeDir, canonical) {
		return errors.New("home dir cannot be changed after startup")
	}
	trustedHomeDir = canonical
	constant.SetHomeDir(canonical)
	return nil
}

func samePath(left, right string) bool {
	if runtime.GOOS == "windows" {
		return strings.EqualFold(left, right)
	}
	return left == right
}

func currentHomeDir() (string, error) {
	homeLock.Lock()
	home := trustedHomeDir
	if home == "" {
		home = constant.Path.HomeDir()
	}
	homeLock.Unlock()
	if home == "" {
		return "", errors.New("home dir not set")
	}
	return home, nil
}

func isPathOutsideHome(rel string) bool {
	return rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// relativePathWithinHome maps filesystem aliases of home back onto the
// trusted root. Android runtimes may expose the same directory through paths
// that neither filepath.Rel nor EvalSymlinks recognizes as aliases.
func relativePathWithinHome(home, target string) (string, error) {
	if rel, err := filepath.Rel(home, target); err == nil && !isPathOutsideHome(rel) {
		return rel, nil
	}

	homeInfo, err := os.Stat(home)
	if err != nil {
		return "", err
	}
	if !homeInfo.IsDir() {
		return "", errors.New("home dir is not a directory")
	}

	current := filepath.Clean(target)
	suffix := ""
	for {
		info, statErr := os.Stat(current)
		if statErr == nil {
			if info.IsDir() && os.SameFile(homeInfo, info) {
				if suffix == "" {
					return ".", nil
				}
				return suffix, nil
			}
		} else if !os.IsNotExist(statErr) {
			return "", statErr
		}

		parent := filepath.Dir(current)
		if parent == current {
			break
		}
		suffix = filepath.Join(filepath.Base(current), suffix)
		current = parent
	}
	return "", errPathOutsideHome
}

func resolveHomePath(path string) (string, string, error) {
	home, err := currentHomeDir()
	if err != nil {
		return "", "", err
	}
	canonicalHome, err := canonicalizePath(home)
	if err != nil {
		return "", "", err
	}
	canonicalPath, err := canonicalizePath(path)
	if err != nil {
		return "", "", err
	}
	rel, err := relativePathWithinHome(canonicalHome, canonicalPath)
	if err != nil {
		return "", "", err
	}
	return canonicalHome, rel, nil
}

// resolveSafePath follows existing symlinks and maps equivalent filesystem
// aliases back into the trusted home before enforcing the boundary.
func resolveSafePath(path string) (string, error) {
	canonicalHome, rel, err := resolveHomePath(path)
	if err != nil {
		return "", err
	}
	return filepath.Join(canonicalHome, rel), nil
}

func openHomePath(path string) (*os.Root, string, error) {
	canonicalHome, rel, err := resolveHomePath(path)
	if err != nil {
		return nil, "", err
	}
	root, err := os.OpenRoot(canonicalHome)
	if err != nil {
		return nil, "", err
	}
	return root, rel, nil
}

func verifyRuntimeListeners(cfg *config.Config) error {
	if cfg == nil || cfg.General == nil {
		return errors.New("runtime listener config is unavailable")
	}
	listeners := cfg.Listeners
	general := cfg.General

	state := listener.GetRuntimeState()
	if state.Ports.Port != general.Port ||
		state.Ports.SocksPort != general.SocksPort ||
		state.Ports.RedirPort != general.RedirPort ||
		state.Ports.TProxyPort != general.TProxyPort ||
		state.Ports.MixedPort != general.MixedPort {
		return fmt.Errorf("listener ports did not reach configured state")
	}
	if state.InboundCount != len(listeners) {
		return fmt.Errorf("started %d of %d inbound listeners", state.InboundCount, len(listeners))
	}
	expectedTCP, expectedUDP := expectedTunnelListenerCounts(cfg)
	if state.TunnelTCPCount != expectedTCP || state.TunnelUDPCount != expectedUDP {
		return fmt.Errorf(
			"started tunnel listeners tcp=%d/%d udp=%d/%d",
			state.TunnelTCPCount,
			expectedTCP,
			state.TunnelUDPCount,
			expectedUDP,
		)
	}
	if runtime.GOOS != "android" && state.Tun != general.Tun.Enable {
		return fmt.Errorf("TUN listener did not reach configured state")
	}
	if state.ShadowSocks != (general.ShadowSocksConfig != "") ||
		state.Vmess != (general.VmessConfig != "") ||
		state.Tuic != general.TuicServer.Enable {
		return fmt.Errorf("server listener did not reach configured state")
	}
	return nil
}

func verifyRuntimeSuspended() error {
	state := listener.GetRuntimeState()
	if state.Ports != (listener.Ports{}) ||
		state.InboundCount != 0 ||
		state.TunnelTCPCount != 0 ||
		state.TunnelUDPCount != 0 ||
		state.Tun ||
		state.ShadowSocks ||
		state.Vmess ||
		state.Tuic {
		return fmt.Errorf("suspended runtime retained listeners: %+v", state)
	}
	return nil
}

func expectedTunnelListenerCounts(cfg *config.Config) (int, int) {
	tcpKeys := map[string]struct{}{}
	udpKeys := map[string]struct{}{}
	for _, tunnelConfig := range cfg.Tunnels {
		key := tunnelConfig.Address + "\x00" + tunnelConfig.Target + "\x00" + tunnelConfig.Proxy
		for _, network := range tunnelConfig.Network {
			switch network {
			case "tcp":
				tcpKeys[key] = struct{}{}
			case "udp":
				udpKeys[key] = struct{}{}
			}
		}
	}
	return len(tcpKeys), len(udpKeys)
}

func patchSelectGroup(mapping map[string]string) {
	for name, proxy := range tunnel.AllProxies() {
		outbound, ok := proxy.(*adapter.Proxy)
		if !ok {
			continue
		}

		selector, ok := outbound.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			continue
		}

		selected, exist := mapping[name]
		if !exist {
			continue
		}

		selector.ForceSet(selected)
	}
}

func defaultSetupParams() *SetupParams {
	return &SetupParams{
		TestURL:     "https://www.gstatic.com/generate_204",
		SelectedMap: map[string]string{},
	}
}

func readFile(path string) ([]byte, error) {
	root, rel, err := openHomePath(path)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	return root.ReadFile(rel)
}

func updateConfig(params *UpdateParams) error {
	runLock.Lock()
	defer runLock.Unlock()
	if currentConfig == nil {
		return errors.New("current config is unavailable")
	}
	bumpRuntimeStateEpoch()
	defer bumpRuntimeStateEpoch()
	return patchCoreConfig(context.Background(), func(candidate *config.Config) {
		general := candidate.General
		if params.AllowLan != nil {
			general.AllowLan = *params.AllowLan
		}
		if params.MixedPort != nil {
			general.MixedPort = *params.MixedPort
		}
		if params.Sniffing != nil {
			general.Sniffing = *params.Sniffing
		}
		if params.FindProcessMode != nil {
			general.FindProcessMode = *params.FindProcessMode
		}
		if params.TCPConcurrent != nil {
			general.TCPConcurrent = *params.TCPConcurrent
		}
		if params.Interface != nil {
			general.Interface = *params.Interface
		}
		if params.UnifiedDelay != nil {
			general.UnifiedDelay = *params.UnifiedDelay
		}
		if params.Mode != nil {
			general.Mode = *params.Mode
		}
		if params.LogLevel != nil {
			general.LogLevel = *params.LogLevel
		}
		if params.IPv6 != nil {
			general.IPv6 = *params.IPv6
		}
		if params.ExternalController != nil {
			candidate.Controller.ExternalController = *params.ExternalController
		}
		if params.Tun != nil {
			general.Tun.Enable = params.Tun.Enable
			if params.Tun.AutoRoute != nil {
				general.Tun.AutoRoute = *params.Tun.AutoRoute
			}
			if params.Tun.Device != nil {
				general.Tun.Device = *params.Tun.Device
			}
			if params.Tun.RouteAddress != nil {
				general.Tun.RouteAddress = *params.Tun.RouteAddress
			}
			if params.Tun.DNSHijack != nil {
				general.Tun.DNSHijack = *params.Tun.DNSHijack
			}
			if params.Tun.Stack != nil {
				general.Tun.Stack = *params.Tun.Stack
			}
		}
		if params.GeoAutoUpdate != nil {
			general.GeoAutoUpdate = *params.GeoAutoUpdate
		}
		if params.GeoUpdateInterval != nil {
			general.GeoUpdateInterval = *params.GeoUpdateInterval
		}
	})
}

func applyConfig(params *SetupParams) error {
	operation, err := registerConfigApplyOperation()
	if err != nil {
		return err
	}
	runLocked := false
	defer func() {
		finishConfigApplyOperation(operation)
		if runLocked {
			runLock.Unlock()
		}
	}()
	home, err := currentHomeDir()
	if err != nil {
		return err
	}
	nextConfig, err := parseConfigBounded(operation, filepath.Join(home, "config.yaml"), params.TestURL)
	if err != nil {
		return err
	}
	if err := operation.context.Err(); err != nil {
		return errors.Join(err, disposeParsedConfig(nextConfig))
	}
	runLock.Lock()
	runLocked = true
	if err := operation.context.Err(); err != nil {
		return errors.Join(err, disposeParsedConfig(nextConfig))
	}
	previousConfig := currentConfig
	wasRunning := isRunning.Load()
	previousTestURL := constant.GetDefaultTestURL()
	cancelActiveProxyGeoRequests()
	constant.SetDefaultTestURL(params.TestURL)
	providerRuntimeGen.Add(1)
	applyEpoch := bumpRuntimeStateEpoch()
	runLock.Unlock()
	runLocked = false
	transaction, err, rootOwnsCandidate := beginConfigTransactionBounded(operation, nextConfig, wasRunning)
	if err != nil {
		var disposeErr error
		if rootOwnsCandidate {
			disposeErr = disposeParsedConfig(nextConfig)
		}
		runLock.Lock()
		runLocked = true
		stateChanged := runtimeStateChangedSince(applyEpoch, previousConfig, wasRunning)
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		if operation.context.Err() != nil || operation.phase.Load() == configApplyCanceled || stateChanged {
			return errors.Join(err, disposeErr, errConfigApplyStale)
		}
		return errors.Join(err, disposeErr, restoreAfterApplyFailureLocked(err, previousConfig, wasRunning))
	}
	runLock.Lock()
	runLocked = true
	finalized := false
	defer func() {
		if !finalized {
			_ = transaction.Rollback()
		}
	}()
	if runtimeStateChangedSince(applyEpoch, previousConfig, wasRunning) {
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(errConfigApplyStale, rollbackStaleConfigTransactionLocked(transaction))
	}
	if operation.context.Err() != nil || operation.phase.Load() == configApplyCanceled {
		cancelErr := operation.context.Err()
		if cancelErr == nil {
			cancelErr = context.Canceled
		}
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(cancelErr, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	if err := operation.context.Err(); err != nil {
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(err, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	if !operation.phase.CompareAndSwap(configApplyPreparing, configApplyCommitting) {
		cancelErr := operation.context.Err()
		if cancelErr == nil {
			cancelErr = context.Canceled
		}
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(cancelErr, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	if err := operation.context.Err(); err != nil {
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(err, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	var commitErr error
	if wasRunning {
		commitErr = transaction.Commit()
	} else {
		commitErr = transaction.CommitSuspended()
	}
	if commitErr != nil {
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(commitErr, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	var verifyErr error
	if wasRunning {
		verifyErr = verifyRuntimeListeners(nextConfig)
	} else {
		verifyErr = verifyRuntimeSuspended()
	}
	if verifyErr != nil {
		constant.CompareAndSwapDefaultTestURL(params.TestURL, previousTestURL)
		finalized = true
		return errors.Join(verifyErr, rollbackConfigTransactionLocked(transaction, previousConfig, wasRunning))
	}
	finalized = true
	currentConfig = nextConfig
	isRunning.Store(wasRunning)
	patchSelectGroup(params.SelectedMap)
	bumpRuntimeStateEpoch()
	return nil
}

func rollbackConfigTransactionLocked(transaction configApplyTransaction, previous *config.Config, wasRunning bool) error {
	rollbackErr := transaction.Rollback()
	var restoreErr error
	if rollbackErr != nil {
		restoreErr = restorePreviousConfigLocked(previous, wasRunning)
	} else {
		restoreErr = restorePreviousRuntimeLocked(previous, wasRunning)
	}
	bumpRuntimeStateEpoch()
	return errors.Join(rollbackErr, restoreErr)
}

func rollbackStaleConfigTransactionLocked(transaction configApplyTransaction) error {
	err := transaction.Rollback()
	bumpRuntimeStateEpoch()
	if errors.Is(err, hub.ErrApplyTransactionFinalized) || errors.Is(err, executor.ErrApplyTransactionFinalized) {
		return nil
	}
	return err
}

func restorePreviousConfigLocked(previous *config.Config, wasRunning bool) error {
	bumpRuntimeStateEpoch()
	if previous == nil {
		currentConfig = nil
		isRunning.Store(false)
		return hub.DiscardConfig()
	}
	if err := applyCoreConfig(previous); err != nil {
		currentConfig = previous
		isRunning.Store(false)
		return errors.Join(err, stopCoreRuntime())
	}
	if wasRunning {
		if err := verifyRuntimeListeners(previous); err != nil {
			currentConfig = previous
			isRunning.Store(false)
			return errors.Join(err, stopCoreRuntime())
		}
	} else if err := stopCoreRuntime(); err != nil {
		currentConfig = previous
		isRunning.Store(false)
		return err
	}
	currentConfig = previous
	isRunning.Store(wasRunning)
	return nil
}

func restoreAfterApplyFailureLocked(applyErr error, previous *config.Config, wasRunning bool) error {
	if errors.Is(applyErr, hub.ErrApplyTransactionActive) || errors.Is(applyErr, executor.ErrApplyTransactionActive) {
		return nil
	}
	var typedErr *hub.ApplyError
	if errors.As(applyErr, &typedErr) {
		switch typedErr.State {
		case hub.ApplyActiveUnchanged, hub.ApplyActiveRestored:
			currentConfig = previous
			isRunning.Store(previous != nil && wasRunning)
			bumpRuntimeStateEpoch()
			return nil
		}
	}
	return restorePreviousConfigLocked(previous, wasRunning)
}

func restorePreviousRuntimeLocked(previous *config.Config, wasRunning bool) error {
	bumpRuntimeStateEpoch()
	currentConfig = previous
	if previous == nil {
		isRunning.Store(false)
		return stopCoreRuntime()
	}
	if !wasRunning {
		isRunning.Store(false)
		return nil
	}
	if err := verifyRuntimeListeners(previous); err != nil {
		isRunning.Store(false)
		return errors.Join(err, stopCoreRuntime())
	}
	isRunning.Store(true)
	return nil
}

func UnmarshalJson(data []byte, v any) error {
	decoder := json.NewDecoder(b.NewReader(data))
	decoder.UseNumber()
	err := decoder.Decode(v)
	return err
}

func logError(format string, args ...interface{}) {
	log.Errorln(format, args...)
	if debugError {
		fmt.Fprintf(os.Stderr, "[ERROR] "+format+"\n", args...)
	}
}
