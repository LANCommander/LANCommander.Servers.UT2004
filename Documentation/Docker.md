---
sidebar_label: Docker
---

# Unreal Tournament 2004 Docker Container
This Docker container provides an Unreal Tournament 2004 dedicated server that automatically downloads the dedicated server binaries, supports file overlaying using OverlayFS, and integrates with the LANCommander hook system.

## Quick Start

```yaml
services:
  ut2004:
    image: lancommander/ut2004:latest
    container_name: ut2004

    ports:
      - 7777:7777/udp
      - 7778:7778/udp

    volumes:
      - "/data/Servers/UT2004:/config"

    environment:
      # START_ARGS: "-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini"

    cap_add:
      - SYS_ADMIN

    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

## Configuration Options

### Ports

The container exposes the following ports:

- **7777/udp** - Main game port. Clients connect to this port to join the server.
- **7778/udp** - Query port. Used by server browsers to retrieve server information.

**Port Mapping:**
In the example configuration, ports are mapped as:
- `7777:7777/udp` - Maps host port 7777 to container port 7777
- `7778:7778/udp` - Maps host port 7778 to container port 7778

You can customize these mappings based on your network requirements. If you're running multiple servers, use different host ports for each instance.

### Volumes

The container requires a volume mount for the `/config` directory, which stores:

- **Server/** - Base server files, installed by the `PostInitialization` hook.
- **Overlay/** - Custom files that overlay on top of the server directory.
- **Merged/** - OverlayFS merged view (auto-created).
- **Scripts/** - Custom PowerShell scripts for hooks.

**Example:**
```yaml
volumes:
  - "/data/Servers/UT2004:/config"
```

The host path can be:
- An absolute path (Windows: `C:\data\...`, Linux: `/data/...`)
- A relative path (e.g., `./config:/config`)
- A named volume (e.g., `ut2004-server-data:/config`)

**Important:** The mounted directory must be writable by the container.

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `SERVER_URL` | URL to download the UT2004 dedicated server archive | `https://s3.amazonaws.com/ut2004-files/dedicated-server-3339-bonuspack.tar.gz` | No |
| `START_EXE` | Server executable path relative to `SERVER_DIR` | `System/ucc-bin` | No |
| `START_ARGS` | Arguments passed to the server executable | `-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini` | No |

### Security Options

The container requires elevated privileges to use OverlayFS for file overlaying.

#### `cap_add: SYS_ADMIN`

Adds the `SYS_ADMIN` capability, which is required for mounting OverlayFS. This is the recommended approach as it provides minimal necessary privileges.

```yaml
cap_add:
  - SYS_ADMIN
```

#### `security_opt: apparmor:unconfined`

On Ubuntu hosts with AppArmor enabled, you may need to disable AppArmor restrictions for the container. This is often necessary for OverlayFS to function properly.

```yaml
security_opt:
  - apparmor:unconfined
```

**Alternative Options:**

If you prefer less security but simpler configuration, you can use privileged mode:

```yaml
privileged: true
```

**Note:** Privileged mode grants the container extensive access to the host system and is less secure than using `cap_add: SYS_ADMIN`.

### Restart Policy

```yaml
restart: unless-stopped
```

This ensures the container automatically restarts if it stops unexpectedly, but won't restart if you manually stop it.

**Other options:**
- `no` - Never restart
- `always` - Always restart, even after manual stop
- `on-failure` - Restart only on failure

## Directory Structure

The `/config` directory contains the following structure:

```
/config/
├── Server/              # UT2004 server files (auto-downloaded on first run)
│   └── System/          # Executables and configuration files
│       ├── ucc-bin      # Server binary (32-bit)
│       ├── ucc          # Launcher wrapper
│       ├── UT2004.ini   # Main server configuration
│       └── ...
├── Overlay/             # Custom files overlay (your modifications)
│   └── System/
│       ├── UT2004.ini   # Override server configuration
│       └── ...
├── Merged/              # OverlayFS merged view (auto-created)
├── .overlay-work/       # OverlayFS work directory (auto-created)
└── Scripts/
    └── Hooks/           # Custom PowerShell scripts for hooks
```

## OverlayFS

The container uses Linux OverlayFS to merge the base server files with your custom files:

- **Lower layer**: `/config/Server` (base server files)
- **Upper layer**: `/config/Overlay` (your custom files)
- **Merged view**: `/config/Merged` (where the game server runs from)

**Benefits:**
- Replace files without modifying the base installation
- Add custom content (maps, mutators, configs)
- No file copying required - OverlayFS is a union filesystem
- Easy updates - base server files can be updated without losing customizations

If OverlayFS cannot be mounted (e.g., missing privileges), the container will fall back to using `/config/Server` directly and log a warning.

## Troubleshooting

### Container Won't Start

1. **Check logs:**
   ```bash
   docker logs ut2004
   ```

2. **Verify permissions:**
   Ensure the mounted volume is writable:
   ```bash
   # Linux
   chmod -R 755 "/data/Servers/UT2004"

   # Windows
   # Ensure the directory has proper permissions in Windows
   ```

3. **Check security options:**
   Ensure `cap_add: SYS_ADMIN` is set, or use `privileged: true`

### Game Server Not Starting

1. **Verify START_ARGS:**
   Check that `START_ARGS` contains valid server arguments:
   ```yaml
   START_ARGS: "-ini=SystemSettings.ini -ini=UT2004.ini -ini=UT2004Server.ini"
   ```

2. **Check server directory:**
   Verify that server files were downloaded:
   ```bash
   docker exec ut2004 ls -la /config/Server/System
   ```

3. **Review server logs:**
   Check container logs for server startup messages and errors.

### Port Already in Use

If you get port binding errors:

1. **Check for existing containers:**
   ```bash
   docker ps -a
   ```

2. **Use different ports:**
   Change the port mapping in docker-compose.yml:
   ```yaml
   ports:
     - 7778:7777/udp  # Use a different host port
   ```

3. **Stop conflicting containers:**
   ```bash
   docker stop <container-name>
   ```

## Advanced Usage

### Custom Hooks

You can create custom PowerShell scripts that execute at various points in the container's lifecycle. Place scripts in:

```
/config/Scripts/Hooks/{HookName}/
```

**Available hooks:**
- `PreInstallUT2004` - Before the UT2004 server is downloaded/extracted
- `PostInstallUT2004` - After the UT2004 server is installed and the master server is patched

**Example hook script** (`/config/Scripts/Hooks/PostInstallUT2004/10-CustomSetup.ps1`):
```powershell
Write-Host "Running custom setup..."
# Your custom commands here
```

### Master Server

The `PostInitialization` hook automatically patches the server's INI file to point at the OpenSpy community master server (`utmaster.openspy.net:28902`), replacing any existing `MasterServerList` entries under `[IpDrv.MasterServerLink]`. No manual configuration is required.

### Custom Maps and Content

Place additional maps, textures, or other game content in `/config/Overlay/Maps/`, `/config/Overlay/Textures/`, etc. OverlayFS will merge them with the base installation transparently.
