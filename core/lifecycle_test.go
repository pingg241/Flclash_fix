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

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/ntp/ntp"
	"github.com/metacubex/mihomo/tunnel"
)

type failingCloseInboundConfig struct {
	name string
}

func (c failingCloseInboundConfig) Name() string {
	return c.name
}

func (c failingCloseInboundConfig) Equal(other constant.InboundConfig) bool {
	o, ok := other.(failingCloseInboundConfig)
	return ok && c == o
}

type failingCloseInbound struct {
	config   failingCloseInboundConfig
	closeErr error
}

func (l *failingCloseInbound) Name() string {
	return l.config.name
}

func (l *failingCloseInbound) Listen(constant.Tunnel) error {
	return nil
}

func (l *failingCloseInbound) Close() error {
	return l.closeErr
}

func (l *failingCloseInbound) Address() string {
	return ""
}

func (l *failingCloseInbound) RawAddress() string {
	return ""
}

func (l *failingCloseInbound) Config() constant.InboundConfig {
	return l.config
}

func TestRuntimeStartStopIsRepeatable(t *testing.T) {
	mixedPort := reserveTCPUDPPort(t)
	controllerPort := reserveTCPPort(t)
	dnsPort := reserveTCPUDPPort(t)
	tunnelPort := reserveTCPPort(t)
	ntpPort := startUDPEchoServer(t)

	home := t.TempDir()
	oldHome := constant.Path.HomeDir()
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	constant.SetHomeDir(home)
	currentConfig = nil
	isRunning.Store(false)
	t.Cleanup(func() {
		_ = corehub.StopRuntime()
		_ = cachefile.Cache().Close()
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		constant.SetHomeDir(oldHome)
	})

	raw := fmt.Sprintf(`
mixed-port: %d
external-controller: 127.0.0.1:%d
dns:
  enable: true
  listen: 127.0.0.1:%d
  nameserver:
    - 1.1.1.1
ntp:
  enable: true
  server: 127.0.0.1
  port: %d
  interval: 60
proxies:
  - name: test-direct
    type: direct
proxy-groups:
  - name: TEST
    type: select
    proxies:
      - DIRECT
      - test-direct
tunnels:
  - tcp,127.0.0.1:%d,127.0.0.1:9,DIRECT
rules:
  - MATCH,DIRECT
`, mixedPort, controllerPort, dnsPort, ntpPort, tunnelPort)
	if err := os.WriteFile(filepath.Join(home, "config.yaml"), []byte(raw), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := executor.ParseWithBytes([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	if err := corehub.ApplyConfig(cfg); err != nil {
		t.Fatal(err)
	}
	if err := startListeners(cfg); err != nil {
		t.Fatal(err)
	}
	currentConfig = cfg
	isRunning.Store(true)
	assertRuntimeReady(t, mixedPort, controllerPort, dnsPort, tunnelPort)

	group := tunnel.AllProxies()["TEST"].(*adapter.Proxy).ProxyAdapter.(outboundgroup.ProxyGroup)
	selectable := group.(outboundgroup.SelectAble)
	if err := selectable.Set("test-direct"); err != nil {
		t.Fatal(err)
	}

	for round := 0; round < 2; round++ {
		if !handleStopListener() {
			t.Fatalf("stop failed in round %d", round)
		}
		if !handleStopListener() {
			t.Fatalf("second stop failed in round %d", round)
		}
		if ntp.IsRunning() {
			t.Fatalf("NTP still running in round %d", round)
		}
		assertTCPPortFree(t, mixedPort)
		assertTCPPortFree(t, controllerPort)
		assertTCPUDPPortFree(t, dnsPort)
		assertTCPPortFree(t, tunnelPort)

		if !handleStartListener() {
			t.Fatalf("start failed in round %d", round)
		}
		if !handleStartListener() {
			t.Fatalf("second start failed in round %d", round)
		}
		assertRuntimeReady(t, mixedPort, controllerPort, dnsPort, tunnelPort)
		if !ntp.IsRunning() {
			t.Fatalf("NTP not restored in round %d", round)
		}
		if group.Now() != "test-direct" {
			t.Fatalf("proxy selection was reset in round %d: %s", round, group.Now())
		}
	}

	if !handleStopListener() {
		t.Fatal("stop before failure test failed")
	}
	blocker, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort))
	if err != nil {
		t.Fatal(err)
	}
	if handleStartListener() {
		_ = blocker.Close()
		t.Fatal("start unexpectedly succeeded with occupied mixed port")
	}
	if isRunning.Load() {
		_ = blocker.Close()
		t.Fatal("failed start marked runtime as running")
	}
	assertTCPPortFree(t, controllerPort)
	assertTCPUDPPortFree(t, dnsPort)
	assertTCPPortFree(t, tunnelPort)
	_ = blocker.Close()
	if !handleStartListener() {
		t.Fatal("runtime did not recover after failed start")
	}
}

func TestStopFailureRestoresPreviousRuntimeState(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte(`
mixed-port: 0
rules:
  - MATCH,DIRECT
`))
	if err != nil {
		t.Fatal(err)
	}
	inbound := &failingCloseInbound{
		config:   failingCloseInboundConfig{name: "failing-close"},
		closeErr: errors.New("close failed"),
	}
	cfg.Listeners = map[string]constant.InboundListener{
		inbound.Name(): inbound,
	}

	oldConfig, oldRunning := currentConfig, isRunning.Load()
	currentConfig = cfg
	isRunning.Store(true)
	if err := startListeners(cfg); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		inbound.closeErr = nil
		_ = corehub.StopRuntime()
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
	})

	if handleStopListener() {
		t.Fatal("stop unexpectedly reported success")
	}
	if !isRunning.Load() {
		t.Fatal("runtime was not restored after stop failure")
	}
	if err := startListeners(cfg); err != nil {
		t.Fatalf("restored runtime is not usable: %v", err)
	}
}

func assertRuntimeReady(t *testing.T, ports ...int) {
	t.Helper()
	for _, port := range ports {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), time.Second)
		if err != nil {
			t.Fatalf("port %d is not ready: %v", port, err)
		}
		_ = conn.Close()
	}
}

func reserveTCPPort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	_ = l.Close()
	return port
}

func reserveTCPUDPPort(t *testing.T) int {
	t.Helper()
	for {
		port := reserveTCPPort(t)
		p, err := net.ListenPacket("udp", fmt.Sprintf("127.0.0.1:%d", port))
		if err != nil {
			continue
		}
		_ = p.Close()
		return port
	}
}

func startUDPEchoServer(t *testing.T) int {
	t.Helper()
	p, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = p.Close() })
	go func() {
		buf := make([]byte, 512)
		for {
			n, addr, err := p.ReadFrom(buf)
			if err != nil {
				return
			}
			_, _ = p.WriteTo(buf[:n], addr)
		}
	}()
	return p.LocalAddr().(*net.UDPAddr).Port
}

func assertTCPPortFree(t *testing.T, port int) {
	t.Helper()
	l, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatalf("TCP port %d was not released: %v", port, err)
	}
	_ = l.Close()
}

func assertTCPUDPPortFree(t *testing.T, port int) {
	t.Helper()
	assertTCPPortFree(t, port)
	p, err := net.ListenPacket("udp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		t.Fatalf("UDP port %d was not released: %v", port, err)
	}
	_ = p.Close()
}
