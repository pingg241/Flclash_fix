//go:build !cgo && linux

package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

func currentProcessIdentity() (string, int, error) {
	startTime, pgid, err := readLinuxProcessIdentity(os.Getpid())
	return startTime, pgid, err
}

func readLinuxProcessIdentity(pid int) (string, int, error) {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err != nil {
		return "", 0, err
	}
	closeIndex := bytes.LastIndexByte(data, ')')
	if closeIndex < 0 || closeIndex+2 >= len(data) {
		return "", 0, errors.New("invalid proc stat")
	}
	fields := strings.Fields(string(data[closeIndex+2:]))
	if len(fields) <= 19 {
		return "", 0, errors.New("incomplete proc stat")
	}
	pgid, err := strconv.Atoi(fields[2])
	if err != nil {
		return "", 0, fmt.Errorf("parse process group: %w", err)
	}
	return fields[19], pgid, nil
}

func terminateVerifiedProcess(metadata launchMetadata) error {
	pidfd, err := unix.PidfdOpen(metadata.PID, 0)
	if err != nil {
		if errors.Is(err, unix.ESRCH) {
			return nil
		}
		return fmt.Errorf("open core pidfd: %w", err)
	}
	defer unix.Close(pidfd)
	if err := verifyLinuxProcess(metadata); err != nil {
		return err
	}
	if err := unix.PidfdSendSignal(pidfd, unix.SIGTERM, nil, 0); err != nil && !errors.Is(err, unix.ESRCH) {
		return fmt.Errorf("terminate core: %w", err)
	}
	if waitForLinuxProcessExit(metadata.PID, metadata.StartTime, 3*time.Second) {
		return nil
	}
	if err := verifyLinuxProcess(metadata); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if err := unix.PidfdSendSignal(pidfd, unix.SIGKILL, nil, 0); err != nil && !errors.Is(err, unix.ESRCH) {
		return fmt.Errorf("kill core: %w", err)
	}
	if !waitForLinuxProcessExit(metadata.PID, metadata.StartTime, 3*time.Second) {
		return errors.New("core process did not exit")
	}
	return nil
}

func verifyLinuxProcess(metadata launchMetadata) error {
	startTime, pgid, err := readLinuxProcessIdentity(metadata.PID)
	if err != nil {
		return err
	}
	if startTime != metadata.StartTime || pgid != metadata.PGID {
		return errors.New("core process identity changed")
	}
	executable, err := os.Readlink(fmt.Sprintf("/proc/%d/exe", metadata.PID))
	if err != nil {
		return err
	}
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return err
	}
	if filepath.Clean(executable) != filepath.Clean(metadata.Executable) {
		return errors.New("core executable changed")
	}
	environ, err := os.ReadFile(fmt.Sprintf("/proc/%d/environ", metadata.PID))
	if err != nil {
		return err
	}
	needle := []byte(launchNonceEnvironment + "=" + metadata.Nonce + "\x00")
	if !bytes.Contains(environ, needle) {
		return errors.New("core launch nonce is absent")
	}
	return nil
}

func waitForLinuxProcessExit(pid int, startTime string, timeout time.Duration) bool {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		current, _, err := readLinuxProcessIdentity(pid)
		if errors.Is(err, os.ErrNotExist) || (err == nil && current != startTime) {
			return true
		}
		time.Sleep(50 * time.Millisecond)
	}
	return false
}
