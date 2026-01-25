#!/bin/bash

# Default values if not provided
HOST_IP=${HOST_IP:-$(ip route get 1 | awk '{print $7; exit}')}
ETCD_IP=${ETCD_IP:-$HOST_IP}

echo "Starting Flannel..."
echo "  Etcd Endpoint: http://${ETCD_IP}:2379"
echo "  Public IP:     ${HOST_IP}"
echo "  Interface:     tap0"
echo "  Role:          ${HPK_ROLE}"

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Wait for tap0 interface to appear (created by slirp4netns)
echo "Waiting for tap0 interface..."
while ! ip link show tap0 >/dev/null 2>&1; do
    sleep 0.1
done
# Ensure it is up
ip link set tap0 up

# Add Host IP as secondary address to tap0
# This is required for Flannel VXLAN to use it as a source IP
ip addr add ${HOST_IP}/32 dev tap0

# Start Etcd if Controller
if [ "$HPK_ROLE" = "controller" ]; then
    echo "Starting Etcd..."
    # Config for single node etcd
    etcd --name default \
         --listen-client-urls http://0.0.0.0:2379 \
         --advertise-client-urls http://${HOST_IP}:2379 \
         --listen-peer-urls http://0.0.0.0:2380 \
         --initial-advertise-peer-urls http://${HOST_IP}:2380 \
         --initial-cluster default=http://${HOST_IP}:2380 \
         --initial-cluster-token etcd-cluster-1 \
         --initial-cluster-state new \
         --data-dir /var/lib/etcd \
         >> /var/log/etcd.log 2>&1 &
    
    # Wait for etcd
    sleep 5
    
    # Initialize Flannel config
    echo "Initializing Flannel config in Etcd..."
    etcdctl --endpoints=http://127.0.0.1:2379 put /coreos.com/network/config '{"Network": "10.244.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
fi

# Start flanneld
# Connecting to ETCD_IP (which is host IP of controller, or localhost if controller)
# Simplest: If Controller, use localhost for Flannel. If Node, use ETCD_IP.

FLANNEL_ETCD="http://${ETCD_IP}:2379"
if [ "$HPK_ROLE" = "controller" ]; then
    FLANNEL_ETCD="http://127.0.0.1:2379"
fi

flanneld \
  --etcd-endpoints=$FLANNEL_ETCD \
  -ip-masq \
  -iface tap0 \
  --public-ip=${HOST_IP} \
  >> /var/log/flannel.log 2>&1 &

FLANNEL_PID=$!
echo "Flannel started with PID $FLANNEL_PID"

# Start K3s if Controller
if [ "$HPK_ROLE" = "controller" ]; then
    echo "Starting K3s Server..."
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
      --bind-address $(ip addr show tap0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1) \
      --node-ip=$(ip addr show tap0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1) \
      --advertise-address ${HOST_IP} \
      --tls-san ${HOST_IP} \
      --write-kubeconfig /etc/kubernetes/admin.conf \
      >> /var/log/k3s.log 2>&1 &
fi


# Keep the container running (or maybe run a shell?)
# If this is a bubble, user likely wants a shell or just to keep it alive.
# "The user should first run a bubble, then connect to the container"
# So we probably just sleep infinity or wait.
# But if prompt is needed? entrypoint usually execs CMD.
# Let's exec bash if no args, or exec args.

if [ "$#" -eq 0 ]; then
    # Default to bash
    exec /bin/bash
else
    exec "$@"
fi
