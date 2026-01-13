# Hpktainer

**Hpktainer** is a CLI wrapper for [Apptainer](https://apptainer.org/) that provides a custom networking solution integrated with [Flannel](https://github.com/flannel-io/flannel). It enables Apptainer containers to run with an IP address from a Flannel subnet, allowing for pod-like networking.

## Features

*   **Custom Networking**: Assigns unique IPs to containers from a Flannel-managed subnet.
*   **Host Bridge integration**: Connects containers to a host bridge (`hpk-bridge`) for connectivity.
*   **Traffic Forwarding**: Uses a client-server daemon (`hpk-net-daemon`) over UNIX sockets to tunnel traffic between the host tap interface and the container.
*   **Easy CLI**: Wraps `apptainer` commands, injecting necessary network configurations automatically.

## Prerequisites

*   **Linux**: Required for network namespaces, bridge support, and iptables.
*   **Go 1.23+**: For building the project.
*   **Apptainer**: The core container runtime.
*   **Flannel**: Must be running on the host. Hpktainer reads subnet config from `/run/flannel/subnet.env`.
*   **CNI Plugins**: Specifically the `host-local` plugin is used for IP allocation.
*   **Docker**: To build the base container image.

## Build Instructions

1.  **Build the binaries**:
    ```bash
    GOOS=linux go build -o hpktainer ./cmd/hpktainer
    GOOS=linux go build -o hpk-net-daemon ./cmd/hpk-net-daemon
    ```
    *Ensure `hpk-net-daemon` is in the same directory as `hpktainer` or in your `$PATH`.*

2.  **Build the Base Docker Image**:
    The container image requires the `hpk-net-daemon` and an entrypoint script.
    ```bash
    docker build -t hpktainer-base .
    ```

## Usage

Run an Apptainer container using `hpktainer`. Hpktainer intercepts the command, sets up the network, and then executes Apptainer.

```bash
./hpktainer run docker://hpktainer-base [command] [args...]
```

> **Note**: Root access (`sudo`) is required to configure network interfaces and iptables.

### Example: Interactive Shell

Start a shell inside a container with networking enabled:

```bash
./hpktainer run docker://hpktainer-base /bin/sh
```

### Verification Steps

Once inside the container (via the command above), try the following commands to verify connectivity:

1.  **Check Interface**:
    ```sh
    ip addr show tap0
    ```
    You should see an IP address from your Flannel subnet (e.g., `10.244.x.x`).

2.  **Check Route**:
    ```sh
    ip route
    ```
    The default gateway should be the host bridge IP.

3.  **Ping Host Bridge**:
    ```sh
    ping -c 3 $HPK_GATEWAY_IP
    ```

4.  **Ping External Address** (requires internet access on host):
    ```sh
    ping -c 3 8.8.8.8
    ```

5.  **Test TCP Connection**:
    ```sh
    wget -qO- http://google.com
    ```

## Architecture Overview

1.  **Initialization**: `hpktainer` reads Flannel config, creates/configures `hpk-bridge`, and allocates a container IP via `host-local` CNI.
2.  **Host Setup**: It creates a tap interface on the host, adds it to the bridge, and starts `hpk-net-daemon` in **server mode** to listen on a UNIX socket.
3.  **Container Launch**: `apptainer` is executed with `--network none` and `--bind` for the socket directory.
4.  **Container Start**: The container entrypoint starts `hpk-net-daemon` in **client mode**, which connects to the host socket. Traffic is forwarded between the host tap and the container via this socket.
