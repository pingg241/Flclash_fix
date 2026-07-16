package main

import (
	"context"
	"crypto/tls"
	"errors"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"golang.org/x/sync/singleflight"
)

const (
	proxyExitEndpointSetVersion = "exit-echo-v2"
	proxyExitMaxDepth           = 16
	proxyExitConcurrency        = 2
	proxyExitPendingLimit       = 8
	proxyExitResponseLimit      = 64
	proxyExitHeaderLimit        = 8 << 10
	proxyExitTimeout            = 8 * time.Second
	proxyExitPhaseTimeout       = 3 * time.Second
	proxyExitHedgeDelay         = 300 * time.Millisecond
	proxyExitCacheTTL           = 10 * time.Minute
)

var proxyExitEndpointSpecs = [...]struct {
	rawURL  string
	version string
}{
	{rawURL: "https://api.ipify.org/", version: "ipify-v4-v1"},
	{rawURL: "https://api.ip.sb/ip", version: "ipsb-v4-v1"},
	{rawURL: "https://api64.ipify.org/", version: "ipify-dual-v1"},
}

var (
	errProxyExitStale         = errors.New("stale proxy snapshot")
	errProxyExitInvalidGroup  = errors.New("invalid proxy group")
	errProxyExitInvalidMember = errors.New("proxy member is not in group")
	errProxyExitCycle         = errors.New("proxy group cycle detected")
	errProxyExitDepth         = errors.New("proxy group nesting is too deep")
	errProxyExitRouteChanged  = errors.New("proxy group route changed")
	errProxyExitDial          = errors.New("proxy exit dial failed")
	errProxyExitRequest       = errors.New("proxy exit request failed")
	errProxyExitResponse      = errors.New("invalid proxy exit response")
	errProxyExitEndpoint      = errors.New("invalid proxy exit endpoint")
	errProxyExitBusy          = errors.New("too many pending proxy exit probes")
	errProxyExitSuperseded    = errors.New("proxy exit request superseded")
	proxyExitSlots            = make(chan struct{}, proxyExitConcurrency)
	proxyExitSpecialPrefixes  = []netip.Prefix{
		netip.MustParsePrefix("0.0.0.0/8"),
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("100.64.0.0/10"),
		netip.MustParsePrefix("127.0.0.0/8"),
		netip.MustParsePrefix("169.254.0.0/16"),
		netip.MustParsePrefix("172.16.0.0/12"),
		netip.MustParsePrefix("192.0.0.0/24"),
		netip.MustParsePrefix("192.0.2.0/24"),
		netip.MustParsePrefix("192.88.99.0/24"),
		netip.MustParsePrefix("192.168.0.0/16"),
		netip.MustParsePrefix("198.18.0.0/15"),
		netip.MustParsePrefix("198.51.100.0/24"),
		netip.MustParsePrefix("203.0.113.0/24"),
		netip.MustParsePrefix("224.0.0.0/4"),
		netip.MustParsePrefix("240.0.0.0/4"),
		netip.MustParsePrefix("::/128"),
		netip.MustParsePrefix("::1/128"),
		netip.MustParsePrefix("100::/64"),
		netip.MustParsePrefix("2001:2::/48"),
		netip.MustParsePrefix("2001:10::/28"),
		netip.MustParsePrefix("2001:20::/28"),
		netip.MustParsePrefix("2001:db8::/32"),
		netip.MustParsePrefix("3fff::/20"),
		netip.MustParsePrefix("fc00::/7"),
		netip.MustParsePrefix("fe80::/10"),
		netip.MustParsePrefix("ff00::/8"),
	}
)

type proxyExitGateEntry struct {
	waiters      int
	callbacks    int
	pendingStart bool
}

type proxyExitGate struct {
	mu      sync.Mutex
	entries map[string]*proxyExitGateEntry
	limit   int
}

func newProxyExitGate(limit int) *proxyExitGate {
	return &proxyExitGate{entries: make(map[string]*proxyExitGateEntry), limit: limit}
}

