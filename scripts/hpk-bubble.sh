#!/bin/bash -x

BUBBLE_ID=${1:-1}

NAME=bubble$BUBBLE_ID

CIDR=10.0.$((BUBBLE_ID + 1)).0
CIDR_PREFIX=$(echo "$CIDR" | awk -F. '{print $1"."$2"."$3}')
DNS_ADDR=$CIDR_PREFIX.3
NS_ADDR=$CIDR_PREFIX.100

# Detect Host IP (first non-loopback)
HOST_IP_DETECTED=$(ip route get 1 | awk '{print $7; exit}')
# Use provided ETCD_IP or default to detected host IP
ETCD_IP=${ETCD_IP:-$HOST_IP_DETECTED}
PUBLIC_IP=${PUBLIC_IP:-$HOST_IP_DETECTED}

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

echo "Starting Bubble $NAME..."
echo "  CIDR: $CIDR"
echo "  Host IP: $HOST_IP_DETECTED"
echo "  Etcd IP: $ETCD_IP"

# Pass IPs as env variables
apptainer instance run \
	--fakeroot \
	--no-mount home \
	--no-mount cwd \
	--no-mount tmp \
	--no-mount hostfs \
	--writable-tmpfs \
	--network=none \
	--bind resolv.conf:/etc/resolv.conf \
	--env HOST_IP=$HOST_IP_DETECTED \
	--env ETCD_IP=$ETCD_IP \
	--env PUBLIC_IP=$PUBLIC_IP \
	docker://docker.io/chazapis/hpk-bubble:latest \
	$NAME
PID=$(apptainer instance list -j $NAME | jq -r '.instances[] | .pid')

# Userlevel networking
slirp4netns --configure --cidr=$CIDR/24 --mtu=65520 --api-socket $NAME-slirp4netns.sock $PID tap0 &
SLIRP_PID=$!

# Forward ports based on Role
# 8472: Flannel VXLAN (UDP) - All
# 6443: K3s API (TCP) - Controller
# 2379: Etcd (TCP) - Controller

# Construct JSON for hostfwd
# Always forward 8472 UDP
FWD_JSON='{"execute": "add_hostfwd", "arguments": {"proto": "udp", "host_addr": "0.0.0.0", "host_port": 8472, "guest_addr": "'$NS_ADDR'", "guest_port": 8472}}'

HPK_ROLE=${HPK_ROLE:-controller}

if [ "$HPK_ROLE" = "controller" ]; then
    # Add K3s 6443
    FWD_JSON_K3S='{"execute": "add_hostfwd", "arguments": {"proto": "tcp", "host_addr": "0.0.0.0", "host_port": 6443, "guest_addr": "'$NS_ADDR'", "guest_port": 6443}}'
    
    # Add Etcd 2379
    FWD_JSON_ETCD='{"execute": "add_hostfwd", "arguments": {"proto": "tcp", "host_addr": "0.0.0.0", "host_port": 2379, "guest_addr": "'$NS_ADDR'", "guest_port": 2379}}'
fi

while [ ! -e $NAME-slirp4netns.sock ]; do
    sleep 1
done

echo -n "$FWD_JSON" | nc -U $NAME-slirp4netns.sock
if [ "$HPK_ROLE" = "controller" ]; then
    sleep 0.1
    echo -n "$FWD_JSON_K3S" | nc -U $NAME-slirp4netns.sock
    sleep 0.1
    echo -n "$FWD_JSON_ETCD" | nc -U $NAME-slirp4netns.sock
fi

echo "Bubble started. Press Ctrl+C to stop."
wait $SLIRP_PID
