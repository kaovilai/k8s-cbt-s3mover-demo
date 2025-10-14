FROM golang:1.22-alpine AS builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s" \
    -o cbt-backup \
    ./cmd

# Final stage
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Copy binary from builder
COPY --from=builder /build/cbt-backup /usr/local/bin/cbt-backup

# Run as non-root user
RUN addgroup -g 1000 backup && \
    adduser -D -u 1000 -G backup backup

USER backup

ENTRYPOINT ["/usr/local/bin/cbt-backup"]
CMD ["--help"]
