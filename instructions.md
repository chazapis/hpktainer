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