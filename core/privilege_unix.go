//go:build !cgo && darwin

package main

import (
	"fmt"
	"os"
	"syscall"
)

func dropSetuidPrivileges() error {
	if err := syscall.Setpgid(0, 0); err != nil && err != syscall.EPERM {
		return fmt.Errorf("create core process group: %w", err)
	}
	realUID, effectiveUID := os.Getuid(), os.Geteuid()
	realGID, effectiveGID := os.Getgid(), os.Getegid()
	if realUID == effectiveUID && realGID == effectiveGID {
		return nil
	}
	if effectiveUID == 0 {
		if err := syscall.Setgroups([]int{}); err != nil {
			return fmt.Errorf("drop supplementary groups: %w", err)
		}
	}
	if err := syscall.Setgid(realGID); err != nil {
		return fmt.Errorf("drop setgid privileges: %w", err)
	}
	if err := syscall.Setuid(realUID); err != nil {
		return fmt.Errorf("drop setuid privileges: %w", err)
	}
	if os.Geteuid() != realUID || os.Getegid() != realGID {
		return fmt.Errorf("setuid privilege drop did not take effect")
	}
	return nil
}
