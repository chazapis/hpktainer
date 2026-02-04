# Makefile for hpktainer project

REGISTRY ?= docker.io/chazapis
VERSION ?= $(shell date +%Y%m%d)

# Binary output directory
BIN_DIR = bin

.PHONY: all binaries images clean

all: images

binaries:
	@echo "Building binaries..."
	@mkdir -p $(BIN_DIR)/linux/amd64 $(BIN_DIR)/linux/arm64
	
	# Linux amd64
	GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/linux/amd64/hpktainer ./cmd/hpktainer
	GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/linux/amd64/hpk-net-daemon ./cmd/hpk-net-daemon
	GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/linux/amd64/hpk-kubelet ./cmd/hpk-kubelet
	GOOS=linux GOARCH=amd64 go build -o $(BIN_DIR)/linux/amd64/hpk-pause ./cmd/hpk-pause
	
	# Linux arm64
	GOOS=linux GOARCH=arm64 go build -o $(BIN_DIR)/linux/arm64/hpktainer ./cmd/hpktainer
	GOOS=linux GOARCH=arm64 go build -o $(BIN_DIR)/linux/arm64/hpk-net-daemon ./cmd/hpk-net-daemon
	GOOS=linux GOARCH=arm64 go build -o $(BIN_DIR)/linux/arm64/hpk-kubelet ./cmd/hpk-kubelet
	GOOS=linux GOARCH=arm64 go build -o $(BIN_DIR)/linux/arm64/hpk-pause ./cmd/hpk-pause

images:
	@echo "Building and pushing images..."
	
	# hpktainer-base
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(REGISTRY)/hpktainer-base:$(VERSION) \
		-t $(REGISTRY)/hpktainer-base:latest \
		--push \
		-f images/hpktainer-base/Dockerfile .

	# hpk-bubble
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(REGISTRY)/hpk-bubble:$(VERSION) \
		-t $(REGISTRY)/hpk-bubble:latest \
		--push \
		-f images/hpk-bubble/Dockerfile .

	# hpk-pause
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(REGISTRY)/hpk-pause:$(VERSION) \
		-t $(REGISTRY)/hpk-pause:latest \
		--push \
		-f images/hpk-pause/Dockerfile .

clean:
	rm -rf $(BIN_DIR)
