FROM golang:1.26-alpine AS builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s" \
    -o cbt-backup \
    ./cmd

# Final stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Copy binary from builder
COPY --from=builder /build/cbt-backup /usr/local/bin/cbt-backup

ENTRYPOINT ["/usr/local/bin/cbt-backup"]
CMD ["--help"]
