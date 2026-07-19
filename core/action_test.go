//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

func TestDeleteHomePathRejectsBusyRuntimeResources(t *testing.T) {
	home := t.TempDir()
	target := filepath.Join(home, "provider-cache.yaml")
	if err := os.WriteFile(target, []byte("cache"), 0o600); err != nil {
		t.Fatal(err)
	}

	oldHome := constant.Path.HomeDir()
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = home
	homeLock.Unlock()
	constant.SetHomeDir(home)
	var operation *configApplyOperation
	t.Cleanup(func() {
		finishConfigApplyOperation(operation)
		constant.SetHomeDir(oldHome)
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
	})

	operation, err := registerConfigApplyOperation()
	if err != nil {
		t.Fatal(err)
	}
	if err := deleteHomePath(target); !errors.Is(err, errRuntimeResourceBusy) {
		t.Fatalf("delete during config apply = %v, want busy", err)
	}
	finishConfigApplyOperation(operation)
	operation = nil

	detachedConfigWork.Add(1)
	if err := deleteHomePath(target); !errors.Is(err, errRuntimeResourceBusy) {
		detachedConfigWork.Add(-1)
		t.Fatalf("delete during detached config work = %v, want busy", err)
	}
	detachedConfigWork.Add(-1)

	activeProviderUpdates.Add(1)
	if err := deleteHomePath(target); !errors.Is(err, errRuntimeResourceBusy) {
		activeProviderUpdates.Add(-1)
		t.Fatalf("delete during provider update = %v, want busy", err)
	}
	activeProviderUpdates.Add(-1)

	if err := deleteHomePath(target); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("target still exists after idle delete: %v", err)
	}
}

type bufferReadWriteCloser struct {
	bytes.Buffer
}

func (b *bufferReadWriteCloser) Close() error {
	return nil
}

func (b *bufferReadWriteCloser) SetWriteDeadline(time.Time) error {
	return nil
}

func installTestSession(t *testing.T, rw io.ReadWriteCloser) {
	t.Helper()
	session := newIPCSession(rw)
	connMu.Lock()
	old := current
	current = session
	connMu.Unlock()
	t.Cleanup(func() {
		connMu.Lock()
		if current == session {
			current = old
		}
		connMu.Unlock()
		_ = session.close()
		<-session.writerDone
	})
}

func waitForBuffer(t *testing.T, buffer *bytes.Buffer) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for buffer.Len() == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if buffer.Len() == 0 {
		t.Fatal("timed out waiting for IPC writer")
	}
}

type shortWriter struct {
	buffer bytes.Buffer
	limit  int
}

type blockingReadWriteCloser struct {
	started   chan struct{}
	closed    chan struct{}
	startOnce sync.Once
	closeOnce sync.Once
}

type gatedReadWriteCloser struct {
	started chan struct{}
	permits chan struct{}
	writes  chan []byte
	closed  chan struct{}
	once    sync.Once
}

func newGatedReadWriteCloser() *gatedReadWriteCloser {
	return &gatedReadWriteCloser{
		started: make(chan struct{}, 4),
		permits: make(chan struct{}, 4),
		writes:  make(chan []byte, 4),
		closed:  make(chan struct{}),
	}
}

func (g *gatedReadWriteCloser) Read([]byte) (int, error) {
	<-g.closed
	return 0, io.EOF
}

func (g *gatedReadWriteCloser) Write(data []byte) (int, error) {
	g.started <- struct{}{}
	select {
	case <-g.permits:
		copied := append([]byte(nil), data...)
		g.writes <- copied
		return len(data), nil
	case <-g.closed:
		return 0, io.ErrClosedPipe
	}
}

func (g *gatedReadWriteCloser) Close() error {
	g.once.Do(func() { close(g.closed) })
	return nil
}

func (g *gatedReadWriteCloser) SetWriteDeadline(time.Time) error {
	return nil
}

func newBlockingReadWriteCloser() *blockingReadWriteCloser {
	return &blockingReadWriteCloser{
		started: make(chan struct{}),
		closed:  make(chan struct{}),
	}
}

func (b *blockingReadWriteCloser) Read([]byte) (int, error) {
	<-b.closed
	return 0, io.EOF
}

