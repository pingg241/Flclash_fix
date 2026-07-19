package main

import (
	"encoding/json"
	"github.com/metacubex/mihomo/adapter/provider"
	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"net/netip"
	"time"
)

type InitParams struct {
	HomeDir string `json:"home-dir"`
	Version int    `json:"version"`
}

type SetupParams struct {
	SelectedMap map[string]string `json:"selected-map"`
	TestURL     string            `json:"test-url"`
}

type UpdateParams struct {
	Tun                *tunSchema         `json:"tun"`
	AllowLan           *bool              `json:"allow-lan"`
	MixedPort          *int               `json:"mixed-port"`
	FindProcessMode    *P.FindProcessMode `json:"find-process-mode"`
	Mode               *tunnel.TunnelMode `json:"mode"`
	LogLevel           *log.LogLevel      `json:"log-level"`
	IPv6               *bool              `json:"ipv6"`
	Sniffing           *bool              `json:"sniffing"`
	TCPConcurrent      *bool              `json:"tcp-concurrent"`
	ExternalController *string            `json:"external-controller"`
	Interface          *string            `json:"interface-name"`
	UnifiedDelay       *bool              `json:"unified-delay"`
	GeoAutoUpdate      *bool              `json:"geo-auto-update"`
	GeoUpdateInterval  *int               `json:"geo-update-interval"`
}

type tunSchema struct {
	Enable       bool               `yaml:"enable" json:"enable"`
	Device       *string            `yaml:"device" json:"device"`
	Stack        *constant.TUNStack `yaml:"stack" json:"stack"`
	DNSHijack    *[]string          `yaml:"dns-hijack" json:"dns-hijack"`
	AutoRoute    *bool              `yaml:"auto-route" json:"auto-route"`
	RouteAddress *[]netip.Prefix    `yaml:"route-address" json:"route-address,omitempty"`
}

type ChangeProxyParams struct {
	GroupName  *string `json:"group-name"`
	ProxyName  *string `json:"proxy-name"`
	GroupID    *string `json:"group-id"`
	MemberID   *string `json:"member-id"`
	Generation *uint64 `json:"generation"`
}

type TestDelayParams struct {
	ProxyName string `json:"proxy-name"`
	TestUrl   string `json:"test-url"`
	Timeout   int64  `json:"timeout"`
}

type ExternalProvider struct {
	Name             string                     `json:"name"`
	Type             string                     `json:"type"`
	VehicleType      string                     `json:"vehicle-type"`
	Count            int                        `json:"count"`
	Path             string                     `json:"path"`
	UpdateAt         time.Time                  `json:"update-at"`
	SubscriptionInfo *provider.SubscriptionInfo `json:"subscription-info"`
}

type ProxiesData struct {
	Proxies    map[string]constant.Proxy    `json:"proxies"`
	All        []string                     `json:"all"`
	Generation uint64                       `json:"generation"`
	Groups     []ProxyGroupSnapshot         `json:"groups"`
	NodesByID  map[string]ProxyNodeSnapshot `json:"nodesById"`
}

type ProxyGroupSnapshot struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Type      string   `json:"type"`
	NowID     string   `json:"nowId,omitempty"`
	MemberIDs []string `json:"memberIds"`
}

type ProxyNodeSnapshot struct {
	ID           string `json:"id"`
	StableKey    string `json:"stableKey"`
	Name         string `json:"name"`
	Type         string `json:"type"`
	ProviderName string `json:"providerName,omitempty"`
}

type ProxyServerGeoParams struct {
	Generation      uint64   `json:"generation"`
	NetworkRevision uint64   `json:"networkRevision,omitempty"`
	RequestID       string   `json:"requestId,omitempty"`
	All             bool     `json:"all,omitempty"`
	MemberIDs       []string `json:"memberIds,omitempty"`
}

type GeoDatabaseGeneration struct {
	Country uint64 `json:"country"`
	ASN     uint64 `json:"asn"`
}

type ProxyGeoAddress struct {
	IP          string `json:"ip"`
	CountryCode string `json:"countryCode,omitempty"`
	ASN         string `json:"asn,omitempty"`
	ASO         string `json:"aso,omitempty"`
}

type ProxyServerGeo struct {
	MemberID    string            `json:"memberId"`
	ServerHost  string            `json:"serverHost,omitempty"`
	Source      string            `json:"source,omitempty"`
	Status      string            `json:"status"`
	MultiRegion bool              `json:"multiRegion,omitempty"`
	Addresses   []ProxyGeoAddress `json:"addresses,omitempty"`
}

type ProxyServerGeos struct {
	Generation   uint64                    `json:"generation"`
	RequestID    string                    `json:"requestId,omitempty"`
	Stale        bool                      `json:"stale,omitempty"`
	DBGeneration GeoDatabaseGeneration     `json:"dbGeneration"`
	Members      map[string]ProxyServerGeo `json:"members"`
}

