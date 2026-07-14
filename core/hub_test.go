package main

import (
	"context"
	"testing"
	"time"
)

func TestDelayTimeoutIsBounded(t *testing.T) {
	if got, ok := delayTimeout(0); !ok || got != defaultDelayTimeout {
		t.Fatalf("default timeout = %v/%v", got, ok)
	}
	if got, ok := delayTimeout(maximumDelayTimeout.Milliseconds()); !ok || got != maximumDelayTimeout {
		t.Fatalf("maximum timeout = %v/%v", got, ok)
	}
	if _, ok := delayTimeout(maximumDelayTimeout.Milliseconds() + 1); ok {
		t.Fatal("timeout above maximum was accepted")
	}
	if _, ok := delayTimeout(-1); !ok {
		t.Fatal("non-positive timeout should use the default")
	}
}

func TestAcquireDelaySlotStopsWaitingAtContextDeadline(t *testing.T) {
	previousSlots := delaySlots
	delaySlots = make(chan struct{}, 1)
	delaySlots <- struct{}{}
	defer func() { delaySlots = previousSlots }()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	started := time.Now()
	if acquireDelaySlot(ctx) {
		t.Fatal("acquired an already full delay slot")
	}
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("slot acquisition remained blocked for %v", elapsed)
	}
}
