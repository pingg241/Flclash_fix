package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/dialer"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

func newExitTestSelector(t *testing.T, name string, members ...C.Proxy) C.Proxy {
	t.Helper()
	provider := newIdentityTestProvider(t, name+"-provider", members...)
	t.Cleanup(func() { _ = provider.Close() })
	return adapter.NewProxy(outboundgroup.NewSelector(
		&outboundgroup.GroupCommonOption{Name: name, URL: C.DefaultTestURL},
		members[0],
		[]P.ProxyProvider{provider},
	))
}

func newSimpleExitTestService(t *testing.T, generation uint64) (*proxyExitService, C.Proxy, C.Proxy) {
	t.Helper()
	leaf := newIdentityTestProxy("leaf", "provider")
	group := newExitTestSelector(t, "GROUP", leaf)
	snapshot := tunnel.ProxySnapshot{
		Generation: generation,
		ByID: map[string]C.Proxy{
			group.Id(): group,
			leaf.Id():  leaf,
		},
		Members: map[string][]C.Proxy{group.Id(): {leaf}},
	}
	geo := newTestProxyGeoService(generation)
	service := newProxyExitService(geo)
	service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
	return service, group, leaf
}

func setTestProxyExitEndpoints(t *testing.T, service *proxyExitService) {
	t.Helper()
	service.endpoints = nil
	for index, host := range []string{"one.example", "two.example", "three.example"} {
		endpoint, err := parseProxyExitEndpoint(
			"https://"+host+"/",
			fmt.Sprintf("test-%d", index),
		)
		if err != nil {
			t.Fatal(err)
		}
		service.endpoints = append(service.endpoints, endpoint)
	}
	service.endpoint = service.endpoints[0]
	service.endpoint.version = "test-set-v1"
	service.hedgeDelay = 5 * time.Millisecond
	service.slots = make(chan struct{}, 1)
}

func TestResolveProxyExitRouteUsesExactNestedMember(t *testing.T) {
	const generation = 21
	leafA := newIdentityTestProxy("same", "provider-a")
	leafB := newIdentityTestProxy("same", "provider-b")
	inner := newExitTestSelector(t, "INNER", leafA, leafB)
	if err := inner.Adapter().(*outboundgroup.Selector).SetByID(leafB.Id()); err != nil {
		t.Fatal(err)
	}
	outer := newExitTestSelector(t, "OUTER", inner)
	snapshot := tunnel.ProxySnapshot{
		Generation: generation,
		ByID: map[string]C.Proxy{
			outer.Id(): outer,
			inner.Id(): inner,
			leafA.Id(): leafA,
			leafB.Id(): leafB,
		},
		Members: map[string][]C.Proxy{
			outer.Id(): {inner},
			inner.Id(): {leafA, leafB},
		},
	}
	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER}
	if err := metadata.SetRemoteAddress("api64.ipify.org:443"); err != nil {
		t.Fatal(err)
	}
	leaf, path, routeSample, err := resolveProxyExitRoute(snapshot, ProbeProxyExitParams{
		Generation: generation,
		GroupID:    outer.Id(),
		MemberID:   inner.Id(),
	}, metadata)
	if err != nil {
		t.Fatal(err)
	}
	if leaf.Id() != leafB.Id() || routeSample {
		t.Fatalf("leaf = %q, routeSample = %v", leaf.Id(), routeSample)
	}
	wantPath := fmt.Sprintf("[%s %s %s]", outer.Id(), inner.Id(), leafB.Id())
	if got := fmt.Sprint(path); got != wantPath {
		t.Fatalf("path = %s, want %s", got, wantPath)
	}

	_, _, _, err = resolveProxyExitRoute(snapshot, ProbeProxyExitParams{
		Generation: generation,
		GroupID:    outer.Id(),
		MemberID:   leafA.Id(),
	}, metadata)
	if !errors.Is(err, errProxyExitInvalidMember) {
		t.Fatalf("invalid member error = %v", err)
	}
}

type fixedRouteGroup struct {
	outboundgroup.ProxyGroup
	next        C.Proxy
	adapterType C.AdapterType
}

type proxyWithDialerProxy struct {
	C.Proxy
}

func (p *proxyWithDialerProxy) ProxyInfo() C.ProxyInfo {
	info := p.Proxy.ProxyInfo()
	info.DialerProxy = "DYNAMIC"
	return info
}

type contextIgnoringDialProxy struct {
	C.Proxy
	started chan struct{}
	release chan struct{}
	once    sync.Once
}

func (p *contextIgnoringDialProxy) DialContext(
	_ context.Context,
	_ *C.Metadata,
) (C.Conn, error) {
	p.once.Do(func() { close(p.started) })
	<-p.release
	return nil, errors.New("blocked dial released")
}

func (g *fixedRouteGroup) Type() C.AdapterType {
	return g.adapterType
}

func (g *fixedRouteGroup) NowProxy() C.Proxy {
	return g.next
}

func (g *fixedRouteGroup) Unwrap(_ *C.Metadata, _ bool) C.Proxy {
	return g.next
}

