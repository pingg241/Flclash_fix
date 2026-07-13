package main

import (
	"bytes"
	"errors"
	"io"
	"reflect"
	"testing"
)

func TestValidateDarwinTunRequest(t *testing.T) {
	valid := darwinTunRequest{
		Operation:    darwinTunCreateOperation,
		Name:         "utun7",
		MTU:          9000,
		AutoRoute:    true,
		Inet4Address: []string{"198.18.0.1/30"},
	}
	if err := validateDarwinTunRequest(valid); err != nil {
		t.Fatalf("valid request rejected: %v", err)
	}

	tests := []struct {
		name   string
		mutate func(*darwinTunRequest)
	}{
		{"operation", func(r *darwinTunRequest) { r.Operation = "exec" }},
		{"name", func(r *darwinTunRequest) { r.Name = "en0" }},
		{"index", func(r *darwinTunRequest) { r.Name = "utun99999" }},
		{"mtu", func(r *darwinTunRequest) { r.MTU = 1 }},
		{"family", func(r *darwinTunRequest) { r.Inet4Address = []string{"fd00::1/64"} }},
		{"prefix", func(r *darwinTunRequest) { r.Inet4Address = []string{"not-a-prefix"} }},
		{"address", func(r *darwinTunRequest) { r.Inet4Address = nil }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := valid
			test.mutate(&request)
			if err := validateDarwinTunRequest(request); err == nil {
				t.Fatal("invalid request accepted")
			}
		})
	}
}

func TestDarwinTunLeaseInvalidatesStaleGeneration(t *testing.T) {
	var lease darwinTunLease
	first := lease.renew()
	if !lease.valid(first) {
		t.Fatal("renewed lease was not valid")
	}
	lease.invalidate()
	if lease.valid(first) {
		t.Fatal("invalidated lease accepted a stale generation")
	}
	second := lease.renew()
	if second == first || !lease.valid(second) {
		t.Fatal("re-prepared lease did not use a fresh generation")
	}
}

func TestDecodeDarwinTunResponseClosesDescriptorOnMalformedPayload(t *testing.T) {
	closed := make([]int, 0, 1)
	descriptors := testDarwinTunDescriptors([]int{7}, &closed)
	_, fd, err := decodeDarwinTunResponse(bytes.NewBufferString("{"), 1, descriptors)
	if err == nil || fd != -1 {
		t.Fatalf("decode result = fd %d, error %v", fd, err)
	}
	if !reflect.DeepEqual(closed, []int{7}) {
		t.Fatalf("closed descriptors = %v, want [7]", closed)
	}
}

func TestDecodeDarwinTunResponseClosesDescriptorOnTruncatedPayload(t *testing.T) {
	closed := make([]int, 0, 1)
	descriptors := testDarwinTunDescriptors([]int{8}, &closed)
	_, fd, err := decodeDarwinTunResponse(bytes.NewBufferString("{}"), 4, descriptors)
	if !errors.Is(err, io.ErrUnexpectedEOF) || fd != -1 {
		t.Fatalf("decode result = fd %d, error %v", fd, err)
	}
	if !reflect.DeepEqual(closed, []int{8}) {
		t.Fatalf("closed descriptors = %v, want [8]", closed)
	}
}

func TestDecodeDarwinTunResponseClosesAllExtraDescriptors(t *testing.T) {
	closed := make([]int, 0, 2)
	descriptors := testDarwinTunDescriptors([]int{9, 10}, &closed)
	_, fd, err := decodeDarwinTunResponse(bytes.NewBufferString("{}"), 2, descriptors)
	if err == nil || fd != -1 {
		t.Fatalf("decode result = fd %d, error %v", fd, err)
	}
	if !reflect.DeepEqual(closed, []int{9, 10}) {
		t.Fatalf("closed descriptors = %v, want [9 10]", closed)
	}
}

func TestDecodeDarwinTunResponseTransfersSingleDescriptor(t *testing.T) {
	closed := make([]int, 0, 1)
	descriptors := testDarwinTunDescriptors([]int{11}, &closed)
	response, fd, err := decodeDarwinTunResponse(bytes.NewBufferString("{}"), 2, descriptors)
	if err != nil {
		t.Fatal(err)
	}
	if response.Error != "" || fd != 11 {
		t.Fatalf("decode result = %#v, fd %d", response, fd)
	}
	if len(closed) != 0 {
		t.Fatalf("transferred descriptor was closed: %v", closed)
	}
}

func testDarwinTunDescriptors(values []int, closed *[]int) *darwinTunDescriptors {
	return &darwinTunDescriptors{
		values: append([]int(nil), values...),
		closeFD: func(fd int) error {
			*closed = append(*closed, fd)
			return nil
		},
	}
}
