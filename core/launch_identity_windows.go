//go:build !cgo && windows

package main

import "errors"

func writeLaunchMetadata() error {
	return nil
}

func terminateLaunchedCore(_, _ string) error {
	return errors.New("unix core termination is unavailable on windows")
}
