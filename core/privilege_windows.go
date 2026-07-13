//go:build !cgo && windows

package main

func dropSetuidPrivileges() error {
	return nil
}
