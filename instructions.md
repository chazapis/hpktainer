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
* If it does not exist, hpktainer will create a local bridge (named `hpk-bridge`) and give it the first IP in the subnet. It will also set up iptables to NAT all traffic from the bridge's subnet to the host's default gateway (assuming the subnet is `10.0.0.1/24`, the bridge's IP will be `10.0.0.1`, so the necessary iptables commands are `iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o tap0 -j MASQUERADE`, where `tap0` is the interface handling traffic to the host's default gateway). This also requires that `net.ipv4.ip_forward` is set to `1`.
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