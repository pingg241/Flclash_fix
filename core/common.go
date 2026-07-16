package main

import (
	b "bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

var (
	currentConfig      *config.Config
	version            atomic.Int64
	isRunning          atomic.Bool
	runLock            sync.Mutex
	homeLock           sync.Mutex
	trustedHomeDir     string
	debugError         = false
	registerGeoUpdater = updater.RegisterGeoUpdaterWithCancel
	cancelGeoUpdater   = updater.CancelGeoUpdater
	errPathOutsideHome = errors.New("path outside home directory")
)

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

func startListeners(cfg *config.Config) error {
	listeners := cfg.Listeners
	general := cfg.General
	listener.PatchInboundListeners(listeners, tunnel.Tunnel, true)

	allowLan := general.AllowLan
	listener.SetAllowLan(allowLan)
	inbound.SetSkipAuthPrefixes(general.SkipAuthPrefixes)
	inbound.SetAllowedIPs(general.LanAllowedIPs)
	inbound.SetDisAllowedIPs(general.LanDisAllowedIPs)

	bindAddress := general.BindAddress
	listener.SetBindAddress(bindAddress)
	listener.ReCreateHTTP(general.Port, tunnel.Tunnel)
	listener.ReCreateSocks(general.SocksPort, tunnel.Tunnel)
	if err := listener.ReCreateRedir(general.RedirPort, tunnel.Tunnel); err != nil {
		return fmt.Errorf("start redir listener: %w", err)
	}
	if err := listener.ReCreateTProxy(general.TProxyPort, tunnel.Tunnel); err != nil {
		return fmt.Errorf("start tproxy listener: %w", err)
	}
	if err := listener.ReCreateMixed(general.MixedPort, tunnel.Tunnel); err != nil {
		return fmt.Errorf("start mixed listener: %w", err)
	}
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, tunnel.Tunnel)
	listener.ReCreateVmess(general.VmessConfig, tunnel.Tunnel)
	listener.ReCreateTuic(general.TuicServer, tunnel.Tunnel)
	if !features.Android {
		listener.ReCreateTun(general.Tun, tunnel.Tunnel)
	}

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
	if !features.Android && state.Tun != general.Tun.Enable {
		return fmt.Errorf("TUN listener did not reach configured state")
	}
	if state.ShadowSocks != (general.ShadowSocksConfig != "") ||
		state.Vmess != (general.VmessConfig != "") ||
		state.Tuic != general.TuicServer.Enable {
		return fmt.Errorf("server listener did not reach configured state")
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

func updateListeners() error {
	if !isRunning.Load() || currentConfig == nil {
		return nil
	}
	return startListeners(currentConfig)
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
	previousGeneral := *currentConfig.General
	previousController := *currentConfig.Controller
	wasRunning := isRunning.Load()
	routeChanged := params.ExternalController != nil
	general := currentConfig.General
	if params.AllowLan != nil {
		general.AllowLan = *params.AllowLan
	}
	if params.MixedPort != nil {
		general.MixedPort = *params.MixedPort
	}
	if params.Sniffing != nil {
		general.Sniffing = *params.Sniffing
		tunnel.SetSniffing(general.Sniffing)
	}
	if params.FindProcessMode != nil {
		general.FindProcessMode = *params.FindProcessMode
		tunnel.SetFindProcessMode(general.FindProcessMode)
	}
	if params.TCPConcurrent != nil {
		general.TCPConcurrent = *params.TCPConcurrent
		dialer.SetTcpConcurrent(general.TCPConcurrent)
	}
	if params.Interface != nil {
		general.Interface = *params.Interface
		dialer.DefaultInterface.Store(general.Interface)
	}
	if params.UnifiedDelay != nil {
		general.UnifiedDelay = *params.UnifiedDelay
		adapter.UnifiedDelay.Store(general.UnifiedDelay)
	}
	if params.Mode != nil {
		general.Mode = *params.Mode
		tunnel.SetMode(general.Mode)
	}
	if params.LogLevel != nil {
		general.LogLevel = *params.LogLevel
		log.SetLevel(general.LogLevel)
	}
	if params.IPv6 != nil {
		general.IPv6 = *params.IPv6
		resolver.DisableIPv6 = !general.IPv6
	}
	if params.ExternalController != nil {
		currentConfig.Controller.ExternalController = *params.ExternalController
		if wasRunning {
			if err := route.ReCreateServer(routeConfigFor(currentConfig)); err != nil {
				return errors.Join(
					err,
					rollbackHotConfigLocked(previousGeneral, previousController, routeChanged, wasRunning),
				)
			}
		}
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
		updater.SetGeoAutoUpdate(general.GeoAutoUpdate)
	}
	if params.GeoUpdateInterval != nil {
		general.GeoUpdateInterval = *params.GeoUpdateInterval
		updater.SetGeoUpdateInterval(general.GeoUpdateInterval)
	}

	if err := updateListeners(); err != nil {
		return errors.Join(
			err,
			rollbackHotConfigLocked(previousGeneral, previousController, routeChanged, wasRunning),
		)
	}
	if err := syncGeoUpdater(wasRunning); err != nil {
		return errors.Join(
			err,
			rollbackHotConfigLocked(previousGeneral, previousController, routeChanged, wasRunning),
		)
	}
	return nil
}

func syncGeoUpdater(running bool) error {
	if running && updater.GeoAutoUpdate() {
		return registerGeoUpdater()
	}
	return cancelGeoUpdater()
}

func routeConfigFor(cfg *config.Config) *route.Config {
	return &route.Config{
		Addr:           cfg.Controller.ExternalController,
		TLSAddr:        cfg.Controller.ExternalControllerTLS,
		UnixAddr:       cfg.Controller.ExternalControllerUnix,
		PipeAddr:       cfg.Controller.ExternalControllerPipe,
		Secret:         cfg.Controller.Secret,
		Certificate:    cfg.TLS.Certificate,
		PrivateKey:     cfg.TLS.PrivateKey,
		ClientAuthType: cfg.TLS.ClientAuthType,
		ClientAuthCert: cfg.TLS.ClientAuthCert,
		EchKey:         cfg.TLS.EchKey,
		DohServer:      cfg.Controller.ExternalDohServer,
		IsDebug:        cfg.General.LogLevel == log.DEBUG,
		Cors: route.Cors{
			AllowOrigins:        cfg.Controller.Cors.AllowOrigins,
			AllowPrivateNetwork: cfg.Controller.Cors.AllowPrivateNetwork,
		},
	}
}

func rollbackHotConfigLocked(
	previousGeneral config.General,
	previousController config.Controller,
	routeChanged bool,
	wasRunning bool,
) error {
	*currentConfig.General = previousGeneral
	*currentConfig.Controller = previousController
	tunnel.SetSniffing(previousGeneral.Sniffing)
	tunnel.SetFindProcessMode(previousGeneral.FindProcessMode)
	dialer.SetTcpConcurrent(previousGeneral.TCPConcurrent)
	dialer.DefaultInterface.Store(previousGeneral.Interface)
	adapter.UnifiedDelay.Store(previousGeneral.UnifiedDelay)
	tunnel.SetMode(previousGeneral.Mode)
	log.SetLevel(previousGeneral.LogLevel)
	resolver.DisableIPv6 = !previousGeneral.IPv6
	updater.SetGeoAutoUpdate(previousGeneral.GeoAutoUpdate)
	updater.SetGeoUpdateInterval(previousGeneral.GeoUpdateInterval)

	var routeErr error
	if routeChanged && wasRunning {
		routeErr = route.ReCreateServer(routeConfigFor(currentConfig))
	}
	listenerErr := updateListeners()
	updaterErr := syncGeoUpdater(wasRunning)
	rollbackErr := errors.Join(routeErr, listenerErr, updaterErr)
	if rollbackErr == nil {
		return nil
	}
	cleanupErr := hub.StopRuntime()
	isRunning.Store(false)
	return errors.Join(rollbackErr, cleanupErr)
}

func applyConfig(params *SetupParams) error {
	runLock.Lock()
	defer runLock.Unlock()
	previousConfig := currentConfig
	wasRunning := isRunning.Load()
	previousTestURL := constant.DefaultTestURL
	nextConfig, err := executor.ParseWithPath(filepath.Join(constant.Path.HomeDir(), "config.yaml"))
	if err != nil {
		return err
	}
	cancelActiveProxyGeoRequests()
	constant.DefaultTestURL = params.TestURL
	if err := hub.ApplyConfig(nextConfig); err != nil {
		constant.DefaultTestURL = previousTestURL
		return errors.Join(err, restorePreviousConfigLocked(previousConfig, wasRunning))
	}
	if wasRunning {
		if err := startListeners(nextConfig); err != nil {
			constant.DefaultTestURL = previousTestURL
			return errors.Join(err, restorePreviousConfigLocked(previousConfig, wasRunning))
		}
		if err := syncGeoUpdater(true); err != nil {
			constant.DefaultTestURL = previousTestURL
			return errors.Join(err, restorePreviousConfigLocked(previousConfig, wasRunning))
		}
	} else if err := hub.StopRuntime(); err != nil {
		constant.DefaultTestURL = previousTestURL
		return errors.Join(err, restorePreviousConfigLocked(previousConfig, wasRunning))
	}
	currentConfig = nextConfig
	isRunning.Store(wasRunning)
	patchSelectGroup(params.SelectedMap)
	// GC off the critical path so setup/apply is not blocked by a full STW.
	go runtime.GC()
	return err
}

func restorePreviousConfigLocked(previous *config.Config, wasRunning bool) error {
	if previous == nil {
		currentConfig = nil
		isRunning.Store(false)
		return hub.DiscardConfig()
	}
	if err := hub.ApplyConfig(previous); err != nil {
		currentConfig = previous
		isRunning.Store(false)
		return errors.Join(err, hub.StopRuntime())
	}
	if wasRunning {
		if err := startListeners(previous); err != nil {
			currentConfig = previous
			isRunning.Store(false)
			return errors.Join(err, hub.StopRuntime())
		}
		if err := syncGeoUpdater(true); err != nil {
			currentConfig = previous
			isRunning.Store(false)
			return errors.Join(err, hub.StopRuntime())
		}
	} else if err := hub.StopRuntime(); err != nil {
		currentConfig = previous
		isRunning.Store(false)
		return err
	}
	currentConfig = previous
	isRunning.Store(wasRunning)
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
