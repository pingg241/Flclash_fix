//go:build android && cgo

package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"core/platform"
	t "core/tun"
	"encoding/json"
	"errors"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	corehub "github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"net"
	"strings"
	"sync"
	"syscall"
	"unsafe"
)

var (
	eventListener     unsafe.Pointer
	eventListenerLock sync.Mutex
)

type TunHandler struct {
	mu       sync.Mutex
	listener *sing_tun.Listener
	callback unsafe.Pointer
	active   int
	closing  bool

	socketHookGeneration      uint64
	packageResolverGeneration uint64
}

func (th *TunHandler) start(fd int, stack, address, dns string) bool {
	runLock.Lock()
	defer runLock.Unlock()
	th.initHook()
	tunListener := t.Start(fd, stack, address, dns)
	if tunListener != nil {
		log.Infoln("TUN address: %v", tunListener.Address())
		th.mu.Lock()
		th.listener = tunListener
		th.mu.Unlock()
		return true
	}
	th.close()
	return false
}

func (th *TunHandler) close() {
	th.removeHook()
	th.mu.Lock()
	if th.closing {
		th.mu.Unlock()
		return
	}
	th.closing = true
	listener := th.listener
	th.listener = nil
	var callback unsafe.Pointer
	if th.active == 0 {
		callback = th.callback
		th.callback = nil
	}
	th.mu.Unlock()
	if listener != nil {
		_ = listener.Close()
	}
	if callback != nil {
		releaseObject(callback)
	}
}

func (th *TunHandler) acquireCallback() (unsafe.Pointer, bool) {
	th.mu.Lock()
	defer th.mu.Unlock()
	if th.closing || th.listener == nil || th.callback == nil {
		return nil, false
	}
	th.active++
	return th.callback, true
}

func (th *TunHandler) releaseCallback() {
	th.mu.Lock()
	th.active--
	var callback unsafe.Pointer
	if th.closing && th.active == 0 {
		callback = th.callback
		th.callback = nil
	}
	th.mu.Unlock()
	if callback != nil {
		releaseObject(callback)
	}
}

func (th *TunHandler) handleProtect(fd int) error {
	callback, ok := th.acquireCallback()
	if !ok {
		return errBlocked
	}
	defer th.releaseCallback()
	if !protect(callback, fd) {
		return errBlocked
	}
	return nil
}

func (th *TunHandler) handleResolveProcess(source, target net.Addr) string {
	callback, ok := th.acquireCallback()
	if !ok {
		return ""
	}
	defer th.releaseCallback()
	var protocol int
	uid := -1
	switch source.Network() {
	case "udp", "udp4", "udp6":
		protocol = syscall.IPPROTO_UDP
	case "tcp", "tcp4", "tcp6":
		protocol = syscall.IPPROTO_TCP
	}
	if version.Load() < 29 {
		uid = platform.QuerySocketUidFromProcFs(source, target)
	}
	return resolveProcess(callback, protocol, source.String(), target.String(), uid)
}

func (th *TunHandler) initHook() {
	handler := th
	th.socketHookGeneration = dialer.InstallDefaultSocketHook(func(network, address string, conn syscall.RawConn) error {
		if platform.ShouldBlockConnection() {
			return errBlocked
		}
		var protectErr error
		if err := conn.Control(func(fd uintptr) {
			protectErr = handler.handleProtect(int(fd))
		}); err != nil {
			return err
		}
		return protectErr
	})
	th.packageResolverGeneration = process.InstallDefaultPackageNameResolver(func(metadata *constant.Metadata) (string, error) {
		src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
		if src == nil || dst == nil {
			return "", process.ErrInvalidNetwork
		}
		return handler.handleResolveProcess(src, dst), nil
	})
}

func (th *TunHandler) removeHook() {
	dialer.RemoveDefaultSocketHook(th.socketHookGeneration)
	process.RemoveDefaultPackageNameResolver(th.packageResolverGeneration)
}

var (
	tunLock    sync.Mutex
	errBlocked = errors.New("blocked")
	tunHandler *TunHandler
)

func handleStopTun() {
	tunLock.Lock()
	defer tunLock.Unlock()
	handler := tunHandler
	tunHandler = nil
	if handler != nil {
		handler.close()
	}
}

func handleStartTun(callback unsafe.Pointer, fd int, stack, address, dns string) bool {
	handleStopTun()
	tunLock.Lock()
	defer tunLock.Unlock()
	if fd == 0 {
		releaseObject(callback)
		return false
	}
	handler := &TunHandler{
		callback: callback,
	}
	tunHandler = handler
	if !handler.start(fd, stack, address, dns) {
		tunHandler = nil
		return false
	}
	return true
}

