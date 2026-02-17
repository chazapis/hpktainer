package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	log.Println("=== Test: Find Container PID ===")

	// Build alpine.sif image
	alpineSIF := "/tmp/alpine.sif"
	log.Println("Building alpine.sif image...")
	pullCmd := exec.Command("apptainer", "pull", "--force", alpineSIF, "docker://alpine:latest")
	pullCmd.Stdout = os.Stdout
	pullCmd.Stderr = os.Stderr

	if err := pullCmd.Run(); err != nil {
		log.Fatalf("Failed to pull alpine image: %v", err)
	}
	log.Println("Alpine image ready at:", alpineSIF)

	// Start apptainer container with alpine.sif image
	log.Println("Starting apptainer container with alpine.sif...")
	cmd := exec.Command("apptainer", "exec", alpineSIF, "/bin/sh", "-c", "echo 'Hello from Alpine'; sleep 3600")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		log.Fatalf("Failed to start container: %v", err)
	}

	apptainerPID := cmd.Process.Pid
	log.Printf("Apptainer process started with PID: %d", apptainerPID)

	// Give the container a moment to start
	time.Sleep(500 * time.Millisecond)

	// Try to find the actual container process (sleep, sh, echo, etc.)
	log.Println("\nSearching for container processes...")
	
	// Look for common process names that might be running inside
	processNames := []string{"sleep", "sh", "echo", "apptainer", "init"}
	
	for _, name := range processNames {
		pid := findChildProcessByName(apptainerPID, name)
		if pid > 0 {
			log.Printf("✓ Found '%s' process with PID: %d", name, pid)
		}
	}

	// List all children
	log.Printf("\nAll child processes of apptainer (PID %d):\n", apptainerPID)
	listAllChildProcesses(apptainerPID)

	// Try to find hpk-pause and parse its namespace/pod
	log.Println("\nLooking for hpk-pause process...")
	hpkPausePID := findChildProcessByName(apptainerPID, "hpk-pause")
	if hpkPausePID > 0 {
		log.Printf("Found hpk-pause with PID: %d", hpkPausePID)
		if ns, pod, err := getProcessInfo(hpkPausePID); err == nil {
			log.Printf("  Namespace: %s", ns)
			log.Printf("  Pod: %s", pod)
		} else {
			log.Printf("  Could not parse namespace/pod: %v", err)
		}
	}

	// Cleanup
	log.Printf("\nTerminating container (PID %d)...", apptainerPID)
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		log.Printf("Warning: failed to signal process: %v", err)
	}
	cmd.Wait()

	log.Println("=== Test completed ===")
}

// findChildProcessByName searches for a child process by name using /proc
// Returns the PID if found, or 0 if not found
func findChildProcessByName(parentPID int, processName string) int {
	taskPath := fmt.Sprintf("/proc/%d/task/%d/children", parentPID, parentPID)
	data, err := os.ReadFile(taskPath)
	if err != nil {
		return 0
	}

	childPIDs := strings.Fields(string(data))
	for _, pidStr := range childPIDs {
		// Check if this PID's command name matches
		cmdlinePath := fmt.Sprintf("/proc/%s/cmdline", pidStr)
		cmdline, err := os.ReadFile(cmdlinePath)
		if err != nil {
			continue
		}
		// cmdline is null-separated, so we check the first part (the binary name)
		parts := strings.Split(string(cmdline), "\x00")
		if len(parts) > 0 {
			// Extract just the binary name from the path
			binaryName := filepath.Base(parts[0])
			if binaryName == processName {
				if pid, err := parseIntFromString(pidStr); err == nil {
					return pid
				}
			}
		}
	}
	return 0
}

// listAllChildProcesses lists all child processes of a given parent PID
func listAllChildProcesses(parentPID int) {
	taskPath := fmt.Sprintf("/proc/%d/task/%d/children", parentPID, parentPID)
	data, err := os.ReadFile(taskPath)
	if err != nil {
		log.Printf("  Could not read children: %v", err)
		return
	}

	childPIDs := strings.Fields(string(data))
	if len(childPIDs) == 0 {
		log.Println("  No child processes found")
		return
	}

	for _, pidStr := range childPIDs {
		cmdlinePath := fmt.Sprintf("/proc/%s/cmdline", pidStr)
		cmdline, err := os.ReadFile(cmdlinePath)
		if err != nil {
			continue
		}
		// cmdline is null-separated
		parts := strings.Split(string(cmdline), "\x00")
		if len(parts) > 0 && parts[0] != "" {
			binaryName := filepath.Base(parts[0])
			log.Printf("  PID %s: %s (%s)", pidStr, binaryName, parts[0])
		}
	}
}

// parseIntFromString converts a string to int
func parseIntFromString(s string) (int, error) {
	var result int
	_, err := fmt.Sscanf(s, "%d", &result)
	return result, err
}

// getProcessInfo retrieves namespace and pod name from hpk-pause process
// Expected format: /usr/local/bin/hpk-pause -namespace <NS> -pod <POD>
func getProcessInfo(pid int) (namespace, pod string, err error) {
	cmdlinePath := fmt.Sprintf("/proc/%d/cmdline", pid)
	cmdline, err := os.ReadFile(cmdlinePath)
	if err != nil {
		return "", "", fmt.Errorf("failed to read cmdline for PID %d: %v", pid, err)
	}

	// cmdline is null-separated, parse it
	parts := strings.Split(string(cmdline), "\x00")
	
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
		return "", "", fmt.Errorf("could not parse namespace and pod from PID %d", pid)
	}

	return namespace, pod, nil
}