func newFixedRouteGroup(t *testing.T, name string, adapterType C.AdapterType, fallback C.Proxy) (*fixedRouteGroup, C.Proxy) {
	t.Helper()
	base := newExitTestSelector(t, name+"-base", fallback)
	group := &fixedRouteGroup{
		ProxyGroup:  base.Adapter().(outboundgroup.ProxyGroup),
		adapterType: adapterType,
	}
	return group, adapter.NewProxy(group)
}

func TestProxyExitActionTimeoutSurvivesDialerIgnoringContext(t *testing.T) {
	for _, test := range []struct {
		name     string
		uncached bool
	}{
		{name: "fixed leaf"},
		{name: "dialer proxy leaf", uncached: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			const generation = 73
			started := make(chan struct{})
			release := make(chan struct{})
			var releaseOnce sync.Once
			releaseDial := func() { releaseOnce.Do(func() { close(release) }) }
			defer releaseDial()

			base := newIdentityTestProxy("leaf", "provider")
			blocking := &contextIgnoringDialProxy{
				Proxy:   base,
				started: started,
				release: release,
			}
			var leaf C.Proxy = blocking
			if test.uncached {
				leaf = &proxyWithDialerProxy{Proxy: blocking}
			}
			group := newExitTestSelector(t, "GROUP", leaf)
			snapshot := tunnel.ProxySnapshot{
				Generation: generation,
				ByID: map[string]C.Proxy{
					group.Id(): group,
					leaf.Id():  leaf,
				},
				Members: map[string][]C.Proxy{group.Id(): {leaf}},
			}
			service := newProxyExitService(newTestProxyGeoService(generation))
			service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
			service.timeout = 30 * time.Millisecond
			service.slots = make(chan struct{}, 1)

			type probeResult struct {
				response ProxyExitGeo
				err      error
			}
			result := make(chan probeResult, 1)
			go func() {
				response, err := service.probe(context.Background(), ProbeProxyExitParams{
					Generation: generation,
					GroupID:    group.Id(),
					MemberID:   leaf.Id(),
				})
				result <- probeResult{response: response, err: err}
			}()

			select {
			case <-started:
			case <-time.After(200 * time.Millisecond):
				t.Fatal("proxy exit dial did not start")
			}
			select {
			case got := <-result:
				if !errors.Is(got.err, context.DeadlineExceeded) {
					t.Fatalf("probe error = %v, want deadline exceeded", got.err)
				}
				if got.response.IP != "" {
					t.Fatalf("timed out probe returned IP %q", got.response.IP)
				}
			case <-time.After(200 * time.Millisecond):
				releaseDial()
				t.Fatal("proxy exit action did not honor its hard timeout")
			}

			deadline := time.Now().Add(200 * time.Millisecond)
			for {
				service.gate.mu.Lock()
				pending := len(service.gate.entries)
				service.gate.mu.Unlock()
				if pending == 0 {
					break
				}
				if time.Now().After(deadline) {
					t.Fatalf("proxy exit gate retained %d timed out entries", pending)
				}
				time.Sleep(time.Millisecond)
			}

			// The abandoned dial remains bounded by its worker slot until it
			// actually returns, instead of allowing unbounded stuck goroutines.
			if got := len(service.slots); got != 1 {
				t.Fatalf("worker slots in use = %d, want 1", got)
			}
			releaseDial()
			deadline = time.Now().Add(200 * time.Millisecond)
			for len(service.slots) != 0 && time.Now().Before(deadline) {
				time.Sleep(time.Millisecond)
			}
			if got := len(service.slots); got != 0 {
				t.Fatalf("worker slots in use after dial returned = %d", got)
			}

			service.fetch = func(
				context.Context,
				C.Proxy,
				*C.Metadata,
				proxyExitEndpoint,
			) (netip.Addr, error) {
				return netip.MustParseAddr("8.8.8.8"), nil
			}
			response, err := service.probe(context.Background(), ProbeProxyExitParams{
				Generation: generation,
				GroupID:    group.Id(),
				MemberID:   leaf.Id(),
			})
			if err != nil || response.IP != "8.8.8.8" {
				t.Fatalf("retry response = (%q, %v)", response.IP, err)
			}
		})
	}
}

func TestProxyExitFetchPanicReturnsErrorAndReleasesSlot(t *testing.T) {
	const generation = 74
	service, group, leaf := newSimpleExitTestService(t, generation)
	service.slots = make(chan struct{}, 1)
	service.fetch = func(
		context.Context,
		C.Proxy,
		*C.Metadata,
		proxyExitEndpoint,
	) (netip.Addr, error) {
		panic("test panic")
	}

	response, err := service.probe(context.Background(), ProbeProxyExitParams{
		Generation: generation,
		GroupID:    group.Id(),
		MemberID:   leaf.Id(),
	})
	if !errors.Is(err, errProxyExitRequest) || response.IP != "" {
		t.Fatalf("panic response = (%q, %v)", response.IP, err)
	}
	if got := len(service.slots); got != 0 {
		t.Fatalf("worker slots in use after panic = %d", got)
	}
}

