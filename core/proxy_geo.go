package main

import (
	"container/list"
	"context"
	"errors"
	"net"
	"net/netip"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/tunnel"
	"golang.org/x/net/idna"
	"golang.org/x/sync/singleflight"
)

const (
	serverGeoConcurrency     = 4
	serverGeoMemberLimit     = 2048
	serverGeoUniqueHostLimit = 512
	serverGeoAddressLimit    = 16
	serverGeoHostTimeout     = 3 * time.Second
	serverGeoBatchTimeout    = 15 * time.Second
	serverGeoDNSTTL          = 30 * time.Minute
	serverGeoNegativeTTL     = 5 * time.Minute
	serverGeoIPTTL           = 24 * time.Hour
	serverGeoCacheEntries    = 1536
	serverGeoCacheByteBudget = 512 << 10
)

var serverGeoSlots = make(chan struct{}, serverGeoConcurrency)

var (
	errProxyGeoStale      = errors.New("stale proxy snapshot")
	errProxyGeoSuperseded = errors.New("proxy geo request superseded")
)

const (
	proxyGeoStatusOK           = "ok"
	proxyGeoStatusUnsupported  = "unsupported"
	proxyGeoStatusNotFound     = "not-found"
	proxyGeoStatusGroup        = "group"
	proxyGeoStatusHostLimit    = "host-limit"
	proxyGeoStatusResolveError = "resolve-error"
)

type proxyGeoCacheValue struct {
	addresses []netip.Addr
	geo       *ProxyGeoAddress
	status    string
}

func (v proxyGeoCacheValue) clone() proxyGeoCacheValue {
	result := v
	result.addresses = append([]netip.Addr(nil), v.addresses...)
	if v.geo != nil {
		geo := *v.geo
		result.geo = &geo
	}
	return result
}

type proxyGeoCacheEntry struct {
	key       string
	value     proxyGeoCacheValue
	expiresAt time.Time
	size      int
}

type proxyGeoCache struct {
	mu         sync.Mutex
	items      map[string]*list.Element
	lru        list.List
	bytes      int
	maxEntries int
	maxBytes   int
}

func newProxyGeoCache(maxEntries, maxBytes int) *proxyGeoCache {
	return &proxyGeoCache{
		items:      make(map[string]*list.Element, maxEntries),
		maxEntries: maxEntries,
		maxBytes:   maxBytes,
	}
}

func (c *proxyGeoCache) get(key string, now time.Time) (proxyGeoCacheValue, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	element := c.items[key]
	if element == nil {
		return proxyGeoCacheValue{}, false
	}
	entry := element.Value.(*proxyGeoCacheEntry)
	if !now.Before(entry.expiresAt) {
		c.remove(element)
		return proxyGeoCacheValue{}, false
	}
	c.lru.MoveToFront(element)
	return entry.value.clone(), true
}

