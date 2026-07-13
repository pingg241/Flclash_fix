package main

import (
	b "bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/batch"
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
	currentConfig *config.Config
	version       = 0
	isRunning     = false
	runLock       sync.Mutex
	mBatch, _     = batch.New[bool](context.Background(), batch.WithConcurrencyNum[bool](30))
	debugError    = false
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

// resolveSafePath ensures path is absolute and stays under the core home dir.
func resolveSafePath(path string) (string, error) {
	home := constant.Path.HomeDir()
	if home == "" {
		return "", errors.New("home dir not set")
	}
	absHome, err := filepath.Abs(home)
	if err != nil {
		return "", err
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	// Clean + separator-aware prefix check (handles Windows + Unix).
	absHome = filepath.Clean(absHome)
	absPath = filepath.Clean(absPath)
	rel, err := filepath.Rel(absHome, absPath)
	if err != nil {
		return "", errPathOutsideHome
	}
	if rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", errPathOutsideHome
	}
	return absPath, nil
}

func updateListeners() {
	if !isRunning {
		return
	}
	if currentConfig == nil {
		return
	}
	listeners := currentConfig.Listeners
	general := currentConfig.General
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
	listener.ReCreateRedir(general.RedirPort, tunnel.Tunnel)
	listener.ReCreateTProxy(general.TProxyPort, tunnel.Tunnel)
	listener.ReCreateMixed(general.MixedPort, tunnel.Tunnel)
	listener.ReCreateShadowSocks(general.ShadowSocksConfig, tunnel.Tunnel)
	listener.ReCreateVmess(general.VmessConfig, tunnel.Tunnel)
	listener.ReCreateTuic(general.TuicServer, tunnel.Tunnel)
	if !features.Android {
		listener.ReCreateTun(general.Tun, tunnel.Tunnel)
	}
}

func stopListeners() {
	listener.StopListener()
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
	safe, err := resolveSafePath(path)
	if err != nil {
		return nil, err
	}
	return os.ReadFile(safe)
}

func updateConfig(params *UpdateParams) {
	runLock.Lock()
	defer runLock.Unlock()
	if currentConfig == nil {
		return
	}
	general := currentConfig.General
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
		route.ReCreateServer(&route.Config{
			Addr: currentConfig.Controller.ExternalController,
		})
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
		updater.SetGeoAutoUpdate(*params.GeoAutoUpdate)
	}
	if params.GeoUpdateInterval != nil {
		updater.SetGeoUpdateInterval(*params.GeoUpdateInterval)
	}

	updateListeners()
	if updater.GeoAutoUpdate() {
		updater.RegisterGeoUpdaterWithCancel()
	}
}

func applyConfig(params *SetupParams) error {
	runLock.Lock()
	defer runLock.Unlock()
	var err error
	constant.DefaultTestURL = params.TestURL
	currentConfig, err = executor.ParseWithPath(filepath.Join(constant.Path.HomeDir(), "config.yaml"))
	if err != nil {
		defaultCfg, defaultErr := config.ParseRawConfig(config.DefaultRawConfig())
		if defaultErr != nil {
			return err
		}
		currentConfig = defaultCfg
		// Parse failed but default config applied successfully.
		err = nil
	}
	hub.ApplyConfig(currentConfig)
	patchSelectGroup(params.SelectedMap)
	updateListeners()
	if updater.GeoAutoUpdate() {
		updater.RegisterGeoUpdaterWithCancel()
	}
	// GC off the critical path so setup/apply is not blocked by a full STW.
	go runtime.GC()
	return err
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