func (g *proxyExitGate) acquire(key string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if entry := g.entries[key]; entry != nil {
		entry.waiters++
		if entry.callbacks == 0 {
			entry.pendingStart = true
		}
		return true
	}
	if len(g.entries) >= g.limit {
		return false
	}
	g.entries[key] = &proxyExitGateEntry{waiters: 1, pendingStart: true}
	return true
}

func (g *proxyExitGate) callbackStarted(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	entry := g.entries[key]
	if entry == nil {
		return
	}
	entry.pendingStart = false
	entry.callbacks++
}

func (g *proxyExitGate) callbackDone(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	entry := g.entries[key]
	if entry == nil {
		return
	}
	entry.callbacks--
	g.removeIdle(key, entry)
}

func (g *proxyExitGate) release(key string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	entry := g.entries[key]
	if entry == nil {
		return
	}
	entry.waiters--
	g.removeIdle(key, entry)
}

func (g *proxyExitGate) removeIdle(key string, entry *proxyExitGateEntry) {
	if entry.waiters == 0 && entry.callbacks == 0 && !entry.pendingStart {
		delete(g.entries, key)
	}
}

type proxyExitEndpoint struct {
	rawURL     string
	hostPort   string
	serverName string
	version    string
}

func parseProxyExitEndpoint(rawURL, version string) (proxyExitEndpoint, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Scheme != "https" || parsed.User != nil || parsed.Hostname() == "" ||
		parsed.RawQuery != "" || parsed.Fragment != "" {
		return proxyExitEndpoint{}, errProxyExitEndpoint
	}
	port := parsed.Port()
	if port == "" {
		port = "443"
	}
	if port != "443" || (parsed.Path != "/" && parsed.Path != "/ip") || parsed.RawPath != "" {
		return proxyExitEndpoint{}, errProxyExitEndpoint
	}
	return proxyExitEndpoint{
		rawURL:     rawURL,
		hostPort:   net.JoinHostPort(parsed.Hostname(), port),
		serverName: parsed.Hostname(),
		version:    version,
	}, nil
}

type proxyExitService struct {
	geo           *proxyGeoService
	snapshot      func() tunnel.ProxySnapshot
	endpoint      proxyExitEndpoint
	endpoints     []proxyExitEndpoint
	timeout       time.Duration
	hedgeDelay    time.Duration
	slots         chan struct{}
	fetch         func(context.Context, C.Proxy, *C.Metadata, proxyExitEndpoint) (netip.Addr, error)
	flights       singleflight.Group
	gate          *proxyExitGate
	requestMu     sync.Mutex
	requestSeq    uint64
	requestCancel context.CancelCauseFunc
	sampleSeq     atomic.Uint64
}

func newProxyExitService(geo *proxyGeoService) *proxyExitService {
	endpoints := make([]proxyExitEndpoint, 0, len(proxyExitEndpointSpecs))
	for _, spec := range proxyExitEndpointSpecs {
		endpoint, err := parseProxyExitEndpoint(spec.rawURL, spec.version)
		if err != nil {
			panic(err)
		}
		endpoints = append(endpoints, endpoint)
	}
	primary := endpoints[0]
	primary.version = proxyExitEndpointSetVersion
	return &proxyExitService{
		geo:        geo,
		snapshot:   tunnel.AllProxiesSnapshot,
		endpoint:   primary,
		endpoints:  endpoints,
		timeout:    proxyExitTimeout,
		hedgeDelay: proxyExitHedgeDelay,
		slots:      proxyExitSlots,
		fetch:      fetchProxyExitIP,
		gate:       newProxyExitGate(proxyExitPendingLimit),
	}
}

var defaultProxyExitService = newProxyExitService(defaultProxyGeoService)

func handleProbeProxyExit(
	ctx context.Context,
	params ProbeProxyExitParams,
	arrivalSequence uint64,
) (ProxyExitGeo, error) {
	return defaultProxyExitService.probeForAction(ctx, params, arrivalSequence)
}

