//go:build !cgo

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
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

type fakeRuntimeStartTransaction struct {
	commit   func() error
	rollback func() error
}

func (tx *fakeRuntimeStartTransaction) Commit() error {
	return tx.commit()
}

func (tx *fakeRuntimeStartTransaction) Rollback() error {
	return tx.rollback()
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
	if err := verifyRuntimeListeners(cfg); err != nil {
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

func TestStopStartAdvancesRuntimeEpochWhenStateReturns(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte(`
mixed-port: 0
rules:
  - MATCH,DIRECT
`))
	if err != nil {
		t.Fatal(err)
	}

	oldBegin, oldStop := beginCoreRuntimeStart, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	beginCoreRuntimeStart = func(candidate *config.Config) (runtimeStartTransaction, error) {
		if candidate != cfg {
			t.Fatal("start received an unexpected candidate")
		}
		return &fakeRuntimeStartTransaction{
			commit:   func() error { return nil },
			rollback: func() error { return nil },
		}, nil
	}
	stopCoreRuntime = func() error { return nil }
	currentConfig = cfg
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	t.Cleanup(func() {
		beginCoreRuntimeStart = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	epoch := runtimeStateEpoch.Load()
	if !handleStopListener() || isRunning.Load() {
		t.Fatal("stop did not leave the root runtime suspended")
	}
	if !handleStartListener() || !isRunning.Load() {
		t.Fatal("start did not restore the root runtime state")
	}
	if currentConfig != cfg {
		t.Fatal("stop/start changed the active config pointer")
	}
	if !runtimeStateChangedSince(epoch, cfg, true) {
		t.Fatal("stop/start returned the same business state without advancing the runtime epoch")
	}
}

func TestStopAndShutdownInvalidateBlockedRuntimeStart(t *testing.T) {
	tests := []struct {
		name     string
		shutdown bool
	}{
		{name: "stop"},
		{name: "shutdown", shutdown: true},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cfg := &config.Config{}
			beginStarted := make(chan struct{})
			releaseBegin := make(chan struct{})
			var releaseOnce sync.Once
			rollbackCalls := 0

			oldBegin := beginCoreRuntimeStart
			oldStop := stopCoreRuntime
			oldDiscard := discardCoreConfig
			oldShutdown := shutdownCore
			oldConfig := currentConfig
			oldRunning := isRunning.Load()
			oldInit := isInit.Load()
			oldCleanupPending := runtimeCleanupPending.Load()
			oldStartGeneration := runtimeStartGen.Load()
			beginCoreRuntimeStart = func(candidate *config.Config) (runtimeStartTransaction, error) {
				if candidate != cfg {
					t.Fatal("start received an unexpected candidate")
				}
				close(beginStarted)
				<-releaseBegin
				return &fakeRuntimeStartTransaction{
					commit: func() error {
						t.Fatal("stale runtime start was committed")
						return nil
					},
					rollback: func() error {
						rollbackCalls++
						return nil
					},
				}, nil
			}
			stopCoreRuntime = func() error { return nil }
			discardCoreConfig = func() error { return nil }
			shutdownCore = func() {}
			currentConfig = cfg
			isRunning.Store(false)
			isInit.Store(true)
			runtimeCleanupPending.Store(false)
			startDone := make(chan struct{})
			t.Cleanup(func() {
				releaseOnce.Do(func() { close(releaseBegin) })
				select {
				case <-startDone:
				case <-time.After(time.Second):
				}
				beginCoreRuntimeStart = oldBegin
				stopCoreRuntime = oldStop
				discardCoreConfig = oldDiscard
				shutdownCore = oldShutdown
				currentConfig = oldConfig
				isRunning.Store(oldRunning)
				isInit.Store(oldInit)
				runtimeCleanupPending.Store(oldCleanupPending)
				runtimeStartGen.Store(oldStartGeneration)
			})

			startResult := make(chan bool, 1)
			go func() {
				defer close(startDone)
				startResult <- handleStartListener()
			}()
			select {
			case <-beginStarted:
			case <-time.After(time.Second):
				t.Fatal("runtime start did not enter preparation")
			}

			controlResult := make(chan bool, 1)
			go func() {
				if test.shutdown {
					controlResult <- handleShutdown()
					return
				}
				controlResult <- handleStopListener()
			}()
			select {
			case success := <-controlResult:
				if !success {
					t.Fatal("control action failed")
				}
			case <-time.After(time.Second):
				t.Fatal("control action waited for blocked runtime preparation")
			}

			releaseOnce.Do(func() { close(releaseBegin) })
			select {
			case success := <-startResult:
				if success {
					t.Fatal("stale runtime start succeeded after control action")
				}
			case <-time.After(time.Second):
				t.Fatal("stale runtime start did not finish")
			}
			if rollbackCalls != 1 {
				t.Fatalf("stale runtime rollback calls = %d, want 1", rollbackCalls)
			}
			if isRunning.Load() {
				t.Fatal("stale runtime start revived the runtime")
			}
			if test.shutdown && currentConfig != nil {
				t.Fatal("stale runtime start restored config after shutdown")
			}
		})
	}
}

func TestCoreStartBeginFailureDoesNotRepeatMetaCleanupAndKeepsCandidate(t *testing.T) {
	cfg, err := executor.ParseWithBytes([]byte(`
mixed-port: 0
proxies:
  - name: candidate
    type: direct
rules:
  - MATCH,candidate
`))
	if err != nil {
		t.Fatal(err)
	}
	oldBegin, oldStop := beginCoreRuntimeStart, stopCoreRuntime
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	beginCalls, stopCalls := 0, 0
	beginCoreRuntimeStart = func(candidate *config.Config) (runtimeStartTransaction, error) {
		beginCalls++
		if candidate != cfg {
			t.Fatal("start received an unexpected candidate")
		}
		return nil, errors.New("injected core start failure")
	}
	stopCoreRuntime = func() error {
		stopCalls++
		return errors.New("injected cleanup failure")
	}
	currentConfig = cfg
	isRunning.Store(false)
	runtimeCleanupPending.Store(false)
	t.Cleanup(func() {
		beginCoreRuntimeStart = oldBegin
		stopCoreRuntime = oldStop
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	if handleStartListener() {
		t.Fatal("failed core start was reported as successful")
	}
	if beginCalls != 1 || stopCalls != 0 {
		t.Fatalf("begin/root cleanup calls = %d/%d, want 1/0", beginCalls, stopCalls)
	}
	if currentConfig != cfg || isRunning.Load() {
		t.Fatal("failed start discarded the candidate or marked it running")
	}
}

func TestHandleStartListenerFinalizesRuntimeTransaction(t *testing.T) {
	tests := []struct {
		name          string
		blockListener bool
		commitErr     error
		wantSuccess   bool
		wantCommit    int
		wantRollback  int
		wantStop      int
	}{
		{
			name:        "success",
			wantSuccess: true,
			wantCommit:  1,
		},
		{
			name:          "post-commit listener verification failure",
			blockListener: true,
			wantCommit:    1,
			wantStop:      1,
		},
		{
			name:         "activation failure",
			commitErr:    errors.New("injected activation failure"),
			wantCommit:   1,
			wantRollback: 1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			mixedPort := 0
			var blocker net.Listener
			if test.blockListener {
				mixedPort = reserveTCPPort(t)
				var err error
				blocker, err = net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort))
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = blocker.Close() })
			}
			cfg, err := executor.ParseWithBytes([]byte(fmt.Sprintf(`
mixed-port: %d
rules:
  - MATCH,DIRECT
`, mixedPort)))
			if err != nil {
				t.Fatal(err)
			}

			oldBegin, oldStop := beginCoreRuntimeStart, stopCoreRuntime
			oldConfig, oldRunning := currentConfig, isRunning.Load()
			oldCleanupPending := runtimeCleanupPending.Load()
			beginCalls, commitCalls, rollbackCalls, stopCalls := 0, 0, 0, 0
			beginCoreRuntimeStart = func(candidate *config.Config) (runtimeStartTransaction, error) {
				beginCalls++
				if candidate != cfg {
					t.Fatal("begin received an unexpected candidate")
				}
				return &fakeRuntimeStartTransaction{
					commit: func() error {
						commitCalls++
						return test.commitErr
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
			currentConfig = cfg
			isRunning.Store(false)
			runtimeCleanupPending.Store(false)
			t.Cleanup(func() {
				beginCoreRuntimeStart = oldBegin
				stopCoreRuntime = oldStop
				currentConfig = oldConfig
				isRunning.Store(oldRunning)
				runtimeCleanupPending.Store(oldCleanupPending)
			})

			if got := handleStartListener(); got != test.wantSuccess {
				t.Fatalf("start result = %t, want %t", got, test.wantSuccess)
			}
			if beginCalls != 1 || commitCalls != test.wantCommit || rollbackCalls != test.wantRollback || stopCalls != test.wantStop {
				t.Fatalf(
					"begin/commit/rollback/stop calls = %d/%d/%d/%d, want 1/%d/%d/%d",
					beginCalls,
					commitCalls,
					rollbackCalls,
					stopCalls,
					test.wantCommit,
					test.wantRollback,
					test.wantStop,
				)
			}
			if isRunning.Load() != test.wantSuccess {
				t.Fatalf("running state = %t, want %t", isRunning.Load(), test.wantSuccess)
			}
		})
	}
}

func TestStopCleanupFailureCanBeRetriedWhileStopped(t *testing.T) {
	oldStop := stopCoreRuntime
	oldRunning := isRunning.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	stopCalls := 0
	stopCoreRuntime = func() error {
		stopCalls++
		if stopCalls == 1 {
			return errors.New("injected cleanup failure")
		}
		return nil
	}
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	t.Cleanup(func() {
		stopCoreRuntime = oldStop
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	if !handleStopListener() || isRunning.Load() {
		t.Fatal("first stop did not commit the stopped state")
	}
	if stopCalls != 1 || !runtimeCleanupPending.Load() {
		t.Fatalf("first stop calls/pending = %d/%t, want 1/true", stopCalls, runtimeCleanupPending.Load())
	}
	if !handleStopListener() {
		t.Fatal("cleanup retry was reported as a failed stop intent")
	}
	if stopCalls != 2 || runtimeCleanupPending.Load() {
		t.Fatalf("retry stop calls/pending = %d/%t, want 2/false", stopCalls, runtimeCleanupPending.Load())
	}
	if !handleStopListener() || stopCalls != 2 {
		t.Fatalf("clean stopped runtime performed another cleanup: calls = %d", stopCalls)
	}
}

func TestShutdownDiscardsConfigAndCompletesDespiteCleanupError(t *testing.T) {
	oldDiscard, oldShutdown := discardCoreConfig, shutdownCore
	oldConfig, oldRunning := currentConfig, isRunning.Load()
	oldInit := isInit.Load()
	oldCleanupPending := runtimeCleanupPending.Load()
	discardCalls, shutdownCalls := 0, 0
	discardCoreConfig = func() error {
		discardCalls++
		return errors.New("injected discard failure")
	}
	shutdownCore = func() {
		shutdownCalls++
	}
	currentConfig = &config.Config{}
	isRunning.Store(true)
	isInit.Store(true)
	runtimeCleanupPending.Store(true)
	t.Cleanup(func() {
		discardCoreConfig = oldDiscard
		shutdownCore = oldShutdown
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		isInit.Store(oldInit)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	if !handleShutdown() {
		t.Fatal("committed shutdown was reported as incomplete")
	}
	if discardCalls != 1 || shutdownCalls != 1 {
		t.Fatalf("discard/shutdown calls = %d/%d, want 1/1", discardCalls, shutdownCalls)
	}
	if currentConfig != nil || isRunning.Load() || isInit.Load() || runtimeCleanupPending.Load() {
		t.Fatal("shutdown did not clear root lifecycle state")
	}
}

func TestStopFailureKeepsRuntimeStopped(t *testing.T) {
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
	oldCleanupPending := runtimeCleanupPending.Load()
	currentConfig = cfg
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	listener.PatchInboundListeners(cfg.Listeners, tunnel.Tunnel, true)
	if err := verifyRuntimeListeners(cfg); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		inbound.closeErr = nil
		_ = corehub.StopRuntime()
		currentConfig = oldConfig
		isRunning.Store(oldRunning)
		runtimeCleanupPending.Store(oldCleanupPending)
	})

	if !handleStopListener() {
		t.Fatal("committed stop was reported as still running")
	}
	if isRunning.Load() {
		t.Fatal("stop failure restarted the runtime")
	}
	if !runtimeCleanupPending.Load() {
		t.Fatal("stop failure did not retain cleanup retry state")
	}
	inbound.closeErr = nil
	if !handleStopListener() || runtimeCleanupPending.Load() {
		t.Fatal("stopped runtime cleanup did not recover on retry")
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
