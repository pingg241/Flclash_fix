package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

func newTestProxyGeoService(generation uint64) *proxyGeoService {
	return &proxyGeoService{
		cache: newProxyGeoCache(serverGeoCacheEntries, serverGeoCacheByteBudget),
		now:   time.Now,
		snapshot: func() tunnel.ProxySnapshot {
			return tunnel.ProxySnapshot{Generation: generation}
		},
		resolve: func(_ context.Context, _ string) ([]netip.Addr, error) {
			return nil, errors.New("unexpected DNS lookup")
		},
		lookupCountry: func(_ net.IP) ([]string, error) {
			return []string{"US"}, nil
		},
		lookupASN: func(_ net.IP) (string, string, error) {
			return "15169", "Google LLC", nil
		},
		countryGen: func() uint64 { return 1 },
		asnGen:     func() uint64 { return 1 },
	}
}

type proxyWithServerAddress struct {
	C.Proxy
	address string
}

func (p *proxyWithServerAddress) Addr() string {
	return p.address
}

func TestNormalizedProxyServerHost(t *testing.T) {
	tests := []struct {
		name        string
		address     string
		wantHost    string
		wantSource  string
		wantSuccess bool
	}{
		{name: "IPv4", address: "1.2.3.4:443", wantHost: "1.2.3.4", wantSource: "literal", wantSuccess: true},
		{name: "mapped IPv4", address: "[::ffff:1.2.3.4]:443", wantHost: "1.2.3.4", wantSource: "literal", wantSuccess: true},
		{name: "IPv6", address: "[2001:0db8::1]:443", wantHost: "2001:db8::1", wantSource: "literal", wantSuccess: true},
		{name: "IDNA", address: "B\u00dcCHER.Example.:443", wantHost: "xn--bcher-kva.example", wantSource: "dns", wantSuccess: true},
		{name: "missing port", address: "example.com", wantSuccess: false},
		{name: "empty host", address: ":443", wantSuccess: false},
		{name: "zone", address: "[fe80::1%eth0]:443", wantSuccess: false},
		{name: "invalid IDNA", address: "bad host:443", wantSuccess: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			host, source, ok := normalizedProxyServerHost(test.address)
			if host != test.wantHost || source != test.wantSource || ok != test.wantSuccess {
				t.Fatalf("normalizedProxyServerHost(%q) = (%q, %q, %v)", test.address, host, source, ok)
			}
		})
	}
}

func TestNormalizeResolvedAddressesIsDeterministicAndBounded(t *testing.T) {
	input := []netip.Addr{
		netip.MustParseAddr("2001:db8::2"),
		netip.MustParseAddr("8.8.8.8"),
		netip.MustParseAddr("::ffff:8.8.8.8"),
		netip.Addr{},
		netip.IPv6Unspecified(),
		netip.MustParseAddr("2001:db8::1"),
	}
	got := normalizeResolvedAddresses(input)
	want := []netip.Addr{
		netip.MustParseAddr("8.8.8.8"),
		netip.MustParseAddr("2001:db8::1"),
		netip.MustParseAddr("2001:db8::2"),
	}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("addresses = %v, want %v", got, want)
	}

	many := make([]netip.Addr, serverGeoAddressLimit+10)
	for i := range many {
		many[i] = netip.AddrFrom4([4]byte{11, 0, 0, byte(i + 1)})
	}
	if got := len(normalizeResolvedAddresses(many)); got != serverGeoAddressLimit {
		t.Fatalf("address count = %d, want %d", got, serverGeoAddressLimit)
	}
}

