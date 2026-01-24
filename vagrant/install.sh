#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

ROLE=$(cat /etc/vagrant_role)
echo "Provisioning as $ROLE..."

# 1. Disable Security
echo "Disabling security features..."
systemctl stop ufw
systemctl disable ufw
# AppArmor
systemctl stop apparmor
systemctl disable apparmor
# SELinux is not installed by default on Ubuntu, but just in case
if command -v setenforce &> /dev/null; then
    setenforce 0
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
fi

# Fix /etc/hosts (Remove 127.0.x.x entries that confuse Slurm)
sed -i '/127.0.1.1/d' /etc/hosts
sed -i '/127.0.2.1/d' /etc/hosts

# Disable AppArmor (Kernel parameter required)
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="apparmor=0 /' /etc/default/grub
update-grub

# 2. Update System & Install Basics
# Fix slow SSH
echo "UseDNS no" >> /etc/ssh/sshd_config
# Fix slow apt (ipv6)
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
systemctl restart ssh

apt-get update
apt-get install -y build-essential git slurm-wlm munge nfs-common avahi-daemon libnss-mdns

# Enable mDNS
systemctl enable avahi-daemon
systemctl start avahi-daemon

# Time Sync (Crucial for Munge)
echo "Setting up Time Sync..."
apt-get install -y chrony
systemctl restart chrony

# 3. NFS Setup
if [ "$ROLE" == "controller" ]; then
    echo "Setting up NFS Server..."
    apt-get install -y nfs-kernel-server
    mkdir -p /home
    echo "/home *(rw,sync,no_root_squash,no_subtree_check)" >> /etc/exports
    exportfs -a
    systemctl restart nfs-kernel-server
else
    echo "Setting up NFS Client..."
    echo "Waiting for controller.local..."
    until ping -c1 controller.local &>/dev/null; do :; done
    mount controller.local:/home /home
    echo "controller.local:/home /home nfs defaults 0 0" >> /etc/fstab
fi

# 4. Munge Setup (Shared Key)
echo "Setting up Munge..."
echo -n "hpktainer-test-munge-key-12345678" > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# 5. Slurm Setup
echo "Setting up Slurm..."
# Create configuration
cat <<EOF > /etc/slurm/slurm.conf
ClusterName=hpk
SlurmctldHost=controller(controller.local)
AuthType=auth/munge
ProctrackType=proctrack/linuxproc
ReturnToService=1
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/lib/slurm/slurmd
SlurmUser=slurm
StateSaveLocation=/var/lib/slurm/slurmctld
SwitchType=switch/none
TaskPlugin=task/none
# TIMERS
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0
# NODES
NodeName=controller NodeAddr=controller.local CPUs=2 State=UNKNOWN
NodeName=node       NodeAddr=node.local       CPUs=2 State=UNKNOWN
# PARTITIONS
PartitionName=debug Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF

mkdir -p /var/lib/slurm/slurmd /var/lib/slurm/slurmctld /var/run/slurm
chown -R slurm:slurm /var/lib/slurm /var/run/slurm

# Enable Services
if [ "$ROLE" == "controller" ]; then
    systemctl enable slurmctld
    systemctl start slurmctld
    systemctl enable slurmd
    systemctl start slurmd
else
    systemctl enable slurmd
    systemctl start slurmd
fi

# Add hosts to /etc/hosts - Not needed with mDNS
echo "Provisioning complete."