func TestProxyExitEndpointRaceReturnsFirstValidResult(t *testing.T) {
	const generation = 75
	service, group, leaf := newSimpleExitTestService(t, generation)
	setTestProxyExitEndpoints(t, service)
	releaseLoser := make(chan struct{})
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(releaseLoser) }) }
	defer release()
	var calls [3]atomic.Int32
	service.fetch = func(
		ctx context.Context,
		_ C.Proxy,
		metadata *C.Metadata,
		endpoint proxyExitEndpoint,
	) (netip.Addr, error) {
		if metadata.RemoteAddress() != endpoint.hostPort {
			return netip.Addr{}, errors.New("endpoint metadata mismatch")
		}
		switch endpoint.serverName {
		case "one.example":
			calls[0].Add(1)
			<-releaseLoser
			return netip.Addr{}, errProxyExitRequest
		case "two.example":
			calls[1].Add(1)
			return netip.MustParseAddr("8.8.8.8"), nil
		default:
			calls[2].Add(1)
			return netip.MustParseAddr("1.1.1.1"), nil
		}
	}

	response, err := service.probe(context.Background(), ProbeProxyExitParams{
		Generation: generation,
		GroupID:    group.Id(),
		MemberID:   leaf.Id(),
	})
	if err != nil || response.IP != "8.8.8.8" {
		t.Fatalf("endpoint race response = (%q, %v)", response.IP, err)
	}
	if calls[0].Load() != 1 || calls[1].Load() != 1 || calls[2].Load() != 0 {
		t.Fatalf("endpoint calls = [%d %d %d]", calls[0].Load(), calls[1].Load(), calls[2].Load())
	}
	if got := len(service.slots); got != 1 {
		t.Fatalf("winner waited for context-ignoring loser, slots = %d", got)
	}
	release()
	deadline := time.Now().Add(200 * time.Millisecond)
	for len(service.slots) != 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := len(service.slots); got != 0 {
		t.Fatalf("worker slots after loser cleanup = %d", got)
	}
}

func TestProxyExitEndpointRaceReturnsAfterAllFail(t *testing.T) {
	const generation = 76
	service, group, leaf := newSimpleExitTestService(t, generation)
	setTestProxyExitEndpoints(t, service)
	var calls atomic.Int32
	service.fetch = func(
		context.Context,
		C.Proxy,
		*C.Metadata,
		proxyExitEndpoint,
	) (netip.Addr, error) {
		calls.Add(1)
		return netip.Addr{}, errProxyExitRequest
	}

	response, err := service.probe(context.Background(), ProbeProxyExitParams{
		Generation: generation,
		GroupID:    group.Id(),
		MemberID:   leaf.Id(),
	})
	if !errors.Is(err, errProxyExitRequest) || response.IP != "" {
		t.Fatalf("all-fail response = (%q, %v)", response.IP, err)
	}
	if got := calls.Load(); got != int32(len(service.endpoints)) {
		t.Fatalf("endpoint calls = %d, want %d", got, len(service.endpoints))
	}
	if got := len(service.slots); got != 0 {
		t.Fatalf("worker slots after all-fail = %d", got)
	}
}

func TestProxyExitEndpointRaceSharesHardTimeoutAndBoundsOrphans(t *testing.T) {
	const generation = 77
	service, group, leaf := newSimpleExitTestService(t, generation)
	setTestProxyExitEndpoints(t, service)
	service.timeout = 30 * time.Millisecond
	release := make(chan struct{})
	var releaseOnce sync.Once
	releaseAll := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseAll()
	started := make(chan struct{})
	var calls atomic.Int32
	service.fetch = func(
		context.Context,
		C.Proxy,
		*C.Metadata,
		proxyExitEndpoint,
	) (netip.Addr, error) {
		if calls.Add(1) == int32(len(service.endpoints)) {
			close(started)
		}
		<-release
		return netip.Addr{}, errProxyExitRequest
	}

	result := make(chan error, 1)
	go func() {
		_, err := service.probe(context.Background(), ProbeProxyExitParams{
			Generation: generation,
			GroupID:    group.Id(),
			MemberID:   leaf.Id(),
		})
		result <- err
	}()
	select {
	case <-started:
	case <-time.After(200 * time.Millisecond):
		t.Fatal("all endpoint attempts did not start")
	}
	select {
	case err := <-result:
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("timeout error = %v", err)
		}
	case <-time.After(200 * time.Millisecond):
		releaseAll()
		t.Fatal("endpoint race exceeded its shared hard timeout")
	}
	deadline := time.Now().Add(200 * time.Millisecond)
	pending := 0
	for {
		service.gate.mu.Lock()
		pending = len(service.gate.entries)
		service.gate.mu.Unlock()
		if pending == 0 || time.Now().After(deadline) {
			break
		}
		time.Sleep(time.Millisecond)
	}
	if pending != 0 || len(service.slots) != 1 {
		t.Fatalf("timeout resources = gate:%d slots:%d", pending, len(service.slots))
	}

	releaseAll()
	deadline = time.Now().Add(200 * time.Millisecond)
	for len(service.slots) != 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := len(service.slots); got != 0 {
		t.Fatalf("worker slots after orphan cleanup = %d", got)
	}
}