func (b *blockingReadWriteCloser) Write([]byte) (int, error) {
	b.startOnce.Do(func() { close(b.started) })
	<-b.closed
	return 0, io.ErrClosedPipe
}

func (b *blockingReadWriteCloser) Close() error {
	b.closeOnce.Do(func() { close(b.closed) })
	return nil
}

func (b *blockingReadWriteCloser) SetWriteDeadline(time.Time) error {
	return nil
}

func (w *shortWriter) Write(data []byte) (int, error) {
	if len(data) > w.limit {
		data = data[:w.limit]
	}
	return w.buffer.Write(data)
}

func TestWriteFrameHandlesShortWrites(t *testing.T) {
	w := &shortWriter{limit: 3}
	want := []byte("short-write-payload")
	if err := writeFrame(w, want); err != nil {
		t.Fatal(err)
	}
	got, err := readFrame(bytes.NewReader(w.buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("payload = %q, want %q", got, want)
	}
}

func TestIPCEventSaturationDoesNotDisplaceRequiredFrames(t *testing.T) {
	connection := newBlockingReadWriteCloser()
	session := newIPCSession(connection)
	t.Cleanup(func() {
		_ = session.close()
		<-session.writerDone
	})

	if !session.enqueue(outboundFrame{data: []byte("blocked")}, false) {
		t.Fatal("failed to enqueue initial frame")
	}
	select {
	case <-connection.started:
	case <-time.After(time.Second):
		t.Fatal("writer did not start")
	}
	for range ipcEventQueueSize {
		if !session.enqueue(outboundFrame{data: []byte("event")}, false) {
			t.Fatal("queue filled earlier than expected")
		}
	}
	if session.enqueue(outboundFrame{data: []byte("dropped")}, false) {
		t.Fatal("event was accepted after queue saturation")
	}
	if session.dropped.Load() != 1 {
		t.Fatalf("dropped events = %d, want 1", session.dropped.Load())
	}
	if !session.enqueue(outboundFrame{data: []byte("response")}, true) {
		t.Fatal("event saturation displaced a required response")
	}
	select {
	case <-session.done:
		t.Fatal("event saturation disconnected IPC")
	default:
	}
}

func TestIPCRequiredQueueSaturationDisconnects(t *testing.T) {
	connection := newBlockingReadWriteCloser()
	session := newIPCSession(connection)
	t.Cleanup(func() {
		_ = session.close()
		<-session.writerDone
	})

	if !session.enqueue(outboundFrame{data: []byte("blocked")}, false) {
		t.Fatal("failed to enqueue blocking frame")
	}
	select {
	case <-connection.started:
	case <-time.After(time.Second):
		t.Fatal("writer did not start")
	}
	for range ipcRequiredQueueSize {
		if !session.enqueue(outboundFrame{data: []byte("response")}, true) {
			t.Fatal("required queue filled earlier than expected")
		}
	}
	if session.enqueue(outboundFrame{data: []byte("overflow")}, true) {
		t.Fatal("required frame was accepted after queue saturation")
	}
	select {
	case <-session.done:
	case <-time.After(time.Second):
		t.Fatal("required queue saturation did not disconnect IPC")
	}
}

func TestIPCWriterPrefersQueuedRequiredFrameOverEventBacklog(t *testing.T) {
	connection := newGatedReadWriteCloser()
	session := newIPCSession(connection)
	t.Cleanup(func() {
		_ = session.close()
		<-session.writerDone
	})

	if !session.enqueue(outboundFrame{data: []byte("event-1")}, false) {
		t.Fatal("failed to enqueue first event")
	}
	select {
	case <-connection.started:
	case <-time.After(time.Second):
		t.Fatal("writer did not start first frame")
	}
	if !session.enqueue(outboundFrame{data: []byte("event-2")}, false) {
		t.Fatal("failed to enqueue event backlog")
	}
	if !session.enqueue(outboundFrame{data: []byte("required")}, true) {
		t.Fatal("failed to enqueue required frame")
	}

	connection.permits <- struct{}{}
	first := <-connection.writes
	firstPayload, err := readFrame(bytes.NewReader(first))
	if err != nil {
		t.Fatal(err)
	}
	if string(firstPayload) != "event-1" {
		t.Fatalf("first frame = %q", firstPayload)
	}

	select {
	case <-connection.started:
	case <-time.After(time.Second):
		t.Fatal("writer did not start second frame")
	}
	connection.permits <- struct{}{}
	second := <-connection.writes
	secondPayload, err := readFrame(bytes.NewReader(second))
	if err != nil {
		t.Fatal(err)
	}
	if string(secondPayload) != "required" {
		t.Fatalf("second frame = %q, want required", secondPayload)
	}
}

func TestActionResultRespondsExactlyOnce(t *testing.T) {
	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)

	result := newActionResult("id", getIsInitMethod, nil)
	result.success("first")
	result.error("second")
	waitForBuffer(t, &buffer.Buffer)

	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != 0 || response.Data != "first" {
		t.Fatalf("unexpected response: %#v", response)
	}
	reader := bytes.NewReader(buffer.Bytes()[4+len(payload):])
	if _, err := readFrame(reader); err != io.EOF {
		t.Fatalf("expected one response frame, got %v", err)
	}
}

