//go:build darwin && !cgo

package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	singtun "github.com/metacubex/mihomo/listener/sing_tun"
	tun "github.com/metacubex/sing-tun"
	"github.com/metacubex/sing/common"
	E "github.com/metacubex/sing/common/exceptions"
	"golang.org/x/net/route"
	"golang.org/x/sys/unix"
)

const (
	darwinTunHelperMode    = "--darwin-tun-helper"
	darwinTunAuthCoreLabel = "flclash-darwin-tun-core-v1"
	darwinTunAuthRootLabel = "flclash-darwin-tun-helper-v1"
	darwinTunReleaseDelay  = 10 * time.Second
	darwinTunRPCTimeout    = 15 * time.Second
	utunControlName        = "com.apple.net.utun_control"
)

type darwinTunAuth struct {
	Nonce string `json:"nonce"`
	Proof string `json:"proof"`
}

type darwinTunHelperManager struct {
	mu           sync.Mutex
	conn         *net.UnixConn
	command      *exec.Cmd
	releaseTimer *time.Timer
	releaseEpoch uint64
	lease        darwinTunLease
}

var defaultDarwinTunHelper darwinTunHelperManager

func init() {
	singtun.DarwinTunFileDescriptorProvider = acquireDarwinTunFileDescriptor
	singtun.DarwinTunClosed = scheduleDarwinTunHelperRelease
}

func prepareDarwinTunHelper() error {
	return defaultDarwinTunHelper.prepare()
}

func releaseDarwinTunHelper() error {
	return defaultDarwinTunHelper.release()
}

func acquireDarwinTunFileDescriptor(options tun.Options) (int, error) {
	return defaultDarwinTunHelper.acquire(options)
}

func scheduleDarwinTunHelperRelease() {
	defaultDarwinTunHelper.scheduleRelease()
}

func (manager *darwinTunHelperManager) prepare() error {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.releaseEpoch++
	if manager.releaseTimer != nil {
		manager.releaseTimer.Stop()
		manager.releaseTimer = nil
	}
	if manager.conn != nil {
		if err := manager.pingLocked(); err == nil {
			manager.lease.renew()
			return nil
		}
		manager.closeLocked()
	}

	home, err := currentTrustedHomeDir()
	if err != nil {
		return err
	}
	tmpDir := filepath.Join(home, ".tmp")
	if err := os.MkdirAll(tmpDir, 0o700); err != nil {
		return fmt.Errorf("create helper directory: %w", err)
	}
	if err := os.Chmod(tmpDir, 0o700); err != nil {
		return fmt.Errorf("secure helper directory: %w", err)
	}
	secret, err := randomDarwinTunToken()
	if err != nil {
		return err
	}
	suffix, err := randomDarwinTunToken()
	if err != nil {
		return err
	}
	suffix = strings.NewReplacer("/", "_", "+", "-", "=", "").Replace(suffix[:16])
	tokenPath := filepath.Join(tmpDir, "tun-helper-"+suffix+".token")
	socketPath := filepath.Join(tmpDir, "tun-helper-"+suffix+".sock")
	if err := os.WriteFile(tokenPath, []byte(secret), 0o600); err != nil {
		return fmt.Errorf("write helper token: %w", err)
	}
	defer os.Remove(tokenPath)
	if err := os.Chmod(tokenPath, 0o600); err != nil {
		return fmt.Errorf("secure helper token: %w", err)
	}

	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: socketPath, Net: "unix"})
	if err != nil {
		return fmt.Errorf("listen for privileged helper: %w", err)
	}
	defer func() {
		_ = listener.Close()
		_ = os.Remove(socketPath)
	}()
	if err := os.Chmod(socketPath, 0o600); err != nil {
		return fmt.Errorf("secure helper socket: %w", err)
	}
	if err := listener.SetDeadline(time.Now().Add(30 * time.Second)); err != nil {
		return fmt.Errorf("set helper accept deadline: %w", err)
	}
	command, err := startDarwinTunHelperProcess(socketPath, tokenPath, home)
	if err != nil {
		return err
	}
	conn, err := listener.AcceptUnix()
	if err != nil {
		_ = command.Process.Kill()
		_ = command.Wait()
		return fmt.Errorf("accept privileged helper: %w", err)
	}
	if err := verifyDarwinPeerUID(conn, 0); err != nil {
		_ = conn.Close()
		_ = command.Process.Kill()
		_ = command.Wait()
		return fmt.Errorf("verify privileged helper: %w", err)
	}
	if err := authenticateDarwinTunCore(conn, secret); err != nil {
		_ = conn.Close()
		_ = command.Process.Kill()
		_ = command.Wait()
		return err
	}
	manager.conn = conn
	manager.command = command
	manager.lease.renew()
	return nil
}

