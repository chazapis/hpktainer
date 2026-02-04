# Builder stage
FROM golang:alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /bin/hpk-pause ./cmd/hpk-pause

# Final stage
ARG BASE_IMAGE=docker.io/chazapis/hpktainer-base:latest
FROM ${BASE_IMAGE}

# Install Apptainer (required for hpk-pause agent to spawn containers)
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:apptainer/ppa && \
    apt-get install -y apptainer && \
    rm -rf /var/lib/apt/lists/*

# Copy hpk-pause binary
COPY --from=builder /bin/hpk-pause /usr/local/bin/hpk-pause

ENTRYPOINT ["/usr/local/bin/hpk-pause"]
