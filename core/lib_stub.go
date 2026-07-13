//go:build cgo && !android

package main

// Non-Android CGO builds are compile-only. Desktop runtime builds use
// CGO_ENABLED=0 and provide these methods through server.go.
func (ActionResult) send() {}

func nextHandle(*Action, ActionResult) bool {
	return false
}

func sendMessage(Message) {}
