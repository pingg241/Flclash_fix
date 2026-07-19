package main

import (
	"bytes"
	"cmp"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net"
	"reflect"
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
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	isInit                atomic.Bool
	externalProviders     = map[string]cp.Provider{}
	logSubscriber         observable.Subscription[log.Event]
	delaySlots            = make(chan struct{}, 30)
	providerForUpdate     = lookupExternalProvider
	sideUpdateProvider    = sideUpdateExternalProvider
	runtimeCleanupPending atomic.Bool
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
	if isRunning.Load() {
		runLock.Unlock()
		return true
	}
	bumpRuntimeStateEpoch()
	if runtimeCleanupPending.Load() {
		if err := stopCoreRuntime(); err != nil {
			bumpRuntimeStateEpoch()
			logError("retry runtime cleanup: %v", err)
			runLock.Unlock()
			return false
		}
		runtimeCleanupPending.Store(false)
	}
	if currentConfig == nil {
		runLock.Unlock()
		return false
	}
	candidate := currentConfig
	generation := runtimeStartGen.Add(1)
	epoch := runtimeStateEpoch.Load()
	runLock.Unlock()

	transaction, err := beginCoreRuntimeStart(candidate)
	runLock.Lock()
	defer runLock.Unlock()
	stale := runtimeStartGen.Load() != generation ||
		runtimeStateChangedSince(epoch, candidate, false)
	if err != nil {
		if !stale {
			bumpRuntimeStateEpoch()
			logError("start runtime: %v", err)
		}
		return false
	}
	if transaction == nil {
		if !stale {
			bumpRuntimeStateEpoch()
			logError("start runtime: transaction is unavailable")
		}
		return false
	}
	if stale {
		rollbackErr := transaction.Rollback()
		if isRuntimeStartFinalizedError(rollbackErr) {
			rollbackErr = nil
		}
		if rollbackErr != nil {
			logError("rollback stale runtime start: %v", rollbackErr)
		}
		return false
	}
	finalized := false
	defer func() {
		if !finalized {
			_ = transaction.Rollback()
		}
	}()
	if err := transaction.Commit(); err != nil {
		finalized = true
		rollbackErr := transaction.Rollback()
		runtimeCleanupPending.Store(rollbackErr != nil)
		bumpRuntimeStateEpoch()
		logError("activate runtime: %v", errors.Join(err, rollbackErr))
		return false
	}
	if err := verifyRuntimeListeners(candidate); err != nil {
		finalized = true
		cleanupErr := stopCoreRuntime()
		runtimeCleanupPending.Store(cleanupErr != nil)
		bumpRuntimeStateEpoch()
		logError("verify runtime listeners: %v", errors.Join(err, cleanupErr))
		return false
	}
	finalized = true
	isRunning.Store(true)
	runtimeCleanupPending.Store(false)
	resolver.ResetConnection()
	bumpRuntimeStateEpoch()
	return true
}

func handleStopListener() bool {
	cancelActiveProxyGeoRequests()
	runtimeStartGen.Add(1)
	lockRunAfterCancelingConfigApply()
	defer runLock.Unlock()
	bumpRuntimeStateEpoch()
	if !isRunning.Load() && !runtimeCleanupPending.Load() {
		return true
	}
	stopErr := stopCoreRuntime()
	isRunning.Store(false)
	runtimeCleanupPending.Store(stopErr != nil)
	resolver.ResetConnection()
	bumpRuntimeStateEpoch()
	if stopErr != nil {
		logError("stop runtime failed: %v", stopErr)
	}
	// StopRuntime commits the stopped/suspended state before best-effort cleanup.
	// Report the stop intent as complete so callers clear their runtime state.
	return true
}

func handleGetIsInit() bool {
	return isInit.Load()
}

func handleForceGC() {
	log.Infoln("[APP] request force GC")
	runtime.GC()
	if features.Android {
		debug.FreeOSMemory()
	}
}