func TestProxyExitEndpointRaceBoundsUnderlyingAttempts(t *testing.T) {
	service, _, leaf := newSimpleExitTestService(t, 78)
	setTestProxyExitEndpoints(t, service)
	service.slots = make(chan struct{}, proxyExitConcurrency)
	release := make(chan struct{})
	var releaseOnce sync.Once
	releaseAll := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseAll()
	started := make(chan struct{})
	var calls atomic.Int32
	service.fetch = func(
		context.Context,
		C.Proxy,
		*C.Metadata,
		proxyExitEndpoint,
	) (netip.Addr, error) {
		if calls.Add(1) == proxyExitConcurrency*int32(len(service.endpoints)) {
			close(started)
		}
		<-release
		return netip.Addr{}, errProxyExitRequest
	}
	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER}
	if err := metadata.SetRemoteAddress(service.endpoint.hostPort); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	var wg sync.WaitGroup
	for range proxyExitConcurrency + 1 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, _ = service.probeWithLimit(ctx, leaf, metadata.Clone())
		}()
	}
	select {
	case <-started:
	case <-time.After(200 * time.Millisecond):
		t.Fatalf("underlying attempts = %d, want %d", calls.Load(), proxyExitConcurrency*len(service.endpoints))
	}
	wg.Wait()
	if got, limit := calls.Load(), proxyExitConcurrency*int32(len(service.endpoints)); got > limit {
		t.Fatalf("underlying attempts = %d, limit %d", got, limit)
	}
	if got := len(service.slots); got != proxyExitConcurrency {
		t.Fatalf("bounded worker slots = %d, want %d", got, proxyExitConcurrency)
	}
	releaseAll()
	deadline := time.Now().Add(200 * time.Millisecond)
	for len(service.slots) != 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := len(service.slots); got != 0 {
		t.Fatalf("worker slots after bounded cleanup = %d", got)
	}
}

func TestResolveProxyExitRouteRejectsCycleAndDepth(t *testing.T) {
	fallback := newIdentityTestProxy("fallback", "provider")
	groupAAdapter, groupA := newFixedRouteGroup(t, "A", C.Selector, fallback)
	groupBAdapter, groupB := newFixedRouteGroup(t, "B", C.Selector, fallback)
	groupAAdapter.next = groupB
	groupBAdapter.next = groupA
	cycleSnapshot := tunnel.ProxySnapshot{
		Generation: 1,
		ByID:       map[string]C.Proxy{groupA.Id(): groupA, groupB.Id(): groupB},
		Members: map[string][]C.Proxy{
			groupA.Id(): {groupB},
			groupB.Id(): {groupA},
		},
	}
	_, _, _, err := resolveProxyExitRoute(cycleSnapshot, ProbeProxyExitParams{
		Generation: 1,
		GroupID:    groupA.Id(),
		MemberID:   groupB.Id(),
	}, &C.Metadata{})
	if !errors.Is(err, errProxyExitCycle) {
		t.Fatalf("cycle error = %v", err)
	}

	groups := make([]C.Proxy, proxyExitMaxDepth+2)
	adapters := make([]*fixedRouteGroup, len(groups))
	for i := range groups {
		adapters[i], groups[i] = newFixedRouteGroup(t, fmt.Sprintf("depth-%d", i), C.Selector, fallback)
	}
	depthSnapshot := tunnel.ProxySnapshot{
		Generation: 2,
		ByID:       make(map[string]C.Proxy, len(groups)+1),
		Members:    make(map[string][]C.Proxy, len(groups)),
	}
	for i, group := range groups {
		depthSnapshot.ByID[group.Id()] = group
		if i+1 < len(groups) {
			adapters[i].next = groups[i+1]
			depthSnapshot.Members[group.Id()] = []C.Proxy{groups[i+1]}
		} else {
			adapters[i].next = fallback
			depthSnapshot.Members[group.Id()] = []C.Proxy{fallback}
		}
	}
	depthSnapshot.ByID[fallback.Id()] = fallback
	_, _, _, err = resolveProxyExitRoute(depthSnapshot, ProbeProxyExitParams{
		Generation: 2,
		GroupID:    groups[0].Id(),
		MemberID:   groups[1].Id(),
	}, &C.Metadata{})
	if !errors.Is(err, errProxyExitDepth) {
		t.Fatalf("depth error = %v", err)
	}
}

func TestProxyExitFixedLeafCachesAndDoesNotTouchDelayHistory(t *testing.T) {
	const generation = 31
	service, group, leaf := newSimpleExitTestService(t, generation)
	var calls atomic.Int32
	service.fetch = func(_ context.Context, gotLeaf C.Proxy, metadata *C.Metadata, endpoint proxyExitEndpoint) (netip.Addr, error) {
		calls.Add(1)
		if gotLeaf.Id() != leaf.Id() || metadata.RemoteAddress() != endpoint.hostPort {
			return netip.Addr{}, errors.New("wrong exact leaf or endpoint")
		}
		return netip.MustParseAddr("8.8.8.8"), nil
	}
	params := ProbeProxyExitParams{Generation: generation, GroupID: group.Id(), MemberID: leaf.Id()}
	first, err := service.probe(context.Background(), params)
	if err != nil {
		t.Fatal(err)
	}
	second, err := service.probe(context.Background(), params)
	if err != nil {
		t.Fatal(err)
	}
	if first.Cached || !second.Cached || first.IP != "8.8.8.8" || second.IP != "8.8.8.8" || calls.Load() != 1 {
		t.Fatalf("first = %#v, second = %#v, calls = %d", first, second, calls.Load())
	}
	if histories := leaf.DelayHistory(); len(histories) != 0 {
		t.Fatalf("exit probe changed delay history: %#v", histories)
	}
}