func (s *proxyExitService) beginExitRun(
	parent context.Context,
	arrivalSequence uint64,
) (context.Context, func(), bool) {
	ctx, cancel := context.WithCancelCause(parent)
	if arrivalSequence == 0 {
		return ctx, func() { cancel(context.Canceled) }, true
	}
	s.requestMu.Lock()
	if arrivalSequence <= s.requestSeq {
		s.requestMu.Unlock()
		cancel(errProxyExitSuperseded)
		return ctx, func() {}, false
	}
	s.requestSeq = arrivalSequence
	previous := s.requestCancel
	s.requestCancel = cancel
	s.requestMu.Unlock()
	if previous != nil {
		previous(errProxyExitSuperseded)
	}
	return ctx, func() {
		cancel(context.Canceled)
		s.requestMu.Lock()
		if s.requestSeq == arrivalSequence {
			s.requestCancel = nil
		}
		s.requestMu.Unlock()
	}, true
}

func (s *proxyExitService) cancelActive() {
	fence := actionArrivalSequence.Load()
	s.requestMu.Lock()
	if fence > s.requestSeq {
		s.requestSeq = fence
	}
	cancel := s.requestCancel
	s.requestCancel = nil
	s.requestMu.Unlock()
	if cancel != nil {
		cancel(context.Canceled)
	}
}

func (s *proxyExitService) probe(parent context.Context, params ProbeProxyExitParams) (ProxyExitGeo, error) {
	return s.probeForAction(parent, params, 0)
}

func (s *proxyExitService) probeForAction(
	parent context.Context,
	params ProbeProxyExitParams,
	arrivalSequence uint64,
) (ProxyExitGeo, error) {
	response := ProxyExitGeo{Generation: params.Generation, RequestID: params.RequestID}
	if len(params.RequestID) > 128 {
		return response, errors.New("requestId is too long")
	}
	runCtx, finish, accepted := s.beginExitRun(parent, arrivalSequence)
	defer finish()
	if !accepted {
		response.Stale = true
		response.DBGeneration = s.geo.databaseGeneration()
		return response, nil
	}
	snapshot := s.snapshot()
	if params.Generation == 0 || snapshot.Generation != params.Generation {
		response.Stale = true
		response.DBGeneration = s.geo.databaseGeneration()
		return response, nil
	}

	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER}
	if err := metadata.SetRemoteAddress(s.endpoint.hostPort); err != nil {
		return response, errProxyExitEndpoint
	}
	leaf, path, routeSample, err := resolveProxyExitRoute(snapshot, params, metadata)
	response.PathIDs = path
	response.RouteSample = routeSample
	if err != nil {
		if errors.Is(err, errProxyExitRouteChanged) {
			return s.staleResponse(response), nil
		}
		return response, err
	}
	response.LeafID = leaf.Id()
	if s.snapshot().Generation != params.Generation {
		response.Stale = true
		response.DBGeneration = s.geo.databaseGeneration()
		return response, nil
	}

	ctx, cancel := context.WithTimeout(runCtx, s.timeout)
	defer cancel()
	var ip netip.Addr
	if routeSample || leaf.ProxyInfo().DialerProxy != "" {
		ip, err = s.probeUncached(ctx, leaf, metadata)
	} else {
		var cached bool
		ip, cached, err = s.fixedExitIP(
			ctx,
			params.Generation,
			params.NetworkRevision,
			params.RequestID,
			leaf,
			metadata,
		)
		response.Cached = cached
	}
	if errors.Is(context.Cause(ctx), errProxyExitSuperseded) {
		return s.staleResponse(response), nil
	}
	if errors.Is(err, errProxyExitStale) || s.snapshot().Generation != params.Generation {
		response.Stale = true
		response.DBGeneration = s.geo.databaseGeneration()
		return response, nil
	}
	if err != nil {
		return response, err
	}
	if !s.routeStillCurrent(snapshot, params, leaf.Id(), path, routeSample) {
		return s.staleResponse(response), nil
	}

	address := s.geo.geoForIP(ip)
	response.IP = address.IP
	response.CountryCode = address.CountryCode
	response.ASN = address.ASN
	response.ASO = address.ASO
	response.DBGeneration = s.geo.databaseGeneration()
	if !s.routeStillCurrent(snapshot, params, leaf.Id(), path, routeSample) {
		return s.staleResponse(response), nil
	}
	if errors.Is(context.Cause(ctx), errProxyExitSuperseded) {
		return s.staleResponse(response), nil
	}
	return response, nil
}

