#!/bin/bash
#SBATCH --job-name=hpk-cluster
#SBATCH --output=%x-%j.out
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G

# Usage: sbatch hpk.slurm
# The number of nodes allocated (N) determines the cluster size:
# Node 0: Controller Bubble (ID 1)
# Node 1..N-1: Node (Worker) Bubbles (ID 2..N)

NODES=($(scontrol show hostnames $SLURM_JOB_NODELIST))
NUM_NODES=${#NODES[@]}

if [ "$NUM_NODES" -eq 0 ]; then
    echo "This script must be run via sbatch/srun."
    exit 1
fi

CONTROLLER_NODE=${NODES[0]}
CONTROLLER_IP=$(srun --nodes=1 -w $CONTROLLER_NODE hostname -I | awk '{print $1}')

echo "Cluster Setup:"
echo "  Controller Node: $CONTROLLER_NODE ($CONTROLLER_IP)"
echo "  Nodes: ${NODES[@]}"

# Start Controller Bubble
echo "Starting Controller on $CONTROLLER_NODE..."
export HPK_ROLE="controller"
export ETCD_IP=$CONTROLLER_IP 
export PUBLIC_IP=$CONTROLLER_IP 
srun --nodes=1 -w $CONTROLLER_NODE --exclusive ./scripts/hpk-bubble.sh 1 &

# Wait for Controller initialization
echo "Waiting for Controller initialization..."
sleep 15

# Start Node (Worker) Bubbles
BUBBLE_ID=2
for ((i=1; i<NUM_NODES; i++)); do
    NODE=${NODES[$i]}
    echo "Starting Node on $NODE (Bubble ID $BUBBLE_ID)..."
    
    (
        export HPK_ROLE="node"
        export ETCD_IP=$CONTROLLER_IP
        srun --nodes=1 -w $NODE --exclusive ./scripts/hpk-bubble.sh $BUBBLE_ID
    ) &
    
    ((BUBBLE_ID++))
done

# Wait for all background jobs
wait
