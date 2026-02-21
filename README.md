# Unreal Tournament 2004 Dedicated Server (Docker)

This repository provides a Dockerized **Unreal Tournament 2004 dedicated server** built on the LANCommander base image. The container automatically downloads the dedicated server binaries on first run, supports file overlaying using OverlayFS, and integrates with the LANCommander hook system.

---

## Features

- Runs the **Unreal Tournament 2004 dedicated server** (`ucc-bin`)
- Automatically downloads and extracts server binaries on first startup via the `PostInitialization` hook
- Patches the master server list to use the OpenSpy community server
- Supports custom file overlays via OverlayFS
- Extensible via custom PowerShell hook scripts

## Docker Compose Example
```yaml
services:
  ut2004:
    image: lancommander/ut2004:latest
    container_name: ut2004

    ports:
      - "7777:7777/udp"  # Game port
      - "7778:7778/udp"  # Query port

    volumes:
      - ./config:/config

    environment:
      # Optional overrides
      # START_ARGS: "-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini"

    cap_add:
      - SYS_ADMIN

    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

---

## Directory Layout (Host)

```text
config/
├── Server/              # UT2004 server files (auto-downloaded on first run)
│   └── System/
│       ├── ucc-bin      # Server binary
│       ├── UT2004.ini   # Main server configuration
│       └── ...
├── Overlay/             # Drop-in overrides (maps, configs, mutators)
├── Merged/              # OverlayFS merged view (auto-created)
└── Scripts/
    └── Hooks/           # Custom PowerShell hook scripts
```

The `config` directory **must be writable** by Docker. Server binaries are downloaded and extracted automatically on first run by the `PostInitialization` hook.

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SERVER_URL` | URL to download the UT2004 dedicated server archive | `https://s3.amazonaws.com/ut2004-files/dedicated-server-3339-bonuspack.tar.gz` |
| `START_EXE` | Server executable path relative to the server directory | `System/ucc-bin` |
| `START_ARGS` | Arguments passed to the server executable | `-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini` |

---

## Configuration

Server configuration files live under `/config/Server/System/` (or `/config/Overlay/System/` for overrides that survive reinstalls):

- `UT2004.ini` - Main server configuration
- `Default.ini` - Default game settings
- `User.ini` - User-specific settings

Example `UT2004.ini` snippet:
```ini
[Engine.GameInfo]
ServerName=My UT2004 Server
MaxPlayers=16
AdminPassword=changeme
```

---

## Ports

- **UDP 7777** – Game port (clients connect here)
- **UDP 7778** – Query port (server browser)

---

## License

Unreal Tournament 2004 is distributed under its own license.
This repository contains only Docker build logic and helper scripts licensed under MIT.
