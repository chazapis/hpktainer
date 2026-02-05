# Instructions

## Overview

This is an empty directory.
* This directory will contain the source code and documentation of the hpktainer project.
* This project will be a cli app written in Golang, similar in function to apptainer, with the following differences:
    * It will use apptainer to run containers, passing through all arguments to apptainer except those that refer to network configuration. Apptainer containers will run with `--network none`.
    * It will prepare a custom networking solution for the running containers which is described in detail below.
* This project will also include a Dockerfile for building a base container image that is compatible with hpktainer, which is necessary in order to complete the network configuration within the container.

The custom networking solution is:
* Assuming flannel is running in the host, hpktainer will read the local flannel configuration from `/run/flannel/subnet.env` and extract the subnet information. If the file is not found, hpktainer will exit with an error.
* If it does not exist, hpktainer will create a local bridge (named `hpk-bridge`) and give it the first IP in the subnet. It will also set up iptables to NAT all traffic from the bridge's subnet to the host's default gateway (assuming the subnet is `10.0.0.0/24`, the bridge's IP will be `10.0.0.1`, so the necessary iptables commands are `iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o tap0 -j MASQUERADE`, where `tap0` is the interface handling traffic to the host's default gateway). This also requires that `net.ipv4.ip_forward` is set to `1`.
* Then, hpktainer will use the host-local CNI plugin to get a local IP address for the container to run.
* Next, hpktainer will create a local tap interface in the host, add it to the bridge and run a local daemon/utility (a separate binary in Golang) that copies all traffic from the tap interface to a local UNIX socket (named after the container's unique IP or ID). The host will act as the server side of the UNIX socket.
* Then, hpktainer will create the necessary environment variables for the container (container's unique IP, host bridge IP, UNIX socket path) and run the container with all parameters given by the user (but `--network none`).
* The running container will receive the environment variables and similarly, create a local tap interface, assign to it the container's unique IP, set the host's bridge IP as the default gateway, and run the same local daemon/utility used in the host that copies all traffic from the tap interface to the local UNIX socket. The container will act as the client side of the UNIX socket.
* The UNIX socket will be used to forward all traffic from the container to the host and vice versa, effectively creating a virtual Ethernet pair in the container, one end of which will be attached to the bridge network and the other end will be attached to the host. The daemon/utility that copies all traffic from the tap interface to the local UNIX socket will have to make sure that complete packets (and not fragments) are copied to the UNIX socket.

Tell me if you understand the above description in its entirety. If you have any - even minor question - let me know. Do not write any code yet.

## Done - Clarifications requested

1. Regarding the iptables interface, I mentioned `tap0`, but this can indeed be any interface name. hpktainer should detect the the physical output interface of the host and use it in the iptables command. 
2. hpktainer needs to ensure the container can access the UNIX socket. hpktainer should automatically add the approppriate `--bind` argument to apptainer to expose the socket path. These sockets should be placed in `/var/run/hpktainer` on both the host and the container.
3. hpktainer can invoke the host-local executable binary directly (standard CNI assumption), as invoking the binary is simpler/standard for this description.
4. hpktainer will run as root and have all necessary permissions to perform the tasks it needs to perform. hpktainer should not require root to run; if any command fails as a result of insufficient permissions, the error should be clear and the user should be able to run hpktainer as root to resolve the issue.

## Done - Reviewed plan, generated code, and fixed issues

* Expand the walkthrough (build and run guide) to include some simple commands on how to verify the network setup is working within the container.
* Place the contents in a README.md file at the root of the repository.
* Initialize a git repository locally (add any necessary .gitignore and .dockerignore rules) and commit all changes.

## Done

* Add the Apache 2.0 license to the repository.
* Commit all changes and push the repository to GitHub, at https://github.com/chazapis/hpktainer, using git@github.com:chazapis/hpktainer.git as the remote.

## Done - Had to manually fix some compile time issues

* I fixed .dockerignore, as it prevented copying the repository code into the container. I also updated README.md to remove sudo from every command.
* `hpk-bridge` should also include the flannel interface (typically `flannel0`; has an IP address in the flannel subnet). hpktainer should add the it to the bridge if it is not already a member.
* I ran hpktainer and it gave the bridge a `.2` IP address. I am curious why it did not use the `.1` address. 

## Done

The bridge looks ok now. It fails when trying to get an IP for the container with the following:
```
2026/01/12 17:50:49 Failed to allocate IP: cni add failed: {
    "code": 999,
    "msg": "invalid range set 0: Network has host bits set. For a subnet mask of length 24 the network address is 10.244.20.0"
}: exit status 1
```

## Done

Output from latest run:
```
# ./hpktainer run docker://chazapis/hpktainer-base:20250112 /bin/sh
2026/01/12 20:28:33 Using Subnet: 10.244.20.1/24
2026/01/12 20:28:33 Bridge hpk-bridge ready with IP 10.244.20.1
2026/01/12 20:28:33 Default interface: tap0
2026/01/12 20:28:33 Allocated IP 10.244.20.4/24 for container 9b21e35f-cd05-4c2a-874f-6c08627800ca
2026/01/12 20:28:33 Opened TAP interface: veth-9b21e35f
2026/01/12 20:28:33 Failed to listen on socket /var/run/hpktainer/10.244.20.4/24.sock: listen unix /var/run/hpktainer/10.244.20.4/24.sock: bind: no such file or directory
2026/01/12 20:28:33 Warning: Socket /var/run/hpktainer/10.244.20.4/24.sock not found yet
2026/01/12 20:28:33 Executing apptainer: [run --network none --bind /var/run/hpktainer docker://chazapis/hpktainer-base:20250112 /bin/sh]
INFO:    Using cached SIF image
INFO:    Setting --net (required by --network)
Starting hpk-net-daemon...
2026/01/12 20:28:36 Opened TAP interface: tap0
Configuring network...
Network ready. Executing command: /bin/sh
Apptainer> 2026/01/12 20:28:41 Failed to connect to socket /var/run/hpktainer/10.244.20.4/24.sock: dial unix /var/run/hpktainer/10.244.20.4/24.sock: connect: no such file or directory
```

Issues/questions:
* The logs mention the creation of veth-9b21e35f, but it is not created. I can not see it with `ip a`.
* hpktainer fails to create the UNIX socket for the container.
* The name of the socket should not contain the subnet mask; this is probably the reason the socket is not created, as the name generated is not valid.
* Are IP addresses released back to the pool when the container is stopped?

## Done

New output:
```
# ./hpktainer run docker://chazapis/hpktainer-base:20250112 /bin/sh
2026/01/12 20:41:20 Using Subnet: 10.244.20.1/24
2026/01/12 20:41:20 Bridge hpk-bridge ready with IP 10.244.20.1
2026/01/12 20:41:21 Default interface: tap0
2026/01/12 20:41:21 Allocated IP 10.244.20.2/24 for container 1c35f335-159b-4d4d-818b-3ef5fd186bbd
2026/01/12 20:41:21 Opened TAP interface: veth-1c35f335
2026/01/12 20:41:21 Listening on /var/run/hpktainer/10.244.20.2.sock
2026/01/12 20:41:21 Executing apptainer: [run --network none --bind /var/run/hpktainer docker://chazapis/hpktainer-base:20250112 /bin/sh]
INFO:    Converting OCI blobs to SIF format
WARNING: 'nodev' mount option set on /tmp, it could be a source of failure during build process
INFO:    Starting build...
INFO:    Fetching OCI image...
3.8MiB / 3.8MiB [=======================================================================] 100 % 455.6 KiB/s 0s
1.7MiB / 1.7MiB [=======================================================================] 100 % 455.6 KiB/s 0s
1.2MiB / 1.2MiB [=======================================================================] 100 % 455.6 KiB/s 0s
INFO:    Extracting OCI image...
INFO:    Inserting Apptainer configuration...
INFO:    Creating SIF file...
[===================================================================================================] 100 % 0s
INFO:    Setting --net (required by --network)
Starting hpk-net-daemon...
2026/01/12 20:41:31 Opened TAP interface: tap0
2026/01/12 20:41:31 Connected to /var/run/hpktainer/10.244.20.2.sock
2026/01/12 20:41:31 Accepted connection
2026/01/12 20:41:31 Copy error: write to tap error: write tun: input/output error
2026/01/12 20:41:31 Copy error: read length from socket error: read unix /var/run/hpktainer/10.244.20.2.sock->@: read: connection reset by peer
Timeout waiting for tap0 creation
```

The socket is created, correctly named, and the corresponding file can be found both at the host and the container. However, the tap interface (both at the host and the container) cannot be found. Also, please name the host tap `hpk-tap-<ID>` where ID is the container's IP suffix (`21` for `10.0.0.21`).

## Done

The device naming is ok. The tap interface is not created. I can not even list it.

## Done

I still have similar errors:
```
...
2026/01/13 15:02:10 Opened TAP interface: tap0
2026/01/13 15:02:10 Connected to /var/run/hpktainer/10.244.20.2.sock
2026/01/13 15:02:10 Accepted connection
2026/01/13 15:02:10 Copy error: write to tap error: write tun: input/output error
2026/01/13 15:02:10 Copy error: read length from socket error: read unix /var/run/hpktainer/10.244.20.2.sock->@: read: connection reset by peer
Timeout waiting for tap0 creation
```

I ran the hpk-net-daemon manually in server mode and it created the tap interface, the socket, and started the daemon.

## Done

You suggested that I was using an old version of the container. I rebuilt and pushed the container with the latest binary of hpk-net-daemon and the error is gone.

## Done

Commit all and push to GitHub.

## Done

I now want to take this project a step further. hpktainer is meant to run inside a "master" apptainer container, which I call "bubble".
* The bubble runs rootless at the host (with fakeroot), using slirp4netns to get an IP for its network namespace.
* The bubble runs flannel and exposes UDP port 8472 to the host, for cross-bubble/cross-host traffic. The network fabric managed by flannel functions as an overlay network for inter-bubble communication.
* The bubble includes several tools, including apptainer, hpktainer, and hpk-net-daemon. Apptainer can be used (via hpktainer) within the bubble to start containers that are connected to the bubble's network overlay.

I have already implemented a Dockerfile for the bubble (named `hpk-bubble`) and a script to start it (named `hpk-bubble.sh`), which are provided below:

Dockerfile:
```
FROM ubuntu:24.04

# Basic utilities
RUN apt-get update && \
    apt-get install -y vim-tiny curl iproute2 net-tools bridge-utils iputils-ping

# Apptainer
RUN apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:apptainer/ppa && \
    apt-get install -y apptainer

# CNI plugins
RUN curl -LO https://github.com/containernetworking/plugins/releases/download/v1.9.0/cni-plugins-linux-arm64-v1.9.0.tgz && \
    mkdir -p /opt/cni/bin && \
    (cd /opt/cni/bin && tar -zxvf /cni-plugins-linux-arm64-v1.9.0.tgz) && \
    rm /cni-plugins-linux-arm64-v1.9.0.tgz

# Etcd and Flannel
RUN apt-get install -y etcd-server etcd-client && \
    apt-get install -y iptables nscd && \
    curl -L -o /usr/local/bin/flanneld https://github.com/flannel-io/flannel/releases/download/v0.27.4/flanneld-arm64 && \
    chmod +x /usr/local/bin/flanneld

# TAP traffic forwarder
COPY tap_forward.py /usr/local/bin/tap_forward
```

Script to start the bubble:
```
#!/bin/bash -x

BUBBLE_ID=${1:-1}

NAME=bubble$BUBBLE_ID

CIDR=10.0.$((BUBBLE_ID + 1)).0
CIDR_PREFIX=$(echo "$CIDR" | awk -F. '{print $1"."$2"."$3}')
DNS_ADDR=$CIDR_PREFIX.3
NS_ADDR=$CIDR_PREFIX.100

cleanup() {
	echo "Cleaning up..."
	if [[ -n $SLIRP_PID ]]; then
		kill $SLIRP_PID 2>/dev/null
		wait $SLIRP_PID 2>/dev/null
	fi
	apptainer instance stop $NAME
	[ -e $NAME-slirp4netns.sock ] && rm -f $NAME-slirp4netns.sock
}

trap cleanup INT TERM

# Namespace
[ -f resolv.conf ] || echo "nameserver $DNS_ADDR" > resolv.conf
apptainer instance run \
	--fakeroot \
	--no-mount home \
	--no-mount cwd \
	--no-mount tmp \
	--no-mount hostfs \
	--writable-tmpfs \
	--network=none \
	--bind resolv.conf:/etc/resolv.conf \
	docker://chazapis/hpk-bubble:4 \
	$NAME
PID=$(apptainer instance list -j $NAME | jq -r '.instances[] | .pid')

# Userlevel networking
slirp4netns --configure --cidr=$CIDR/24 --mtu=65520 --api-socket $NAME-slirp4netns.sock $PID tap0 &
SLIRP_PID=$!

while [ ! -e $NAME-slirp4netns.sock ]; do
    sleep 1
done
echo -n '{"execute": "add_hostfwd", "arguments": {"proto": "udp", "host_addr": "0.0.0.0", "host_port": 8472, "guest_addr": "'$NS_ADDR'", "guest_port": 8472}}' | nc -U $NAME-slirp4netns.sock

wait $SLIRP_PID
```

The script requires a network CIDR to be passed as an argument, which is used by slirp4netns to allocate an IP address for the bubble's network namespace. This IP address in that CIDR is then used to assign an IP address to the bubble's network namespace and set up the a NAT-enabled gateway for the bubble at the host. This network has nothing to do with the flannel network, which is auto-negotiated between flannel instances running in the bubbles.

What I want:
* Integrate this code into the repository. Since we now will have two Dockerfiles, you will need to place all files necessary for each container image in some directory (separate for `hpktainer-base` and `hpk-bubble`).
* Create a `Makefile` that will build all components (binaries, containers) and push the container images to the registry (separate commands).
* Extend the `hpk-bubble` container with the necessary `entrypoint.sh` script to start flannel and log its output somewhere at `/var/log`. In the `hpk-bubble.sh` script, you will need the IP address of an etcd instance to pass to flannel, which you can get from an environmental variable (should default to the host's IP address). The script should also use the host's IP address as the public IP of flannel. Assuming the host's IP is `192.168.64.9`, the command should look like this (`tap0` is always the tap interface created by slirp4netns):
```
flanneld --etcd-endpoints=http://192.168.64.9:2379 -ip-masq -iface tap0 --public-ip=192.168.64.9
```
* Make both container images build for arm64 and x86_64.
* Expand the README file to include instructions for building and running the bubble and hpktainer. The user should first run a bubble, then connect to the container and run hpktainer inside the bubble.

Tell me if you understand the above description in its entirety. If you have any - even minor question - let me know. Do not write any code yet.

## Done - Clarifications requested

Regarding the plan:
* Name container image folders `hpktainer-base` and `hpktainer-bubble`. The whole repository will probably be renaimed to `hpk-bubble` or something else, so use the full name for each component.
* In `hpk-bubble.sh`, name environment variables `HOST_IP` and `PUBLIC_IP` (avoid using the `APPTAINERENV_` prefix you suggested).

Regarding clarifications requested:
* Indeed, the `hpk-bubble` Dockerfile provided references some `tap_forward.py` file. This was an old version of the `hpk-net-daemon` binary. Place the `hpk-net-daemon` binary in `/usr/bin` instead.
* Indeed, the `hpk-bubble` Dockerfile provided installs etcd server and client. This is not necessary. Remove them.
* The registry prefix to be used in the Makefile should be variable, with a default name of `docker.io/chazapis`.

## Done - Reviewed plan and generated code

I am looking at the generated code and have some comments:
* Please avoid using too verbose comments. Add comments (no objection to that), just be brief and to the point. Don't explain all the thought process, unless the code implements something non-trivial that needs justification.
* The `hpktainer-base` Dockerfile will probably work for multiple architectures, as it uses a builder stage. The `hpk-bubble` Dockerfile will need to be updated to handle multiple architectures. It currently uses `arm64` as the default architecture and downloads `arm64` binaries for the CNI tools and flannel.

Also, I updated .gitignore to exclude bin/, instead of hpktainer and hpk-net-daemon.

## Done

I also need to tag applied to container images in the Makefile to default to the current date in YYYYMMDD format, instead of "latest".

## Done

* In the Makefile, after pushing the images, add a command to tag the images with `latest` and push them again, so the scripts work with the latest tag.
* You need to make `hpk-bubble.sh` executable.
* Add in the README the command necessary to connect to the bubble once it is running (I use `apptainer shell instance://bubble1` when running with `./hpk-bubble.sh 1`).

## Done

I successfully started a bubble and connected to it. I need to run hpktainer inside the bubble, but it is missing from the `hpktainer-bubble` container image. I also want you to rename the `hpktainer-bubble` container image to `hpk-bubble`.

## Done

I successfully started a bubble, connected to it, and ran a container via hpktainer inside the bubble. Networking is not working, as the bubble is not configured with `sysctl net.ipv4.ip_forward=1`. This can be done in the bubble's entrypoint script.

## Done

Commit all and push to GitHub.

## Done

I updated the README file. Commit and push.

## Done

Let's move one more step towards the final goal. Multiple bubbles are meant to run concurrently on an HPC cluster and host an internal Kubernetes environment.
* Add K3s to each bubble. K3s should be started in the bubble's entrypoint script and its logs should go to `/var/log/k3s.log`.
* One of the bubbles will be the master node. The others will be worker nodes.
* Flannel should be reconfigured to use the Kubernetes API as the backend (running at the IP of the master bubble), instead of etcd.

K3s (both master and workers) should run without the kubelet, as this requires root privileges and we don't want to run it as root in the bubble. I have another solution for the kubelet, but let's do this first.

I have sucessfully ran K3s like this with:
```
k3s server \
  --disable-agent \
  --disable scheduler \
  --disable coredns \
  --disable servicelb \
  --disable traefik \
  --disable local-storage \
  --disable metrics-server \
  --disable-cloud-controller \
  --write-kubeconfig-mode 777 \
  --bind-address $IP_ADDRESS \
  --node-ip=$IP_ADDRESS \
  --write-kubeconfig /etc/kubernetes/admin.conf
```

In the Dockerfile, I used (this refers to a slightly older version, which I would like updated):
```
ARG TARGETARCH

# K3s
ARG K3S_VERSION=v1.29.1+k3s1

RUN set -eux; \
    if [ "${TARGETARCH}" = "amd64" ]; then \
        K3S_ARCH=""; \
    else \
        K3S_ARCH="-${TARGETARCH}"; \
    fi; \
    curl -sfL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s${K3S_ARCH}" -o /usr/local/bin/k3s && \
    chmod +x /usr/local/bin/k3s

RUN mkdir -p /var/lib/rancher/k3s /etc/rancher/k3s
```

Tell me if you understand the above description in its entirety. If you have any - even minor question - let me know. Do not write any code yet.

## Done - Clarifications requested

1. I can't provide the exact K3s command for the worker bubbles, as it depends on the IP address of the master bubble. Note that it may be necessary to start the workers after the master has completed its initialization. In the setup, there will always be one master bubble (no HA mode) and zero or more worker bubbles. Master and workers should use the same container image and differentiate using environment variables.
2. Correct, setting up flannel with a Kubernetes API backend requires the Kubernetes API to be operational and accessible using a `kubeconfig` file with the appropriate credentials. Ok. Let's do this later. For now keep the flannel setup as it is (with an etcd backend) and install/deploy etcd server at the master bubble. The etcd server should be started in the bubble's entrypoint script and its logs should go to `/var/log/etcd.log`.
3. Yes, the bubble running the master should have port 6443 (Kubernetes API) exposed to the host, similar to how we expose UDP port 8472 for flannel now.
4. Update K3s to a recent version. Use the latest one if possible.

To deploy the setup the user will run the `hpk.slurm` slurm script, passing it the desired number of bubbles (minimum 1). `hpk.slurm` will then use `hpk-bubble.sh` to start individual bubbles, taking care of ordering (master first, then workers) and naming (as each bubble needs a separate $BUBBLE_ID).

## Done

* Use versions v1.35.0+k3s1 for K3s and v0.28.0 for flannel. Make the versions a variable in the Dockerfile for easy updating (as it currently is for K3s).
* The default role for `hpk-bubble.sh` should be `master`; needed if someone wants to run then script directly (e.g. for debugging).
* Be less verbose in your comments in `hpk.slurm`.

## Done

K3s v1.35.0+k3s1 was recently released. I set it in the Dockerfile manually. I also edited the Makefile, as `make images` is not necessary to create binaries as well.

## Done

I need to be able to test this setup. I use a macOS computer with Apple Silicon and UTM. I have installed Vagrant with the UTM plugin.

I want the Vagrantfile (and any other files) to:
* Start a two node cluster with Ubuntu 24.04 LTS, installed with Slurm.
* The first node should run the Slurm controller and worker, while the second node should run another Slurm worker.
* The fist node should expose `/home` via NFS. The second node should mount it at `/home`.
* Make sure that both nodes have all security features disabled (firewall, SELinux, AppArmor, etc.).

Then I need the instructions to upload the scripts to the nodes and run them.

Tell me if you understand the above description in its entirety. If you have any - even minor question - let me know. Do not write any code yet.

## Done - Clarifications requested

I have no prefered Vagrant box to use. A generic one should be ok.

Proceed with the implementation.

## Done

I ran `vagrant up` and it created the two nodes. However, I have issues connecting to them via `vagrant ssh`. The connection takes several minutes to complete.

I have noticed that the VMs have different IP addresses. The master has `192.168.64.11` and the node has `192.168.64.12`.

There are some errors in the provisioning logs, which I paste below:
```
    ...
    master: cat: /etc/vagrant_role: No such file or directory
    ...
    master: Setting up NFS Client...
    master: Created symlink /run/systemd/system/remote-fs.target.wants/rpc-statd.service → /usr/lib/systemd/system/rpc-statd.service.
    master: mount.nfs: Connection refused for 192.168.56.11:/home on /home
    master: Setting up Munge...
    master: Setting up Slurm...
    master: Synchronizing state of slurmd.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
    master: Executing: /usr/lib/systemd/systemd-sysv-install enable slurmd
    master: Job for slurmd.service failed because the control process exited with error code.
    master: See "systemctl status slurmd.service" and "journalctl -xeu slurmd.service" for details.
    ...
    node1: cat: /etc/vagrant_role: No such file or directory
    ...
    node1: Setting up NFS Client...
    node1: Created symlink /run/systemd/system/remote-fs.target.wants/rpc-statd.service → /usr/lib/systemd/system/rpc-statd.service.
    node1: mount.nfs: Connection refused for 192.168.56.11:/home on /home
    node1: Setting up Munge...
    node1: Setting up Slurm...
    node1: Synchronizing state of slurmd.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
    node1: Executing: /usr/lib/systemd/systemd-sysv-install enable slurmd
    node1: Provisioning complete.
    node1: Job for slurmd.service failed because the control process exited with error code.
    node1: See "systemctl status slurmd.service" and "journalctl -xeu slurmd.service" for details.
    ...
```

When inside the master, Slurm does not work:
```
$ sinfo
sinfo: error: _parse_next_key: Parsing error at unrecognized key: MungeSocketPath
sinfo: fatal: Unable to process configuration file
```

Neither does NFS, as both nodes have been setup as clients, which is logical, as the `install.sh` script reports that it can not find `/etc/vagrant_role`.

## Done

The nodes are provisioned correctly now and ssh works. I can connect to the master and the node. However, the node has been assigned a new, unexpected IP address (`192.168.64.13`). It seems that these addresses are assigned by UTM? Can they be fixed somehow, so the provisioning script can work predictably (ideally across different environments of different developers)?

## Done

Things work better now that you use mDNS and `.local` hostnames. NFS looks ok. Slurm shows both nodes, but I cannot run commands. Output:
```
$ sinfo
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
debug*       up   infinite      1  idle* master
debug*       up   infinite      1   idle node1
$ srun hostname
srun: error: Task launch for StepId=1.0 failed on node node1: Header lengths are longer than data received
srun: error: Application launch failed: Header lengths are longer than data received
srun: Job step aborted
```

Also, yes, update the README with the new instructions for using `master.local` to connect.

## Done

Syncing clocks with chrony did not fix it. Still the same error.

Also, remove the comments from the files in the `vagrant` directory mentioning the IP addresses. They are not needed anymore.

## Done

I rejected the change to fix the uids/gids of Slurm and munge in the `install.sh` script, as it is not needed. Ubuntu packages use specific uids/gids for Slurm and munge, and I have verified that they are the same on both nodes.

I would start by removing the `127.0.2.1` entries from the `/etc/hosts` file on both nodes, as they are not needed. In the master node it points to `master` and in node1 it points to `node1`. There is also an `127.0.1.1` entry in both nodes, pointing to `vagrant`.

Then, set `SlurmUser` to `slurm` in the `/etc/slurm/slurm.conf` file on both nodes, as this is expected by the Slurm packages.

Furthermore, apparmor is not disabled. It seems the only way to completely disable it is add `apparmor=0` to `GRUB_CMDLINE_LINUX_DEFAULT` or `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, run `update-grub`, and reboot.

## Done

Maybe because I rejected some of the updates in `install.sh`, you could not apply the changes. Please try again now.

## Done

When I run `vagrant reload`, the node reboots, but Vagrant cannot connect to it. It loops with the message:
```
    node1: Warning: Authentication failure. Retrying...
```

If I run `vagrant ssh node1` it connects (although asks for a password, which is weird).

Also, rename `master` to `controller` and `node1` to `node`.

## Done

Update the README with the new vagrant instructions (including `vagrant reload`).

Also, rename `master` to `controller` and `worker` to `node` for all the other files (for bubbles).

## Done

Update the README as follows:
* I want three sections "Building", "Running", and "Evaluating locally".
* "Building" should contain the instructions for building the images. This should be the Makefile default anyway. There is no real need to build the binaries outside the bubble (unless you are a developer and want to try out things).
* "Running" should contain the instructions for running the bubble through the Slurm script. There is no need to run the `hpk-bubble.sh` script directly. Add a note that this internally runs the `hpk-bubble.sh` script with the appropriate arguments.
* "Evaluating locally" should contain the instructions for setting up a cluster locally using Vagrant. This should mention the Vagrant stuff, how to upload the `scripts` directory to the controller, and how to connect to the controller and run the Slurm script.

## Done

Nice! Commit and push the changes (note I have manually commited and pushed just before starting with the Vagrant stuff).

## Done

I don't need the `build-essentials` package within the Vagrant containers, but I need `apptainer` and `slirp4netns`. Apptainer is available in the default repository, so you need to add the PPA and install it (`ppa:apptainer/ppa`).

## Done

Remove any resource constraints from the `hpk.slurm` batch script. This should run one per node, regardless of the available CPU cores and memory on each node.

Inside the bubbles, flannel probably needs some etcd initialization. The error I see is:
```
E0124 15:43:16.016622      24 main.go:519] Couldn't fetch network config: flannel config not found in etcd store. Did you create your config using etcdv3 API?
```

## Done

Setting the initial value in etcd, requires a `put` instead of a `set`:
```
Apptainer>     etcdctl --endpoints=http://127.0.0.1:2379 set /coreos.com/network/config '{"Network": "10.244.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
Error: unknown command "set" for "etcdctl"
```

Also, I suppose we need to enable `br_netfilter` in the VMs somehow, as flannel logs:
```E0124 15:48:01.877147      17 main.go:278] Failed to check br_netfilter: stat /proc/sys/net/bridge/bridge-nf-call-iptables: no such file or directory
```

## Done

Commit and push the changes.

## Done

Following the instructions in the README, I successfully started the VMs, copied the code in, and ran the Slurm script. This created one bubble on each node. I connected to the bubbles and everything is running inside them, but I don't seem to have network/Internet connectivity in the node (everything is ok in the controller).

## Done

There is an issue. I'm starting 2 bubbles, and this shows up in the log:
```
+ apptainer instance run --fakeroot --no-mount home --no-mount cwd --no-mount tmp --no-mount hostfs --writable-tmpfs --network=none --bind resolv.conf.bubble1:/etc/resolv.conf --env HOST_IP=192.168.64.11 --env ETCD_IP=192.168.64.11 --env PUBLIC_IP=192.168.64.11 docker://docker.io/chazapis/hpk-bubble:latest bubble1
+ apptainer instance run --fakeroot --no-mount home --no-mount cwd --no-mount tmp --no-mount hostfs --writable-tmpfs --network=none --bind resolv.conf.bubble2:/etc/resolv.conf --env HOST_IP=192.168.64.23 --env ETCD_IP=192.168.64.11 --env PUBLIC_IP=192.168.64.11 docker://docker.io/chazapis/hpk-bubble:latest bubble2
```

Both have the same value for `PUBLIC_IP` set to `192.168.64.11`. I think this variable is not even necessary. In `hpk.slurm`, `hpk-bubble.sh`, and the `entrypoint.sh` of the `hpk-bubble` image, it should be merged with `HOST_IP`.

## Done

Now I see this:
```
+ apptainer instance run --fakeroot --no-mount home --no-mount cwd --no-mount tmp --no-mount hostfs --writable-tmpfs --network=none --bind resolv.conf.bubble1:/etc/resolv.conf --env HOST_IP=10.0.2.15 --env ETCD_IP=192.168.64.11 docker://docker.io/chazapis/hpk-bubble:latest bubble1
```

The problem lies in the fact that the VMs have two interfaces, both with a default gateway. Route list from the `controller` VM:
```
$ ip route
default via 10.0.2.2 dev eth1 proto dhcp src 10.0.2.15 metric 100 
default via 192.168.64.1 dev eth0 proto dhcp src 192.168.64.11 metric 100 
10.0.2.0/24 dev eth1 proto kernel scope link src 10.0.2.15 metric 100 
10.0.2.2 dev eth1 proto dhcp scope link src 10.0.2.15 metric 100 
10.0.2.3 dev eth1 proto dhcp scope link src 10.0.2.15 metric 100 
192.168.64.0/24 dev eth0 proto kernel scope link src 192.168.64.11 metric 100 
192.168.64.1 dev eth0 proto dhcp scope link src 192.168.64.11 metric 100 
```

Can we disable the `10.0.2.15` interface on setup? Or just remove the default route?

I understand that `hpk.slurm` sets the `ETCD_IP` from `hostname -I | awk '{print $1}'`, while `hpk-bubble.sh` sets the `HOST_IP` from `ip route get 1 | awk '{print $7; exit}'`. Choose one way to set the IP (the latter is more accurate) and update the code accordingly.

## Done

I accepted the changes. In `install.sh` you remove the default route for the `10.0.2.15` interface, but this is not permanent across reboots.

## Done

Looks like DNS broke. I rebuilt the VMs and:
```
vagrant@node:~$ ping controller.local
ping: controller.local: Name or service not known
vagrant@node:~$ ping node.local
PING node.local (10.0.2.15) 56(84) bytes of data.
^C64 bytes from 10.0.2.15: icmp_seq=1 ttl=64 time=0.027 ms

--- node.local ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
```
## Done

Tested the whole thing, and it works within a node. For some reason, traffic across nodes does not work. I will debug this later, but I am listening to any suggestions.

Commit and push all changes.

## Done

The cross-node issue is caused by the fact that flannel's VXLAN interface was configured to use local 192.168.64.11 (the VM host IP) as the source for VXLAN packets, but that IP didn't exist on any interface inside the Apptainer container. The kernel couldn't send packets with a non-existent source IP, so VXLAN encapsulation silently failed. The solution is to add the public IP as a secondary address on tap0:
```
ip addr add 192.168.64.11/32 dev tap0  # example
```

Also, after `vagrant reload`, the node shows up in Slurm as down. We need to `scontrol update nodename=node state=resume` after a while, unless there is  a way to tell Slurm to automatically resume nodes.

## Done

Setting the second IP on the tap interface is not working. Logs state:
```
Cannot find device "tap0"
```

## Done

Commit and push all changes (including `instructions.md`).

## Done

I want you to download the `staging` directory of the [HPK project](https://github.com/CARV-ICS-FORTH/HPK) into an `hpk` folder and analyze its contents. In there, you should find code, documentation, and tests for a Kubernetes kubelet (based on the Virtual Kubelet project) that aims to provide Kubernetes integration with Slurm.

The project folder contains two binaries written in Go, `hpk` and `pause`, compiled via a Makefile to `hpk-kubelet` and `hpk-pause` respectively:
* `hpk-kubelet` is meant to run as the kubelet alongside K3s (with the internal kubelet disabled) on one node. The user communicates via `kubectl` to K3s's API server, which forwards pod lifecycle events to `hpk-kubelet`. `hpk-kubelet` then interacts with Slurm to allocate resources and starts apptainer (or singularity) containers in the Slurm cluster.
* Each Kubernetes pod is implemented in HPK with nested containers, where the parent container is a "pause" container running the `hpk-pause` agent, and the child containers are the actual containers of the pod.

What I want you to do:
* Analyze the code and the documentation to understand how HPK works.
* Copy over the code for the `hpk-kubelet` and `hpk-pause` binaries in the `hpktainer` project (I would suggest putting `cmd/hpk` into `cmd/hpk-kubelet` and `cmd/pause` into `cmd/hpk-pause`).
* Integrate `hpk-kubelet` into the `hpk-bubble` image and use it as the kubelet for the K3s instance that runs in the `hpk-bubble`.
* Create a new `hpk-pause` image based on the `hpktainer-base` image, as it will be used by HPK's kubelet.
* If needed, modify HPK's code to use apptainer instead of singularity.
* Rename the whole project to HPK (hpktainer is just the name of one component ).

This will be HPK 2.0 that differs in one fundamental way from the HPK 1.x version you will download: HPK 1.x used one K3s instance and one kubelet that was responsible for the pod lifecycle across the whole Slurm installation. HPK 2.0 will use a more "typical" deployment scheme, where each Slurm node runs a bubble containing one K3s instance and one kubelet.

Tell me if you understand the above description in its entirety. If you have any - even minor question - let me know. You can download the code to analyze it, but do not do any actions or write any new code yet.

## Done - Analyzed code, created an implementation plan

Hold on. The repository downloaded is not at the `staging` branch. Please checkout `staging` and re-analyze the code.

Also, you mention that "`hpk-pause` is an active agent (written in Go) that runs inside the job. It queries the K8s API, sets up DNS, and spawns Apptainer containers." Correct. Note that it implements the top-level pod functionality. The containers it spawns are the pod-internal containers. `hpk-pause` cannot be integrated into `hpktainer`. It should run with `hpktainer` as an implementation derived from `hpktainer-base`. The idea is: `hpk.slurm` runs `hpk-bubble.sh` on each node. This creates bubbles (1st level environments) where K3s runs. `hpk-kubelet` runs inside each bubble and manages the lifecycle of the pods. Each pod (2nd level environment) is spawned with `hpktainer`. `hpk-pause` runs inside each pod and manages the lifecycle of the containers in the pod (3rd level environment).

## Done - Analyzed code, updated the implementation plan

You got the conceptual part of it correct. I have some comments regarding the implementation plan:
* `hpk-kubelet` has a flag to avoid `sbatch` and run apptainer directly. Use that instead of refactoring. Use `hpktainer` instead of `apptainer` when the flag is active. If this is not possible (i.e., same code running containers in both cases) let me know, so we can figure out some other solution.
* `hpk-kubelet` should not start from `hpk-bubble.sh`, but inside the `hpk-bubble` container by its `entrypoint.sh`. Make sure to keep logs in `/var/log/hpk-kubelet.log` like other daemons.

One more thing I forgot to mention is that the HPK 1.x integration also includes a custom simple scheduler and a webhook that monitors Kubernetes service objects. These are not needed for HPK 2.0, so you can ignore them.

## Done - Updated the implementation plan

One comment on the implementation plan: You mention "create hpk-pause image derived from hpktainer-base (...), ensure hpktainer-base has apptainer installed." This is not necessary. The `hpk-pause` image that will be derived from `hpktainer-base` will have apptainer installed, but `hpktainer-base` does not need to have apptainer installed. It will just be a minimal container showcasing the bubble-based networking integration.

## Done

* In the Makefile, add the new binaries to the `binaries` target and remove the `binaries` target from the `all` target.
* Remove the `temp_hpk_repo` directory and `hpk` if not necessary.
* Rename this project to "HPK" in the README and other places. Rename the `hpktainer` package to `hpk` in the `go.mod` file and update all imports accordingly.
* Update the "architecture" section of the README with the new overall design (as you described it-with 4 stages-in the latest implementation plan).

## Stopped

Don't just change all strings in all `.go` files from `hpktainer` to `hpk`. `hpktainer` is still a binary that will be used by `hpk-kubelet` to spawn containers. So it should keep its name. The only thing that should change is the package name and the imports. Perhaps it is safer to rename `hpktainer/` strings to `hpk/`.

## Done

I updated the README manually.

Commit and push all changes (including `instructions.md`) to a new branch called `hpk2`.

## Done

`hpk-kubelet` fails to build:
```
GOOS=linux GOARCH=amd64 go build -o bin/linux/amd64/hpk-kubelet ./cmd/hpk-kubelet
cmd/hpk-kubelet/main.go:27:2: no required module provides package github.com/pkg/errors; to add it:
	go get github.com/pkg/errors
cmd/hpk-kubelet/main.go:28:2: no required module provides package github.com/sirupsen/logrus; to add it:
	go get github.com/sirupsen/logrus
cmd/hpk-kubelet/main.go:29:2: no required module provides package github.com/spf13/cobra; to add it:
	go get github.com/spf13/cobra
...
```

## Done

It still fails.

## Done

Still fails.

Looking at the errors, there are still imports in the code for `hpk/compute` and `hpk/provider`. These should change to `hpk/pkg/compute` and `hpk/pkg/provider` respectively.

Also, these two folders were not under `pkg` in the original repository. They were at the top level. Perhaps they should go under `internal` instead of `pkg`?

## Done

I fixed compilation by running `go get hpk/cmd/hpk-kubelet` and `go get hpk/cmd/hpk-pause`. This added a lot of dependencies to `go.mod` and `go.sum`. There was also some non-working import in one of the files that needed updating.

Now move `compute` and `provider` folders from `pkg` to `internal` and update all imports accordingly.

Do not automatically commit and push. I will tell you when to do that.

## Done - Switched model from Gemini 3 Pro (High) to Claude Sonnet 4.5

The `hpk-pause` image failed to build. Log:
```
...
 => WARN: InvalidDefaultArgInFrom: Default value for ARG ${BASE_IMAGE} results in empty or invalid bas  0.0s
 => WARN: UndefinedArgInFrom: FROM argument 'BASE_IMAGE' is not declared (line 11)                      0.0s

 2 warnings found (use docker --debug to expand):
 - InvalidDefaultArgInFrom: Default value for ARG ${BASE_IMAGE} results in empty or invalid base image name (line 11)
 - UndefinedArgInFrom: FROM argument 'BASE_IMAGE' is not declared (line 11)
Dockerfile:11
--------------------
   9 |     # Final stage
  10 |     ARG BASE_IMAGE=docker.io/chazapis/hpktainer-base:latest
  11 | >>> FROM ${BASE_IMAGE}
  12 |     
  13 |     # Install Apptainer (required for hpk-pause agent to spawn containers)
--------------------
ERROR: failed to solve: base name (${BASE_IMAGE}) should not be blank
```

## Done

Also, for the `hpk-pause` image, the BASE_IMAGE argument should come from the Makefile, so in case the user sets a different REGISTRY, it will pass through.

## Done

I fixed it by pushing the `ARG` with `FROM` at the very beginning of the Dockerfile. Re-declaring `ARG` after `FROM` was not necessary.

The image build now fails because `hpk-pause` extends `hpktainer-base`, the former being built on Ubuntu, the latter on Alpine. I want you to switch all container images to Ubuntu, so we are consistent and binaries are built on the same base image.

## Done

You build all images using `golang:1.23`, but this is based on another Debian instead of Ubuntu and it uses an older version of Go.

Create a new image called `hpk-builder` based on `ubuntu:24.04` and use it to build all images. You need the following commands to install Go 1.25 (which is the version mentioned in `go.mod` and the one I have installed locally):
```
apt-get install -y software-properties-common
add-apt-repository ppa:longsleep/golang-backports
apt-get update
apt-get install golang-1.25
```

And you need to set these variables in `.bashrc`:
```
export GOROOT=/usr/lib/go-1.25
export GOPATH=$HOME/.go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
```

Add a separate step in the Makefile, called `builder`, that builds and uploads the `hpk-builder` image. Add `builder` as a dependency to the `all` target, before `images`.

Change the README to suggest using just `make` instead of `make images` to build the project.

## Done

Instead of using `BASE_IMAGE` and `BUILDER_IMAGE` in the Dockerfiles, use `REGISTRY`, which is consistent with the Makefile variable. Also, use only one `ARG` for the registry, not two, at the top of the file, before any `FROM` commands, or else it doesn't work.

## Done

Commit and push all changes.