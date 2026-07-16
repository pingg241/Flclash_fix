package main

import (
	"bytes"
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"net"
	"runtime"
	"runtime/debug"
	"slices"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/constant/features"
	cp "github.com/metacubex/mihomo/constant/provider"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	isInit            atomic.Bool
	externalProviders = map[string]cp.Provider{}
	logSubscriber     observable.Subscription[log.Event]
	delaySlots        = make(chan struct{}, 30)
)

const (
	defaultDelayTimeout = 5 * time.Second
	maximumDelayTimeout = 30 * time.Second
	delaySlotWaitLimit  = time.Second
)

func handleInitClash(paramsString string) bool {
	var params = InitParams{}
	err := json.Unmarshal([]byte(paramsString), &params)
	if err != nil {
		return false
	}
	if err := initializeHomeDir(params.HomeDir); err != nil {
		logError("initialize home dir: %v", err)
		return false
	}
	runLock.Lock()
	defer runLock.Unlock()
	version.Store(int64(params.Version))
	isInit.Store(true)
	return true
}

func handleStartListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	if isRunning.Load() {
		return true
	}
	if currentConfig == nil {
		return false
	}
	if err := corehub.StartRuntime(currentConfig); err != nil {
		logError("start runtime: %v", err)
		return false
	}
	if err := startListeners(currentConfig); err != nil {
		logError("start listeners: %v", err)
		_ = corehub.StopRuntime()
		return false
	}
	isRunning.Store(true)
	resolver.ResetConnection()
	return true
}

func handleStopListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	if !isRunning.Load() {
		return true
	}
	stopErr := corehub.StopRuntime()
	isRunning.Store(false)
	resolver.ResetConnection()
	if stopErr == nil {
		return true
	}

	recoverErr := recoverRuntimeLocked()
	if recoverErr == nil {
		logError("stop runtime failed; previous runtime restored: %v", stopErr)
		return false
	}
	cleanupErr := corehub.StopRuntime()
	isRunning.Store(false)
	logError("stop runtime failed and recovery failed: %v", errors.Join(stopErr, recoverErr, cleanupErr))
	return false
}

func handleGetIsInit() bool {
	return isInit.Load()
}

func recoverRuntimeLocked() error {
	if currentConfig == nil {
		return errors.New("current config is unavailable")
	}
	if err := corehub.StartRuntime(currentConfig); err != nil {
		return err
	}
	if err := startListeners(currentConfig); err != nil {
		return errors.Join(err, corehub.StopRuntime())
	}
	isRunning.Store(true)
	resolver.ResetConnection()
	return nil
}

func handleForceGC() {
	log.Infoln("[APP] request force GC")
	runtime.GC()
	if features.Android {
		debug.FreeOSMemory()
	}
}

func handleShutdown() bool {
	runLock.Lock()
	defer runLock.Unlock()
	stopErr := corehub.StopRuntime()
	helperErr := releaseDarwinTunHelper()
	isRunning.Store(false)
	executor.Shutdown()
	handleForceGC()
	isInit.Store(false)
	if stopErr != nil || helperErr != nil {
		logError("stop runtime for shutdown: %v", errors.Join(stopErr, helperErr))
		return false
	}
	return true
}

