//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"io"
	"sync"
	"testing"
	"time"
)

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

func TestIPCQueueDropsEventsAndDisconnectsForResponseSaturation(t *testing.T) {
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
	for range ipcOutboundQueueSize {
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
	if session.enqueue(outboundFrame{data: []byte("response")}, true) {
		t.Fatal("response was accepted after queue saturation")
	}
	select {
	case <-session.done:
	case <-time.After(time.Second):
		t.Fatal("response saturation did not disconnect IPC")
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
