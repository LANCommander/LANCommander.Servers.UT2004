# Unreal Tournament 2004 Dedicated Server (Docker)

This Docker image provides a **Unreal Tournament 2004 dedicated server** suitable for running multiplayer UT2004 servers in a clean, reproducible way.  
The image is designed for **headless operation**, automatically downloads game assets on first startup, and supports bind-mounted configuration files.

---

## Features

- Runs the **Unreal Tournament 2004 dedicated server** (`ucc-bin`)
- Automatically downloads and extracts game assets on first startup
- Tracks downloaded assets to prevent re-downloading on container restarts
- Non-root runtime using `gosu`
- Supports custom server configuration files

## Docker Compose Example
```yaml
services:
  ut2004:
    image: lancommander/ut2004:latest
    container_name: ut2004-server

    # UT2004 uses UDP for game, query, and beacon ports
    ports:
      - "7777:7777/udp"  # Game port
      - "7778:7778/udp"  # Query port
      - "7779:7779/udp"  # Beacon port

    # Bind mounts so files appear on the host
    volumes:
      - ./config:/config

    environment:
      # Optional overrides
      # SERVER_PORT: 7777
      # SERVER_ARGS: 'CTF-Face?Game=XGame.xCTFGame?MaxPlayers=16'

    # Ensure container restarts if the server crashes or host reboots
    restart: unless-stopped
```

---

## Directory Layout (Host)

```text
.
├── config/
│   ├── ut-server/          # Game assets (auto-downloaded on first startup)
│   │   ├── ucc-bin
│   │   ├── System/
│   │   └── ...
│   ├── .assets-downloaded  # Marker file to track downloads
│   ├── UT2004.ini
│   ├── Default.ini
│   └── User.ini
```

The `config` directory **must be writable** by Docker. The `ut-server` directory and its contents are automatically downloaded and extracted on first startup.

---

## Configuration

UT2004 server configuration files should be placed in `/config`:

- `UT2004.ini` - Main server configuration
- `Default.ini` - Default game settings
- `User.ini` - User-specific settings

The server will use these configuration files if they exist. You can customize server settings, game modes, maps, and other options in these files.

Example server configuration in `UT2004.ini`:
```ini
[Engine.GameInfo]
ServerName=My UT2004 Server
MaxPlayers=16
GamePassword=
AdminPassword=changeme
```

---

## Environment Variables

| Variable | Description | Default |
|--------|-------------|---------|
| `SERVER_PORT` | UDP port the server listens on (game port) | `7777` |
| `SERVER_ARGS` | Map and game type arguments (see below) | *(empty - uses default: DM-Rankin)* |
| `UT2004_DOWNLOAD_URL` | URL to download game assets from | `https://s3.amazonaws.com/ut2004-files/dedicated-server-3339-bonuspack.tar.gz` |

### `SERVER_ARGS`

If `SERVER_ARGS` is not set, the server will use the default map `DM-Rankin` with DeathMatch game type.

To customize the map and game type, set `SERVER_ARGS` with the map name and options. The format is: `<MapName>?Game=<GameType>?<Options>`

Common examples:

```bash
# Capture the Flag on Face map
SERVER_ARGS="CTF-Face?Game=XGame.xCTFGame?MaxPlayers=16"

# DeathMatch on Rankin map (default)
SERVER_ARGS="DM-Rankin?Game=XGame.xDeathMatch?MaxPlayers=8"

# Team DeathMatch
SERVER_ARGS="DM-Rankin?Game=XGame.xTeamGame?MaxPlayers=16"

# Onslaught mode
SERVER_ARGS="ONS-Torlan?Game=Onslaught.ONSOnslaughtGame?MaxPlayers=16"
```

---

## Running the Server
### Basic run (recommended)
```bash
mkdir -p config
chmod -R 777 config

docker run --rm -it \
  -p 7777:7777/udp \
  -p 7778:7778/udp \
  -p 7779:7779/udp \
  -v "$(pwd)/config:/config" \
  lancommander/ut2004:latest
```

### With custom server arguments
```bash
docker run --rm -it \
  -p 7777:7777/udp \
  -p 7778:7778/udp \
  -p 7779:7779/udp \
  -v "$(pwd)/config:/config" \
  -e SERVER_ARGS="CTF-Face?Game=XGame.xCTFGame?MaxPlayers=16" \
  lancommander/ut2004:latest
```

## Ports
- **UDP 7777** – Game port (default)
- **UDP 7778** – Query port (for server browser)
- **UDP 7779** – Beacon port (for server discovery)

## Asset Download

On first startup, the container will automatically download the UT2004 dedicated server assets from the configured URL. The download is tracked using a marker file, so subsequent container restarts will skip the download if the assets are already present.