func handleValidateConfig(path string) string {
	buf, err := readFile(path)
	if err != nil {
		return err.Error()
	}
	bufWithoutBOM := bytes.TrimPrefix(buf, []byte{0xEF, 0xBB, 0xBF})
	if len(bytes.Trim(bufWithoutBOM, " \t\r\n")) == 0 {
		return "config is empty"
	}
	_, err = config.UnmarshalRawConfig(buf)
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleGetProxies() ProxiesData {
	// AllProxies is a COW snapshot; no global runLock needed for reads.
	nameList := config.GetProxyNameList()
	proxies := tunnel.AllProxies()

	hasGlobal := false
	allNames := make([]string, 0, len(nameList)+1)

	for _, name := range nameList {
		if name == "GLOBAL" {
			hasGlobal = true
		}

		p, ok := proxies[name]
		if !ok || p == nil {
			continue
		}
		switch p.Type() {
		case constant.Selector, constant.URLTest, constant.Fallback, constant.Relay, constant.LoadBalance:
			allNames = append(allNames, name)
		default:
		}
	}

	if !hasGlobal {
		if p, ok := proxies["GLOBAL"]; ok && p != nil {
			allNames = append([]string{"GLOBAL"}, allNames...)
		}
	}

	return ProxiesData{
		All:     allNames,
		Proxies: proxies,
	}
}

func handleChangeProxy(data string, fn func(string string)) {
	var params = &ChangeProxyParams{}
	err := json.Unmarshal([]byte(data), params)
	if err != nil {
		fn(err.Error())
		return
	}
	if params.GroupName == nil || params.ProxyName == nil {
		fn("invalid change proxy params")
		return
	}
	groupName := *params.GroupName
	proxyName := *params.ProxyName
	proxies := tunnel.AllProxies()
	group, ok := proxies[groupName]
	if !ok {
		fn("Not found group")
		return
	}
	adapterProxy, ok := group.(*adapter.Proxy)
	if !ok {
		fn("Invalid group")
		return
	}
	selector, ok := adapterProxy.ProxyAdapter.(outboundgroup.SelectAble)
	if !ok {
		fn("Group is not selectable")
		return
	}
	if proxyName == "" {
		selector.ForceSet(proxyName)
	} else {
		err = selector.Set(proxyName)
	}
	if err != nil {
		fn(err.Error())
		return
	}
	fn("")
}

func trafficData(up, down int64) TrafficData {
	return TrafficData{Up: up, Down: down}
}

// handleGetTraffic returns structured traffic (no pre-stringified JSON).
func handleGetTraffic(onlyStatisticsProxy bool) TrafficData {
	up, down := statistic.DefaultManager.NowTraffic(onlyStatisticsProxy)
	return trafficData(up, down)
}

func handleGetTotalTraffic(onlyStatisticsProxy bool) TrafficData {
	up, down := statistic.DefaultManager.TotalTraffic(onlyStatisticsProxy)
	return trafficData(up, down)
}

// handleGetTrafficSnapshot returns now + total in one RPC to cut UI poll cost.
func handleGetTrafficSnapshot(onlyStatisticsProxy bool) TrafficSnapshot {
	up, down := statistic.DefaultManager.NowTraffic(onlyStatisticsProxy)
	totalUp, totalDown := statistic.DefaultManager.TotalTraffic(onlyStatisticsProxy)
	return TrafficSnapshot{
		Now:   trafficData(up, down),
		Total: trafficData(totalUp, totalDown),
	}
}

// marshalTrafficJSON is used by CGO exports that must return a C string.
func marshalTrafficJSON(v any) string {
	data, err := json.Marshal(v)
	if err != nil {
		logError("traffic marshal: %s", err)
		return ""
	}
	return string(data)
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func encodeDelay(d *Delay) string {
	data, err := json.Marshal(d)
	if err != nil {
		return ""
	}
	return string(data)
}

// emptyExpectedStatus is reused for delay tests that accept any HTTP status.
var emptyExpectedStatus = mustEmptyStatusRanges()

func mustEmptyStatusRanges() utils.IntRanges[uint16] {
	r, err := utils.NewUnsignedRanges[uint16]("")
	if err != nil {
		return nil
	}
	return r
}

func handleAsyncTestDelay(paramsString string, fn func(string)) {
	var params = &TestDelayParams{}
	err := json.Unmarshal([]byte(paramsString), params)
	if err != nil {
		fn("")
		return
	}

	timeout, ok := delayTimeout(params.Timeout)
	if !ok {
		fn(encodeDelay(&Delay{Name: params.ProxyName, Value: -1}))
		return
	}

	queueTimeout := min(timeout, delaySlotWaitLimit)
	queueCtx, cancelQueue := context.WithTimeout(context.Background(), queueTimeout)
	defer cancelQueue()
	if !acquireDelaySlot(queueCtx) {
		fn(encodeDelay(&Delay{Name: params.ProxyName, Value: -1}))
		return
	}
	defer func() { <-delaySlots }()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	proxies := tunnel.AllProxies()
	proxy := proxies[params.ProxyName]

	delayData := &Delay{
		Name: params.ProxyName,
	}

	if proxy == nil {
		delayData.Value = -1
		fn(encodeDelay(delayData))
		return
	}

	testUrl := constant.DefaultTestURL
	if params.TestUrl != "" {
		testUrl = params.TestUrl
	}
	delayData.Url = testUrl
	delay, err := proxy.URLTest(ctx, testUrl, emptyExpectedStatus)
	if err != nil || delay == 0 {
		delayData.Value = -1
		fn(encodeDelay(delayData))
		return
	}

	delayData.Value = int32(delay)
	fn(encodeDelay(delayData))
}

func acquireDelaySlot(ctx context.Context) bool {
	select {
	case delaySlots <- struct{}{}:
		return true
	case <-ctx.Done():
		return false
	}
}

func delayTimeout(milliseconds int64) (time.Duration, bool) {
	if milliseconds <= 0 {
		return defaultDelayTimeout, true
	}
	if milliseconds > maximumDelayTimeout.Milliseconds() {
		return 0, false
	}
	return time.Duration(milliseconds) * time.Millisecond, true
}

// handleGetConnections returns the live connection snapshot object (single JSON encode on the wire).
func handleGetConnections() any {
	// Snapshot only reads concurrent maps/atomics — no runLock.
	return statistic.DefaultManager.Snapshot()
}

func handleCloseConnections() bool {
	return statistic.DefaultManager.CloseAll() == nil
}

func handleResetConnections() bool {
	resolver.ResetConnection()
	return true
}

func handleCloseConnection(connectionId string) bool {
	found, err := statistic.DefaultManager.Close(connectionId)
	return found && err == nil
}

func handleGetExternalProviders() []ExternalProvider {
	runLock.Lock()
	defer runLock.Unlock()
	// Refresh module-level cache for any legacy readers; primary path uses live lookup.
	externalProviders = getExternalProvidersRaw()
	eps := make([]ExternalProvider, 0, len(externalProviders))
	for _, p := range externalProviders {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	slices.SortFunc(eps, func(a, b ExternalProvider) int {
		return cmp.Compare(a.Name, b.Name)
	})
	return eps
}

func handleGetExternalProvider(externalProviderName string) *ExternalProvider {
	runLock.Lock()
	defer runLock.Unlock()
	externalProvider, exist := lookupExternalProvider(externalProviderName)
	if !exist {
		return nil
	}
	e, err := toExternalProvider(externalProvider)
	if err != nil {
		return nil
	}
	return e
}

func handleUpdateGeoData(geoType string) error {
	return updater.UpdateGeoResource(geoType)
}

func handleUpdateExternalProvider(providerName string, fn func(value string)) {
	externalProvider, exist := lookupExternalProvider(providerName)
	if !exist {
		fn("external provider is not exist")
		return
	}
	err := externalProvider.Update()
	if err != nil {
		fn(err.Error())
		return
	}
	fn("")
}

func handleSideLoadExternalProvider(providerName string, data []byte, fn func(value string)) {
	runLock.Lock()
	defer runLock.Unlock()
	externalProvider, exist := lookupExternalProvider(providerName)
	if !exist {
		fn("external provider is not exist")
		return
	}
	err := sideUpdateExternalProvider(externalProvider, data)
	if err != nil {
		fn(err.Error())
		return
	}
	fn("")
}

func handleSuspend(suspended bool) bool {
	if suspended {
		tunnel.OnSuspend()
	} else {
		tunnel.OnRunning()
	}
	return true
}

func handleStartLog() {
	runLock.Lock()
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	logSubscriber = log.Subscribe()
	sub := logSubscriber
	runLock.Unlock()
	go func() {
		for logData := range sub {
			// emit already level-gates; keep a cheap re-check for late subscribers
			if logData.LogLevel < log.Level() {
				continue
			}
			sendMessage(Message{
				Type: LogMessage,
				Data: logData,
			})
		}
	}()
}

func handleStopLog() {
	runLock.Lock()
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	runLock.Unlock()
}

func handleGetCountryCode(ip string, fn func(value string)) {
	// MMDB lookup is read-only; skip runLock and extra goroutine when already
	// dispatched from handleAction's goroutine (desktop/Android invoke paths).
	parsed := net.ParseIP(ip)
	if parsed == nil {
		fn("")
		return
	}
	codes := mmdb.IPInstance().LookupCode(parsed)
	if len(codes) == 0 {
		fn("")
		return
	}
	fn(codes[0])
}

func handleGetMemory(fn func(value string)) {
	fn(strconv.FormatUint(statistic.DefaultManager.Memory(), 10))
}

func handleGetConfig(path string) (*config.RawConfig, error) {
	bytes, err := readFile(path)
	if err != nil {
		return nil, err
	}
	prof, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		return nil, err
	}
	return prof, nil
}

func handleCrash() {
	panic("handle invoke crash")
}

func handleUpdateConfig(bytes []byte) string {
	var params = &UpdateParams{}
	err := json.Unmarshal(bytes, params)
	if err != nil {
		return err.Error()
	}
	if err := updateConfig(params); err != nil {
		return err.Error()
	}
	return ""
}

func handleDelFile(path string, result ActionResult) {
	root, rel, err := openHomePath(path)
	if err != nil {
		result.success(err.Error())
		return
	}
	defer root.Close()
	if rel == "." {
		result.success("refusing to delete home directory")
		return
	}
	err = root.RemoveAll(rel)
	if err != nil {
		result.success(err.Error())
		return
	}
	result.success("")
}

func handleSetupConfig(bytes []byte) string {
	if !isInit.Load() {
		return "not initialized"
	}
	var params = defaultSetupParams()
	err := UnmarshalJson(bytes, params)
	if err != nil {
		logError("unmarshalRawConfig error %v", err)
		return err.Error()
	}
	err = applyConfig(params)
	if err != nil {
		return err.Error()
	}
	return ""
}

func init() {
	route.SetEmbedMode(true)
	// Wire Meta provider hot-update → COW proxy map refresh (avoids import cycle
	// that would occur if tunnel imported adapter/provider).
	provider.OnProxyProviderUpdated = tunnel.RefreshAllProxies

	adapter.UrlTestHook = func(url string, name string, delay uint16) {
		delayData := &Delay{
			Url:  url,
			Name: name,
		}
		if delay == 0 {
			delayData.Value = -1
		} else {
			delayData.Value = int32(delay)
		}
		sendMessage(Message{
			Type: DelayMessage,
			Data: delayData,
		})
	}
	// Bounded async queue so Join never blocks on IPC, and connection storms
	// cannot spawn unlimited goroutines.
	requestNotifyCh := make(chan *statistic.TrackerInfo, 256)
	go func() {
		for info := range requestNotifyCh {
			sendMessage(Message{
				Type: RequestMessage,
				Data: info,
			})
		}
	}()
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		info := c.Info()
		select {
		case requestNotifyCh <- info:
		default:
			// drop under backpressure — prefer accepting traffic over UI fidelity
		}
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		sendMessage(Message{
			Type: LoadedMessage,
			Data: providerName,
		})
	}
	updater.GeoUpdateHook = func(geoType string, updating bool, skipped bool, updateErr error) {
		status := GeoUpdateStatus{
			Type:     geoType,
			Updating: updating,
			Skipped:  skipped,
		}
		if updateErr != nil {
			status.Error = updateErr.Error()
		}
		sendMessage(Message{
			Type: GeoUpdateMessage,
			Data: status,
		})
	}
}