func TestActionResultMarshalFailureSendsFallback(t *testing.T) {
	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)

	result := newActionResult("fallback-id", getIsInitMethod, nil)
	result.success(make(chan int))
	waitForBuffer(t, &buffer.Buffer)

	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	if response.Id != "fallback-id" || response.Method != getIsInitMethod || response.Code != -1 {
		t.Fatalf("unexpected fallback response: %#v", response)
	}
	if response.Data != "failed to encode core action result" {
		t.Fatalf("fallback message = %#v", response.Data)
	}
	if len(buffer.Bytes()) != 4+len(payload) {
		t.Fatal("marshal failure emitted more than one response")
	}
}

func TestControlActionsBypassSaturatedActionSlots(t *testing.T) {
	const normalMethod Method = "test-blocking-normal"
	controlMethods := []Method{startListenerMethod, stopListenerMethod, shutdownMethod}

	previousNormal, normalExisted := actionHandlers[normalMethod]
	previousControls := make(map[Method]actionHandler, len(controlMethods))
	for _, method := range controlMethods {
		previousControls[method] = actionHandlers[method]
	}
	t.Cleanup(func() {
		if normalExisted {
			actionHandlers[normalMethod] = previousNormal
		} else {
			delete(actionHandlers, normalMethod)
		}
		for method, handler := range previousControls {
			actionHandlers[method] = handler
		}
	})

	normalStarted := make(chan struct{}, maxConcurrentActions+1)
	normalRelease := make(chan struct{})
	var normalReleaseOnce sync.Once
	releaseNormal := func() { normalReleaseOnce.Do(func() { close(normalRelease) }) }
	t.Cleanup(releaseNormal)
	actionHandlers[normalMethod] = func(_ *Action, result ActionResult) {
		normalStarted <- struct{}{}
		<-normalRelease
		result.success(true)
	}

	controlStarted := make(chan Method, len(controlMethods)+1)
	controlRelease := make(chan struct{})
	var controlReleaseOnce sync.Once
	releaseControls := func() { controlReleaseOnce.Do(func() { close(controlRelease) }) }
	t.Cleanup(releaseControls)
	for _, method := range controlMethods {
		method := method
		actionHandlers[method] = func(_ *Action, result ActionResult) {
			controlStarted <- method
			<-controlRelease
			result.success(true)
		}
	}

	silentResult := func(id string, method Method) ActionResult {
		once := &sync.Once{}
		once.Do(func() {})
		return ActionResult{Id: id, Method: method, once: once}
	}
	for index := 0; index < maxConcurrentActions; index++ {
		dispatchAction(
			&Action{Id: fmt.Sprintf("normal-%d", index), Method: normalMethod},
			silentResult("", normalMethod),
		)
	}
	for index := 0; index < maxConcurrentActions; index++ {
		select {
		case <-normalStarted:
		case <-time.After(time.Second):
			t.Fatalf("normal action %d did not start", index)
		}
	}
	dispatchAction(
		&Action{Id: "normal-overflow", Method: normalMethod},
		silentResult("normal-overflow", normalMethod),
	)
	select {
	case <-normalStarted:
		t.Fatal("the 65th normal action bypassed backpressure")
	case <-time.After(20 * time.Millisecond):
	}

	for _, method := range controlMethods {
		dispatchAction(
			&Action{Id: string(method), Method: method},
			silentResult(string(method), method),
		)
	}
	started := make(map[Method]bool, len(controlMethods))
	for range controlMethods {
		select {
		case method := <-controlStarted:
			started[method] = true
		case <-time.After(time.Second):
			t.Fatal("control action did not bypass saturated normal slots")
		}
	}
	for _, method := range controlMethods {
		if !started[method] {
			t.Fatalf("control action %s did not start", method)
		}
	}
	if len(controlSlots) != len(controlMethods) {
		t.Fatalf("active control slots = %d, want %d", len(controlSlots), len(controlMethods))
	}

	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)
	dispatchAction(
		&Action{Id: "duplicate-stop", Method: stopListenerMethod},
		newActionResult("duplicate-stop", stopListenerMethod, nil),
	)
	waitForBuffer(t, &buffer.Buffer)
	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != -1 || response.Data != "core control action is already in progress" {
		t.Fatalf("duplicate control response = %#v", response)
	}
	if len(buffer.Bytes()) != 4+len(payload) {
		t.Fatal("duplicate control action emitted more than one response")
	}
	select {
	case method := <-controlStarted:
		t.Fatalf("duplicate control action started: %s", method)
	case <-time.After(20 * time.Millisecond):
	}

	releaseControls()
	waitForSlotCount(t, controlSlots, 0)
	for _, method := range controlMethods {
		if _, active := activeControlActions.Load(method); active {
			t.Fatalf("control action %s remained active", method)
		}
	}
	releaseNormal()
	waitForSlotCount(t, actionSlots, 0)
}

