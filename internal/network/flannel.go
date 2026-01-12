package network

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

type FlannelConfig struct {
	Subnet string
	MTU    string
	IPMasq bool
}

// ParseFlannelConfig reads /run/flannel/subnet.env and extracts FLANNEL_SUBNET.
func ParseFlannelConfig(path string) (*FlannelConfig, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open flannel config: %w", err)
	}
	defer file.Close()

	config := &FlannelConfig{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		value := parts[1]

		switch key {
		case "FLANNEL_SUBNET":
			config.Subnet = value
		case "FLANNEL_MTU":
			config.MTU = value
		case "FLANNEL_IPMASQ":
			config.IPMasq = (value == "true")
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading flannel config: %w", err)
	}

	if config.Subnet == "" {
		return nil, fmt.Errorf("FLANNEL_SUBNET not found in config")
	}

	return config, nil
}