func TestProxyExitLoadBalanceSampleIsNotCached(t *testing.T) {
	const generation = 41
	leaf := newIdentityTestProxy("leaf", "provider")
	loadBalanceAdapter, loadBalance := newFixedRouteGroup(t, "LB", C.LoadBalance, leaf)
	loadBalanceAdapter.next = leaf
	outer := newExitTestSelector(t, "OUTER", loadBalance)
	snapshot := tunnel.ProxySnapshot{
		Generation: generation,
		ByID: map[string]C.Proxy{
			outer.Id():       outer,
			loadBalance.Id(): loadBalance,
			leaf.Id():        leaf,
		},
		Members: map[string][]C.Proxy{
			outer.Id():       {loadBalance},
			loadBalance.Id(): {leaf},
		},
	}
	service := newProxyExitService(newTestProxyGeoService(generation))
	service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
	var calls atomic.Int32
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		calls.Add(1)
		return netip.MustParseAddr("1.1.1.1"), nil
	}
	params := ProbeProxyExitParams{Generation: generation, GroupID: outer.Id(), MemberID: loadBalance.Id()}
	for i := 0; i < 2; i++ {
		result, err := service.probe(context.Background(), params)
		if err != nil {
			t.Fatal(err)
		}
		if !result.RouteSample || result.Cached {
			t.Fatalf("load-balance result = %#v", result)
		}
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("load-balance fetches = %d, want 2", got)
	}
}

func TestProxyExitSingleflightAndGlobalConcurrency(t *testing.T) {
	const generation = 51
	service, group, leaf := newSimpleExitTestService(t, generation)
	var calls atomic.Int32
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		calls.Add(1)
		time.Sleep(30 * time.Millisecond)
		return netip.MustParseAddr("9.9.9.9"), nil
	}
	params := ProbeProxyExitParams{Generation: generation, GroupID: group.Id(), MemberID: leaf.Id()}
	start := make(chan struct{})
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			result, err := service.probe(context.Background(), params)
			if err != nil || result.IP != "9.9.9.9" {
				t.Errorf("result = %#v, err = %v", result, err)
			}
		}()
	}
	close(start)
	wg.Wait()
	if got := calls.Load(); got != 1 {
		t.Fatalf("singleflight fetches = %d, want 1", got)
	}

	var active atomic.Int32
	var maximum atomic.Int32
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		current := active.Add(1)
		for {
			old := maximum.Load()
			if current <= old || maximum.CompareAndSwap(old, current) {
				break
			}
		}
		time.Sleep(20 * time.Millisecond)
		active.Add(-1)
		return netip.MustParseAddr("9.9.9.9"), nil
	}
	metadata := &C.Metadata{}
	wg = sync.WaitGroup{}
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := service.probeWithLimit(context.Background(), leaf, metadata.Clone()); err != nil {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if got := maximum.Load(); got > proxyExitConcurrency {
		t.Fatalf("maximum exit concurrency = %d, want <= %d", got, proxyExitConcurrency)
	}
}

func TestProxyExitPendingGateIsBoundedAndReleases(t *testing.T) {
	gate := newProxyExitGate(proxyExitPendingLimit)
	for i := 0; i < proxyExitPendingLimit; i++ {
		key := fmt.Sprintf("key-%d", i)
		if !gate.acquire(key) {
			t.Fatalf("gate rejected key %d before limit", i)
		}
		gate.callbackStarted(key)
	}
	if gate.acquire("overflow") {
		t.Fatal("gate accepted a unique key above the pending limit")
	}
	for i := 0; i < proxyExitPendingLimit; i++ {
		key := fmt.Sprintf("key-%d", i)
		gate.callbackDone(key)
		gate.release(key)
	}
	if !gate.acquire("after-release") {
		t.Fatal("gate did not release capacity after callbacks completed")
	}
	gate.callbackStarted("after-release")
	gate.callbackDone("after-release")
	gate.release("after-release")
}

func TestProxyExitCacheBindsNetworkRevisionAndLatestRequestCancels(t *testing.T) {
	const generation = 53
	service, group, leaf := newSimpleExitTestService(t, generation)
	var calls atomic.Int32
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		calls.Add(1)
		return netip.MustParseAddr("9.9.9.9"), nil
	}
	for _, revision := range []uint64{1, 1, 2} {
		result, err := service.probe(context.Background(), ProbeProxyExitParams{
			Generation:      generation,
			NetworkRevision: revision,
			GroupID:         group.Id(),
			MemberID:        leaf.Id(),
		})
		if err != nil || result.IP != "9.9.9.9" {
			t.Fatalf("network revision %d result = %#v, err = %v", revision, result, err)
		}
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("network-bound exit calls = %d, want 2", got)
	}

	oldContext, finishOld, accepted := service.beginExitRun(context.Background(), 1)
	if !accepted {
		t.Fatal("old exit request was rejected")
	}
	defer finishOld()
	newContext, finishNew, accepted := service.beginExitRun(context.Background(), 2)
	if !accepted {
		t.Fatal("new exit request was rejected")
	}
	defer finishNew()
	select {
	case <-oldContext.Done():
	case <-time.After(time.Second):
		t.Fatal("new exit request did not cancel the old request")
	}
	if err := newContext.Err(); err != nil {
		t.Fatalf("new exit request was canceled: %v", err)
	}

	lateOldContext, finishLateOld, accepted := service.beginExitRun(context.Background(), 1)
	defer finishLateOld()
	if accepted {
		t.Fatal("late old exit request was accepted")
	}
	if lateOldContext.Err() == nil {
		t.Fatal("late old exit request context is live")
	}
	if err := newContext.Err(); err != nil {
		t.Fatalf("late old request canceled the latest request: %v", err)
	}
	response, err := service.probeForAction(
		context.Background(),
		ProbeProxyExitParams{
			Generation: generation,
			RequestID:  "late-old",
			GroupID:    group.Id(),
			MemberID:   leaf.Id(),
		},
		1,
	)
	if err != nil || !response.Stale || response.RequestID != "late-old" {
		t.Fatalf("late old response = %#v, err = %v", response, err)
	}
}

