package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/netip"
	"strconv"
	"strings"
)

const (
	darwinTunCreateOperation   = "create-utun"
	darwinTunPingOperation     = "ping"
	darwinTunShutdownOperation = "shutdown"
	maxDarwinTunPrefixes       = 256
	maxDarwinTunResponse       = 64 << 10
)

type darwinTunLease struct {
	generation uint64
	ready      bool
}

func (lease *darwinTunLease) renew() uint64 {
	lease.generation++
	lease.ready = true
	return lease.generation
}

func (lease *darwinTunLease) invalidate() {
	lease.generation++
	lease.ready = false
}

func (lease *darwinTunLease) valid(generation uint64) bool {
	return lease.ready && lease.generation == generation
}

type darwinTunRequest struct {
	Operation                string   `json:"operation"`
	Name                     string   `json:"name,omitempty"`
	MTU                      uint32   `json:"mtu,omitempty"`
	AutoRoute                bool     `json:"autoRoute,omitempty"`
	Inet4Address             []string `json:"inet4Address,omitempty"`
	Inet6Address             []string `json:"inet6Address,omitempty"`
	Inet4RouteAddress        []string `json:"inet4RouteAddress,omitempty"`
	Inet6RouteAddress        []string `json:"inet6RouteAddress,omitempty"`
	Inet4RouteExcludeAddress []string `json:"inet4RouteExcludeAddress,omitempty"`
	Inet6RouteExcludeAddress []string `json:"inet6RouteExcludeAddress,omitempty"`
}

type darwinTunResponse struct {
	Error string `json:"error,omitempty"`
}

type darwinTunDescriptors struct {
	values  []int
	closeFD func(int) error
}

func (descriptors *darwinTunDescriptors) closeAll() {
	for _, fd := range descriptors.values {
		_ = descriptors.closeFD(fd)
	}
	descriptors.values = nil
}

func (descriptors *darwinTunDescriptors) takeSingle() (int, error) {
	switch len(descriptors.values) {
	case 0:
		return -1, nil
	case 1:
		fd := descriptors.values[0]
		descriptors.values = nil
		return fd, nil
	default:
		return -1, errors.New("invalid helper descriptor response")
	}
}

func decodeDarwinTunResponse(
	reader io.Reader,
	length uint32,
	descriptors *darwinTunDescriptors,
) (darwinTunResponse, int, error) {
	defer descriptors.closeAll()
	if length > maxDarwinTunResponse {
		return darwinTunResponse{}, -1, errors.New("helper response too large")
	}
	payload := make([]byte, length)
	if _, err := io.ReadFull(reader, payload); err != nil {
		return darwinTunResponse{}, -1, err
	}
	var response darwinTunResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return darwinTunResponse{}, -1, err
	}
	fd, err := descriptors.takeSingle()
	if err != nil {
		return darwinTunResponse{}, -1, err
	}
	return response, fd, nil
}

func validateDarwinTunRequest(request darwinTunRequest) error {
	if request.Operation != darwinTunCreateOperation {
		return errors.New("unsupported helper operation")
	}
	if !strings.HasPrefix(request.Name, "utun") {
		return errors.New("invalid utun name")
	}
	index, err := strconv.ParseUint(strings.TrimPrefix(request.Name, "utun"), 10, 16)
	if err != nil || index > 4095 {
		return errors.New("invalid utun index")
	}
	if request.MTU < 576 || request.MTU > 65535 {
		return errors.New("invalid utun MTU")
	}
	groups := []struct {
		name     string
		prefixes []string
		ipv4     bool
	}{
		{"inet4Address", request.Inet4Address, true},
		{"inet6Address", request.Inet6Address, false},
		{"inet4RouteAddress", request.Inet4RouteAddress, true},
		{"inet6RouteAddress", request.Inet6RouteAddress, false},
		{"inet4RouteExcludeAddress", request.Inet4RouteExcludeAddress, true},
		{"inet6RouteExcludeAddress", request.Inet6RouteExcludeAddress, false},
	}
	for _, group := range groups {
		if len(group.prefixes) > maxDarwinTunPrefixes {
			return fmt.Errorf("too many %s entries", group.name)
		}
		for _, raw := range group.prefixes {
			prefix, err := netip.ParsePrefix(raw)
			if err != nil || prefix.Addr().Is4() != group.ipv4 {
				return fmt.Errorf("invalid %s prefix", group.name)
			}
		}
	}
	if len(request.Inet4Address)+len(request.Inet6Address) == 0 {
		return errors.New("utun requires an interface address")
	}
	return nil
}