func (manager *darwinTunHelperManager) acquire(options tun.Options) (int, error) {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.releaseEpoch++
	if manager.releaseTimer != nil {
		manager.releaseTimer.Stop()
		manager.releaseTimer = nil
	}
	if manager.conn == nil || !manager.lease.ready {
		return -1, errors.New("privileged TUN helper is not authorized")
	}
	request := darwinTunRequest{
		Operation:                darwinTunCreateOperation,
		Name:                     options.Name,
		MTU:                      options.MTU,
		AutoRoute:                options.AutoRoute,
		Inet4Address:             prefixesToStrings(options.Inet4Address),
		Inet6Address:             prefixesToStrings(options.Inet6Address),
		Inet4RouteAddress:        prefixesToStrings(options.Inet4RouteAddress),
		Inet6RouteAddress:        prefixesToStrings(options.Inet6RouteAddress),
		Inet4RouteExcludeAddress: prefixesToStrings(options.Inet4RouteExcludeAddress),
		Inet6RouteExcludeAddress: prefixesToStrings(options.Inet6RouteExcludeAddress),
	}
	if err := validateDarwinTunRequest(request); err != nil {
		manager.scheduleReleaseLocked(darwinTunReleaseDelay)
		return -1, err
	}
	if err := manager.conn.SetDeadline(time.Now().Add(darwinTunRPCTimeout)); err != nil {
		return -1, err
	}
	defer manager.conn.SetDeadline(time.Time{})
	if err := writeDarwinTunRequest(manager.conn, request); err != nil {
		manager.closeLocked()
		return -1, err
	}
	response, fd, err := readDarwinTunResponse(manager.conn)
	if err != nil {
		manager.closeLocked()
		return -1, err
	}
	if response.Error != "" {
		if fd >= 0 {
			_ = unix.Close(fd)
		}
		manager.scheduleReleaseLocked(darwinTunReleaseDelay)
		return -1, errors.New(response.Error)
	}
	if fd < 0 {
		manager.scheduleReleaseLocked(darwinTunReleaseDelay)
		return -1, errors.New("privileged helper returned no TUN descriptor")
	}
	return fd, nil
}

func (manager *darwinTunHelperManager) pingLocked() error {
	conn := manager.conn
	if conn == nil {
		return errors.New("privileged TUN helper is not connected")
	}
	if err := conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return err
	}
	defer conn.SetDeadline(time.Time{})
	if err := writeDarwinTunRequest(conn, darwinTunRequest{Operation: darwinTunPingOperation}); err != nil {
		return err
	}
	response, fd, err := readDarwinTunResponse(conn)
	if fd >= 0 {
		_ = unix.Close(fd)
		if err == nil {
			err = errors.New("privileged helper returned a descriptor for ping")
		}
	}
	if err != nil {
		return err
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}

func (manager *darwinTunHelperManager) scheduleRelease() {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.scheduleReleaseLocked(darwinTunReleaseDelay)
}

func (manager *darwinTunHelperManager) scheduleReleaseLocked(delay time.Duration) {
	if manager.releaseTimer != nil {
		manager.releaseTimer.Stop()
	}
	manager.releaseEpoch++
	epoch := manager.releaseEpoch
	manager.releaseTimer = time.AfterFunc(delay, func() {
		manager.mu.Lock()
		defer manager.mu.Unlock()
		if manager.releaseEpoch != epoch {
			return
		}
		if err := manager.releaseLocked(); err != nil {
			logError("release Darwin TUN helper: %v", err)
		}
	})
}

func (manager *darwinTunHelperManager) release() error {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	manager.releaseEpoch++
	return manager.releaseLocked()
}