func TestPopulateServerGeosDeduplicatesDNSAndBoundsWorkers(t *testing.T) {
	const generation = 7
	service := newTestProxyGeoService(generation)
	var calls atomic.Int32
	var active atomic.Int32
	var maximum atomic.Int32
	service.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
		calls.Add(1)
		current := active.Add(1)
		for {
			old := maximum.Load()
			if current <= old || maximum.CompareAndSwap(old, current) {
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
		active.Add(-1)
		return []netip.Addr{
			netip.MustParseAddr("2001:4860:4860::8888"),
			netip.MustParseAddr("8.8.8.8"),
			netip.MustParseAddr("8.8.8.8"),
		}, nil
	}

	members := make([]proxyServerMember, 0, 24)
	for i := 0; i < 12; i++ {
		host := fmt.Sprintf("host-%d.example", i)
		members = append(members,
			proxyServerMember{id: fmt.Sprintf("%d-a", i), host: host, source: "dns"},
			proxyServerMember{id: fmt.Sprintf("%d-b", i), host: host, source: "dns"},
		)
	}
	results := make(map[string]ProxyServerGeo)
	service.populateServerGeos(context.Background(), generation, 0, "", members, results)
	if got := calls.Load(); got != 12 {
		t.Fatalf("DNS calls = %d, want 12", got)
	}
	if got := maximum.Load(); got > serverGeoConcurrency {
		t.Fatalf("maximum DNS concurrency = %d, want <= %d", got, serverGeoConcurrency)
	}
	if got := len(results); got != len(members) {
		t.Fatalf("results = %d, want %d", got, len(members))
	}
	for id, result := range results {
		if result.Status != proxyGeoStatusOK || len(result.Addresses) != 2 ||
			result.Addresses[0].IP != "8.8.8.8" || result.Addresses[1].IP != "2001:4860:4860::8888" {
			t.Fatalf("result %s = %#v", id, result)
		}
	}
}

func TestServerGeoExplicitBatchesCoverThousandUniqueDomains(t *testing.T) {
	const (
		generation = 8
		nodeCount  = 1000
		batchSize  = 512
	)
	service := newTestProxyGeoService(generation)
	var calls atomic.Int32
	var active atomic.Int32
	var maximum atomic.Int32
	service.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
		calls.Add(1)
		current := active.Add(1)
		for {
			old := maximum.Load()
			if current <= old || maximum.CompareAndSwap(old, current) {
				break
			}
		}
		time.Sleep(time.Millisecond)
		active.Add(-1)
		return []netip.Addr{netip.MustParseAddr("8.8.8.8")}, nil
	}

	members := make([]proxyServerMember, nodeCount)
	for i := range members {
		members[i] = proxyServerMember{
			id:     fmt.Sprintf("node-%04d", i),
			host:   fmt.Sprintf("node-%04d.example", i),
			source: "dns",
		}
	}
	results := make(map[string]ProxyServerGeo, nodeCount)
	for offset := 0; offset < len(members); offset += batchSize {
		end := min(offset+batchSize, len(members))
		service.populateServerGeos(
			context.Background(),
			generation,
			0,
			fmt.Sprintf("batch-%d", offset/batchSize),
			members[offset:end],
			results,
		)
	}

	if got := calls.Load(); got != nodeCount {
		t.Fatalf("DNS calls = %d, want %d", got, nodeCount)
	}
	if got := maximum.Load(); got > serverGeoConcurrency {
		t.Fatalf("maximum DNS concurrency = %d, want <= %d", got, serverGeoConcurrency)
	}
	if got := len(results); got != nodeCount {
		t.Fatalf("results = %d, want %d", got, nodeCount)
	}
	for id, result := range results {
		if result.Status != proxyGeoStatusOK || len(result.Addresses) != 1 {
			t.Fatalf("result %s = %#v", id, result)
		}
	}
}

