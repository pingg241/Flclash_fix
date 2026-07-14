//go:build !cgo

package main

import (
	"bytes"
	"encoding/binary"
	"net"
	"testing"
	"time"
)

func TestIdleIPCDoesNotDisconnectBeforeFirstByte(t *testing.T) {
	client, server := net.Pipe()
	t.Cleanup(func() {
		_ = client.Close()
		_ = server.Close()
	})

	type result struct {
		data []byte
		err  error
	}
	resultCh := make(chan result, 1)
	go func() {
		data, err := readFrameWithTimeout(server, 20*time.Millisecond)
		resultCh <- result{data: data, err: err}
	}()

	time.Sleep(60 * time.Millisecond)
	select {
	case got := <-resultCh:
		t.Fatalf("idle IPC returned before the first byte: %v", got.err)
	default:
	}
	want := []byte("idle connection remains usable")
	if err := writeFrame(client, want); err != nil {
		t.Fatal(err)
	}
	select {
	case got := <-resultCh:
		if got.err != nil {
			t.Fatal(got.err)
		}
		if !bytes.Equal(got.data, want) {
			t.Fatalf("payload = %q, want %q", got.data, want)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for idle IPC frame")
	}
}

func TestReadFrameWithTimeoutRejectsPartialFrame(t *testing.T) {
	client, server := net.Pipe()
	errCh := make(chan error, 1)
	go func() {
		_, err := readFrameWithTimeout(server, 20*time.Millisecond)
		errCh <- err
	}()

	header := make([]byte, 4)
	binary.LittleEndian.PutUint32(header, 4)
	if _, err := client.Write(header[:1]); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-errCh:
		if err == nil {
			t.Fatal("partial frame unexpectedly succeeded")
		}
	case <-time.After(time.Second):
		t.Fatal("partial frame did not time out")
	}
	_ = client.Close()
	_ = server.Close()
}

func TestUnexpectedIPCDisconnectTriggersShutdownOnce(t *testing.T) {
	oldInit := isInit.Load()
	oldRunning := isRunning.Load()
	t.Cleanup(func() {
		isInit.Store(oldInit)
		isRunning.Store(oldRunning)
	})
	isInit.Store(true)
	isRunning.Store(true)

	shutdownCalls := 0
	shutdown := func() bool {
		shutdownCalls++
		isInit.Store(false)
		isRunning.Store(false)
		return true
	}
	shutdownAfterIPCDisconnect(shutdown)
	shutdownAfterIPCDisconnect(shutdown)
	if shutdownCalls != 1 {
		t.Fatalf("shutdown calls = %d, want 1", shutdownCalls)
	}
}

func TestExplicitShutdownIsNotRepeatedByDisconnectCleanup(t *testing.T) {
	oldInit := isInit.Load()
	oldRunning := isRunning.Load()
	t.Cleanup(func() {
		isInit.Store(oldInit)
		isRunning.Store(oldRunning)
	})
	isInit.Store(true)
	isRunning.Store(true)

	shutdownCalls := 0
	explicitShutdown := func() bool {
		shutdownCalls++
		isInit.Store(false)
		isRunning.Store(false)
		return true
	}
	if !explicitShutdown() {
		t.Fatal("explicit shutdown failed")
	}
	shutdownAfterIPCDisconnect(explicitShutdown)
	if shutdownCalls != 1 {
		t.Fatalf("shutdown calls = %d, want 1", shutdownCalls)
	}
}