func (manager *darwinTunHelperManager) releaseLocked() error {
	if manager.releaseTimer != nil {
		manager.releaseTimer.Stop()
		manager.releaseTimer = nil
	}
	if manager.conn == nil {
		return nil
	}
	conn := manager.conn
	_ = conn.SetDeadline(time.Now().Add(5 * time.Second))
	err := writeDarwinTunRequest(conn, darwinTunRequest{Operation: darwinTunShutdownOperation})
	if err == nil {
		var response darwinTunResponse
		var fd int
		response, fd, err = readDarwinTunResponse(conn)
		if fd >= 0 {
			_ = unix.Close(fd)
			if err == nil {
				err = errors.New("privileged helper returned a descriptor for shutdown")
			}
		}
		if err == nil && response.Error != "" {
			err = errors.New(response.Error)
		}
	}
	manager.closeLocked()
	return err
}

func (manager *darwinTunHelperManager) closeLocked() {
	conn := manager.conn
	command := manager.command
	manager.conn = nil
	manager.command = nil
	manager.lease.invalidate()
	if conn != nil {
		_ = conn.Close()
	}
	if command != nil {
		go func() {
			wait := make(chan struct{})
			go func() {
				_ = command.Wait()
				close(wait)
			}()
			select {
			case <-wait:
			case <-time.After(5 * time.Second):
				_ = command.Process.Kill()
				<-wait
			}
		}()
	}
}

func currentTrustedHomeDir() (string, error) {
	homeLock.Lock()
	defer homeLock.Unlock()
	if trustedHomeDir == "" {
		return "", errors.New("home dir not initialized")
	}
	return trustedHomeDir, nil
}

func randomDarwinTunToken() (string, error) {
	data := make([]byte, 32)
	if _, err := rand.Read(data); err != nil {
		return "", fmt.Errorf("generate helper token: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}

func startDarwinTunHelperProcess(socketPath, tokenPath, home string) (*exec.Cmd, error) {
	executable, err := os.Executable()
	if err != nil {
		return nil, fmt.Errorf("resolve core executable: %w", err)
	}
	executableHash, err := hashDarwinTunExecutable(executable)
	if err != nil {
		return nil, err
	}
	const script = `
set helperPath to system attribute "FLCLASH_TUN_HELPER_PATH"
set socketPath to system attribute "FLCLASH_TUN_SOCKET_PATH"
set tokenPath to system attribute "FLCLASH_TUN_TOKEN_PATH"
set homePath to system attribute "FLCLASH_TUN_HOME_PATH"
set userID to system attribute "FLCLASH_TUN_USER_ID"
set helperHash to system attribute "FLCLASH_TUN_HELPER_HASH"
set launchCommand to quoted form of helperPath & " --darwin-tun-helper " & quoted form of socketPath & " " & quoted form of tokenPath & " " & quoted form of homePath & " " & quoted form of userID & " " & quoted form of helperHash
do shell script launchCommand with administrator privileges
`
	command := exec.Command("/usr/bin/osascript", "-e", script)
	command.Env = append(os.Environ(),
		"FLCLASH_TUN_HELPER_PATH="+executable,
		"FLCLASH_TUN_SOCKET_PATH="+socketPath,
		"FLCLASH_TUN_TOKEN_PATH="+tokenPath,
		"FLCLASH_TUN_HOME_PATH="+home,
		"FLCLASH_TUN_USER_ID="+strconv.Itoa(os.Getuid()),
		"FLCLASH_TUN_HELPER_HASH="+executableHash,
	)
	command.Stdout = io.Discard
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		return nil, fmt.Errorf("start privileged helper: %w", err)
	}
	return command, nil
}

func runDarwinTunHelper(args []string) (bool, error) {
	if len(args) == 0 || args[0] != darwinTunHelperMode {
		return false, nil
	}
	if len(args) != 6 {
		return true, errors.New("invalid Darwin TUN helper arguments")
	}
	if os.Geteuid() != 0 {
		return true, errors.New("Darwin TUN helper requires root")
	}
	expectedUID64, err := strconv.ParseUint(args[4], 10, 32)
	if err != nil || expectedUID64 == 0 {
		return true, errors.New("invalid Darwin TUN helper uid")
	}
	expectedUID := uint32(expectedUID64)
	executable, err := os.Executable()
	if err != nil {
		return true, fmt.Errorf("resolve helper executable: %w", err)
	}
	executableHash, err := hashDarwinTunExecutable(executable)
	if err != nil || !hmac.Equal([]byte(executableHash), []byte(args[5])) {
		return true, errors.New("Darwin TUN helper executable changed")
	}
	secret, err := readDarwinTunHelperToken(args[2], args[3], expectedUID)
	if err != nil {
		return true, err
	}
	if err := validateDarwinTunHelperPath(args[1], args[3], "tun-helper-", ".sock"); err != nil {
		return true, err
	}
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: args[1], Net: "unix"})
	if err != nil {
		return true, fmt.Errorf("connect helper socket: %w", err)
	}
	defer conn.Close()
	if err := verifyDarwinPeerUID(conn, expectedUID); err != nil {
		return true, fmt.Errorf("verify core peer: %w", err)
	}
	if err := authenticateDarwinTunHelper(conn, secret); err != nil {
		return true, err
	}
	return true, serveDarwinTunHelper(conn)
}

