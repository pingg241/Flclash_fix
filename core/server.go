//go:build !cgo

package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

var (
	connMu  sync.RWMutex
	current *ipcSession
)

const (
	ipcTokenEnvironment     = "FLCLASH_IPC_TOKEN"
	ipcTokenFileEnvironment = "FLCLASH_IPC_TOKEN_FILE"
	ipcServerLabel          = "flclash-ipc-server-v1"
	ipcCoreLabel            = "flclash-ipc-core-v1"
	ipcRequiredQueueSize    = 256
	ipcEventQueueSize       = 256
	ipcWriteTimeout         = 5 * time.Second
	ipcReadTimeout          = 30 * time.Second
)

type outboundFrame struct {
	data       []byte
	closeAfter bool
	done       chan error
}

type ipcSession struct {
	conn       io.ReadWriteCloser
	required   chan outboundFrame
	events     chan outboundFrame
	done       chan struct{}
	closeOnce  sync.Once
	writerDone chan struct{}
	dropped    atomic.Uint64
}

func newIPCSession(rw io.ReadWriteCloser) *ipcSession {
	session := &ipcSession{
		conn:       rw,
		required:   make(chan outboundFrame, ipcRequiredQueueSize),
		events:     make(chan outboundFrame, ipcEventQueueSize),
		done:       make(chan struct{}),
		writerDone: make(chan struct{}),
	}
	go session.writeLoop()
	return session
}

func (session *ipcSession) close() error {
	var err error
	session.closeOnce.Do(func() {
		close(session.done)
		err = session.conn.Close()
	})
	return err
}

func (session *ipcSession) enqueue(frame outboundFrame, required bool) bool {
	queue := session.events
	if required {
		queue = session.required
	}
	select {
	case <-session.done:
		return false
	case queue <- frame:
		return true
	default:
		if required {
			logError("IPC response queue is full; disconnecting client")
			_ = session.close()
		} else {
			dropped := session.dropped.Add(1)
			if dropped == 1 || dropped%100 == 0 {
				logError("IPC event queue is full; dropped %d events", dropped)
			}
		}
		return false
	}
}

func (session *ipcSession) nextFrame() (outboundFrame, bool) {
	select {
	case <-session.done:
		return outboundFrame{}, false
	default:
	}

	// Prefer responses and lifecycle notifications that are already waiting
	// before selecting another best-effort UI event.
	select {
	case frame := <-session.required:
		return frame, true
	default:
	}

	select {
	case <-session.done:
		return outboundFrame{}, false
	case frame := <-session.required:
		return frame, true
	case frame := <-session.events:
		return frame, true
	}
}

func setWriteDeadline(writer io.Writer, deadline time.Time) error {
	connection, ok := writer.(interface{ SetWriteDeadline(time.Time) error })
	if !ok {
		return fmt.Errorf("IPC connection does not support write deadlines")
	}
	return connection.SetWriteDeadline(deadline)
}

func (session *ipcSession) writeLoop() {
	defer close(session.writerDone)
	for {
		frame, ok := session.nextFrame()
		if !ok {
			return
		}
		err := setWriteDeadline(session.conn, time.Now().Add(ipcWriteTimeout))
		if err == nil && len(frame.data) != 0 {
			err = writeFrame(session.conn, frame.data)
		}
		if frame.done != nil {
			frame.done <- err
			close(frame.done)
		}
		if err != nil {
			logError("server write error: %v", err)
			_ = session.close()
			return
		}
		if frame.closeAfter {
			_ = session.close()
			return
		}
	}
}

func (result ActionResult) send() {
	data, err := result.marshalForSend()
	if err != nil {
		logError("ActionResult marshal error: method=%s id=%s err=%v", result.Method, result.Id, err)
	}
	send(data, true)
}

func sendMessage(message Message) {
	eventType, eventKey, required := requiredEventMetadata(message)
	result := ActionResult{
		Method:        messageMethod,
		Data:          message,
		EventRequired: required,
		EventType:     eventType,
		EventKey:      eventKey,
	}
	data, err := result.Json()
	if err != nil {
		logError("Message marshal error: %v", err)
		return
	}
	send(data, required)
}

func writeFrame(w io.Writer, data []byte) error {
	if len(data) > maxIPCFrameSize {
		return fmt.Errorf("frame too large: %d > %d", len(data), maxIPCFrameSize)
	}
	// length prefix + payload in one write to cut syscall count
	frame := make([]byte, 4+len(data))
	binary.LittleEndian.PutUint32(frame, uint32(len(data)))
	copy(frame[4:], data)
	for len(frame) > 0 {
		n, err := w.Write(frame)
		if err != nil {
			return err
		}
		if n <= 0 || n > len(frame) {
			return io.ErrShortWrite
		}
		frame = frame[n:]
	}
	return nil
}

func readFrame(r io.Reader) ([]byte, error) {
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(r, lenBuf); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint32(lenBuf)
	if length > maxIPCFrameSize {
		return nil, fmt.Errorf("frame too large: %d > %d", length, maxIPCFrameSize)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, err
	}
	return data, nil
}