func TestProxyExitArrivalSequenceSurvivesReverseHandlerStart(t *testing.T) {
	service, _, _ := newSimpleExitTestService(t, 54)
	startOld := make(chan struct{})
	latestStarted := make(chan struct{})
	finishLatest := make(chan struct{})
	latestContext := make(chan context.Context, 1)
	oldAccepted := make(chan bool, 1)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		<-startOld
		_, finish, accepted := service.beginExitRun(context.Background(), 1)
		oldAccepted <- accepted
		finish()
	}()
	go func() {
		defer wg.Done()
		ctx, finish, accepted := service.beginExitRun(context.Background(), 2)
		if !accepted {
			t.Error("latest request was rejected")
			close(latestStarted)
			return
		}
		latestContext <- ctx
		close(latestStarted)
		<-finishLatest
		finish()
	}()

	<-latestStarted
	ctx := <-latestContext
	close(startOld)
	if accepted := <-oldAccepted; accepted {
		t.Error("older request was accepted after the latest request")
	}
	if err := ctx.Err(); err != nil {
		t.Errorf("older request canceled the latest request: %v", err)
	}
	close(finishLatest)
	wg.Wait()
}

func TestProxyExitSupersededActiveActionReturnsStale(t *testing.T) {
	const generation = 60
	service, group, leaf := newSimpleExitTestService(t, generation)
	started := make(chan struct{})
	var calls atomic.Int32
	service.fetch = func(ctx context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		if calls.Add(1) == 1 {
			close(started)
			<-ctx.Done()
			return netip.Addr{}, ctx.Err()
		}
		return netip.MustParseAddr("9.9.9.9"), nil
	}
	type actionResult struct {
		response ProxyExitGeo
		err      error
	}
	oldResult := make(chan actionResult, 1)
	go func() {
		response, err := service.probeForAction(
			context.Background(),
			ProbeProxyExitParams{
				Generation: generation,
				RequestID:  "old",
				GroupID:    group.Id(),
				MemberID:   leaf.Id(),
			},
			100,
		)
		oldResult <- actionResult{response: response, err: err}
	}()
	<-started

	latest, err := service.probeForAction(
		context.Background(),
		ProbeProxyExitParams{
			Generation: generation,
			RequestID:  "latest",
			GroupID:    group.Id(),
			MemberID:   leaf.Id(),
		},
		101,
	)
	if err != nil || latest.Stale || latest.IP != "9.9.9.9" {
		t.Fatalf("latest response = %#v, err = %v", latest, err)
	}
	select {
	case old := <-oldResult:
		if old.err != nil || !old.response.Stale || old.response.RequestID != "old" || old.response.IP != "" {
			t.Fatalf("superseded response = %#v, err = %v", old.response, old.err)
		}
	case <-time.After(time.Second):
		t.Fatal("superseded proxy exit action did not finish")
	}
}