type ProbeProxyExitParams struct {
	Generation      uint64 `json:"generation"`
	NetworkRevision uint64 `json:"networkRevision,omitempty"`
	RequestID       string `json:"requestId,omitempty"`
	GroupID         string `json:"groupId"`
	MemberID        string `json:"memberId"`
}

type ProxyExitGeo struct {
	Generation   uint64                `json:"generation"`
	RequestID    string                `json:"requestId,omitempty"`
	Stale        bool                  `json:"stale,omitempty"`
	LeafID       string                `json:"leafId,omitempty"`
	PathIDs      []string              `json:"pathIds,omitempty"`
	RouteSample  bool                  `json:"routeSample,omitempty"`
	Cached       bool                  `json:"cached,omitempty"`
	IP           string                `json:"ip,omitempty"`
	CountryCode  string                `json:"countryCode,omitempty"`
	ASN          string                `json:"asn,omitempty"`
	ASO          string                `json:"aso,omitempty"`
	DBGeneration GeoDatabaseGeneration `json:"dbGeneration"`
}

// TrafficData is the wire shape for live / total traffic counters.
type TrafficData struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

// TrafficSnapshot returns live speed and cumulative totals in one payload.
type TrafficSnapshot struct {
	Now   TrafficData `json:"now"`
	Total TrafficData `json:"total"`
}

// maxIPCFrameSize caps desktop socket frames (setup configs can be large).
const maxIPCFrameSize = 64 << 20 // 64 MiB

const (
	messageMethod                  Method = "message"
	initClashMethod                Method = "initClash"
	getIsInitMethod                Method = "getIsInit"
	forceGcMethod                  Method = "forceGc"
	shutdownMethod                 Method = "shutdown"
	validateConfigMethod           Method = "validateConfig"
	updateConfigMethod             Method = "updateConfig"
	getProxiesMethod               Method = "getProxies"
	getProxyServerGeosMethod       Method = "getProxyServerGeos"
	probeProxyExitMethod           Method = "probeProxyExit"
	changeProxyMethod              Method = "changeProxy"
	getTrafficMethod               Method = "getTraffic"
	getTotalTrafficMethod          Method = "getTotalTraffic"
	getTrafficSnapshotMethod       Method = "getTrafficSnapshot"
	resetTrafficMethod             Method = "resetTraffic"
	asyncTestDelayMethod           Method = "asyncTestDelay"
	getConnectionsMethod           Method = "getConnections"
	closeConnectionsMethod         Method = "closeConnections"
	resetConnectionsMethod         Method = "resetConnections"
	closeConnectionMethod          Method = "closeConnection"
	getExternalProvidersMethod     Method = "getExternalProviders"
	getExternalProviderMethod      Method = "getExternalProvider"
	getCountryCodeMethod           Method = "getCountryCode"
	getMemoryMethod                Method = "getMemory"
	updateGeoDataMethod            Method = "updateGeoData"
	updateExternalProviderMethod   Method = "updateExternalProvider"
	sideLoadExternalProviderMethod Method = "sideLoadExternalProvider"
	startLogMethod                 Method = "startLog"
	stopLogMethod                  Method = "stopLog"
	startListenerMethod            Method = "startListener"
	stopListenerMethod             Method = "stopListener"
	updateDnsMethod                Method = "updateDns"
	crashMethod                    Method = "crash"
	setupConfigMethod              Method = "setupConfig"
	getConfigMethod                Method = "getConfig"
	deleteFile                     Method = "deleteFile"
	prepareTunHelperMethod         Method = "prepareTunHelper"
	releaseTunHelperMethod         Method = "releaseTunHelper"
)

type Method string

type MessageType string

type Delay struct {
	Url   string `json:"url"`
	Name  string `json:"name"`
	Value int32  `json:"value"`
}

type Message struct {
	Type MessageType `json:"type"`
	Data interface{} `json:"data"`
}

const (
	LogMessage       MessageType = "log"
	DelayMessage     MessageType = "delay"
	RequestMessage   MessageType = "request"
	LoadedMessage    MessageType = "loaded"
	GeoUpdateMessage MessageType = "geoUpdate"
)

type GeoUpdateStatus struct {
	Type     string `json:"type"`
	Updating bool   `json:"updating"`
	Skipped  bool   `json:"skipped,omitempty"`
	Error    string `json:"error,omitempty"`
}

func (message *Message) Json() (string, error) {
	data, err := json.Marshal(message)
	return string(data), err
}

func requiredEventMetadata(message Message) (MessageType, string, bool) {
	switch message.Type {
	case LoadedMessage:
		key, _ := message.Data.(string)
		return message.Type, key, true
	case GeoUpdateMessage:
		switch status := message.Data.(type) {
		case GeoUpdateStatus:
			return message.Type, status.Type, true
		case *GeoUpdateStatus:
			if status != nil {
				return message.Type, status.Type, true
			}
		}
		return message.Type, "", true
	default:
		return "", "", false
	}
}
