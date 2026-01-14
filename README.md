# HPKtainer

**HPKtainer** is a CLI wrapper for [Apptainer](https://apptainer.org/) providing custom networking integrated with [Flannel](https://github.com/flannel-io/flannel). It is designed to run inside a **bubble** (a rootless Apptainer instance) to provide overlay networking between nested containers across different hosts.

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

## Running HPKtainer

### 1. Start the Bubble
Run the `hpk-bubble.sh` script on the host. You need to assign an ID (to determine the slirp4netns subnet) and typically run it in the background or a separate terminal.

```bash
# Usage: ./scripts/hpk-bubble.sh [ID]
# ID defaults to 1. CIDR will be 10.0.(ID+1).0/24.

./scripts/hpk-bubble.sh 1
```

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
ip addr show tap0                # Should see the internal IP from the bubble's Flannel subnet (e.g., 10.244.x.x).
ip route                         # Should see a default route via the bubble's bridge.
ping 8.8.8.8                     # External access
ping <other nested container IP> # Inter-container access
wget -qO- http://google.com      # External access
```

## Architecture

Everything happens inside the **bubble** - the "master" container (`hpk-bubble`) running rootless on the host. The bubble uses [slirp4netns](https://github.com/rootless-containers/slirp4netns) for external networking, runs **Flannel** for internal, overlay networking, manages a bridge (`hpk-bridge`) that connects the Flannel interface with the interfaces of nested containers, and configures iptables for NATting traffic from the nested containers to the outside world.

Inside the bubble, **HPKtainer** (the Apptainer wrapper) is used to spawn containers that derive from `hpktainer-base`. These containers use a userspace network stack implemented with a pair of tap interfaces; one in the container and one in the bubble (the interface connected to the `hpk-bridge`). The pair is connected via two instances of the `hpk-net-daemon` - one in the container and one in the bubble - that forward traffic over a UNIX socket created in a shared folder.