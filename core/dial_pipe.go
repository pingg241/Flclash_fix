//go:build windows && !cgo

package main

import (
	"io"
	"time"

	"github.com/Microsoft/go-winio"
)

func dial(path string) (io.ReadWriteCloser, error) {
	timeout := 5 * time.Second
	return winio.DialPipe(path, &timeout)
}
