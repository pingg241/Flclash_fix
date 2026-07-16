package main

import (
	"encoding/json"
	"strconv"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

func newIdentityTestProxy(name, providerName string) C.Proxy {
	return adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{
		BasicOption: outbound.BasicOption{ProviderName: providerName},
		Name:        name,
	}))
}

func newIdentityTestProvider(t *testing.T, name string, proxies ...C.Proxy) *provider.CompatibleProvider {
	t.Helper()
	healthCheck := provider.NewHealthCheck(proxies, C.DefaultTestURL, 1000, 0, true, nil)
	p, err := provider.NewCompatibleProvider(name, proxies, healthCheck)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func installIdentityTestRuntime(t *testing.T) (C.Proxy, C.Proxy, C.Proxy) {
	t.Helper()
	oldProxies := tunnel.Proxies()
	oldProviders := tunnel.Providers()
	oldNames := append([]string(nil), config.GetProxyNameList()...)

	proxyA := newIdentityTestProxy("same", "provider-a")
	proxyB := newIdentityTestProxy("same", "provider-b")
	providerA := newIdentityTestProvider(t, "provider-a", proxyA)
	providerB := newIdentityTestProvider(t, "provider-b", proxyB)
	groupAdapter := outboundgroup.NewSelector(
		&outboundgroup.GroupCommonOption{Name: "GROUP", URL: C.DefaultTestURL},
		proxyA,
		[]P.ProxyProvider{providerA, providerB},
	)
	group := adapter.NewProxy(groupAdapter)
	tunnel.UpdateProxies(
		map[string]C.Proxy{"GROUP": group},
		map[string]P.ProxyProvider{
			"provider-a": providerA,
			"provider-b": providerB,
		},
	)
	config.SetProxyNameList([]string{"GROUP"})
	t.Cleanup(func() {
		config.SetProxyNameList(oldNames)
		tunnel.UpdateProxies(oldProxies, oldProviders)
		_ = providerA.Close()
		_ = providerB.Close()
	})
	return group, proxyA, proxyB
}

func invokeProxyChangeForTest(t *testing.T, params ChangeProxyParams) string {
	t.Helper()
	data, err := json.Marshal(params)
	if err != nil {
		t.Fatal(err)
	}
	result := "callback was not invoked"
	handleChangeProxy(string(data), func(value string) {
		result = value
	})
	return result
}

type refreshingSelector struct {
	*outboundgroup.Selector
}

func (s *refreshingSelector) SetByID(id string) error {
	if err := s.Selector.SetByID(id); err != nil {
		return err
	}
	tunnel.RefreshAllProxies()
	return nil
}

func TestRuntimeProxySnapshotKeepsDuplicateNamesDistinct(t *testing.T) {
	group, proxyA, proxyB := installIdentityTestRuntime(t)
	data := handleGetProxies()
	if data.Generation == 0 {
		t.Fatal("runtime snapshot has no generation")
	}
	if len(data.Groups) != 1 {
		t.Fatalf("groups = %d, want 1", len(data.Groups))
	}
	groupData := data.Groups[0]
	if groupData.ID != group.Id() {
		t.Fatalf("group ID = %q, want %q", groupData.ID, group.Id())
	}
	if len(groupData.MemberIDs) != 2 {
		t.Fatalf("member IDs = %#v", groupData.MemberIDs)
	}
	if groupData.MemberIDs[0] == groupData.MemberIDs[1] {
		t.Fatal("duplicate names collapsed to one runtime identity")
	}
	if data.NodesByID[proxyA.Id()].ProviderName != "provider-a" {
		t.Fatalf("provider-a metadata = %#v", data.NodesByID[proxyA.Id()])
	}
	if data.NodesByID[proxyB.Id()].ProviderName != "provider-b" {
		t.Fatalf("provider-b metadata = %#v", data.NodesByID[proxyB.Id()])
	}
	if data.NodesByID[proxyA.Id()].StableKey == data.NodesByID[proxyB.Id()].StableKey {
		t.Fatal("stable provider identities collided")
	}
}

func TestChangeProxyByRuntimeIDAndGeneration(t *testing.T) {
	group, _, proxyB := installIdentityTestRuntime(t)
	data := handleGetProxies()
	generation := data.Generation
	groupID := group.Id()
	memberID := proxyB.Id()
	if got := invokeProxyChangeForTest(t, ChangeProxyParams{
		GroupID:    &groupID,
		MemberID:   &memberID,
		Generation: &generation,
	}); got != "" {
		t.Fatalf("runtime change failed: %s", got)
	}
	selected := group.Adapter().(outboundgroup.ProxyGroup).NowProxy()
	if selected.Id() != proxyB.Id() {
		t.Fatalf("selected ID = %q, want %q", selected.Id(), proxyB.Id())
	}

	tunnel.RefreshAllProxies()
	if got := invokeProxyChangeForTest(t, ChangeProxyParams{
		GroupID:    &groupID,
		MemberID:   &memberID,
		Generation: &generation,
	}); got != "stale proxy snapshot" {
		t.Fatalf("stale result = %q", got)
	}
}

func TestChangeProxyAcceptsProviderRefreshAfterStableSelection(t *testing.T) {
	oldProxies := tunnel.Proxies()
	oldProviders := tunnel.Providers()
	oldNames := append([]string(nil), config.GetProxyNameList()...)

	proxyA := newIdentityTestProxy("same", "provider-a")
	proxyB := newIdentityTestProxy("same", "provider-b")
	providerA := newIdentityTestProvider(t, "provider-a", proxyA)
	providerB := newIdentityTestProvider(t, "provider-b", proxyB)
	selector := &refreshingSelector{Selector: outboundgroup.NewSelector(
		&outboundgroup.GroupCommonOption{Name: "GROUP", URL: C.DefaultTestURL},
		proxyA,
		[]P.ProxyProvider{providerA, providerB},
	)}
	group := adapter.NewProxy(selector)
	tunnel.UpdateProxies(
		map[string]C.Proxy{"GROUP": group},
		map[string]P.ProxyProvider{
			"provider-a": providerA,
			"provider-b": providerB,
		},
	)
	config.SetProxyNameList([]string{"GROUP"})
	t.Cleanup(func() {
		config.SetProxyNameList(oldNames)
		tunnel.UpdateProxies(oldProxies, oldProviders)
		_ = providerA.Close()
		_ = providerB.Close()
	})

	data := handleGetProxies()
	groupID := group.Id()
	memberID := proxyB.Id()
	if got := invokeProxyChangeForTest(t, ChangeProxyParams{
		GroupID:    &groupID,
		MemberID:   &memberID,
		Generation: &data.Generation,
	}); got != "" {
		t.Fatalf("provider refresh made a stable selection stale: %s", got)
	}
	if selected := selector.NowProxy(); !sameStableProxy(selected, proxyB) {
		t.Fatalf("selected proxy = %#v, want provider-b/same", selected)
	}
}

func TestLegacyChangeProxyRejectsAmbiguousName(t *testing.T) {
	installIdentityTestRuntime(t)
	groupName := "GROUP"
	proxyName := "same"
	got := invokeProxyChangeForTest(t, ChangeProxyParams{
		GroupName: &groupName,
		ProxyName: &proxyName,
	})
	if !strings.Contains(got, "ambiguous") {
		t.Fatalf("legacy duplicate-name result = %q", got)
	}
}

func TestRuntimeProxySnapshotMetadataHasBoundedJSONOverhead(t *testing.T) {
	oldProxies := tunnel.Proxies()
	oldProviders := tunnel.Providers()
	oldNames := append([]string(nil), config.GetProxyNameList()...)

	const nodeCount = 1000
	nodes := make([]C.Proxy, 0, nodeCount)
	for i := 0; i < nodeCount; i++ {
		nodes = append(nodes, newIdentityTestProxy(
			"node-"+strconv.Itoa(i),
			"provider",
		))
	}
	provider := newIdentityTestProvider(t, "provider", nodes...)
	group := adapter.NewProxy(outboundgroup.NewSelector(
		&outboundgroup.GroupCommonOption{Name: "GROUP", URL: C.DefaultTestURL},
		nodes[0],
		[]P.ProxyProvider{provider},
	))
	tunnel.UpdateProxies(
		map[string]C.Proxy{"GROUP": group},
		map[string]P.ProxyProvider{"provider": provider},
	)
	config.SetProxyNameList([]string{"GROUP"})
	t.Cleanup(func() {
		config.SetProxyNameList(oldNames)
		tunnel.UpdateProxies(oldProxies, oldProviders)
		_ = provider.Close()
	})

	data := handleGetProxies()
	fullJSON, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	legacyJSON, err := json.Marshal(struct {
		Proxies map[string]C.Proxy `json:"proxies"`
		All     []string           `json:"all"`
	}{Proxies: data.Proxies, All: data.All})
	if err != nil {
		t.Fatal(err)
	}
	overhead := len(fullJSON) - len(legacyJSON)
	const maxMetadataBytesPerNode = 384
	if overhead > nodeCount*maxMetadataBytesPerNode {
		t.Fatalf(
			"runtime metadata overhead = %d bytes for %d nodes",
			overhead,
			nodeCount,
		)
	}
	t.Logf(
		"runtime metadata overhead = %d bytes (%.1f bytes/node)",
		overhead,
		float64(overhead)/nodeCount,
	)
}