func handleUpdateDns(value string) {
	log.Infoln("[DNS] updateDns %s", value)
	dns.UpdateSystemDNS(strings.Split(value, ","))
	dns.FlushCacheWithDefaultResolver()
}

func (result ActionResult) send() {
	data, err := result.marshalForSend()
	if err != nil {
		logError("ActionResult marshal error: method=%s id=%s err=%v", result.Method, result.Id, err)
	}
	invokeResult(result.callback, string(data))
	if result.Method != messageMethod {
		releaseObject(result.callback)
	}
}

func nextHandle(action *Action, result ActionResult) bool {
	switch action.Method {
	case updateDnsMethod:
		data, ok := actionString(action.Data)
		if !ok {
			result.error("invalid data: expected string")
			return true
		}
		handleUpdateDns(data)
		result.success(true)
		return true
	}
	return false
}

//export invokeAction
func invokeAction(callback unsafe.Pointer, paramsChar *C.char) {
	params := takeCString(paramsChar)
	var action = &Action{}
	err := json.Unmarshal([]byte(params), action)
	if err != nil {
		invokeResult(callback, err.Error())
		releaseObject(callback)
		return
	}
	result := newActionResult(action.Id, action.Method, callback)
	dispatchAction(action, result)
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, stackChar, addressChar, dnsChar *C.char) bool {
	ok := handleStartTun(callback, int(fd), takeCString(stackChar), takeCString(addressChar), takeCString(dnsChar))
	if !ok {
		return false
	}
	if !isRunning.Load() {
		if !handleStartListener() {
			handleStopTun()
			return false
		}
	} else {
		handleResetConnections()
	}
	return true
}

//export quickSetup
func quickSetup(callback unsafe.Pointer, initParamsChar *C.char, setupParamsChar *C.char) {
	go func() {
		defer releaseObject(callback)
		initParamsString := takeCString(initParamsChar)
		setupParamsString := takeCString(setupParamsChar)
		if !handleInitClash(initParamsString) {
			stopQuickSetupRuntime()
			invokeResult(callback, "init failed")
			return
		}
		// updateListeners requires isRunning while the config transaction runs.
		runLock.Lock()
		isRunning.Store(true)
		bumpRuntimeStateEpoch()
		runLock.Unlock()
		message := handleSetupConfig([]byte(setupParamsString))
		if message != "" {
			stopQuickSetupRuntime()
		}
		invokeResult(callback, message)
	}()
}

func stopQuickSetupRuntime() {
	cancelActiveProxyGeoRequests()
	runLock.Lock()
	defer runLock.Unlock()
	bumpRuntimeStateEpoch()
	if err := corehub.StopRuntime(); err != nil {
		logError("stop runtime after quick setup failure: %v", err)
	}
	isRunning.Store(false)
	bumpRuntimeStateEpoch()
}

//export setEventListener
func setEventListener(listener unsafe.Pointer) {
	eventListenerLock.Lock()
	defer eventListenerLock.Unlock()
	if eventListener != nil {
		releaseObject(eventListener)
	}
	eventListener = listener
}

//export getTotalTraffic
func getTotalTraffic(onlyStatisticsProxy bool) *C.char {
	// Caller (JNI) must free via free(); do not free here or JNI reads freed memory.
	return C.CString(marshalTrafficJSON(handleGetTotalTraffic(onlyStatisticsProxy)))
}

//export getTraffic
func getTraffic(onlyStatisticsProxy bool) *C.char {
	// Caller (JNI) must free via free(); do not free here or JNI reads freed memory.
	return C.CString(marshalTrafficJSON(handleGetTraffic(onlyStatisticsProxy)))
}

//export getTrafficSnapshot
func getTrafficSnapshot(onlyStatisticsProxy bool) *C.char {
	// Caller (JNI) must free via free(); do not free here or JNI reads freed memory.
	return C.CString(marshalTrafficJSON(handleGetTrafficSnapshot(onlyStatisticsProxy)))
}

func sendMessage(message Message) {
	eventListenerLock.Lock()
	defer eventListenerLock.Unlock()
	if eventListener == nil {
		return
	}
	eventType, eventKey, required := requiredEventMetadata(message)
	result := ActionResult{
		Method:        messageMethod,
		callback:      eventListener,
		Data:          message,
		EventRequired: required,
		EventType:     eventType,
		EventKey:      eventKey,
	}
	result.send()
}

//export stopTun
func stopTun() {
	handleStopTun()
	if isRunning.Load() {
		handleStopListener()
	}
}

//export suspend
func suspend(suspended bool) {
	handleSuspend(suspended)
}

//export forceGC
func forceGC() {
	handleForceGC()
}

//export updateDns
func updateDns(s *C.char) {
	handleUpdateDns(takeCString(s))
}
