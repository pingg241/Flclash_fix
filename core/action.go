package main

import (
	"encoding/json"
	"fmt"
	"runtime"
	"sync"
	"unsafe"
)

type Action struct {
	Id     string      `json:"id"`
	Method Method      `json:"method"`
	Data   interface{} `json:"data"`
}

type ActionResult struct {
	Id       string      `json:"id"`
	Method   Method      `json:"method"`
	Data     interface{} `json:"data"`
	Code     int         `json:"code"`
	callback unsafe.Pointer
	once     *sync.Once
}

func (result ActionResult) Json() ([]byte, error) {
	data, err := json.Marshal(result)
	return data, err
}

func (result ActionResult) success(data interface{}) {
	result.Code = 0
	result.Data = data
	result.respond()
}

func (result ActionResult) error(data interface{}) {
	result.Code = -1
	result.Data = data
	result.respond()
}

func (result ActionResult) respond() {
	if result.once == nil {
		result.send()
		return
	}
	result.once.Do(result.send)
}

func newActionResult(id string, method Method, callback unsafe.Pointer) ActionResult {
	return ActionResult{
		Id:       id,
		Method:   method,
		callback: callback,
		once:     &sync.Once{},
	}
}

// actionString safely extracts a string from Action.Data.
func actionString(data interface{}) (string, bool) {
	s, ok := data.(string)
	return s, ok
}

// actionBool safely extracts a bool (JSON may decode as bool only for raw true/false).
func actionBool(data interface{}) (bool, bool) {
	b, ok := data.(bool)
	return b, ok
}

func requireString(result ActionResult, data interface{}) (string, bool) {
	s, ok := actionString(data)
	if !ok {
		result.error("invalid data: expected string")
	}
	return s, ok
}

func requireBool(result ActionResult, data interface{}) (bool, bool) {
	b, ok := actionBool(data)
	if !ok {
		result.error("invalid data: expected bool")
	}
	return b, ok
}

type actionHandler func(action *Action, result ActionResult)

// actionHandlers is a method table for O(1) dispatch (avoids long switch chains).
var actionHandlers map[Method]actionHandler