func waitForSlotCount(t *testing.T, slots chan struct{}, want int) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for len(slots) != want && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if len(slots) != want {
		t.Fatalf("slot count = %d, want %d", len(slots), want)
	}
}

func TestPanickingActionReturnsErrorWithoutDuplicateSuccess(t *testing.T) {
	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)

	action := &Action{Method: crashMethod}
	handleAction(action, newActionResult("id", crashMethod, nil))
	waitForBuffer(t, &buffer.Buffer)

	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != -1 {
		t.Fatalf("panic response code = %d", response.Code)
	}
	if len(buffer.Bytes()) != 4+len(payload) {
		t.Fatal("panicking action emitted more than one response")
	}
}

func TestUnknownActionReturnsError(t *testing.T) {
	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)

	action := &Action{Method: Method("unknown-action")}
	handleAction(action, newActionResult("id", action.Method, nil))
	waitForBuffer(t, &buffer.Buffer)

	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	if response.Code != -1 || response.Data != "unknown core action: unknown-action" {
		t.Fatalf("unexpected response: %#v", response)
	}
}

func TestGetConfigActionReturnsReadableError(t *testing.T) {
	home := t.TempDir()
	oldHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	homeLock.Lock()
	oldTrustedHome := trustedHomeDir
	trustedHomeDir = ""
	homeLock.Unlock()
	t.Cleanup(func() {
		homeLock.Lock()
		trustedHomeDir = oldTrustedHome
		homeLock.Unlock()
		constant.SetHomeDir(oldHome)
	})

	buffer := &bufferReadWriteCloser{}
	installTestSession(t, buffer)
	action := &Action{
		Method: getConfigMethod,
		Data:   filepath.Join(home, "missing.yaml"),
	}
	handleAction(action, newActionResult("id", getConfigMethod, nil))
	waitForBuffer(t, &buffer.Buffer)

	payload, err := readFrame(bytes.NewReader(buffer.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	var response ActionResult
	if err := json.Unmarshal(payload, &response); err != nil {
		t.Fatal(err)
	}
	message, ok := response.Data.(string)
	if response.Code != -1 || !ok || message == "" || message == "{}" {
		t.Fatalf("getConfig returned an unreadable error: %#v", response)
	}
}