func TestLiteralServerGeoThousandNodesUsesNoDNSAndStaysBounded(t *testing.T) {
	const (
		generation = 9
		nodeCount  = 1000
	)
	service := newTestProxyGeoService(generation)
	var dnsCalls atomic.Int32
	var countryCalls atomic.Int32
	var asnCalls atomic.Int32
	service.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
		dnsCalls.Add(1)
		return nil, errors.New("unexpected DNS lookup")
	}
	service.lookupCountry = func(_ net.IP) ([]string, error) {
		countryCalls.Add(1)
		return []string{"US"}, nil
	}
	service.lookupASN = func(_ net.IP) (string, string, error) {
		asnCalls.Add(1)
		return "64500", "Example", nil
	}

	members := make([]proxyServerMember, nodeCount)
	for i := range members {
		ip := netip.AddrFrom4([4]byte{11, byte(i >> 16), byte(i >> 8), byte(i)})
		members[i] = proxyServerMember{id: fmt.Sprintf("node-%d", i), host: ip.String(), source: "literal"}
	}
	started := time.Now()
	service.populateServerGeos(context.Background(), generation, 0, "", members, make(map[string]ProxyServerGeo, nodeCount))
	firstDuration := time.Since(started)
	if got := dnsCalls.Load(); got != 0 {
		t.Fatalf("DNS calls = %d, want 0", got)
	}
	if got := countryCalls.Load(); got != nodeCount {
		t.Fatalf("country lookups = %d, want %d", got, nodeCount)
	}
	if got := asnCalls.Load(); got != nodeCount {
		t.Fatalf("ASN lookups = %d, want %d", got, nodeCount)
	}

	service.populateServerGeos(context.Background(), generation, 0, "", members, make(map[string]ProxyServerGeo, nodeCount))
	if got := countryCalls.Load(); got != nodeCount {
		t.Fatalf("cached country lookups = %d, want %d", got, nodeCount)
	}
	if got := asnCalls.Load(); got != nodeCount {
		t.Fatalf("cached ASN lookups = %d, want %d", got, nodeCount)
	}
	service.cache.mu.Lock()
	cacheBytes := service.cache.bytes
	cacheEntries := len(service.cache.items)
	service.cache.mu.Unlock()
	if cacheBytes > serverGeoCacheByteBudget || cacheBytes >= 1<<20 {
		t.Fatalf("cache bytes = %d", cacheBytes)
	}
	if cacheEntries > serverGeoCacheEntries {
		t.Fatalf("cache entries = %d", cacheEntries)
	}
	t.Logf("1000 literal nodes: first pass %s, cache %d bytes/%d entries", firstDuration, cacheBytes, cacheEntries)
}

