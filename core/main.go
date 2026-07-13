//go:build !cgo

package main

import (
	"fmt"
	"os"
)

func main() {
	args := os.Args
	if handled, err := runDarwinTunHelper(args[1:]); handled {
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if len(args) == 4 && args[1] == "--terminate" {
		if err := terminateLaunchedCore(args[2], args[3]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	if err := dropSetuidPrivileges(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: FlClashCore <ipc-address> <home-dir>")
		os.Exit(1)
	}
	if err := initializeHomeDir(args[2]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := writeLaunchMetadata(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	startServer(args[1])
}
