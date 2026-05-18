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
    -o cbt-restore \
    ./cmd

# Final stage
FROM alpine:3.21

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Run as non-root user
RUN adduser -D -u 1000 appuser
USER appuser

# Copy binary from builder
COPY --from=builder /build/cbt-restore /usr/local/bin/cbt-restore

ENTRYPOINT ["/usr/local/bin/cbt-restore"]
CMD ["--help"]
