FROM golang:alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /bin/hpk-net-daemon ./cmd/hpk-net-daemon

FROM alpine:latest
RUN apk add --no-cache iproute2
COPY --from=builder /bin/hpk-net-daemon /usr/local/bin/hpk-net-daemon
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
