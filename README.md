# Hpktainer

**Hpktainer** is a CLI wrapper for [Apptainer](https://apptainer.org/) providing custom networking integrated with [Flannel](https://github.com/flannel-io/flannel). It is designed to run inside a **Bubble** (a rootless Apptainer instance) to provide overlay networking between containers across different hosts.

## Architecture

*   **Bubble**: A "master" container (`hpk-bubble`) running rootless on the host. It runs:
    *   **Flannel**: For overlay networking (VXLAN).
    *   **Apptainer**: To spawn nested containers (`hpktainer-base`).
*   **Hpktainer**: The CLI tool running inside the Bubble. It:
    *   Configures a bridge (`hpk-bridge`) and connects it to the Bubble's Flannel network.
    *   Launches nested containers with IPs from the Flannel subnet.
    *   Uses `hpk-net-daemon` to forward traffic over UNIX sockets.

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

### 1. Build Binaries and Images
Use the included `Makefile` to build binaries and multi-arch Docker images (amd64/arm64).

```bash
make all      # Builds binaries and images
# OR
make binaries # Just binaries (output to bin/)
make images   # Just images
```
*Note: `make images` requires `docker buildx` support.*

### 2. Push Images
The Makefile pushes to `docker.io/chazapis` by default. Override the registry:

```bash
REGISTRY=myregistry.io/user make images
```

## Running Hpktainer (Bubble Mode)

### 1. Start the Bubble
Run the `hpk-bubble.sh` script on the host. You need to assign an ID (to determine the subnet) and typically run it in the background or a separate terminal.

```bash
# Usage: ./scripts/hpk-bubble.sh [ID]
# ID defaults to 1. CIDR will be 10.0.(ID+1).0/24.

./scripts/hpk-bubble.sh 1
```

This starts the `hpk-bubble` instance interactively (or follow its logs). It will:
*   Start Flannel (auto-detecting host IP).
*   Provide a shell inside the bubble.

### 2. Connect to the Bubble
Once the bubble is running, you can open a shell inside it:

```bash
apptainer shell instance://bubble1
```
*(Replace `bubble1` with `bubble<ID>` if you used a different ID)*

### 3. Run Containers Inside the Bubble
Inside the bubble shell, you can use `hpktainer` to run nested containers connected to the overlay network.

```bash
# Inside the bubble
hpktainer run docker://docker.io/chazapis/hpktainer-base:latest /bin/sh
```

### 4. Verify Connectivity
Inside the nested container:
```bash
ip addr show     # Should see Flannel subnet IP
ping 8.8.8.8     # External access
ping <Other_Bubble_IP> # Inter-bubble access
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
