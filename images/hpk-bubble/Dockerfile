# Builder stage for hpk-net-daemon
FROM golang:alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /bin/hpk-net-daemon ./cmd/hpk-net-daemon
RUN go build -o /bin/hpktainer ./cmd/hpktainer

FROM ubuntu:24.04

# Basic utilities
RUN apt-get update && \
    apt-get install -y vim-tiny curl iproute2 net-tools bridge-utils iputils-ping

# Apptainer
RUN apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:apptainer/ppa && \
    apt-get install -y apptainer

# CNI plugins
ARG TARGETARCH
RUN curl -LO https://github.com/containernetworking/plugins/releases/download/v1.9.0/cni-plugins-linux-${TARGETARCH}-v1.9.0.tgz && \
    mkdir -p /opt/cni/bin && \
    (cd /opt/cni/bin && tar -zxvf /cni-plugins-linux-${TARGETARCH}-v1.9.0.tgz) && \
    rm /cni-plugins-linux-${TARGETARCH}-v1.9.0.tgz

# Flannel
RUN apt-get install -y iptables nscd && \
    curl -L -o /usr/local/bin/flanneld https://github.com/flannel-io/flannel/releases/download/v0.27.4/flanneld-${TARGETARCH} && \
    chmod +x /usr/local/bin/flanneld

COPY --from=builder /bin/hpk-net-daemon /usr/bin/hpk-net-daemon
COPY --from=builder /bin/hpktainer /usr/bin/hpktainer
COPY images/hpk-bubble/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
