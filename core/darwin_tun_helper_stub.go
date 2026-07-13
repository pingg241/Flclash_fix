//go:build !darwin || cgo

package main

func prepareDarwinTunHelper() error { return nil }

func releaseDarwinTunHelper() error { return nil }

func runDarwinTunHelper(_ []string) (bool, error) { return false, nil }