func handleShutdown() bool {
	cancelActiveProxyGeoRequests()
	cancelActiveGeoUpdate()
	runtimeStartGen.Add(1)
	lockRunAfterCancelingConfigApply()
	defer runLock.Unlock()
	bumpRuntimeStateEpoch()
	discardErr := discardCoreConfig()
	helperErr := releaseDarwinTunHelper()
	currentConfig = nil
	isRunning.Store(false)
	runtimeCleanupPending.Store(false)
	// Hub discard clears both ownership layers; executor shutdown then persists
	// resolver state and is intentionally idempotent.
	shutdownCore()
	handleForceGC()
	isInit.Store(false)
	bumpRuntimeStateEpoch()
	if discardErr != nil || helperErr != nil {
		logError("shutdown cleanup: %v", errors.Join(discardErr, helperErr))
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
	// A full config apply holds runLock. Capture its ordered group list and the
	// immutable tunnel snapshot together, then build the response lock-free.
	runLock.Lock()
	nameList := append([]string(nil), config.GetProxyNameList()...)
	snapshot := tunnel.AllProxiesSnapshot()
	runLock.Unlock()
	proxies := snapshot.Proxies

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

	nodesByID := make(map[string]ProxyNodeSnapshot, len(snapshot.ByID))
	for id, proxy := range snapshot.ByID {
		nodesByID[id] = newProxyNodeSnapshot(proxy)
	}
	groups := make([]ProxyGroupSnapshot, 0, len(allNames))
	for _, name := range allNames {
		proxy := proxies[name]
		if proxy == nil {
			continue
		}
		group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
		if !ok {
			continue
		}
		members := snapshot.Members[proxy.Id()]
		memberIDs := make([]string, 0, len(members))
		memberSet := make(map[string]struct{}, len(members))
		for _, member := range members {
			memberIDs = append(memberIDs, member.Id())
			memberSet[member.Id()] = struct{}{}
		}
		nowID := ""
		if current := group.NowProxy(); current != nil {
			if _, exists := memberSet[current.Id()]; exists {
				nowID = current.Id()
			}
		}
		groups = append(groups, ProxyGroupSnapshot{
			ID:        proxy.Id(),
			Name:      proxy.Name(),
			Type:      proxy.Type().String(),
			NowID:     nowID,
			MemberIDs: memberIDs,
		})
	}

	return ProxiesData{
		All:        allNames,
		Proxies:    proxies,
		Generation: snapshot.Generation,
		Groups:     groups,
		NodesByID:  nodesByID,
	}
}

func newProxyNodeSnapshot(proxy constant.Proxy) ProxyNodeSnapshot {
	providerName := proxy.ProxyInfo().ProviderName
	stableKey := base64.RawURLEncoding.EncodeToString([]byte(providerName + "\x00" + proxy.Name()))
	return ProxyNodeSnapshot{
		ID:           proxy.Id(),
		StableKey:    stableKey,
		Name:         proxy.Name(),
		Type:         proxy.Type().String(),
		ProviderName: providerName,
	}
}

func handleChangeProxy(data string, fn func(string string)) {
	var params = &ChangeProxyParams{}
	err := json.Unmarshal([]byte(data), params)
	if err != nil {
		fn(err.Error())
		return
	}
	runLock.Lock()
	defer runLock.Unlock()

	if params.GroupID != nil || params.MemberID != nil || params.Generation != nil {
		handleChangeProxyByID(params, fn)
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
	bumpRuntimeStateEpoch()
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

func handleChangeProxyByID(params *ChangeProxyParams, fn func(string)) {
	if params.GroupID == nil || params.MemberID == nil || params.Generation == nil {
		fn("invalid runtime proxy params")
		return
	}
	snapshot := tunnel.AllProxiesSnapshot()
	if snapshot.Generation != *params.Generation {
		fn("stale proxy snapshot")
		return
	}
	groupProxy := snapshot.ByID[*params.GroupID]
	if groupProxy == nil {
		fn("proxy group ID not found")
		return
	}
	group, ok := groupProxy.Adapter().(outboundgroup.ProxyGroup)
	if !ok {
		fn("proxy group ID is not a group")
		return
	}
	selectable, ok := group.(outboundgroup.SelectAble)
	if !ok {
		fn("proxy group is not selectable")
		return
	}
	var requestedMember constant.Proxy
	if *params.MemberID == "" {
		bumpRuntimeStateEpoch()
		selectable.ForceSet("")
	} else {
		for _, member := range snapshot.Members[groupProxy.Id()] {
			if member.Id() == *params.MemberID {
				requestedMember = member
				break
			}
		}
		if requestedMember == nil {
			fn("proxy member ID is not in group")
			return
		}
		selectableByID, ok := group.(outboundgroup.SelectAbleByID)
		if !ok {
			fn("proxy group does not support runtime IDs")
			return
		}
		bumpRuntimeStateEpoch()
		if err := selectableByID.SetByID(*params.MemberID); err != nil {
			fn(err.Error())
			return
		}
	}
	latest := tunnel.AllProxiesSnapshot()
	if latest.Generation != *params.Generation {
		// A provider refresh advances the generation without replacing the group.
		// Accept the operation when its stable target is still selected; a full
		// config apply gives the group a new runtime ID and remains stale.
		if latest.ByID[groupProxy.Id()] == nil {
			fn("stale proxy snapshot")
			return
		}
		if requestedMember != nil {
			current := group.NowProxy()
			if current == nil || !sameStableProxy(current, requestedMember) {
				fn("stale proxy snapshot")
				return
			}
		}
	}
	fn("")
}

func sameStableProxy(left, right constant.Proxy) bool {
	return left.Name() == right.Name() &&
		left.ProxyInfo().ProviderName == right.ProxyInfo().ProviderName
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

	testUrl := constant.GetDefaultTestURL()
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
	operation, err := registerGeoUpdateOperation()
	if err != nil {
		return err
	}
	defer finishGeoUpdateOperation(operation)

	runLock.Lock()
	config := currentConfig
	initialized := isInit.Load()
	runLock.Unlock()
	if config == nil || !initialized {
		return errors.New("runtime is not initialized")
	}

	err = updateGeoResource(operation.context, geoType)
	if err != nil {
		return err
	}
	runLock.Lock()
	defer runLock.Unlock()
	if geoUpdateCancelGen.Load() != operation.generation || currentConfig != config || !isInit.Load() {
		return errConfigApplyStale
	}
	bumpRuntimeStateEpoch()
	return err
}

func handleUpdateExternalProvider(providerName string, fn func(value string)) {
	runLock.Lock()
	bumpRuntimeStateEpoch()
	generation := providerRuntimeGen.Load()
	externalProvider, exist := providerForUpdate(providerName)
	if !exist {
		runLock.Unlock()
		fn("external provider is not exist")
		return
	}
	identity, ok := externalProviderIdentityOf(externalProvider)
	if !ok {
		runLock.Unlock()
		fn("external provider identity is unavailable")
		return
	}
	activeProviderUpdates.Add(1)
	runLock.Unlock()
	err := func() error {
		defer activeProviderUpdates.Add(-1)
		return externalProvider.Update()
	}()
	if err != nil {
		fn(err.Error())
		return
	}

	runLock.Lock()
	bumpRuntimeStateEpoch()
	if providerRuntimeGen.Load() != generation {
		runLock.Unlock()
		fn("runtime changed while updating external provider")
		return
	}
	latest, exist := providerForUpdate(providerName)
	latestIdentity, identityOK := externalProviderIdentityOf(latest)
	runLock.Unlock()
	if !exist || !identityOK || latestIdentity != identity {
		fn("external provider changed while updating")
		return
	}
	fn("")
}

type externalProviderIdentity struct {
	typeOf  reflect.Type
	pointer uintptr
}

func externalProviderIdentityOf(provider cp.Provider) (externalProviderIdentity, bool) {
	if provider == nil {
		return externalProviderIdentity{}, false
	}
	value := reflect.ValueOf(provider)
	if value.Kind() != reflect.Pointer || value.IsNil() {
		return externalProviderIdentity{}, false
	}
	return externalProviderIdentity{typeOf: value.Type(), pointer: value.Pointer()}, true
}

func handleSideLoadExternalProvider(providerName string, data []byte, fn func(value string)) {
	runLock.Lock()
	externalProvider, exist := providerForUpdate(providerName)
	if !exist {
		runLock.Unlock()
		fn("external provider is not exist")
		return
	}
	identity, ok := externalProviderIdentityOf(externalProvider)
	if !ok {
		runLock.Unlock()
		fn("external provider identity is unavailable")
		return
	}
	bumpRuntimeStateEpoch()
	generation := providerRuntimeGen.Add(1)
	activeProviderUpdates.Add(1)
	runLock.Unlock()
	defer activeProviderUpdates.Add(-1)

	err := sideUpdateProvider(externalProvider, data)
	if err != nil {
		fn(err.Error())
		return
	}

	runLock.Lock()
	bumpRuntimeStateEpoch()
	if providerRuntimeGen.Load() != generation {
		runLock.Unlock()
		fn("runtime changed while side-loading external provider")
		return
	}
	latest, exist := providerForUpdate(providerName)
	latestIdentity, identityOK := externalProviderIdentityOf(latest)
	runLock.Unlock()
	if !exist || !identityOK || latestIdentity != identity {
		fn("external provider changed while side-loading")
		return
	}
	fn("")
}

func handleSuspend(suspended bool) bool {
	runLock.Lock()
	defer runLock.Unlock()
	bumpRuntimeStateEpoch()
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
	err := deleteHomePath(path)
	if err != nil {
		result.success(err.Error())
		return
	}
	result.success("")
}

func deleteHomePath(path string) error {
	root, rel, err := openHomePath(path)
	if err != nil {
		return err
	}
	defer root.Close()
	if rel == "." {
		return errors.New("refusing to delete home directory")
	}

	configApplyGate.Lock()
	if activeConfigApply.Load() != nil || detachedConfigWork.Load() != 0 {
		configApplyGate.Unlock()
		return errRuntimeResourceBusy
	}
	runLock.Lock()
	if activeProviderUpdates.Load() != 0 {
		runLock.Unlock()
		configApplyGate.Unlock()
		return errRuntimeResourceBusy
	}
	bumpRuntimeStateEpoch()
	err = root.RemoveAll(rel)
	bumpRuntimeStateEpoch()
	runLock.Unlock()
	configApplyGate.Unlock()
	return err
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