func (c *proxyGeoCache) set(key string, value proxyGeoCacheValue, expiresAt time.Time) {
	size := estimateProxyGeoCacheSize(key, value)
	if size > c.maxBytes {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if element := c.items[key]; element != nil {
		c.remove(element)
	}
	entry := &proxyGeoCacheEntry{key: key, value: value.clone(), expiresAt: expiresAt, size: size}
	element := c.lru.PushFront(entry)
	c.items[key] = element
	c.bytes += size
	for len(c.items) > c.maxEntries || c.bytes > c.maxBytes {
		c.remove(c.lru.Back())
	}
}

func (c *proxyGeoCache) remove(element *list.Element) {
	if element == nil {
		return
	}
	entry := element.Value.(*proxyGeoCacheEntry)
	delete(c.items, entry.key)
	c.bytes -= entry.size
	c.lru.Remove(element)
}

func estimateProxyGeoCacheSize(key string, value proxyGeoCacheValue) int {
	size := 96 + len(key) + len(value.status) + len(value.addresses)*24
	if value.geo != nil {
		size += 64 + len(value.geo.IP) + len(value.geo.CountryCode) + len(value.geo.ASN) + len(value.geo.ASO)
	}
	return size
}

type proxyGeoService struct {
	cache         *proxyGeoCache
	now           func() time.Time
	snapshot      func() tunnel.ProxySnapshot
	resolve       func(context.Context, string) ([]netip.Addr, error)
	lookupCountry func(net.IP) ([]string, error)
	lookupASN     func(net.IP) (string, string, error)
	countryGen    func() uint64
	asnGen        func() uint64
	flights       singleflight.Group
	requestMu     sync.Mutex
	requestSeq    uint64
	requestCancel context.CancelCauseFunc
}

func newProxyGeoService() *proxyGeoService {
	return &proxyGeoService{
		cache:    newProxyGeoCache(serverGeoCacheEntries, serverGeoCacheByteBudget),
		now:      time.Now,
		snapshot: tunnel.AllProxiesSnapshot,
		resolve: func(ctx context.Context, host string) ([]netip.Addr, error) {
			return resolver.LookupIPWithResolver(ctx, host, resolver.ProxyServerHostResolver())
		},
		lookupCountry: mmdb.LookupCountryCodes,
		lookupASN:     mmdb.LookupASN,
		countryGen:    mmdb.IPGeneration,
		asnGen:        mmdb.ASNGeneration,
	}
}

var defaultProxyGeoService = newProxyGeoService()

type proxyServerMember struct {
	id     string
	host   string
	source string
}

func handleGetProxyServerGeos(
	ctx context.Context,
	params ProxyServerGeoParams,
	arrivalSequence uint64,
) (ProxyServerGeos, error) {
	return defaultProxyGeoService.getServerGeosForAction(ctx, params, arrivalSequence)
}

func (s *proxyGeoService) beginServerGeoRun(
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
		cancel(errProxyGeoSuperseded)
		return ctx, func() {}, false
	}
	s.requestSeq = arrivalSequence
	previous := s.requestCancel
	s.requestCancel = cancel
	s.requestMu.Unlock()
	if previous != nil {
		previous(errProxyGeoSuperseded)
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

func (s *proxyGeoService) cancelActive() {
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

func (s *proxyGeoService) getServerGeos(parent context.Context, params ProxyServerGeoParams) (ProxyServerGeos, error) {
	return s.getServerGeosForAction(parent, params, 0)
}

func (s *proxyGeoService) getServerGeosForAction(
	parent context.Context,
	params ProxyServerGeoParams,
	arrivalSequence uint64,
) (ProxyServerGeos, error) {
	if len(params.RequestID) > 128 {
		return ProxyServerGeos{}, errors.New("requestId is too long")
	}
	if len(params.MemberIDs) > serverGeoMemberLimit {
		return ProxyServerGeos{}, errors.New("too many memberIds")
	}
	runCtx, finish, accepted := s.beginServerGeoRun(parent, arrivalSequence)
	defer finish()

	snapshot := s.snapshot()
	response := ProxyServerGeos{
		Generation: params.Generation,
		RequestID:  params.RequestID,
		Members:    make(map[string]ProxyServerGeo),
	}
	if !accepted {
		response.Stale = true
		response.DBGeneration = s.databaseGeneration()
		return response, nil
	}
	if params.Generation == 0 || snapshot.Generation != params.Generation {
		response.Stale = true
		response.DBGeneration = s.databaseGeneration()
		return response, nil
	}
	if params.All {
		leafCount := 0
		for _, proxy := range snapshot.ByID {
			if _, isGroup := proxy.Adapter().(outboundgroup.ProxyGroup); isGroup {
				continue
			}
			leafCount++
			if leafCount > serverGeoMemberLimit {
				return response, errors.New("too many proxy members")
			}
		}
	}
	if !params.All && len(params.MemberIDs) == 0 {
		return response, errors.New("memberIds is empty")
	}

	ctx, cancel := context.WithTimeout(runCtx, serverGeoBatchTimeout)
	defer cancel()
	members := s.serverGeoMembers(snapshot, params, response.Members)
	s.populateServerGeos(ctx, snapshot.Generation, params.NetworkRevision, params.RequestID, members, response.Members)
	response.DBGeneration = s.databaseGeneration()
	if s.snapshot().Generation != params.Generation {
		response.Stale = true
	}
	if errors.Is(context.Cause(ctx), errProxyGeoSuperseded) {
		response.Stale = true
	}
	if err := ctx.Err(); err != nil && !response.Stale {
		return response, err
	}
	return response, nil
}

func (s *proxyGeoService) serverGeoMembers(snapshot tunnel.ProxySnapshot, params ProxyServerGeoParams, results map[string]ProxyServerGeo) []proxyServerMember {
	ids := append([]string(nil), params.MemberIDs...)
	if params.All {
		ids = ids[:0]
		for id, proxy := range snapshot.ByID {
			if _, isGroup := proxy.Adapter().(outboundgroup.ProxyGroup); !isGroup {
				ids = append(ids, id)
			}
		}
	}
	sort.Strings(ids)
	ids = compactStrings(ids)
	members := make([]proxyServerMember, 0, len(ids))
	for _, id := range ids {
		proxy := snapshot.ByID[id]
		if proxy == nil {
			results[id] = ProxyServerGeo{MemberID: id, Status: proxyGeoStatusNotFound}
			continue
		}
		if _, isGroup := proxy.Adapter().(outboundgroup.ProxyGroup); isGroup {
			results[id] = ProxyServerGeo{MemberID: id, Status: proxyGeoStatusGroup}
			continue
		}
		host, source, ok := normalizedProxyServerHost(proxy.Addr())
		if !ok {
			results[id] = ProxyServerGeo{MemberID: id, Status: proxyGeoStatusUnsupported}
			continue
		}
		members = append(members, proxyServerMember{id: id, host: host, source: source})
	}
	return members
}

func normalizedProxyServerHost(address string) (string, string, bool) {
	host, _, err := net.SplitHostPort(strings.TrimSpace(address))
	if err != nil {
		return "", "", false
	}
	host = strings.TrimSpace(strings.TrimSuffix(host, "."))
	if host == "" {
		return "", "", false
	}
	if ip, err := netip.ParseAddr(host); err == nil {
		if ip.Zone() != "" || !ip.IsValid() {
			return "", "", false
		}
		return ip.Unmap().String(), "literal", true
	}
	host, err = idna.Lookup.ToASCII(host)
	if err != nil || len(host) > 253 {
		return "", "", false
	}
	host = strings.ToLower(host)
	if strings.ContainsAny(host, " /\\\x00") {
		return "", "", false
	}
	return host, "dns", true
}

func compactStrings(values []string) []string {
	if len(values) < 2 {
		return values
	}
	result := values[:1]
	for _, value := range values[1:] {
		if value != result[len(result)-1] {
			result = append(result, value)
		}
	}
	return result
}

func (s *proxyGeoService) populateServerGeos(
	ctx context.Context,
	generation uint64,
	networkRevision uint64,
	requestID string,
	members []proxyServerMember,
	results map[string]ProxyServerGeo,
) {
	domainMembers := make(map[string][]proxyServerMember)
	for _, member := range members {
		if member.source == "literal" {
			ip := netip.MustParseAddr(member.host)
			address := s.geoForIP(ip)
			results[member.id] = buildProxyServerGeo(member, []ProxyGeoAddress{address}, proxyGeoStatusOK)
			continue
		}
		domainMembers[member.host] = append(domainMembers[member.host], member)
	}

	hosts := make([]string, 0, len(domainMembers))
	for host := range domainMembers {
		hosts = append(hosts, host)
	}
	sort.Strings(hosts)
	if len(hosts) > serverGeoUniqueHostLimit {
		for _, host := range hosts[serverGeoUniqueHostLimit:] {
			for _, member := range domainMembers[host] {
				results[member.id] = buildProxyServerGeo(member, nil, proxyGeoStatusHostLimit)
			}
		}
		hosts = hosts[:serverGeoUniqueHostLimit]
	}

	type hostResult struct {
		host      string
		addresses []ProxyGeoAddress
		status    string
	}
	jobs := make(chan string)
	completed := make(chan hostResult, len(hosts))
	var workers sync.WaitGroup
	for i := 0; i < serverGeoConcurrency; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for host := range jobs {
				addresses, status := s.resolveServerHost(ctx, generation, networkRevision, requestID, host)
				completed <- hostResult{host: host, addresses: addresses, status: status}
			}
		}()
	}
	go func() {
		defer close(jobs)
		for _, host := range hosts {
			select {
			case jobs <- host:
			case <-ctx.Done():
				return
			}
		}
	}()
	go func() {
		workers.Wait()
		close(completed)
	}()
	for result := range completed {
		for _, member := range domainMembers[result.host] {
			results[member.id] = buildProxyServerGeo(member, result.addresses, result.status)
		}
	}
	for _, host := range hosts {
		for _, member := range domainMembers[host] {
			if _, exists := results[member.id]; !exists {
				results[member.id] = buildProxyServerGeo(member, nil, proxyGeoStatusResolveError)
			}
		}
	}
}

type proxyGeoHostResult struct {
	addresses []netip.Addr
	status    string
}

func (s *proxyGeoService) resolveServerHost(
	ctx context.Context,
	generation uint64,
	networkRevision uint64,
	requestID string,
	host string,
) ([]ProxyGeoAddress, string) {
	now := s.now()
	databaseGeneration := s.databaseGeneration()
	dnsKey := proxyGeoDNSCacheKey(generation, networkRevision, databaseGeneration, host)
	cached, found := s.cache.get(dnsKey, now)
	var ips []netip.Addr
	if found {
		if cached.status != proxyGeoStatusOK {
			return nil, cached.status
		}
		ips = cached.addresses
	} else {
		flightKey := dnsKey
		if requestID != "" {
			flightKey = "request:" + requestID + ":" + dnsKey
		}
		resultChannel := s.flights.DoChan(flightKey, func() (any, error) {
			if cached, found := s.cache.get(dnsKey, s.now()); found {
				return proxyGeoHostResult{
					addresses: cached.addresses,
					status:    cached.status,
				}, nil
			}
			select {
			case serverGeoSlots <- struct{}{}:
				defer func() { <-serverGeoSlots }()
			case <-ctx.Done():
				return nil, ctx.Err()
			}

			hostCtx, cancel := context.WithTimeout(ctx, serverGeoHostTimeout)
			resolved, err := s.resolve(hostCtx, host)
			cancel()
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
			if s.snapshot().Generation != generation {
				return nil, errProxyGeoStale
			}
			if err != nil {
				s.cache.set(
					dnsKey,
					proxyGeoCacheValue{status: proxyGeoStatusResolveError},
					s.now().Add(serverGeoNegativeTTL),
				)
				return proxyGeoHostResult{status: proxyGeoStatusResolveError}, nil
			}
			resolved = normalizeResolvedAddresses(resolved)
			if len(resolved) == 0 {
				s.cache.set(
					dnsKey,
					proxyGeoCacheValue{status: proxyGeoStatusResolveError},
					s.now().Add(serverGeoNegativeTTL),
				)
				return proxyGeoHostResult{status: proxyGeoStatusResolveError}, nil
			}
			s.cache.set(
				dnsKey,
				proxyGeoCacheValue{addresses: resolved, status: proxyGeoStatusOK},
				s.now().Add(serverGeoDNSTTL),
			)
			return proxyGeoHostResult{addresses: resolved, status: proxyGeoStatusOK}, nil
		})
		select {
		case <-ctx.Done():
			s.flights.Forget(flightKey)
			return nil, proxyGeoStatusResolveError
		case result := <-resultChannel:
			if result.Err != nil {
				return nil, proxyGeoStatusResolveError
			}
			hostResult, ok := result.Val.(proxyGeoHostResult)
			if !ok {
				return nil, proxyGeoStatusResolveError
			}
			ips = hostResult.addresses
			if hostResult.status != proxyGeoStatusOK {
				return nil, hostResult.status
			}
		}
	}
	addresses := make([]ProxyGeoAddress, 0, len(ips))
	for _, ip := range ips {
		addresses = append(addresses, s.geoForIP(ip))
	}
	return addresses, proxyGeoStatusOK
}

func proxyGeoDNSCacheKey(
	generation uint64,
	networkRevision uint64,
	databaseGeneration GeoDatabaseGeneration,
	host string,
) string {
	return "dns:" + strconv.FormatUint(generation, 10) + ":" +
		strconv.FormatUint(networkRevision, 10) + ":" +
		strconv.FormatUint(databaseGeneration.Country, 10) + ":" +
		strconv.FormatUint(databaseGeneration.ASN, 10) + ":" + host
}

func normalizeResolvedAddresses(addresses []netip.Addr) []netip.Addr {
	result := make([]netip.Addr, 0, min(len(addresses), serverGeoAddressLimit))
	seen := make(map[netip.Addr]struct{}, len(addresses))
	for _, address := range addresses {
		if !address.IsValid() || address.Zone() != "" || address.IsUnspecified() {
			continue
		}
		address = address.Unmap()
		if _, exists := seen[address]; exists {
			continue
		}
		seen[address] = struct{}{}
		result = append(result, address)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Compare(result[j]) < 0 })
	if len(result) > serverGeoAddressLimit {
		result = result[:serverGeoAddressLimit]
	}
	return result
}

