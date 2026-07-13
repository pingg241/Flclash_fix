//go:build !cgo

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel"
)

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

func TestUpdateConfigAppliesAllowLan(t *testing.T) {
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = &config.Config{
		General:    &config.General{Inbound: config.Inbound{AllowLan: false}},
		Controller: &config.Controller{},
		TLS:        &config.TLS{},
	}
	isRunning.Store(false)
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
}

func TestUpdateConfigRollsBackGeoUpdaterFailure(t *testing.T) {
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldRegister, oldCancel := registerGeoUpdater, cancelGeoUpdater
	oldAutoUpdate := updater.GeoAutoUpdate()
	currentConfig = &config.Config{
		General:    &config.General{},
		Controller: &config.Controller{},
		TLS:        &config.TLS{},
	}
	isRunning.Store(false)
	updater.SetGeoAutoUpdate(false)
	cancelCalls := 0
	cancelGeoUpdater = func() error {
		cancelCalls++
		if cancelCalls == 1 {
			return errors.New("cancel updater failed")
		}
		return nil
	}
	registerGeoUpdater = func() error { return nil }
	t.Cleanup(func() {
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		registerGeoUpdater = oldRegister
		cancelGeoUpdater = oldCancel
		updater.SetGeoAutoUpdate(oldAutoUpdate)
	})

	enabled := true
	if err := updateConfig(&UpdateParams{GeoAutoUpdate: &enabled}); err == nil {
		t.Fatal("expected updater cancellation failure to reject config")
	}
	if currentConfig.General.GeoAutoUpdate || updater.GeoAutoUpdate() {
		t.Fatal("failed updater transition was not rolled back")
	}
	if cancelCalls != 2 {
		t.Fatalf("updater cancellation calls = %d, want 2", cancelCalls)
	}
}

func TestSyncGeoUpdaterCancelsDisabledUpdater(t *testing.T) {
	oldRegister, oldCancel := registerGeoUpdater, cancelGeoUpdater
	oldAutoUpdate := updater.GeoAutoUpdate()
	registerCalls, cancelCalls := 0, 0
	registerGeoUpdater = func() error {
		registerCalls++
		return nil
	}
	cancelGeoUpdater = func() error {
		cancelCalls++
		return nil
	}
	t.Cleanup(func() {
		registerGeoUpdater = oldRegister
		cancelGeoUpdater = oldCancel
		updater.SetGeoAutoUpdate(oldAutoUpdate)
	})

	updater.SetGeoAutoUpdate(false)
	if err := syncGeoUpdater(true); err != nil {
		t.Fatal(err)
	}
	if registerCalls != 0 || cancelCalls != 1 {
		t.Fatalf("register/cancel calls = %d/%d, want 0/1", registerCalls, cancelCalls)
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
  - name: second-rejected-proxy
    type: direct
rules:
  - MATCH,second-rejected-proxy
`, failedDNSPort)
	if err := os.WriteFile(configPath, []byte(second), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(defaultSetupParams()); err == nil {
		t.Fatal("expected occupied DNS port to reject second config")
	}
	proxies := tunnel.AllProxies()
	if proxies["rejected-proxy"] != nil || proxies["second-rejected-proxy"] != nil {
		t.Fatal("failed config resurrected a rejected proxy set")
	}
	assertTCPUnavailable(t, dnsPort)
}

func assertTCPUnavailable(t *testing.T, port int) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 100*time.Millisecond)
	if err == nil {
		_ = conn.Close()
		t.Fatalf("TCP port %d is still listening", port)
	}
}
