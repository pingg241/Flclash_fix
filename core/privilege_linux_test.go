//go:build linux && !cgo

package main

import "testing"

func TestParseIdentityID(t *testing.T) {
	for _, test := range []struct {
		name    string
		value   string
		want    int
		wantErr bool
	}{
		{name: "valid", value: "1000", want: 1000},
		{name: "missing", value: "", wantErr: true},
		{name: "root", value: "0", wantErr: true},
		{name: "negative", value: "-1", wantErr: true},
		{name: "text", value: "user", wantErr: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			got, err := parseIdentityID(test.value, "id")
			if (err != nil) != test.wantErr {
				t.Fatalf("parseIdentityID() error = %v, wantErr %v", err, test.wantErr)
			}
			if got != test.want {
				t.Fatalf("parseIdentityID() = %d, want %d", got, test.want)
			}
		})
	}
}

func TestRetainedCapabilityMaskIsNetworkOnly(t *testing.T) {
	const want = uint32(1<<10 | 1<<12 | 1<<13)
	if got := networkCapabilityMask(); got != want {
		t.Fatalf("capability mask = %#x, want %#x", got, want)
	}
}