func hashDarwinTunExecutable(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open helper executable: %w", err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", fmt.Errorf("hash helper executable: %w", err)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func readDarwinTunHelperToken(path, home string, expectedUID uint32) (string, error) {
	if err := validateDarwinTunHelperPath(path, home, "tun-helper-", ".token"); err != nil {
		return "", err
	}
	fd, err := unix.Open(path, unix.O_RDONLY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return "", fmt.Errorf("open helper token: %w", err)
	}
	file := os.NewFile(uintptr(fd), "tun-helper-token")
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", err
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != expectedUID || !info.Mode().IsRegular() || info.Mode().Perm()&0o077 != 0 || info.Size() > 4096 {
		return "", errors.New("invalid helper token file")
	}
	data, err := io.ReadAll(io.LimitReader(file, 4097))
	if err != nil || len(data) < 32 || len(data) > 4096 {
		return "", errors.New("invalid helper token")
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return "", fmt.Errorf("remove helper token: %w", err)
	}
	return string(data), nil
}

func validateDarwinTunHelperPath(path, home, prefix, suffix string) error {
	canonicalHome, err := filepath.EvalSymlinks(home)
	if err != nil {
		return fmt.Errorf("resolve helper home: %w", err)
	}
	canonicalPath, err := filepath.EvalSymlinks(path)
	if err != nil {
		return fmt.Errorf("resolve helper path: %w", err)
	}
	allowedDir := filepath.Join(canonicalHome, ".tmp")
	if filepath.Dir(canonicalPath) != allowedDir {
		return errors.New("helper path outside private directory")
	}
	base := filepath.Base(canonicalPath)
	if !strings.HasPrefix(base, prefix) || !strings.HasSuffix(base, suffix) {
		return errors.New("invalid helper path name")
	}
	return nil
}

func verifyDarwinPeerUID(conn *net.UnixConn, expected uint32) error {
	raw, err := conn.SyscallConn()
	if err != nil {
		return err
	}
	var credential *unix.Xucred
	var controlErr error
	if err := raw.Control(func(fd uintptr) {
		credential, controlErr = unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
	}); err != nil {
		return err
	}
	if controlErr != nil {
		return controlErr
	}
	if credential == nil || credential.Uid != expected {
		return errors.New("unexpected Unix peer uid")
	}
	return nil
}

func darwinTunProof(secret, label, nonce string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(label))
	_, _ = mac.Write([]byte{0})
	_, _ = mac.Write([]byte(nonce))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func authenticateDarwinTunCore(conn *net.UnixConn, secret string) error {
	nonce, err := randomDarwinTunToken()
	if err != nil {
		return err
	}
	request := darwinTunAuth{Nonce: nonce, Proof: darwinTunProof(secret, darwinTunAuthCoreLabel, nonce)}
	if err := writeJSONFrame(conn, request); err != nil {
		return fmt.Errorf("write helper authentication: %w", err)
	}
	var response darwinTunAuth
	if err := readJSONFrame(conn, &response, 4096); err != nil {
		return fmt.Errorf("read helper authentication: %w", err)
	}
	expected := darwinTunProof(secret, darwinTunAuthRootLabel, nonce)
	if response.Nonce != nonce || !hmac.Equal([]byte(response.Proof), []byte(expected)) {
		return errors.New("invalid privileged helper proof")
	}
	return nil
}

func authenticateDarwinTunHelper(conn *net.UnixConn, secret string) error {
	var request darwinTunAuth
	if err := readJSONFrame(conn, &request, 4096); err != nil {
		return fmt.Errorf("read core authentication: %w", err)
	}
	expected := darwinTunProof(secret, darwinTunAuthCoreLabel, request.Nonce)
	if len(request.Nonce) < 32 || !hmac.Equal([]byte(request.Proof), []byte(expected)) {
		return errors.New("invalid core proof")
	}
	response := darwinTunAuth{Nonce: request.Nonce, Proof: darwinTunProof(secret, darwinTunAuthRootLabel, request.Nonce)}
	return writeJSONFrame(conn, response)
}

func writeJSONFrame(writer io.Writer, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return writeFrame(writer, data)
}

func readJSONFrame(reader io.Reader, value any, limit uint32) error {
	header := make([]byte, 4)
	if _, err := io.ReadFull(reader, header); err != nil {
		return err
	}
	length := binary.LittleEndian.Uint32(header)
	if length > limit {
		return errors.New("helper frame too large")
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(reader, data); err != nil {
		return err
	}
	return json.Unmarshal(data, value)
}

func writeDarwinTunRequest(writer io.Writer, request darwinTunRequest) error {
	return writeJSONFrame(writer, request)
}

func readDarwinTunResponse(conn *net.UnixConn) (darwinTunResponse, int, error) {
	header := make([]byte, 4)
	// Reserve space for a second descriptor so an invalid multi-FD response is
	// observable instead of being silently truncated to the expected single FD.
	oob := make([]byte, unix.CmsgSpace(8))
	n, oobn, flags, _, err := conn.ReadMsgUnix(header, oob)
	if err != nil {
		return darwinTunResponse{}, -1, err
	}
	descriptors := &darwinTunDescriptors{closeFD: unix.Close}
	defer descriptors.closeAll()
	if oobn > 0 {
		messages, err := unix.ParseSocketControlMessage(oob[:oobn])
		if err != nil {
			return darwinTunResponse{}, -1, err
		}
		for index := range messages {
			message := &messages[index]
			if message.Header.Level != unix.SOL_SOCKET || message.Header.Type != unix.SCM_RIGHTS {
				continue
			}
			fds, err := unix.ParseUnixRights(message)
			if err != nil {
				return darwinTunResponse{}, -1, err
			}
			descriptors.values = append(descriptors.values, fds...)
		}
	}
	if flags&unix.MSG_CTRUNC != 0 {
		return darwinTunResponse{}, -1, errors.New("truncated helper descriptor response")
	}
	if n < len(header) {
		if _, err := io.ReadFull(conn, header[n:]); err != nil {
			return darwinTunResponse{}, -1, err
		}
	}
	length := binary.LittleEndian.Uint32(header)
	response, fd, err := decodeDarwinTunResponse(conn, length, descriptors)
	if err != nil {
		return darwinTunResponse{}, -1, err
	}
	return response, fd, nil
}

func sendDarwinTunResponse(conn *net.UnixConn, response darwinTunResponse, fd int) error {
	payload, err := json.Marshal(response)
	if err != nil {
		return err
	}
	frame := make([]byte, 4+len(payload))
	binary.LittleEndian.PutUint32(frame, uint32(len(payload)))
	copy(frame[4:], payload)
	var rights []byte
	if fd >= 0 {
		rights = unix.UnixRights(fd)
	}
	n, oobn, err := conn.WriteMsgUnix(frame, rights, nil)
	if err != nil {
		return err
	}
	if n != len(frame) || oobn != len(rights) {
		return io.ErrShortWrite
	}
	return nil
}

func serveDarwinTunHelper(conn *net.UnixConn) error {
	for {
		var request darwinTunRequest
		if err := readJSONFrame(conn, &request, maxDarwinTunResponse); err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
		if request.Operation == darwinTunShutdownOperation {
			return sendDarwinTunResponse(conn, darwinTunResponse{}, -1)
		}
		if request.Operation == darwinTunPingOperation {
			if err := sendDarwinTunResponse(conn, darwinTunResponse{}, -1); err != nil {
				return err
			}
			continue
		}
		if err := validateDarwinTunRequest(request); err != nil {
			if writeErr := sendDarwinTunResponse(conn, darwinTunResponse{Error: err.Error()}, -1); writeErr != nil {
				return writeErr
			}
			continue
		}
		fd, err := createDarwinTun(request)
		if err != nil {
			if writeErr := sendDarwinTunResponse(conn, darwinTunResponse{Error: err.Error()}, -1); writeErr != nil {
				return writeErr
			}
			continue
		}
		sendErr := sendDarwinTunResponse(conn, darwinTunResponse{}, fd)
		_ = unix.Close(fd)
		if sendErr != nil {
			return sendErr
		}
	}
}

func prefixesToStrings(prefixes []netip.Prefix) []string {
	result := make([]string, len(prefixes))
	for index, prefix := range prefixes {
		result[index] = prefix.String()
	}
	return result
}

func parseDarwinPrefixes(raw []string) ([]netip.Prefix, error) {
	result := make([]netip.Prefix, len(raw))
	for index, value := range raw {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return nil, err
		}
		result[index] = prefix
	}
	return result, nil
}

func createDarwinTun(request darwinTunRequest) (int, error) {
	inet4, _ := parseDarwinPrefixes(request.Inet4Address)
	inet6, _ := parseDarwinPrefixes(request.Inet6Address)
	route4, _ := parseDarwinPrefixes(request.Inet4RouteAddress)
	route6, _ := parseDarwinPrefixes(request.Inet6RouteAddress)
	exclude4, _ := parseDarwinPrefixes(request.Inet4RouteExcludeAddress)
	exclude6, _ := parseDarwinPrefixes(request.Inet6RouteExcludeAddress)
	options := tun.Options{
		Name:                     request.Name,
		MTU:                      request.MTU,
		AutoRoute:                request.AutoRoute,
		Inet4Address:             inet4,
		Inet6Address:             inet6,
		Inet4RouteAddress:        route4,
		Inet6RouteAddress:        route6,
		Inet4RouteExcludeAddress: exclude4,
		Inet6RouteExcludeAddress: exclude6,
	}
	fd, err := unix.Socket(unix.AF_SYSTEM, unix.SOCK_DGRAM, 2)
	if err != nil {
		return -1, err
	}
	unix.CloseOnExec(fd)
	if err := configureDarwinTun(fd, options); err != nil {
		_ = unix.Close(fd)
		return -1, err
	}
	return fd, nil
}

const (
	sioCaIfAddrIn6      = 2155899162
	in6IffNoDad         = 0x0020
	in6IffSecured       = 0x0400
	nd6InfiniteLifetime = 0xFFFFFFFF
)

type darwinIfAliasReq struct {
	Name    [unix.IFNAMSIZ]byte
	Addr    unix.RawSockaddrInet4
	Dstaddr unix.RawSockaddrInet4
	Mask    unix.RawSockaddrInet4
}

type darwinIfAliasReq6 struct {
	Name     [16]byte
	Addr     unix.RawSockaddrInet6
	Dstaddr  unix.RawSockaddrInet6
	Mask     unix.RawSockaddrInet6
	Flags    uint32
	Lifetime darwinAddrLifetime6
}

type darwinAddrLifetime6 struct {
	Expire    float64
	Preferred float64
	Vltime    uint32
	Pltime    uint32
}

func configureDarwinTun(fd int, options tun.Options) error {
	index, _ := strconv.ParseUint(strings.TrimPrefix(options.Name, "utun"), 10, 16)
	control := &unix.CtlInfo{}
	copy(control.Name[:], utunControlName)
	if err := unix.IoctlCtlInfo(fd, control); err != nil {
		return os.NewSyscallError("IoctlCtlInfo", err)
	}
	if err := unix.Connect(fd, &unix.SockaddrCtl{ID: control.Id, Unit: uint32(index) + 1}); err != nil {
		return os.NewSyscallError("Connect", err)
	}
	if err := withDarwinSocket(unix.AF_INET, func(socket int) error {
		var request unix.IfreqMTU
		copy(request.Name[:], options.Name)
		request.MTU = int32(options.MTU)
		return unix.IoctlSetIfreqMTU(socket, &request)
	}); err != nil {
		return os.NewSyscallError("IoctlSetIfreqMTU", err)
	}
	for _, address := range options.Inet4Address {
		request := darwinIfAliasReq{
			Addr:    unix.RawSockaddrInet4{Len: unix.SizeofSockaddrInet4, Family: unix.AF_INET, Addr: address.Addr().As4()},
			Dstaddr: unix.RawSockaddrInet4{Len: unix.SizeofSockaddrInet4, Family: unix.AF_INET, Addr: address.Addr().As4()},
			Mask:    unix.RawSockaddrInet4{Len: unix.SizeofSockaddrInet4, Family: unix.AF_INET, Addr: netip.AddrFrom4([4]byte(net.CIDRMask(address.Bits(), 32))).As4()},
		}
		copy(request.Name[:], options.Name)
		if err := withDarwinSocket(unix.AF_INET, func(socket int) error {
			_, _, errno := unix.Syscall(syscall.SYS_IOCTL, uintptr(socket), uintptr(unix.SIOCAIFADDR), uintptr(unsafe.Pointer(&request)))
			return errno
		}); err != nil {
			return err
		}
	}
	for _, address := range options.Inet6Address {
		mask := net.CIDRMask(address.Bits(), 128)
		var maskBytes [16]byte
		copy(maskBytes[:], mask)
		request := darwinIfAliasReq6{
			Addr:     unix.RawSockaddrInet6{Len: unix.SizeofSockaddrInet6, Family: unix.AF_INET6, Addr: address.Addr().As16()},
			Mask:     unix.RawSockaddrInet6{Len: unix.SizeofSockaddrInet6, Family: unix.AF_INET6, Addr: maskBytes},
			Flags:    in6IffNoDad | in6IffSecured,
			Lifetime: darwinAddrLifetime6{Vltime: nd6InfiniteLifetime, Pltime: nd6InfiniteLifetime},
		}
		if address.Bits() == 128 {
			request.Dstaddr = unix.RawSockaddrInet6{Len: unix.SizeofSockaddrInet6, Family: unix.AF_INET6, Addr: address.Addr().Next().As16()}
		}
		copy(request.Name[:], options.Name)
		if err := withDarwinSocket(unix.AF_INET6, func(socket int) error {
			_, _, errno := unix.Syscall(syscall.SYS_IOCTL, uintptr(socket), uintptr(sioCaIfAddrIn6), uintptr(unsafe.Pointer(&request)))
			return errno
		}); err != nil {
			return err
		}
	}
	if options.AutoRoute {
		ranges, err := options.BuildAutoRouteRanges(false)
		if err != nil {
			return err
		}
		if len(ranges) > 4096 {
			return errors.New("too many generated routes")
		}
		gateway4, gateway6 := options.Inet4GatewayAddr(), options.Inet6GatewayAddr()
		for _, destination := range ranges {
			gateway := gateway6
			if destination.Addr().Is4() {
				gateway = gateway4
			}
			if err := addDarwinTunRoute(destination, gateway); err != nil {
				return E.Cause(err, "add route: ", destination)
			}
		}
		_ = exec.Command("/usr/bin/dscacheutil", "-flushcache").Run()
	}
	return nil
}

func withDarwinSocket(family int, function func(int) error) error {
	fd, err := unix.Socket(family, unix.SOCK_DGRAM, 0)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	return function(fd)
}

func addDarwinTunRoute(destination netip.Prefix, gateway netip.Addr) error {
	message := route.RouteMessage{Type: unix.RTM_ADD, Flags: unix.RTF_UP | unix.RTF_STATIC | unix.RTF_GATEWAY, Version: unix.RTM_VERSION, Seq: 1}
	if gateway.Is4() {
		mask := net.CIDRMask(destination.Bits(), 32)
		var maskBytes [4]byte
		copy(maskBytes[:], mask)
		message.Addrs = []route.Addr{
			syscall.RTAX_DST:     &route.Inet4Addr{IP: destination.Addr().As4()},
			syscall.RTAX_NETMASK: &route.Inet4Addr{IP: maskBytes},
			syscall.RTAX_GATEWAY: &route.Inet4Addr{IP: gateway.As4()},
		}
	} else {
		mask := net.CIDRMask(destination.Bits(), 128)
		var maskBytes [16]byte
		copy(maskBytes[:], mask)
		message.Addrs = []route.Addr{
			syscall.RTAX_DST:     &route.Inet6Addr{IP: destination.Addr().As16()},
			syscall.RTAX_NETMASK: &route.Inet6Addr{IP: maskBytes},
			syscall.RTAX_GATEWAY: &route.Inet6Addr{IP: gateway.As16()},
		}
	}
	request, err := message.Marshal()
	if err != nil {
		return err
	}
	return withDarwinRouteSocket(func(fd int) error { return common.Error(unix.Write(fd, request)) })
}

func withDarwinRouteSocket(function func(int) error) error {
	fd, err := unix.Socket(unix.AF_ROUTE, unix.SOCK_RAW, 0)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	return function(fd)
}
