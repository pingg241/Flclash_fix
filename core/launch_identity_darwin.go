//go:build !cgo && darwin

package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"golang.org/x/sys/unix"
)

func currentProcessIdentity() (string, int, error) {
	return readDarwinProcessIdentity(os.Getpid())
}

func readDarwinProcessIdentity(pid int) (string, int, error) {
	info, err := unix.SysctlKinfoProc("kern.proc.pid", pid)
	if err != nil {
		return "", 0, err
	}
	if int(info.Proc.P_pid) != pid {
		return "", 0, os.ErrNotExist
	}
	start := info.Proc.P_starttime
	return fmt.Sprintf("%d:%d", start.Sec, start.Usec), int(info.Proc.P_pgrp), nil
}

func terminateVerifiedProcess(metadata launchMetadata) error {
	if err := verifyDarwinProcess(metadata); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if err := unix.Kill(-metadata.PGID, unix.SIGTERM); err != nil && !errors.Is(err, unix.ESRCH) {
		return fmt.Errorf("terminate core process group: %w", err)
	}
	if waitForDarwinProcessExit(metadata, 3*time.Second) {
		return nil
	}
	if err := verifyDarwinProcess(metadata); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if err := unix.Kill(-metadata.PGID, unix.SIGKILL); err != nil && !errors.Is(err, unix.ESRCH) {
		return fmt.Errorf("kill core process group: %w", err)
	}
	if !waitForDarwinProcessExit(metadata, 3*time.Second) {
		return errors.New("core process did not exit")
	}
	return nil
}

func verifyDarwinProcess(metadata launchMetadata) error {
	startTime, pgid, err := readDarwinProcessIdentity(metadata.PID)
	if err != nil {
		return err
	}
	if startTime != metadata.StartTime || pgid != metadata.PGID {
		return errors.New("core process identity changed")
	}
	args, err := unix.SysctlRaw("kern.procargs2", metadata.PID)
	if err != nil {
		return err
	}
	if len(args) < 5 {
		return errors.New("core process arguments are unavailable")
	}
	pathEnd := bytes.IndexByte(args[4:], 0)
	if pathEnd < 0 {
		return errors.New("core executable path is unavailable")
	}
	executable := string(args[4 : 4+pathEnd])
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return err
	}
	if filepath.Clean(executable) != filepath.Clean(metadata.Executable) {
		return errors.New("core executable changed")
	}
	needle := []byte(launchNonceEnvironment + "=" + metadata.Nonce + "\x00")
	if !bytes.Contains(args, needle) {
		return errors.New("core launch nonce is absent")
	}
	return nil
}

func waitForDarwinProcessExit(metadata launchMetadata, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		startTime, _, err := readDarwinProcessIdentity(metadata.PID)
		if errors.Is(err, os.ErrNotExist) || (err == nil && startTime != metadata.StartTime) {
			return true
		}
		time.Sleep(50 * time.Millisecond)
	}
	return false
}