func (s *proxyGeoService) geoForIP(ip netip.Addr) ProxyGeoAddress {
	var address ProxyGeoAddress
	for attempt := 0; attempt < 2; attempt++ {
		generation := s.databaseGeneration()
		key := proxyGeoIPCacheKey(generation, ip)
		now := s.now()
		if cached, found := s.cache.get(key, now); found && cached.geo != nil {
			return *cached.geo
		}

		var ttl time.Duration
		address, ttl = s.lookupGeoAddress(ip)
		if s.databaseGeneration() != generation {
			continue
		}
		s.cache.set(key, proxyGeoCacheValue{geo: &address, status: proxyGeoStatusOK}, now.Add(ttl))
		return address
	}
	return address
}

func (s *proxyGeoService) lookupGeoAddress(ip netip.Addr) (ProxyGeoAddress, time.Duration) {
	address := ProxyGeoAddress{IP: ip.String()}
	ipValue := net.IP(ip.AsSlice())
	countries, countryErr := s.lookupCountry(ipValue)
	if len(countries) > 0 {
		sort.Strings(countries)
		address.CountryCode = countries[0]
	}
	var asnErr error
	address.ASN, address.ASO, asnErr = s.lookupASN(ipValue)
	ttl := serverGeoIPTTL
	if countryErr != nil || asnErr != nil {
		ttl = serverGeoNegativeTTL
	}
	return address, ttl
}

func proxyGeoIPCacheKey(generation GeoDatabaseGeneration, ip netip.Addr) string {
	return "geo:" + strconv.FormatUint(generation.Country, 10) + ":" +
		strconv.FormatUint(generation.ASN, 10) + ":" + ip.String()
}

func (s *proxyGeoService) databaseGeneration() GeoDatabaseGeneration {
	return GeoDatabaseGeneration{Country: s.countryGen(), ASN: s.asnGen()}
}

func buildProxyServerGeo(member proxyServerMember, addresses []ProxyGeoAddress, status string) ProxyServerGeo {
	countries := make(map[string]struct{})
	for _, address := range addresses {
		if address.CountryCode != "" {
			countries[address.CountryCode] = struct{}{}
		}
	}
	return ProxyServerGeo{
		MemberID:    member.id,
		ServerHost:  member.host,
		Source:      member.source,
		Status:      status,
		MultiRegion: len(countries) > 1,
		Addresses:   addresses,
	}
}