func (s *proxyExitService) staleResponse(response ProxyExitGeo) ProxyExitGeo {
	response.Stale = true
	response.Cached = false
	response.IP = ""
	response.CountryCode = ""
	response.ASN = ""
	response.ASO = ""
	response.DBGeneration = s.geo.databaseGeneration()
	return response
}

func (s *proxyExitService) routeStillCurrent(
	snapshot tunnel.ProxySnapshot,
	params ProbeProxyExitParams,
	expectedLeafID string,
	expectedPath []string,
	routeSample bool,
) bool {
	if s.snapshot().Generation != params.Generation {
		return false
	}
	metadata := &C.Metadata{NetWork: C.TCP, Type: C.INNER}
	if err := metadata.SetRemoteAddress(s.endpoint.hostPort); err != nil {
		return false
	}
	leaf, path, currentRouteSample, err := resolveProxyExitRoute(snapshot, params, metadata)
	if err != nil || currentRouteSample != routeSample {
		return false
	}
	if routeSample {
		return true
	}
	return leaf.Id() == expectedLeafID && slices.Equal(path, expectedPath)
}

func (s *proxyExitService) probeUncached(
	ctx context.Context,
	leaf C.Proxy,
	metadata *C.Metadata,
) (netip.Addr, error) {
	key := "sample:" + strconv.FormatUint(s.sampleSeq.Add(1), 10)
	if !s.gate.acquire(key) {
		return netip.Addr{}, errProxyExitBusy
	}
	s.gate.callbackStarted(key)
	defer s.gate.release(key)
	defer s.gate.callbackDone(key)
	return s.probeWithLimit(ctx, leaf, metadata)
}

func resolveProxyExitRoute(
	snapshot tunnel.ProxySnapshot,
	params ProbeProxyExitParams,
	metadata *C.Metadata,
) (C.Proxy, []string, bool, error) {
	group := snapshot.ByID[params.GroupID]
	if group == nil {
		return nil, nil, false, errProxyExitInvalidGroup
	}
	groupAdapter, ok := group.Adapter().(outboundgroup.ProxyGroup)
	if !ok {
		return nil, nil, false, errProxyExitInvalidGroup
	}
	member := frozenProxyMember(snapshot.Members[params.GroupID], params.MemberID)
	if member == nil {
		return nil, []string{params.GroupID}, false, errProxyExitInvalidMember
	}
	current := groupAdapter.NowProxy()
	if current == nil || current.Id() != params.MemberID {
		return nil, []string{params.GroupID}, false, errProxyExitRouteChanged
	}

	path := []string{params.GroupID}
	visited := map[string]struct{}{params.GroupID: {}}
	current = member
	routeSample := false
	for depth := 0; ; depth++ {
		if current == nil || current.Id() == "" {
			return nil, path, routeSample, errProxyExitRouteChanged
		}
		if _, exists := visited[current.Id()]; exists {
			return nil, path, routeSample, errProxyExitCycle
		}
		visited[current.Id()] = struct{}{}
		path = append(path, current.Id())

		groupAdapter, isGroup := current.Adapter().(outboundgroup.ProxyGroup)
		if !isGroup {
			return current, path, routeSample, nil
		}
		if depth >= proxyExitMaxDepth {
			return nil, path, routeSample, errProxyExitDepth
		}
		if current.Type() == C.LoadBalance {
			routeSample = true
		}
		selected := groupAdapter.Unwrap(metadata, false)
		if selected == nil {
			return nil, path, routeSample, errProxyExitRouteChanged
		}
		current = frozenProxyMember(snapshot.Members[current.Id()], selected.Id())
		if current == nil {
			return nil, path, routeSample, errProxyExitRouteChanged
		}
	}
}

func frozenProxyMember(members []C.Proxy, id string) C.Proxy {
	for _, member := range members {
		if member != nil && member.Id() == id {
			return member
		}
	}
	return nil
}