func init() {
	actionHandlers = map[Method]actionHandler{
		initClashMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleInitClash(s))
		},
		getIsInitMethod: func(_ *Action, result ActionResult) {
			result.success(handleGetIsInit())
		},
		forceGcMethod: func(_ *Action, result ActionResult) {
			handleForceGC()
			result.success(true)
		},
		shutdownMethod: func(_ *Action, result ActionResult) {
			stopped := handleShutdown()
			result.success(stopped)
			if stopped {
				if err := closeServerConnection(); err != nil {
					logError("close server after shutdown: %v", err)
				}
			}
		},
		validateConfigMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleValidateConfig(s))
		},
		updateConfigMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleUpdateConfig([]byte(s)))
		},
		setupConfigMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleSetupConfig([]byte(s)))
		},
		getProxiesMethod: func(_ *Action, result ActionResult) {
			result.success(handleGetProxies())
		},
		changeProxyMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			handleChangeProxy(s, func(value string) {
				result.success(value)
			})
		},
		getTrafficMethod: func(action *Action, result ActionResult) {
			b, ok := requireBool(result, action.Data)
			if !ok {
				return
			}
			result.success(handleGetTraffic(b))
		},
		getTotalTrafficMethod: func(action *Action, result ActionResult) {
			b, ok := requireBool(result, action.Data)
			if !ok {
				return
			}
			result.success(handleGetTotalTraffic(b))
		},
		getTrafficSnapshotMethod: func(action *Action, result ActionResult) {
			b, ok := requireBool(result, action.Data)
			if !ok {
				return
			}
			result.success(handleGetTrafficSnapshot(b))
		},
		resetTrafficMethod: func(_ *Action, result ActionResult) {
			handleResetTraffic()
			result.success(true)
		},
		asyncTestDelayMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			handleAsyncTestDelay(s, func(value string) {
				result.success(value)
			})
		},
		getConnectionsMethod: func(_ *Action, result ActionResult) {
			result.success(handleGetConnections())
		},
		closeConnectionsMethod: func(_ *Action, result ActionResult) {
			result.success(handleCloseConnections())
		},
		resetConnectionsMethod: func(_ *Action, result ActionResult) {
			result.success(handleResetConnections())
		},
		getConfigMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			config, err := handleGetConfig(s)
			if err != nil {
				result.error(err)
				return
			}
			result.success(config)
		},
		closeConnectionMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleCloseConnection(s))
		},
		getExternalProvidersMethod: func(_ *Action, result ActionResult) {
			result.success(handleGetExternalProviders())
		},
		getExternalProviderMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			result.success(handleGetExternalProvider(s))
		},
		updateGeoDataMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			if err := handleUpdateGeoData(s); err != nil {
				result.error(err.Error())
				return
			}
			result.success("")
		},
		updateExternalProviderMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			handleUpdateExternalProvider(s, func(value string) {
				result.success(value)
			})
		},
		sideLoadExternalProviderMethod: func(action *Action, result ActionResult) {
			paramsString, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			var params = map[string]string{}
			err := json.Unmarshal([]byte(paramsString), &params)
			if err != nil {
				result.error(err.Error())
				return
			}
			handleSideLoadExternalProvider(params["providerName"], []byte(params["data"]), func(value string) {
				result.success(value)
			})
		},
		startLogMethod: func(_ *Action, result ActionResult) {
			handleStartLog()
			result.success(true)
		},
		stopLogMethod: func(_ *Action, result ActionResult) {
			handleStopLog()
			result.success(true)
		},
		startListenerMethod: func(_ *Action, result ActionResult) {
			result.success(handleStartListener())
		},
		stopListenerMethod: func(_ *Action, result ActionResult) {
			result.success(handleStopListener())
		},
		getCountryCodeMethod: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			handleGetCountryCode(s, func(value string) {
				result.success(value)
			})
		},
		getMemoryMethod: func(_ *Action, result ActionResult) {
			handleGetMemory(func(value string) {
				result.success(value)
			})
		},
		crashMethod: func(_ *Action, result ActionResult) {
			handleCrash()
		},
		deleteFile: func(action *Action, result ActionResult) {
			s, ok := requireString(result, action.Data)
			if !ok {
				return
			}
			handleDelFile(s, result)
		},
		prepareTunHelperMethod: func(_ *Action, result ActionResult) {
			if err := prepareDarwinTunHelper(); err != nil {
				result.error(err.Error())
				return
			}
			result.success("")
		},
		releaseTunHelperMethod: func(_ *Action, result ActionResult) {
			if err := releaseDarwinTunHelper(); err != nil {
				result.error(err.Error())
				return
			}
			result.success("")
		},
	}
}

const maxConcurrentActions = 64

var actionSlots = make(chan struct{}, maxConcurrentActions)

func dispatchAction(action *Action, result ActionResult) {
	select {
	case actionSlots <- struct{}{}:
		go func() {
			defer func() { <-actionSlots }()
			handleAction(action, result)
		}()
	default:
		result.error("too many concurrent core actions")
	}
}

func handleAction(action *Action, result ActionResult) {
	defer func() {
		if r := recover(); r != nil {
			buf := make([]byte, 4096)
			n := runtime.Stack(buf, false)
			logError("panic in handleAction(%s): %v\n%s", action.Method, r, buf[:n])
			result.error(fmt.Sprintf("internal panic: %v", r))
		}
	}()
	if h, ok := actionHandlers[action.Method]; ok {
		h(action, result)
		return
	}
	if nextHandle(action, result) {
		return
	}
	result.error(fmt.Sprintf("unknown core action: %s", action.Method))
}