func TestProxyExitDiscardsChangedFixedRoutes(t *testing.T) {
	t.Run("top-level selection", func(t *testing.T) {
		const generation = 55
		leafA := newIdentityTestProxy("leaf-a", "provider")
		leafB := newIdentityTestProxy("leaf-b", "provider")
		group := newExitTestSelector(t, "GROUP", leafA, leafB)
		snapshot := tunnel.ProxySnapshot{
			Generation: generation,
			ByID: map[string]C.Proxy{
				group.Id(): group,
				leafA.Id(): leafA,
				leafB.Id(): leafB,
			},
			Members: map[string][]C.Proxy{group.Id(): {leafA, leafB}},
		}
		service := newProxyExitService(newTestProxyGeoService(generation))
		service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
		started := make(chan struct{})
		release := make(chan struct{})
		service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
			close(started)
			<-release
			return netip.MustParseAddr("8.8.8.8"), nil
		}
		resultChannel := make(chan ProxyExitGeo, 1)
		errorChannel := make(chan error, 1)
		go func() {
			result, err := service.probe(context.Background(), ProbeProxyExitParams{
				Generation: generation,
				GroupID:    group.Id(),
				MemberID:   leafA.Id(),
			})
			resultChannel <- result
			errorChannel <- err
		}()
		<-started
		if err := group.Adapter().(*outboundgroup.Selector).SetByID(leafB.Id()); err != nil {
			t.Fatal(err)
		}
		close(release)
		result := <-resultChannel
		if err := <-errorChannel; err != nil {
			t.Fatal(err)
		}
		if !result.Stale || result.IP != "" {
			t.Fatalf("changed top-level route result = %#v", result)
		}
	})

	t.Run("nested selection", func(t *testing.T) {
		const generation = 56
		leafA := newIdentityTestProxy("leaf-a", "provider")
		leafB := newIdentityTestProxy("leaf-b", "provider")
		inner := newExitTestSelector(t, "INNER", leafA, leafB)
		outer := newExitTestSelector(t, "OUTER", inner)
		snapshot := tunnel.ProxySnapshot{
			Generation: generation,
			ByID: map[string]C.Proxy{
				outer.Id(): outer,
				inner.Id(): inner,
				leafA.Id(): leafA,
				leafB.Id(): leafB,
			},
			Members: map[string][]C.Proxy{
				outer.Id(): {inner},
				inner.Id(): {leafA, leafB},
			},
		}
		service := newProxyExitService(newTestProxyGeoService(generation))
		service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
		started := make(chan struct{})
		release := make(chan struct{})
		service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
			close(started)
			<-release
			return netip.MustParseAddr("8.8.8.8"), nil
		}
		resultChannel := make(chan ProxyExitGeo, 1)
		errorChannel := make(chan error, 1)
		go func() {
			result, err := service.probe(context.Background(), ProbeProxyExitParams{
				Generation: generation,
				GroupID:    outer.Id(),
				MemberID:   inner.Id(),
			})
			resultChannel <- result
			errorChannel <- err
		}()
		<-started
		if err := inner.Adapter().(*outboundgroup.Selector).SetByID(leafB.Id()); err != nil {
			t.Fatal(err)
		}
		close(release)
		result := <-resultChannel
		if err := <-errorChannel; err != nil {
			t.Fatal(err)
		}
		if !result.Stale || result.IP != "" {
			t.Fatalf("changed nested route result = %#v", result)
		}
	})
}

func TestProxyExitLoadBalanceRejectsChangedTopLevelSelection(t *testing.T) {
	const generation = 57
	leaf := newIdentityTestProxy("leaf", "provider")
	other := newIdentityTestProxy("other", "provider")
	loadBalanceAdapter, loadBalance := newFixedRouteGroup(t, "LB", C.LoadBalance, leaf)
	loadBalanceAdapter.next = leaf
	outer := newExitTestSelector(t, "OUTER", loadBalance, other)
	snapshot := tunnel.ProxySnapshot{
		Generation: generation,
		ByID: map[string]C.Proxy{
			outer.Id():       outer,
			loadBalance.Id(): loadBalance,
			leaf.Id():        leaf,
			other.Id():       other,
		},
		Members: map[string][]C.Proxy{
			outer.Id():       {loadBalance, other},
			loadBalance.Id(): {leaf},
		},
	}
	service := newProxyExitService(newTestProxyGeoService(generation))
	service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
	started := make(chan struct{})
	release := make(chan struct{})
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		close(started)
		<-release
		return netip.MustParseAddr("1.1.1.1"), nil
	}
	resultChannel := make(chan ProxyExitGeo, 1)
	go func() {
		result, _ := service.probe(context.Background(), ProbeProxyExitParams{
			Generation: generation,
			GroupID:    outer.Id(),
			MemberID:   loadBalance.Id(),
		})
		resultChannel <- result
	}()
	<-started
	if err := outer.Adapter().(*outboundgroup.Selector).SetByID(other.Id()); err != nil {
		t.Fatal(err)
	}
	close(release)
	result := <-resultChannel
	if !result.Stale || !result.RouteSample || result.IP != "" {
		t.Fatalf("changed load-balance top-level result = %#v", result)
	}
}

func TestProxyExitDialerProxyIsNeverCached(t *testing.T) {
	const generation = 58
	leaf := &proxyWithDialerProxy{Proxy: newIdentityTestProxy("leaf", "provider")}
	group := newExitTestSelector(t, "GROUP", leaf)
	snapshot := tunnel.ProxySnapshot{
		Generation: generation,
		ByID:       map[string]C.Proxy{group.Id(): group, leaf.Id(): leaf},
		Members:    map[string][]C.Proxy{group.Id(): {leaf}},
	}
	service := newProxyExitService(newTestProxyGeoService(generation))
	service.snapshot = func() tunnel.ProxySnapshot { return snapshot }
	var calls atomic.Int32
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		calls.Add(1)
		return netip.MustParseAddr("8.8.8.8"), nil
	}
	params := ProbeProxyExitParams{Generation: generation, GroupID: group.Id(), MemberID: leaf.Id()}
	for i := 0; i < 2; i++ {
		result, err := service.probe(context.Background(), params)
		if err != nil || result.Cached || result.IP != "8.8.8.8" {
			t.Fatalf("dialer-proxy result = %#v, err = %v", result, err)
		}
	}
	if calls.Load() != 2 {
		t.Fatalf("dialer-proxy fetches = %d, want 2", calls.Load())
	}
}

