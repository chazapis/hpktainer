# HPK

HPK allows HPC users to run their own private Kubernetes "mini Cloud" on a typical HPC cluster and then issue commands to it using Kubernetes-native tools.

To deploy, simply run:

```bash
sbatch --nodes=3 scripts/hpk.slurm
```

Then configure and use `kubectl`:

```bash
export KUBECONFIG=${HOME}/.hpk/kubernetes/admin.conf
kubectl get nodes
```

## Implementation

### Overview

Users run a Slurm command to deploy one rootless container per cluster node, which we call **bubble** (using the `hpk-bubble` image). One bubble acts as the Kubernetes control plane, while the others act as worker nodes; together they form the Kubernetes cluster. Each bubble runs an instance of [K3s](https://k3s.io/), alongside the HPK-specific kubelet (`hpk-kubelet`), implemented using the [Virtual Kubelet](https://github.com/virtual-kubelet/virtual-kubelet) framework.

For external networking, bubbles use [slirp4netns](https://github.com/rootless-containers/slirp4netns), while for internal, overlay networking they run [Flannel](https://github.com/flannel-io/flannel) and communicate over VXLAN tunnels (each host forwards UDP port 8472 to the bubble).

Inside the bubble, an [Apptainer](https://apptainer.org/) wrapper (`hpktainer`) is used to spawn "pods" (using the `hpk-pause` image, derived from `hpktainer-base`); these are containers that are given  unique network addresses in the corresponding Flannel subnet and host user application containers.

All pod containers are placed in a bridge (`hpk-bridge`) at the bubble level to talk to each other directly. With the proper routing rules, they can route traffic to pods running in other bubbles (via the Flannel interface) and the outside world.

The pod network stack is again implemented in userspace using a pair of TAP interfaces; one in the nested container and one in the bubble (the interface connected to the `hpk-bridge`). The pair is connected via two instances of the `hpk-net-daemon` that forward traffic over a UNIX socket created in a shared folder.

### Architecture

HPK implements a **4-level distributed architecture**.

1. **Level 1: Host Node (Slurm Worker)**
    * The physical node managed by Slurm.
    * Executes `hpk.slurm`, which launches the bubble.

2. **Level 2: Bubble (Node Overlay)**
    * Implemented in the `hpk-bubble` container.
    * An Apptainer instance acting as a virtual node.
    * Runs K3s (the base Kubernetes distribution) and Flannel (overlay networking). The first bubble, which acts as the Kubernetes control plane, also runs [etcd](https://etcd.io/) for supporting Flannel.
    * Runs the local `hpk-kubelet`, which registers itself as a node in the K3s cluster.
    * Connects to other bubbles via a VXLAN overlay network (Flannel).

3. **Level 3: Pod**
    * Implemented in the `hpk-pause` container.
    * Spawned by `hpk-kubelet` via `hpktainer`.
    * Each Pod is an Apptainer container with its own network namespace connected to the Bubble's bridge (`hpk-bridge`).
    * The Pod's entrypoint is the `hpk-pause` binary, which acts as a "pause container" to hold the network namespace and capture application container signals.

4. **Level 4: Application Container**
    * User application containers spawned by `hpk-pause`.
    * These run within the **same network namespace** as the Level 3 Pod.
    * They share the Pod's IP address and can communicate over `localhost`.

## Building

All binaries are built and embedded in container images. The deployment script uses these images.

To build, run:

```bash
make
```

This uses `docker buildx` to build and push the images with multi-architecture support (amd64/arm64) to the configured registry (default: `docker.io/chazapis`). You can override the registry:

```bash
REGISTRY=myregistry.io/user make
```

*Note for developers: You can also build the binaries locally for testing purposes using `make binaries`. These will be placed in `bin/`.*

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
scp -r -o StrictHostKeyChecking=no scripts vagrant@controller.local:~/scripts # (password is 'vagrant')
```

### 3. Run the Cluster
Connect to the controller and submit the Slurm job:

```bash
ssh -o StrictHostKeyChecking=no vagrant@controller.local # (password is 'vagrant')

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