# Multi-stage build to extract official node_exporter binary
FROM prom/node-exporter:v1.8.2 AS exporter-binary

# Lightweight Alpine Linux base for simulated enterprise VM
FROM alpine:3.20

# Install diagnostic utilities for network isolation testing and interactive debugging
RUN apk add --no-cache \
    bash \
    curl \
    iputils \
    bind-tools \
    iproute2 \
    netcat-openbsd \
    procps \
    ca-certificates

# Copy official node_exporter binary
COPY --from=exporter-binary /bin/node_exporter /bin/node_exporter

# Setup textfile collector directory and startup entrypoint
RUN mkdir -p /var/lib/node_exporter/textfile_collector
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9100

ENTRYPOINT ["/entrypoint.sh"]