func (s *proxyExitService) fixedExitIP(
	ctx context.Context,
	generation uint64,
	networkRevision uint64,
	requestID string,
	leaf C.Proxy,
	metadata *C.Metadata,
) (netip.Addr, bool, error) {
	cacheKey := "exit:" + strconv.FormatUint(generation, 10) + ":" +
		strconv.FormatUint(networkRevision, 10) + ":" + leaf.Id() + ":" + s.endpoint.version
	if cached, found := s.geo.cache.get(cacheKey, s.geo.now()); found &&
		cached.status == proxyGeoStatusOK && len(cached.addresses) == 1 {
		return cached.addresses[0], true, nil
	}

	flightKey := cacheKey
	if requestID != "" {
		flightKey = "request:" + requestID + ":" + cacheKey
	}
	if !s.gate.acquire(flightKey) {
		return netip.Addr{}, false, errProxyExitBusy
	}
	defer s.gate.release(flightKey)

	result := s.flights.DoChan(flightKey, func() (any, error) {
		s.gate.callbackStarted(flightKey)
		defer s.gate.callbackDone(flightKey)
		if s.snapshot().Generation != generation {
			return netip.Addr{}, errProxyExitStale
		}
		ip, err := s.probeWithLimit(ctx, leaf, metadata.Clone())
		if err != nil {
			return netip.Addr{}, err
		}
		if s.snapshot().Generation != generation {
			return netip.Addr{}, errProxyExitStale
		}
		s.geo.cache.set(
			cacheKey,
			proxyGeoCacheValue{addresses: []netip.Addr{ip}, status: proxyGeoStatusOK},
			s.geo.now().Add(proxyExitCacheTTL),
		)
		return ip, nil
	})
	select {
	case <-ctx.Done():
		s.flights.Forget(flightKey)
		return netip.Addr{}, false, ctx.Err()
	case flight := <-result:
		if flight.Err != nil {
			return netip.Addr{}, false, flight.Err
		}
		ip, ok := flight.Val.(netip.Addr)
		if !ok || !ip.IsValid() {
			return netip.Addr{}, false, errProxyExitResponse
		}
		return ip, false, nil
	}
}

func (s *proxyExitService) probeWithLimit(
	ctx context.Context,
	leaf C.Proxy,
	metadata *C.Metadata,
) (netip.Addr, error) {
	select {
	case s.slots <- struct{}{}:
	case <-ctx.Done():
		return netip.Addr{}, ctx.Err()
	}
	if err := ctx.Err(); err != nil {
		<-s.slots
		return netip.Addr{}, err
	}

	result := make(chan proxyExitFetchResult, 1)
	go func() {
		defer func() { <-s.slots }()
		s.raceExitEndpoints(ctx, leaf, metadata, result)
	}()
	select {
	case <-ctx.Done():
		return netip.Addr{}, ctx.Err()
	case value := <-result:
		return value.ip, value.err
	}
}

type proxyExitFetchResult struct {
	ip  netip.Addr
	err error
}

