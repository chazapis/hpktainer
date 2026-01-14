#!/bin/bash

# Default values if not provided
HOST_IP=${HOST_IP:-$(ip route get 1 | awk '{print $7; exit}')}
ETCD_IP=${ETCD_IP:-$HOST_IP}
PUBLIC_IP=${PUBLIC_IP:-$HOST_IP}

echo "Starting Flannel..."
echo "  Etcd Endpoint: http://${ETCD_IP}:2379"
echo "  Public IP:     ${PUBLIC_IP}"
echo "  Interface:     tap0"

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# Start flanneld in background (daemonize? or just background)
# Logging to /var/log/flannel.log as requested.
flanneld \
  --etcd-endpoints=http://${ETCD_IP}:2379 \
  -ip-masq \
  -iface tap0 \
  --public-ip=${PUBLIC_IP} \
  >> /var/log/flannel.log 2>&1 &

FLANNEL_PID=$!
echo "Flannel started with PID $FLANNEL_PID"

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
