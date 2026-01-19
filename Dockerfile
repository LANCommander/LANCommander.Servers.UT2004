# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim

# Runtime directories (mount these as volumes)
ENV CONFIG_DIR=/config

# Server settings
ENV SERVER_PORT=7777
ENV SERVER_ARGS=""

# ----------------------------
# Dependencies
# ----------------------------
# Enable multiarch for 32-bit libraries
RUN dpkg --add-architecture i386 && \
  apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
    gzip \
    gosu \
    lib32gcc-s1 \
    lib32stdc++6 \
    libc6-i386 \
  && rm -rf /var/lib/apt/lists/*

# Install libstdc++5 (32-bit) for UT2004 - download from Debian archive
# Note: libstdc++5 is not available in bookworm, so we download from an older Debian release
RUN set -eux; \
  apt-get update; \
  libstdc5_url="https://archive.debian.org/debian/pool/main/g/gcc-3.3/libstdc++5_3.3.6-20_i386.deb"; \
  curl -fsSL "${libstdc5_url}" -o /tmp/libstdc++5.deb; \
  dpkg -i /tmp/libstdc++5.deb || apt-get -f install -y --no-install-recommends; \
  rm -f /tmp/libstdc++5.deb; \
  rm -rf /var/lib/apt/lists/*; \
  # Verify the library is installed
  ls -la /usr/lib/i386-linux-gnu/libstdc++.so.5* || ls -la /usr/lib32/libstdc++.so.5* || true

# ----------------------------
# Create a non-root user
# ----------------------------
RUN useradd -m -u 10001 -s /usr/sbin/nologin ut2004 \
  && mkdir -p "${CONFIG_DIR}" \
  && chown -R ut2004:ut2004 "${CONFIG_DIR}"

# ----------------------------
# Entrypoint
# ----------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/config"]

EXPOSE 7777/udp 7778/udp 7779/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]