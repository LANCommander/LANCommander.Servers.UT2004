# syntax=docker/dockerfile:1.7

# ----------------------------
# ut2004-stats-bridge (StatsBridge/): reports the games LCServer sees to LANCommander through
# the LANCommander Interposer. Built on Debian 12, as the base image is
# ----------------------------
FROM debian:bookworm AS stats-bridge

ARG INTERPOSER_VERSION=v1.6.0
ARG YAML_CPP_VERSION=0.8.0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates nlohmann-json3-dev \
 && rm -rf /var/lib/apt/lists/*

# The Interposer wants yaml-cpp's namespaced CMake target, which Debian 12's 0.7 lacks
RUN git clone --quiet --depth 1 --branch "${YAML_CPP_VERSION}" https://github.com/jbeder/yaml-cpp /src/yaml-cpp \
 && cmake -S /src/yaml-cpp -B /src/yaml-cpp/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DYAML_BUILD_SHARED_LIBS=OFF -DYAML_CPP_BUILD_TESTS=OFF -DYAML_CPP_BUILD_TOOLS=OFF -DYAML_CPP_BUILD_CONTRIB=OFF \
 && cmake --build /src/yaml-cpp/build -j"$(nproc)" \
 && cmake --install /src/yaml-cpp/build

RUN git clone --quiet --depth 1 --branch "${INTERPOSER_VERSION}" \
        https://github.com/LANCommander/LANCommander.Interposer /src/interposer

COPY StatsBridge/ /src/bridge/
RUN cmake -S /src/bridge -B /src/bridge/build -DCMAKE_BUILD_TYPE=Release \
        -DLANCOMMANDER_INTERPOSER_DIR=/src/interposer \
        -DINTERPOSER_VERSION="${INTERPOSER_VERSION}" \
 && cmake --build /src/bridge/build -j"$(nproc)" \
 && strip /src/bridge/build/ut2004-stats-bridge

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

# ----------------------------
# LCServer (LCServer/): LANCommander's server-side UnrealScript package, never sent to clients.
# On when any of these is set (Hooks/PostInitialization/40-ConfigureLCServer.ps1):
#   - UT2004_MAP_ROTATION: travel URLs, separated by ; or new lines, that can mix game types,
#     e.g. "CTF-FaceClassic?Game=XGame.xCTFGame?GoalScore=3;BR-Anubis?Game=XGame.xBombingRun".
#     When a game ends, the server goes to the entry after the one being played. Options carry
#     over from map to map, so give each entry every option that differs between game types
#   - UT2004_BALANCE_TEAMS: when a team game starts with at least UT2004_BALANCE_MIN_PLAYERS
#     human players, sort them into teams by skill (ratings kept in System/LCSkill.ini)
#   - UT2004_MAX_OVERTIME: minutes of overtime before a tied CTF or Bombing Run game goes to the
#     team whose players scored the most points (0: no limit)
#   - LANCommander match statistics: MATCH_STATS_ENABLED auto (on when MATCH_STATS_SERVER_URL
#     and MATCH_STATS_TOKEN are set), true or false. Every game, bots included, is reported
#     through ut2004-stats-bridge; undelivered matches are kept in /config/.interposer/
#   - UT2004_INI: the server's ini, in System/ (the one given to ucc with ini=)
# ----------------------------
ENV UT2004_INI="UT2004.ini" \
    UT2004_MAP_ROTATION="" \
    UT2004_BALANCE_TEAMS="false" \
    UT2004_BALANCE_MIN_PLAYERS="4" \
    UT2004_MAX_OVERTIME="0" \
    UT2004_STATS_BRIDGE_PORT="7790" \
    MATCH_STATS_ENABLED="auto" \
    MATCH_STATS_SERVER_URL="" \
    MATCH_STATS_TOKEN="" \
    MATCH_STATS_GAME_ID="" \
    MATCH_STATS_SERVER_ID="" \
    MATCH_STATS_REPORTER_NAME="" \
    MATCH_STATS_MIN_PLAYERS="1" \
    MATCH_STATS_RECORD_BOTS="true"

COPY --from=stats-bridge /src/bridge/build/ut2004-stats-bridge /usr/local/bin/ut2004-stats-bridge
COPY LCServer/LCServer.u /usr/local/share/ut2004/LCServer/LCServer.u

EXPOSE 7777/udp
EXPOSE 7778/udp

# COPY Modules/ "${BASE_MODULES}/"
COPY Hooks/ "${BASE_HOOKS}/"

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]