func TestProxyExitCancelActiveStopsPendingAction(t *testing.T) {
	const generation = 59
	service, group, leaf := newSimpleExitTestService(t, generation)
	started := make(chan struct{})
	service.fetch = func(ctx context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		close(started)
		<-ctx.Done()
		return netip.Addr{}, ctx.Err()
	}
	result := make(chan error, 1)
	go func() {
		_, err := service.probeForAction(
			context.Background(),
			ProbeProxyExitParams{
				Generation: generation,
				RequestID:  "pending-exit",
				GroupID:    group.Id(),
				MemberID:   leaf.Id(),
			},
			100,
		)
		result <- err
	}()
	<-started
	service.cancelActive()
	select {
	case err := <-result:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("pending exit error = %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("pending exit action ignored lifecycle cancellation")
	}
}

func TestProxyExitDiscardsResultWhenSnapshotChanges(t *testing.T) {
	const generation = 61
	service, group, leaf := newSimpleExitTestService(t, generation)
	baseSnapshot := service.snapshot()
	var currentGeneration atomic.Uint64
	currentGeneration.Store(generation)
	service.snapshot = func() tunnel.ProxySnapshot {
		snapshot := baseSnapshot
		snapshot.Generation = currentGeneration.Load()
		return snapshot
	}
	service.fetch = func(_ context.Context, _ C.Proxy, _ *C.Metadata, _ proxyExitEndpoint) (netip.Addr, error) {
		currentGeneration.Store(generation + 1)
		return netip.MustParseAddr("8.8.8.8"), nil
	}
	result, err := service.probe(context.Background(), ProbeProxyExitParams{
		Generation: generation,
		GroupID:    group.Id(),
		MemberID:   leaf.Id(),
	})
	if err != nil {
		t.Fatal(err)
	}
	if !result.Stale || result.IP != "" {
		t.Fatalf("stale result = %#v", result)
	}
}

func TestReadProxyExitResponseRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name    string
		status  int
		body    string
		wantIP  string
		wantErr bool
	}{
		{name: "IPv4", status: http.StatusOK, body: "8.8.8.8\n", wantIP: "8.8.8.8"},
		{name: "IPv6", status: http.StatusOK, body: "2606:4700:4700::1111", wantIP: "2606:4700:4700::1111"},
		{name: "redirect", status: http.StatusFound, body: "8.8.8.8", wantErr: true},
		{name: "private", status: http.StatusOK, body: "10.0.0.1", wantErr: true},
		{name: "carrier grade NAT", status: http.StatusOK, body: "100.64.0.1", wantErr: true},
		{name: "IPv4 benchmark", status: http.StatusOK, body: "198.18.0.1", wantErr: true},
		{name: "IPv4 documentation", status: http.StatusOK, body: "203.0.113.1", wantErr: true},
		{name: "IPv4 reserved", status: http.StatusOK, body: "240.0.0.1", wantErr: true},
		{name: "IPv6 benchmark", status: http.StatusOK, body: "2001:2::1", wantErr: true},
		{name: "IPv6 documentation", status: http.StatusOK, body: "2001:db8::1", wantErr: true},
		{name: "loopback", status: http.StatusOK, body: "127.0.0.1", wantErr: true},
		{name: "link-local", status: http.StatusOK, body: "fe80::1", wantErr: true},
		{name: "zone", status: http.StatusOK, body: "fe80::1%eth0", wantErr: true},
		{name: "multicast", status: http.StatusOK, body: "ff02::1", wantErr: true},
		{name: "unspecified", status: http.StatusOK, body: "::", wantErr: true},
		{name: "oversize", status: http.StatusOK, body: strings.Repeat("1", proxyExitResponseLimit+1), wantErr: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			response := &http.Response{
				StatusCode: test.status,
				Body:       io.NopCloser(strings.NewReader(test.body)),
			}
			ip, err := readProxyExitResponse(response)
			if (err != nil) != test.wantErr || (!test.wantErr && ip.String() != test.wantIP) {
				t.Fatalf("response = (%s, %v)", ip, err)
			}
		})
	}
}

func TestProxyExitDirectDialUsesDefaultSocketHook(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	accepted := make(chan struct{})
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr == nil {
			close(accepted)
			_ = conn.Close()
		}
	}()

	oldHook := dialer.DefaultSocketHook
	var hookCalls atomic.Int32
	dialer.DefaultSocketHook = func(_ string, _ string, _ syscall.RawConn) error {
		hookCalls.Add(1)
		return nil
	}
	t.Cleanup(func() { dialer.DefaultSocketHook = oldHook })

	leaf := adapter.NewProxy(outbound.NewDirect())
	endpoint := proxyExitEndpoint{
		rawURL:     "https://" + listener.Addr().String() + "/",
		hostPort:   listener.Addr().String(),
		serverName: "127.0.0.1",
		version:    "test",
	}
	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER}
	if err := metadata.SetRemoteAddress(endpoint.hostPort); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, _ = fetchProxyExitIP(ctx, leaf, metadata, endpoint)
	select {
	case <-accepted:
	case <-ctx.Done():
		t.Fatal("direct exit dial did not reach local listener")
	}
	if got := hookCalls.Load(); got == 0 {
		t.Fatal("direct exit dial bypassed DefaultSocketHook")
	}
}
