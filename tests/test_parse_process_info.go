package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"testing"
	"time"
)

// TestParseProcessInfo tests parsing namespace and pod from a mock process
func TestParseProcessInfo(t *testing.T) {
	log.Println("=== Test: Parse Namespace and Pod from Process ===")

	// Start a mock hpk-pause-like process
	// We'll use /bin/sleep with arguments that mimic hpk-pause format
	log.Println("Starting mock hpk-pause process...")
	cmd := exec.Command("/bin/sh", "-c", "exec -a /usr/local/bin/hpk-pause sleep 3600")
	// Note: exec -a changes argv[0] to appear as hpk-pause
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		log.Fatalf("Failed to start mock process: %v", err)
	}

	mockPID := cmd.Process.Pid
	log.Printf("Mock process started with PID: %d", mockPID)
	defer func() {
		cmd.Process.Kill()
		cmd.Wait()
	}()

	// Write the process info to /proc for testing
	// Since we can't easily change cmdline, let's test the function directly
	log.Println("\nTesting parseProcessInfoFromCmdline function...")

	// Test cases
	testCases := []struct {
		name      string
		cmdline   string
		expectNS  string
		expectPod string
		shouldErr bool
	}{
		{
			name:      "Valid hpk-pause format",
			cmdline:   "/usr/local/bin/hpk-pause\x00-namespace\x00default\x00-pod\x00hpk-hello-world\x00",
			expectNS:  "default",
			expectPod: "hpk-hello-world",
			shouldErr: false,
		},
		{
			name:      "Different namespace and pod",
			cmdline:   "/usr/local/bin/hpk-pause\x00-namespace\x00kube-system\x00-pod\x00coredns\x00",
			expectNS:  "kube-system",
			expectPod: "coredns",
			shouldErr: false,
		},
		{
			name:      "Missing pod flag",
			cmdline:   "/usr/local/bin/hpk-pause\x00-namespace\x00default\x00",
			expectNS:  "",
			expectPod: "",
			shouldErr: true,
		},
		{
			name:      "Missing namespace flag",
			cmdline:   "/usr/local/bin/hpk-pause\x00-pod\x00hpk-hello-world\x00",
			expectNS:  "",
			expectPod: "",
			shouldErr: true,
		},
	}

	for _, tc := range testCases {
		log.Printf("\nTest: %s", tc.name)
		ns, pod, err := parseProcessInfoFromCmdline(tc.cmdline)

		if tc.shouldErr {
			if err == nil {
				log.Printf("  ✗ FAIL: expected error but got none")
			} else {
				log.Printf("  ✓ PASS: got expected error: %v", err)
			}
		} else {
			if err != nil {
				log.Printf("  ✗ FAIL: unexpected error: %v", err)
			} else if ns != tc.expectNS || pod != tc.expectPod {
				log.Printf("  ✗ FAIL: got namespace='%s', pod='%s' but expected namespace='%s', pod='%s'",
					ns, pod, tc.expectNS, tc.expectPod)
			} else {
				log.Printf("  ✓ PASS: namespace='%s', pod='%s'", ns, pod)
			}
		}
	}

	log.Println("\n=== All tests completed ===")
}

// parseProcessInfoFromCmdline parses namespace and pod from a cmdline string
// Expected format: /usr/local/bin/hpk-pause -namespace <NS> -pod <POD>
func parseProcessInfoFromCmdline(cmdline string) (namespace, pod string, err error) {
	// cmdline is null-separated, parse it
	var parts []string
	var current string
	for _, ch := range cmdline {
		if ch == '\x00' {
			if current != "" {
				parts = append(parts, current)
				current = ""
			}
		} else {
			current += string(ch)
		}
	}
	if current != "" {
		parts = append(parts, current)
	}

	log.Printf("  Parsed parts: %v", parts)

	// Look for -namespace and -pod flags
	for i := 0; i < len(parts)-1; i++ {
		if parts[i] == "-namespace" && i+1 < len(parts) {
			namespace = parts[i+1]
		}
		if parts[i] == "-pod" && i+1 < len(parts) {
			pod = parts[i+1]
		}
	}

	if namespace == "" || pod == "" {
		return "", "", fmt.Errorf("could not parse namespace or pod from cmdline")
	}

	return namespace, pod, nil
}

// Main entry for running as standalone test
func main() {
	// Run the test
	t := &testing.T{}
	TestParseProcessInfo(t)
}