func (s *proxyExitService) raceExitEndpoints(
	ctx context.Context,
	leaf C.Proxy,
	metadata *C.Metadata,
	output chan<- proxyExitFetchResult,
) {
	endpoints := s.endpoints
	if len(endpoints) == 0 {
		endpoints = []proxyExitEndpoint{s.endpoint}
	}
	raceCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make(chan proxyExitFetchResult, len(endpoints))
	started := 0
	completed := 0
	published := false
	publish := func(value proxyExitFetchResult) {
		if published {
			return
		}
		published = true
		output <- value
	}
	startNext := func() bool {
		if started >= len(endpoints) {
			return false
		}
		endpoint := endpoints[started]
		started++
		go func() {
			value := proxyExitFetchResult{}
			defer func() {
				if recover() != nil {
					value = proxyExitFetchResult{err: errProxyExitRequest}
				}
				results <- value
			}()
			requestMetadata := metadata.Clone()
			if err := requestMetadata.SetRemoteAddress(endpoint.hostPort); err != nil {
				value.err = errProxyExitEndpoint
				return
			}
			value.ip, value.err = s.fetch(raceCtx, leaf, requestMetadata, endpoint)
		}()
		return true
	}
	drain := func() {
		for completed < started {
			<-results
			completed++
		}
	}
	if !startNext() {
		publish(proxyExitFetchResult{err: errProxyExitEndpoint})
		return
	}
	var hedge <-chan time.Time
	if started < len(endpoints) {
		hedge = time.After(s.hedgeDelay)
	}
	lastErr := error(errProxyExitRequest)
	for {
		select {
		case <-ctx.Done():
			publish(proxyExitFetchResult{err: ctx.Err()})
			cancel()
			drain()
			return
		case value := <-results:
			completed++
			if value.err == nil && value.ip.IsValid() &&
				value.ip.IsGlobalUnicast() && !isSpecialProxyExitIP(value.ip) {
				publish(value)
				cancel()
				drain()
				return
			}
			if value.err != nil {
				lastErr = value.err
			} else {
				lastErr = errProxyExitResponse
			}
			if startNext() {
				if started < len(endpoints) {
					hedge = time.After(s.hedgeDelay)
				} else {
					hedge = nil
				}
				continue
			}
			if completed == started {
				publish(proxyExitFetchResult{err: lastErr})
				return
			}
		case <-hedge:
			startNext()
			if started < len(endpoints) {
				hedge = time.After(s.hedgeDelay)
			} else {
				hedge = nil
			}
		}
	}
}

func fetchProxyExitIP(
	ctx context.Context,
	leaf C.Proxy,
	metadata *C.Metadata,
	endpoint proxyExitEndpoint,
) (netip.Addr, error) {
	conn, err := leaf.DialContext(ctx, metadata)
	if err != nil {
		return netip.Addr{}, errProxyExitDial
	}
	defer conn.Close()

	var used atomic.Bool
	transport := &http.Transport{
		Proxy:                  nil,
		DisableKeepAlives:      true,
		ForceAttemptHTTP2:      false,
		TLSHandshakeTimeout:    proxyExitPhaseTimeout,
		ResponseHeaderTimeout:  proxyExitPhaseTimeout,
		MaxResponseHeaderBytes: proxyExitHeaderLimit,
		TLSClientConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
			ServerName: endpoint.serverName,
		},
		DialContext: func(_ context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" || address != endpoint.hostPort || !used.CompareAndSwap(false, true) {
				return nil, errProxyExitEndpoint
			}
			return conn, nil
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{
		Transport: transport,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.rawURL, nil)
	if err != nil {
		return netip.Addr{}, errProxyExitEndpoint
	}
	request.Header.Set("Accept", "text/plain")
	response, err := client.Do(request)
	if err != nil {
		return netip.Addr{}, errProxyExitRequest
	}
	return readProxyExitResponse(response)
}

func readProxyExitResponse(response *http.Response) (netip.Addr, error) {
	if response == nil || response.Body == nil {
		return netip.Addr{}, errProxyExitResponse
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return netip.Addr{}, errProxyExitResponse
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, proxyExitResponseLimit+1))
	if err != nil || len(body) > proxyExitResponseLimit {
		return netip.Addr{}, errProxyExitResponse
	}
	ip, err := parsePublicExitIP(string(body))
	if err != nil {
		return netip.Addr{}, err
	}
	return ip, nil
}

func parsePublicExitIP(value string) (netip.Addr, error) {
	ip, err := netip.ParseAddr(strings.TrimSpace(value))
	if err != nil || !ip.IsValid() || ip.Zone() != "" {
		return netip.Addr{}, errProxyExitResponse
	}
	ip = ip.Unmap()
	if !ip.IsGlobalUnicast() || isSpecialProxyExitIP(ip) {
		return netip.Addr{}, errProxyExitResponse
	}
	return ip, nil
}

func isSpecialProxyExitIP(ip netip.Addr) bool {
	for _, prefix := range proxyExitSpecialPrefixes {
		if prefix.Contains(ip) {
			return true
		}
	}
	return false
}

func cancelActiveProxyGeoRequests() {
	defaultProxyGeoService.cancelActive()
	defaultProxyExitService.cancelActive()
}
