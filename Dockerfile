# syntax=docker/dockerfile:1.7

FROM lancommander/base:latest

ENV SERVER_URL="https://s3.amazonaws.com/ut2004-files/dedicated-server-3339-bonuspack.tar.gz"

ENV START_EXE="System/ucc-bin"
ENV START_ARGS="-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini"

# ----------------------------
# Dependencies
# ----------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    bzip2 \
    tar \
    unzip \
    xz-utils \
    p7zip-full \
    gosu

RUN dpkg --add-architecture i386 && \
  apt-get update && apt-get install -y --no-install-recommends \
    libc6-i386 \
    lib32gcc-s1 \
    lib32stdc++6 \
    libstdc++5:i386 \
  && rm -rf /var/lib/apt/lists/*

EXPOSE 7777/udp
EXPOSE 7778/udp

# COPY Modules/ "${BASE_MODULES}/"
COPY Hooks/ "${BASE_HOOKS}/"

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]