//go:build !cgo && !windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
)

const (
	launchFileEnvironment  = "FLCLASH_LAUNCH_FILE"
	launchNonceEnvironment = "FLCLASH_LAUNCH_NONCE"
	launchUIDEnvironment   = "FLCLASH_ORIGINAL_UID"
	maxLaunchMetadataSize  = 16 << 10
)

type launchMetadata struct {
	PID        int    `json:"pid"`
	PGID       int    `json:"pgid"`
	Nonce      string `json:"nonce"`
	Executable string `json:"executable"`
	StartTime  string `json:"startTime"`
}

func writeLaunchMetadata() error {
	path := os.Getenv(launchFileEnvironment)
	nonce := os.Getenv(launchNonceEnvironment)
	if path == "" && nonce == "" {
		return nil
	}
	if path == "" || len(nonce) < 32 {
		return errors.New("missing launch identity")
	}
	metadata, err := currentLaunchMetadata(nonce)
	if err != nil {
		return err
	}
	root, rel, err := openHomePath(path)
	if err != nil {
		return fmt.Errorf("open launch identity: %w", err)
	}
	defer root.Close()
	info, err := root.Stat(rel)
	if err != nil {
		return fmt.Errorf("stat launch identity: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0o077 != 0 {
		return errors.New("launch identity must be a private regular file")
	}
	if err := verifyLaunchFileOwner(info); err != nil {
		return err
	}
	file, err := root.OpenFile(rel, os.O_WRONLY|os.O_TRUNC, 0)
	if err != nil {
		return fmt.Errorf("write launch identity: %w", err)
	}
	encoder := json.NewEncoder(file)
	encodeErr := encoder.Encode(metadata)
	closeErr := file.Close()
	if encodeErr != nil {
		return fmt.Errorf("encode launch identity: %w", encodeErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close launch identity: %w", closeErr)
	}
	return nil
}

func verifyLaunchFileOwner(info os.FileInfo) error {
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return errors.New("launch identity owner is unavailable")
	}
	expectedUID := os.Getuid()
	if raw := os.Getenv(launchUIDEnvironment); raw != "" {
		parsed, err := strconv.ParseUint(raw, 10, 32)
		if err != nil {
			return errors.New("invalid original uid")
		}
		expectedUID = int(parsed)
	}
	if uint64(stat.Uid) != uint64(expectedUID) {
		return fmt.Errorf("launch identity owner mismatch")
	}
	return nil
}

func currentLaunchMetadata(nonce string) (launchMetadata, error) {
	executable, err := os.Executable()
	if err != nil {
		return launchMetadata{}, fmt.Errorf("resolve core executable: %w", err)
	}
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return launchMetadata{}, fmt.Errorf("canonicalize core executable: %w", err)
	}
	startTime, pgid, err := currentProcessIdentity()
	if err != nil {
		return launchMetadata{}, err
	}
	return launchMetadata{
		PID:        os.Getpid(),
		PGID:       pgid,
		Nonce:      nonce,
		Executable: filepath.Clean(executable),
		StartTime:  startTime,
	}, nil
}

func terminateLaunchedCore(path, nonce string) error {
	if !filepath.IsAbs(path) || len(nonce) < 32 {
		return errors.New("invalid launch identity arguments")
	}
	file, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return fmt.Errorf("open launch identity: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat launch identity: %w", err)
	}
	if !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxLaunchMetadataSize {
		return errors.New("invalid launch identity file")
	}
	if err := verifyLaunchFileOwner(info); err != nil {
		return err
	}
	data, err := io.ReadAll(io.LimitReader(file, maxLaunchMetadataSize+1))
	if err != nil {
		return fmt.Errorf("read launch identity: %w", err)
	}
	var metadata launchMetadata
	if err := json.Unmarshal(data, &metadata); err != nil {
		return fmt.Errorf("decode launch identity: %w", err)
	}
	if metadata.Nonce != nonce || metadata.PID <= 1 || metadata.PGID != metadata.PID {
		return errors.New("launch identity mismatch")
	}
	return terminateVerifiedProcess(metadata)
}
