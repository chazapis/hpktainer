# HPKtainer

**HPKtainer** is a CLI wrapper for [Apptainer](https://apptainer.org/) providing custom networking integrated with [Flannel](https://github.com/flannel-io/flannel). It is designed to run inside a **bubble** (a rootless Apptainer instance) to provide overlay networking between nested containers across different hosts.

## Architecture
Everything happens inside the **bubble** - the "controller" or "node" container (`hpk-bubble`) running rootless on the host. The bubble uses [slirp4netns](https://github.com/rootless-containers/slirp4netns) for external networking, runs **Flannel** for internal, overlay networking, manages a bridge (`hpk-bridge`) that connects the Flannel interface with the interfaces of nested containers, and configures iptables for NATting traffic from the nested containers to the outside world.

Inside the bubble, **HPKtainer** (the Apptainer wrapper) is used to spawn containers that derive from `hpktainer-base`. These containers use a userspace network stack implemented with a pair of tap interfaces; one in the container and one in the bubble (the interface connected to the `hpk-bridge`). The pair is connected via two instances of the `hpk-net-daemon` - one in the container and one in the bubble - that forward traffic over a UNIX socket created in a shared folder.

## Building

To build the necessary container images (`hpktainer-base` and `hpk-bubble`) for multi-architecture (amd64/arm64) support, run:

```bash
make images
```

This uses `docker buildx` to build and push the images to the configured registry (default: `docker.io/chazapis`). You can override the registry:

```bash
REGISTRY=myregistry.io/user make images
```

*Note for developers: You can also build the binaries locally for testing purposes using `make binaries`. These will be placed in `bin/`.*

## Running

The primary way to run HPKtainer clusters is via the provided Slurm script, which orchestrates the launch of multiple bubbles (one Controller and N-1 Nodes).

To deploy a cluster with N bubbles:

```bash
sbatch --nodes=3 scripts/hpk.slurm
```

This script internally executes `scripts/hpk-bubble.sh` with the appropriate arguments (`1 controller` for the first node, `ID node` for others) on the allocated nodes. It ensures:
1.  The **Controller** bubble starts first, initializing K3s (port 6443) and Etcd (port 2379).
2.  **Node** bubbles join the network, connecting to the Controller's Flannel/Etcd.

## Evaluating locally

You can test the setup locally using the provided Vagrant environment, which simulates a multi-node cluster using VMs.

### 1. Start the Environment
This creates a 2-node cluster (`controller`, `node`) running Ubuntu 24.04 with Slurm pre-installed.

```bash
cd vagrant
vagrant up
vagrant reload # Required to apply security settings (AppArmor disable)
```

The VMs use mDNS for networking and are accessible as `controller.local` and `node.local`.

### 2. Upload Scripts
Upload the project scripts to the controller node. Since the repository structure is needed, upload the entire directory:

```bash
# From the repository root on your host
scp -r -o StrictHostKeyChecking=no . vagrant@controller.local:~/hpktainer
# (Password is 'vagrant')
```

### 3. Run the Cluster
Connect to the controller and submit the Slurm job:

```bash
ssh -o StrictHostKeyChecking=no vagrant@controller.local
# (Password: 'vagrant')

cd hpktainer
# Ensure images are available (or build/pull them if relevant in your env)
sbatch --nodes=2 scripts/hpk.slurm
```

This will launch one controller bubble and one node bubble on the Vagrant VMs.

### 4. Interact with the Bubble
Once running, you can connect to the controller bubble:

```bash
apptainer shell instance://bubble1
```

Inside the bubble, you can run nested containers:

```bash
hpktainer run docker://docker.io/chazapis/hpktainer-base:latest /bin/sh
```

And verify connectivity:
```bash
ip addr show tap0    # Should show Flannel IP
ping 8.8.8.8         # External access
```