func readFrameWithTimeout(r io.Reader, timeout time.Duration) ([]byte, error) {
	connection, hasDeadline := r.(interface{ SetReadDeadline(time.Time) error })
	if !hasDeadline {
		return readFrame(r)
	}
	if err := connection.SetReadDeadline(time.Time{}); err != nil {
		return nil, fmt.Errorf("clear IPC read deadline: %w", err)
	}

	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(r, lenBuf[:1]); err != nil {
		return nil, err
	}
	if err := connection.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return nil, fmt.Errorf("set IPC frame read deadline: %w", err)
	}
	if _, err := io.ReadFull(r, lenBuf[1:]); err != nil {
		return nil, err
	}
	length := binary.LittleEndian.Uint32(lenBuf)
	if length > maxIPCFrameSize {
		return nil, fmt.Errorf("frame too large: %d > %d", length, maxIPCFrameSize)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, err
	}
	if err := connection.SetReadDeadline(time.Time{}); err != nil {
		return nil, fmt.Errorf("clear IPC frame read deadline: %w", err)
	}
	return data, nil
}

func ipcProof(secret, label string) []byte {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(label))
	return mac.Sum(nil)
}

func loadIPCToken() (string, error) {
	secret := os.Getenv(ipcTokenEnvironment)
	_ = os.Unsetenv(ipcTokenEnvironment)
	tokenFile := os.Getenv(ipcTokenFileEnvironment)
	_ = os.Unsetenv(ipcTokenFileEnvironment)
	if secret == "" && tokenFile != "" {
		root, rel, err := openHomePath(tokenFile)
		if err != nil {
			return "", fmt.Errorf("open IPC token file: %w", err)
		}
		defer root.Close()
		data, err := root.ReadFile(rel)
		if err != nil {
			return "", fmt.Errorf("read IPC token file: %w", err)
		}
		if err := root.Remove(rel); err != nil && !os.IsNotExist(err) {
			return "", fmt.Errorf("remove IPC token file: %w", err)
		}
		secret = string(data)
	}
	if len(secret) < 32 {
		return "", fmt.Errorf("missing or invalid IPC token")
	}
	return secret, nil
}

func authenticateIPC(rw io.ReadWriter) error {
	if deadline, ok := rw.(interface{ SetDeadline(time.Time) error }); ok {
		if err := deadline.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
			return fmt.Errorf("set IPC authentication deadline: %w", err)
		}
		defer func() {
			_ = deadline.SetDeadline(time.Time{})
		}()
	}
	secret, err := loadIPCToken()
	if err != nil {
		return err
	}
	serverProof, err := readFrame(rw)
	if err != nil {
		return fmt.Errorf("read IPC server proof: %w", err)
	}
	if !hmac.Equal(serverProof, ipcProof(secret, ipcServerLabel)) {
		return fmt.Errorf("invalid IPC server proof")
	}
	if err := writeFrame(rw, ipcProof(secret, ipcCoreLabel)); err != nil {
		return fmt.Errorf("write IPC core proof: %w", err)
	}
	return nil
}

func send(data []byte, required bool) {
	connMu.RLock()
	session := current
	connMu.RUnlock()
	if session == nil {
		logError("send conn nil")
		return
	}
	session.enqueue(outboundFrame{data: data}, required)
}

// closeServerConnection flushes frames queued before this call, then closes the
// current IPC connection. It is safe to call repeatedly and never holds connMu
// while waiting for the writer.
func closeServerConnection() error {
	connMu.RLock()
	session := current
	connMu.RUnlock()
	if session == nil {
		return nil
	}
	done := make(chan error, 1)
	if !session.enqueue(outboundFrame{closeAfter: true, done: done}, true) {
		return session.close()
	}
	select {
	case err := <-done:
		return err
	case <-time.After(ipcWriteTimeout + time.Second):
		_ = session.close()
		return fmt.Errorf("timed out closing IPC connection")
	}
}

func shutdownAfterIPCDisconnect(shutdown func() bool) {
	if !isInit.Load() && !isRunning.Load() {
		return
	}
	if !shutdown() {
		logError("failed to shut down core after IPC server exit")
	}
}

func startServer(arg string) {
	var err error
	rw, err := dial(arg)
	if err != nil {
		panic(err.Error())
	}

	if err := authenticateIPC(rw); err != nil {
		_ = rw.Close()
		panic(err.Error())
	}
	session := newIPCSession(rw)
	connMu.Lock()
	current = session
	connMu.Unlock()
	defer func() {
		shutdownAfterIPCDisconnect(handleShutdown)
		connMu.Lock()
		if current == session {
			current = nil
		}
		connMu.Unlock()
		_ = session.close()
		<-session.writerDone
	}()

	for {
		data, err := readFrameWithTimeout(rw, ipcReadTimeout)
		if err != nil {
			if err != io.EOF {
				logError("server read error: %v", err)
			}
			return
		}
		var action = &Action{}

		err = json.Unmarshal(data, action)

		if err != nil {
			logError("server unmarshal error: %v (data: %q)", err, data)
			continue
		}

		result := newActionResult(action.Id, action.Method, nil)
		dispatchAction(action, result)
	}
}

func nextHandle(action *Action, result ActionResult) bool {
	return false
}
