#!/bin/bash
# Compiles LCServer.u from Classes/ with the Windows UCC.exe under Wine (the Linux dedicated
# server's ucc-bin has no make commandlet), in a lancommander/wine container.
#
#   LCServer/build.sh <UT2004 install>
#
# The install needs System/ (with UCC.exe and the Windows DLLs, as the 3339 dedicated server
# has) plus Textures/, StaticMeshes/, Sounds/ and Animations/ for the stock packages. It is
# mounted read-only; System/ is copied to a scratch folder.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
game="$(cd "${1:?usage: build.sh <UT2004 install>}" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$game/System" "$work/System"
mkdir -p "$work/LCServer"
cp -r "$here/Classes" "$work/LCServer/Classes"
rm -f "$work/System/LCServer.u"

# UT2004.ini with LCServer after the last EditPackages line
awk '{ lines[NR] = $0 } /^EditPackages=/ { last = NR }
     END { for (i = 1; i <= NR; i++) { print lines[i]; if (i == last) print "EditPackages=LCServer" } }' \
    "$work/System/UT2004.ini" > "$work/System/LCMake.ini"

mounts=()
for dir in Textures StaticMeshes Sounds Animations Maps; do
    [ -d "$game/$dir" ] && mounts+=(-v "$game/$dir:/ut/$dir:ro")
done

docker run --rm --entrypoint "" -u "$(id -u):$(id -g)" -e HOME=/tmp -e WINEPREFIX=/tmp/wine -e WINEDEBUG=-all \
    -v "$work/System:/ut/System" -v "$work/LCServer:/ut/LCServer" "${mounts[@]}" -w /ut/System \
    lancommander/wine:latest sh -c 'wineboot -i >/dev/null 2>&1; wine UCC.exe make ini=LCMake.ini'

cp "$work/System/LCServer.u" "$here/LCServer.u"
echo "Built $here/LCServer.u"
