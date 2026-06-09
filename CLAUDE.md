# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Docker-based deployment of AzerothCore (WoW 3.3.5a private server), adapted from the Synology DSM SPK package (WoWServer v1.0.52). Uses pre-built SPK binaries packaged into Ubuntu 22.04 Docker containers — **not compiled from source** in this repo.

**Two deployment modes:**
- **Local** (`docker-compose.yml`): builds images locally from `Dockerfile.*`, mounts source directories for live development
- **NAS** (`nas/docker-compose.yml`): pulls pre-built images from Docker Hub (`asm0x1/wow-*`), designed for UGREEN Docker UI (no CLI)

## Common Commands

```bash
# Apple Silicon Macs ONLY (Intel Macs skip this)
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# === Local development (build from source) ===
docker compose up -d                        # Start all services
docker compose up -d --build                # Rebuild + start
docker compose down                         # Stop all services
docker compose down -v                      # Stop + remove volumes (full reset)
docker compose logs -f ac-worldserver       # View worldserver logs
docker compose logs -f ac-authserver        # View authserver logs
docker compose restart ac-worldserver       # Restart worldserver (picks up Lua changes)
docker compose --profile management up -d   # Start phpMyAdmin on port 8081

# Access worldserver console (for GM commands)
docker attach acore-worldserver             # Detach: Ctrl+P Ctrl+Q

# === Docker Hub publishing (after code changes) ===
docker build -t asm0x1/wow-worldserver:latest -f Dockerfile.worldserver .
docker build -t asm0x1/wow-authserver:latest -f Dockerfile.authserver .
docker build -t asm0x1/wow-registration:latest -f Dockerfile.registration .
docker push asm0x1/wow-worldserver:latest
docker push asm0x1/wow-authserver:latest
docker push asm0x1/wow-registration:latest
```

## Architecture

### Service Dependency Chain

```
ac-database (MariaDB 10.11, healthcheck: alive)
    ├─► ac-worldserver (creates DBs, runs migrations, playerbots SQL, then game loop)
    │       └─► ac-realm-init (one-shot: updates realmlist IP/port from REALM_IP, then exits)
    │               ├─► ac-authserver (starts after realm-init succeeds)
    │               ├─► ac-registration (PHP 8.2 Apache + WoWSimpleRegistration)
    │               └─► ac-account-init (one-shot: creates admin account via SRP6)
    └─► phpmyadmin (optional, `--profile management`)
```

### Container Build System

Three Dockerfiles (`Dockerfile.worldserver`, `Dockerfile.authserver`, `Dockerfile.registration`) package pre-compiled SPK binaries from `bin/` and `lib/` into Ubuntu 22.04 images.

The SPK binaries hardcode Synology paths (`/var/packages/WoWServer/target/`), so Dockerfiles create symlinks:
```
/var/packages/WoWServer/target/etc → /opt/wow/etc
/var/packages/WoWServer/target/database → /opt/wow/database
```

### Entrypoint Scripts

**`entrypoint-worldserver.sh`** (runs as container ENTRYPOINT, executed in order):
1. Creates databases if they don't exist (`acore_auth`, `acore_characters`, `acore_world`, `acore_playerbots`) — this replaced the MariaDB `docker-entrypoint-initdb.d` approach which had permission issues on NAS
2. Generates `worldserver.conf` from `.template` via `sed` replacing `__DB_PASSWORD__`
3. Generates module configs from `.conf.dist` templates replacing `__BOT_*__` placeholders with env vars
4. Imports playerbots base SQL tables if not already present
5. Execs the worldserver binary

**`entrypoint-authserver.sh`**: generates `authserver.conf` from template, execs authserver.

### .env Sourcing Pattern (NAS Compatibility)

Some platforms (UGREEN Docker UI) don't reliably support Compose's `${VAR:-default}` variable substitution from `.env` files. To work around this, scripts source the `.env` file at runtime when it's mounted as `/env`:

```bash
if [ -f /env ]; then
    set -a; . /env; set +a
fi
```

This pattern is used in `scripts/realm-init.sh` and the `ac-registration` command. Services mount `.env` as `/env:ro`.

### Module System

Game server modules in `conf/modules/` use `.conf.dist` template files with `__BOT_*__` placeholders. The entrypoint script generates the actual `.conf` files at container start by substituting environment variables. Modules include: `1v1arena`, `Anticheat`, `mod_ahbot`, `mod_eluna`, `playerbots`, `PvPScript`, `transmog`.

### Realm IP Initialization

`ac-realm-init` is a one-shot `mariadb:10.11` container that:
1. Sources `/env` if available (NAS compatibility)
2. Waits for `acore_auth.realmlist` table (created by worldserver migrations)
3. Updates the address/port via SQL `UPDATE realmlist SET address=..., port=...`

Variables support dual naming: `DB_PASS`/`DOCKER_DB_ROOT_PASSWORD`, `REALM_PORT`/`DOCKER_WORLD_EXTERNAL_PORT`.

### Default Admin Account Creation

`ac-account-init` is a one-shot `python:3.11-alpine` container that computes SRP6 salt/verifier and inserts accounts into `acore_auth.account`. Built-in account `asm0x1`/`123456` (GM 3) is always created. Optional custom admin from `DEFAULT_ACCOUNT_USER`/`DEFAULT_ACCOUNT_PASS` env vars.

## Two Compose Files

| File | Purpose | Image Source |
|------|---------|-------------|
| `docker-compose.yml` | Local dev/Mac | `build:` from Dockerfile |
| `nas/docker-compose.yml` | NAS deployment | `image:` from Docker Hub |

Key differences in `nas/docker-compose.yml`:
- Uses `image: asm0x1/wow-*:latest` instead of `build:`
- Mounts `./.env:/env:ro` on services that need runtime env (realm-init, registration)
- No source code/data mounts except `./data` (client maps)
- No `database/`, `conf/modules/`, or `scripts/lua/` mounts (baked into images)
- `ac-registration` `command:` sources `/env` at runtime then runs `envsubst` for REALM_IP

## Data Persistence

- `ac-database-data` — named Docker volume for all game data (accounts, characters, world state)
- `acore-logs` — named Docker volume for server logs
- `./data/` — bind-mounted client maps (maps/dbc/vmaps/mmaps/cameras), ~2-3GB, not in repo
- `./scripts/lua/` — bind-mounted Lua scripts (local dev only; baked into image for NAS)

## Key Ports

| Port | Service |
|------|---------|
| 3724 | Authserver (game login) |
| 8085 | Worldserver (game world) |
| 7878 | SOAP (remote admin) |
| 8765 | Web registration |
| 63306 | MariaDB (external) |
| 8081 | phpMyAdmin (management profile) |

## Important Constraints

- **SPK binaries, not source**: No C++ build step. `bin/` and `lib/` contain pre-compiled x86_64 Linux binaries from Synology SPK. Modify behavior via config files or Lua scripts, not recompilation.
- **No test suite**: Infrastructure/deployment repo. CI validates Docker Compose startup flow only.
- **Apple Silicon**: x86_64 binaries require `DOCKER_DEFAULT_PLATFORM=linux/amd64`. Runs under emulation.
- **`.env` is gitignored**: Users create from `conf/dist/.env` (local) or `nas/.env.dist` (NAS).
- **Worldserver must start first**: Runs DB migrations, creating tables that authserver and realm-init depend on.
- **NAS `.env` not auto-read by Compose**: UGREEN Docker UI may not apply `.env` to Compose variable substitution. The runtime sourcing pattern (`/env` mount + `[ -f /env ] && . /env`) is the workaround.