func TestServerGeoCancellationDoesNotPoisonDNSCache(t *testing.T) {
	const generation = 11
	service := newTestProxyGeoService(generation)
	var calls atomic.Int32
	started := make(chan struct{})
	service.resolve = func(ctx context.Context, _ string) ([]netip.Addr, error) {
		if calls.Add(1) == 1 {
			close(started)
			<-ctx.Done()
			return nil, ctx.Err()
		}
		return []netip.Addr{netip.MustParseAddr("8.8.4.4")}, nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	statusChannel := make(chan string, 1)
	go func() {
		_, status := service.resolveServerHost(ctx, generation, 0, "", "example.com")
		statusChannel <- status
	}()
	<-started
	cancel()
	if status := <-statusChannel; status != proxyGeoStatusResolveError {
		t.Fatalf("canceled status = %q", status)
	}
	dnsKey := proxyGeoDNSCacheKey(generation, 0, service.databaseGeneration(), "example.com")
	if _, found := service.cache.get(dnsKey, time.Now()); found {
		t.Fatal("canceled resolution poisoned DNS cache")
	}
	addresses, status := service.resolveServerHost(context.Background(), generation, 0, "", "example.com")
	if status != proxyGeoStatusOK || len(addresses) != 1 || addresses[0].IP != "8.8.4.4" {
		t.Fatalf("second resolution = (%#v, %q)", addresses, status)
	}
	if got := calls.Load(); got != 2 {
		t.Fatalf("DNS calls = %d, want 2", got)
	}
}

func TestServerGeoRequestLimitsAndLatestCancellation(t *testing.T) {
	service := newTestProxyGeoService(12)
	memberIDs := make([]string, serverGeoMemberLimit+1)
	if _, err := service.getServerGeos(context.Background(), ProxyServerGeoParams{
		Generation: 12,
		MemberIDs:  memberIDs,
	}); err == nil {
		t.Fatal("oversized memberIds request was accepted")
	}
	tooManyLeaves := make(map[string]C.Proxy, serverGeoMemberLimit+1)
	for i := 0; i <= serverGeoMemberLimit; i++ {
		proxy := newIdentityTestProxy(fmt.Sprintf("leaf-%d", i), "provider")
		tooManyLeaves[proxy.Id()] = proxy
	}
	service.snapshot = func() tunnel.ProxySnapshot {
		return tunnel.ProxySnapshot{Generation: 12, ByID: tooManyLeaves}
	}
	if _, err := service.getServerGeos(context.Background(), ProxyServerGeoParams{
		Generation: 12,
		All:        true,
	}); err == nil {
		t.Fatal("oversized all-members request was accepted")
	}

	oldContext, finishOld, accepted := service.beginServerGeoRun(context.Background(), 1)
	if !accepted {
		t.Fatal("old server geo request was rejected")
	}
	defer finishOld()
	newContext, finishNew, accepted := service.beginServerGeoRun(context.Background(), 2)
	if !accepted {
		t.Fatal("new server geo request was rejected")
	}
	defer finishNew()
	select {
	case <-oldContext.Done():
	case <-time.After(time.Second):
		t.Fatal("new server geo request did not cancel the old request")
	}
	if err := newContext.Err(); err != nil {
		t.Fatalf("new server geo request was canceled: %v", err)
	}

	lateOldContext, finishLateOld, accepted := service.beginServerGeoRun(context.Background(), 1)
	defer finishLateOld()
	if accepted {
		t.Fatal("late old server geo request was accepted")
	}
	if lateOldContext.Err() == nil {
		t.Fatal("late old server geo request context is live")
	}
	if err := newContext.Err(); err != nil {
		t.Fatalf("late old request canceled the latest request: %v", err)
	}
	response, err := service.getServerGeosForAction(
		context.Background(),
		ProxyServerGeoParams{Generation: 12, RequestID: "late-old", MemberIDs: []string{"missing"}},
		1,
	)
	if err != nil || !response.Stale || response.RequestID != "late-old" {
		t.Fatalf("late old response = %#v, err = %v", response, err)
	}
}

func TestServerGeoArrivalSequenceSurvivesReverseHandlerStart(t *testing.T) {
	service := newTestProxyGeoService(14)
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
		_, finish, accepted := service.beginServerGeoRun(context.Background(), 1)
		oldAccepted <- accepted
		finish()
	}()
	go func() {
		defer wg.Done()
		ctx, finish, accepted := service.beginServerGeoRun(context.Background(), 2)
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

func TestServerGeoSupersededActiveActionReturnsStale(t *testing.T) {
	const generation = 15
	service := newTestProxyGeoService(generation)
	leaf := &proxyWithServerAddress{
		Proxy:   newIdentityTestProxy("leaf", "provider"),
		address: "example.com:443",
	}
	service.snapshot = func() tunnel.ProxySnapshot {
		return tunnel.ProxySnapshot{
			Generation: generation,
			ByID:       map[string]C.Proxy{leaf.Id(): leaf},
		}
	}
	started := make(chan struct{})
	service.resolve = func(ctx context.Context, _ string) ([]netip.Addr, error) {
		close(started)
		<-ctx.Done()
		return nil, ctx.Err()
	}
	type actionResult struct {
		response ProxyServerGeos
		err      error
	}
	oldResult := make(chan actionResult, 1)
	go func() {
		response, err := service.getServerGeosForAction(
			context.Background(),
			ProxyServerGeoParams{
				Generation: generation,
				RequestID:  "old",
				MemberIDs:  []string{leaf.Id()},
			},
			100,
		)
		oldResult <- actionResult{response: response, err: err}
	}()
	<-started

	latest, err := service.getServerGeosForAction(
		context.Background(),
		ProxyServerGeoParams{
			Generation: generation,
			RequestID:  "latest",
			MemberIDs:  []string{"missing"},
		},
		101,
	)
	if err != nil || latest.Stale {
		t.Fatalf("latest response = %#v, err = %v", latest, err)
	}
	select {
	case old := <-oldResult:
		if old.err != nil || !old.response.Stale || old.response.RequestID != "old" {
			t.Fatalf("superseded response = %#v, err = %v", old.response, old.err)
		}
	case <-time.After(time.Second):
		t.Fatal("superseded server geo action did not finish")
	}
}

func TestDispatchActionAssignsArrivalBeforeHandlersCanReorder(t *testing.T) {
	const method Method = "testArrivalSequence"
	type observedAction struct {
		id       string
		sequence uint64
	}
	observed := make(chan observedAction, 2)
	startOld := make(chan struct{})
	newStarted := make(chan struct{})
	previous, existed := actionHandlers[method]
	actionHandlers[method] = func(action *Action, _ ActionResult) {
		if action.Id == "old" {
			<-startOld
		} else {
			close(newStarted)
		}
		observed <- observedAction{id: action.Id, sequence: action.arrivalSequence}
	}
	t.Cleanup(func() {
		if existed {
			actionHandlers[method] = previous
		} else {
			delete(actionHandlers, method)
		}
	})

	dispatchAction(&Action{Id: "old", Method: method}, newActionResult("old", method, nil))
	dispatchAction(&Action{Id: "new", Method: method}, newActionResult("new", method, nil))
	select {
	case <-newStarted:
	case <-time.After(time.Second):
		t.Fatal("new handler did not start")
	}
	close(startOld)
	first := <-observed
	second := <-observed
	var oldSequence, newSequence uint64
	for _, item := range []observedAction{first, second} {
		switch item.id {
		case "old":
			oldSequence = item.sequence
		case "new":
			newSequence = item.sequence
		}
	}
	if oldSequence == 0 || newSequence == 0 || oldSequence >= newSequence {
		t.Fatalf("arrival sequences old=%d new=%d", oldSequence, newSequence)
	}
}

func TestServerGeoCancelActiveStopsPendingAction(t *testing.T) {
	const generation = 17
	service := newTestProxyGeoService(generation)
	leaf := adapter.NewProxy(outbound.NewBase(outbound.BaseOption{
		Name: "domain-leaf",
		Addr: "example.com:443",
		Type: C.Vmess,
	}))
	service.snapshot = func() tunnel.ProxySnapshot {
		return tunnel.ProxySnapshot{
			Generation: generation,
			ByID:       map[string]C.Proxy{leaf.Id(): leaf},
		}
	}
	started := make(chan struct{})
	service.resolve = func(ctx context.Context, _ string) ([]netip.Addr, error) {
		close(started)
		<-ctx.Done()
		return nil, ctx.Err()
	}
	result := make(chan error, 1)
	go func() {
		_, err := service.getServerGeosForAction(
			context.Background(),
			ProxyServerGeoParams{
				Generation: generation,
				RequestID:  "pending-server",
				MemberIDs:  []string{leaf.Id()},
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
			t.Fatalf("pending server geo error = %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("pending server geo action ignored lifecycle cancellation")
	}
}

func TestServerGeoDNSCacheBindsNetworkAndRuntimeGeneration(t *testing.T) {
	var runtimeGeneration atomic.Uint64
	runtimeGeneration.Store(15)
	service := newTestProxyGeoService(15)
	service.snapshot = func() tunnel.ProxySnapshot {
		return tunnel.ProxySnapshot{Generation: runtimeGeneration.Load()}
	}
	var calls atomic.Int32
	service.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
		calls.Add(1)
		return []netip.Addr{netip.MustParseAddr("8.8.8.8")}, nil
	}

	for _, test := range []struct {
		generation uint64
		network    uint64
	}{
		{generation: 15, network: 1},
		{generation: 15, network: 1},
		{generation: 15, network: 2},
		{generation: 16, network: 2},
	} {
		runtimeGeneration.Store(test.generation)
		if _, status := service.resolveServerHost(
			context.Background(),
			test.generation,
			test.network,
			"",
			"example.com",
		); status != proxyGeoStatusOK {
			t.Fatalf("resolution status = %q", status)
		}
	}
	if got := calls.Load(); got != 3 {
		t.Fatalf("DNS calls = %d, want 3", got)
	}
}

func TestServerGeoSingleflightAndProcessWideConcurrency(t *testing.T) {
	const generation = 17
	service := newTestProxyGeoService(generation)
	var calls atomic.Int32
	started := make(chan struct{})
	release := make(chan struct{})
	service.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
		if calls.Add(1) == 1 {
			close(started)
		}
		<-release
		return []netip.Addr{netip.MustParseAddr("8.8.8.8")}, nil
	}
	var waiters sync.WaitGroup
	for i := 0; i < 12; i++ {
		waiters.Add(1)
		go func() {
			defer waiters.Done()
			_, status := service.resolveServerHost(
				context.Background(),
				generation,
				1,
				"shared-request",
				"same.example",
			)
			if status != proxyGeoStatusOK {
				t.Errorf("singleflight status = %q", status)
			}
		}()
	}
	<-started
	close(release)
	waiters.Wait()
	if got := calls.Load(); got != 1 {
		t.Fatalf("singleflight DNS calls = %d, want 1", got)
	}

	var active atomic.Int32
	var maximum atomic.Int32
	waiters = sync.WaitGroup{}
	for serviceIndex := 0; serviceIndex < 3; serviceIndex++ {
		concurrentService := newTestProxyGeoService(generation)
		concurrentService.resolve = func(_ context.Context, _ string) ([]netip.Addr, error) {
			current := active.Add(1)
			for {
				old := maximum.Load()
				if current <= old || maximum.CompareAndSwap(old, current) {
					break
				}
			}
			time.Sleep(10 * time.Millisecond)
			active.Add(-1)
			return []netip.Addr{netip.MustParseAddr("1.1.1.1")}, nil
		}
		members := make([]proxyServerMember, 12)
		for i := range members {
			members[i] = proxyServerMember{
				id:     fmt.Sprintf("%d-%d", serviceIndex, i),
				host:   fmt.Sprintf("%d-%d.example", serviceIndex, i),
				source: "dns",
			}
		}
		waiters.Add(1)
		go func(service *proxyGeoService, members []proxyServerMember) {
			defer waiters.Done()
			service.populateServerGeos(
				context.Background(),
				generation,
				1,
				"process-wide",
				members,
				make(map[string]ProxyServerGeo),
			)
		}(concurrentService, members)
	}
	waiters.Wait()
	if got := maximum.Load(); got > serverGeoConcurrency {
		t.Fatalf("process-wide DNS concurrency = %d, want <= %d", got, serverGeoConcurrency)
	}
}

func TestGeoCacheInvalidatesOnDatabaseGeneration(t *testing.T) {
	service := newTestProxyGeoService(13)
	var generation atomic.Uint64
	generation.Store(1)
	service.countryGen = generation.Load
	service.asnGen = generation.Load
	var lookups atomic.Int32
	service.lookupCountry = func(_ net.IP) ([]string, error) {
		lookups.Add(1)
		if generation.Load() == 1 {
			return []string{"US"}, nil
		}
		return []string{"JP"}, nil
	}
	ip := netip.MustParseAddr("8.8.8.8")
	if got := service.geoForIP(ip).CountryCode; got != "US" {
		t.Fatalf("first country = %q", got)
	}
	if got := service.geoForIP(ip).CountryCode; got != "US" {
		t.Fatalf("cached country = %q", got)
	}
	if got := lookups.Load(); got != 1 {
		t.Fatalf("lookups before update = %d", got)
	}
	generation.Store(2)
	if got := service.geoForIP(ip).CountryCode; got != "JP" {
		t.Fatalf("updated country = %q", got)
	}
	if got := lookups.Load(); got != 2 {
		t.Fatalf("lookups after update = %d", got)
	}
}

func TestGeoPartialLookupErrorsUseShortTTL(t *testing.T) {
	t.Run("ASN recovers", func(t *testing.T) {
		service := newTestProxyGeoService(15)
		now := time.Unix(1_700_000_000, 0)
		service.now = func() time.Time { return now }
		var asnCalls atomic.Int32
		service.lookupASN = func(_ net.IP) (string, string, error) {
			if asnCalls.Add(1) == 1 {
				return "", "", errors.New("ASN database unavailable")
			}
			return "15169", "Google LLC", nil
		}
		ip := netip.MustParseAddr("8.8.8.8")
		first := service.geoForIP(ip)
		if first.CountryCode != "US" || first.ASN != "" {
			t.Fatalf("first partial ASN result = %#v", first)
		}
		now = now.Add(serverGeoNegativeTTL - time.Second)
		if cached := service.geoForIP(ip); cached.ASN != "" || asnCalls.Load() != 1 {
			t.Fatalf("partial ASN cache = %#v, calls = %d", cached, asnCalls.Load())
		}
		now = now.Add(2 * time.Second)
		recovered := service.geoForIP(ip)
		if recovered.ASN != "15169" || recovered.ASO != "Google LLC" || asnCalls.Load() != 2 {
			t.Fatalf("recovered ASN result = %#v, calls = %d", recovered, asnCalls.Load())
		}
	})

	t.Run("country recovers", func(t *testing.T) {
		service := newTestProxyGeoService(16)
		now := time.Unix(1_700_000_000, 0)
		service.now = func() time.Time { return now }
		var countryCalls atomic.Int32
		service.lookupCountry = func(_ net.IP) ([]string, error) {
			if countryCalls.Add(1) == 1 {
				return nil, errors.New("country database unavailable")
			}
			return []string{"US"}, nil
		}
		ip := netip.MustParseAddr("1.1.1.1")
		first := service.geoForIP(ip)
		if first.CountryCode != "" || first.ASN != "15169" {
			t.Fatalf("first partial country result = %#v", first)
		}
		now = now.Add(serverGeoNegativeTTL + time.Second)
		recovered := service.geoForIP(ip)
		if recovered.CountryCode != "US" || countryCalls.Load() != 2 {
			t.Fatalf("recovered country result = %#v, calls = %d", recovered, countryCalls.Load())
		}
	})
}

func TestProxyGeoCacheConcurrentAccess(t *testing.T) {
	cache := newProxyGeoCache(64, 16<<10)
	var wg sync.WaitGroup
	for worker := 0; worker < 8; worker++ {
		wg.Add(1)
		go func(worker int) {
			defer wg.Done()
			for i := 0; i < 500; i++ {
				key := fmt.Sprintf("%d-%d", worker, i%32)
				cache.set(key, proxyGeoCacheValue{status: proxyGeoStatusOK}, time.Now().Add(time.Minute))
				cache.get(key, time.Now())
			}
		}(worker)
	}
	wg.Wait()
	cache.mu.Lock()
	defer cache.mu.Unlock()
	if len(cache.items) > cache.maxEntries || cache.bytes > cache.maxBytes {
		t.Fatalf("cache exceeded limits: %d entries, %d bytes", len(cache.items), cache.bytes)
	}
}
