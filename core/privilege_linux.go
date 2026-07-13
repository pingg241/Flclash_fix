//go:build !cgo && linux

package main

import (
	"fmt"
	"os"
	"os/user"
	"strconv"

	"golang.org/x/sys/unix"
)

const (
	sudoUIDEnvironment = "SUDO_UID"
	sudoGIDEnvironment = "SUDO_GID"
)

type sudoIdentity struct {
	uid    int
	gid    int
	groups []int
}

func resolveSudoIdentity(getenv func(string) string) (sudoIdentity, error) {
	uid, err := parseIdentityID(getenv(sudoUIDEnvironment), sudoUIDEnvironment)
	if err != nil {
		return sudoIdentity{}, err
	}
	gid, err := parseIdentityID(getenv(sudoGIDEnvironment), sudoGIDEnvironment)
	if err != nil {
		return sudoIdentity{}, err
	}
	account, err := user.LookupId(strconv.Itoa(uid))
	if err != nil {
		return sudoIdentity{}, fmt.Errorf("lookup sudo user: %w", err)
	}
	groupIDs, err := account.GroupIds()
	if err != nil {
		return sudoIdentity{}, fmt.Errorf("lookup sudo user groups: %w", err)
	}
	groups := make([]int, 0, len(groupIDs)+1)
	seen := map[int]struct{}{}
	for _, raw := range append(groupIDs, strconv.Itoa(gid)) {
		groupID, parseErr := parseIdentityID(raw, "supplementary group")
		if parseErr != nil {
			return sudoIdentity{}, parseErr
		}
		if _, exists := seen[groupID]; exists {
			continue
		}
		seen[groupID] = struct{}{}
		groups = append(groups, groupID)
	}
	return sudoIdentity{uid: uid, gid: gid, groups: groups}, nil
}

func parseIdentityID(value, name string) (int, error) {
	parsed, err := strconv.ParseUint(value, 10, 31)
	if err != nil || parsed == 0 {
		return 0, fmt.Errorf("missing or invalid %s", name)
	}
	return int(parsed), nil
}

func dropSetuidPrivileges() error {
	if err := unix.Setpgid(0, 0); err != nil && err != unix.EPERM {
		return fmt.Errorf("create core process group: %w", err)
	}
	if os.Geteuid() != 0 {
		return nil
	}
	identity, err := resolveSudoIdentity(os.Getenv)
	if err != nil {
		return fmt.Errorf("refuse unrestricted root core: %w", err)
	}
	if err := unix.Prctl(unix.PR_SET_KEEPCAPS, 1, 0, 0, 0); err != nil {
		return fmt.Errorf("retain network capabilities: %w", err)
	}
	if err := unix.Setgroups(identity.groups); err != nil {
		return fmt.Errorf("set user groups: %w", err)
	}
	if err := unix.Setresgid(identity.gid, identity.gid, identity.gid); err != nil {
		return fmt.Errorf("drop root gid: %w", err)
	}
	if err := unix.Setresuid(identity.uid, identity.uid, identity.uid); err != nil {
		return fmt.Errorf("drop root uid: %w", err)
	}
	if err := retainNetworkCapabilities(); err != nil {
		return err
	}
	if err := unix.Prctl(unix.PR_SET_KEEPCAPS, 0, 0, 0, 0); err != nil {
		return fmt.Errorf("disable capability retention: %w", err)
	}
	if os.Geteuid() != identity.uid || os.Getegid() != identity.gid {
		return fmt.Errorf("root identity drop did not take effect")
	}
	return nil
}

func retainNetworkCapabilities() error {
	mask := networkCapabilityMask()
	header := &unix.CapUserHeader{Version: unix.LINUX_CAPABILITY_VERSION_3}
	data := [2]unix.CapUserData{{Effective: mask, Permitted: mask}}
	if err := unix.Capset(header, &data[0]); err != nil {
		return fmt.Errorf("retain narrow network capabilities: %w", err)
	}
	return nil
}

func networkCapabilityMask() uint32 {
	var mask uint32
	for _, capability := range []int{unix.CAP_NET_BIND_SERVICE, unix.CAP_NET_ADMIN, unix.CAP_NET_RAW} {
		mask |= 1 << uint(capability)
	}
	return mask
}
