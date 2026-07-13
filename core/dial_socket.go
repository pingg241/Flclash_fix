//go:build !cgo && !windows

package main

import (
	"fmt"
	"io"
	"net"
	"strconv"
	"time"
)

func dial(arg string) (io.ReadWriteCloser, error) {
	_, err := strconv.Atoi(arg)
	if err != nil {
		return net.DialTimeout("unix", arg, 5*time.Second)
	}
	return net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%s", arg), 5*time.Second)
}
