# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Docker-based deployment of AzerothCore (WoW 3.3.5a private server), adapted from the Synology DSM SPK package (WoWServer v1.0.52). Uses pre-built SPK binaries packaged into Ubuntu 22.04 Docker containers — **not compiled from source** in this repo.

## Common Commands

```bash
# Apple Silicon Macs ONLY (Intel Macs skip this)
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# Start all services
docker compose up -d

# Stop all services
docker compose down

# Stop and remove volumes (full reset)
docker compose down -v

# Pull updated images
docker compose pull

# View logs
docker compose logs -f ac-worldserver
docker compose logs -f ac-authserver

# Restart specific services
docker compose restart ac-worldserver ac-authserver

# Access worldserver console (for GM commands like account create)
docker attach acore-worldserver
# Detach with: Ctrl+P Ctrl+Q

# Start phpMyAdmin (optional management profile)
docker compose --profile management up -d
```

## Architecture

### Service Dependency Chain

```
ac-database (MariaDB 10.11, healthcheck: alive)
    ├─► ac-worldserver (runs DB migrations, creates realmlist table)
    │       └─► ac-realm-init (one-shot: updates realmlist IP/port, then exits)
    │               ├─► ac-authserver (starts after realm-init succeeds)
    │               ├─► ac-registration (PHP 8.2 Apache + WoWSimpleRegistration)
    │               └─► ac-account-init (one-shot: creates default admin account via SRP6)
    └─► phpmyadmin (optional, `--profile management`)
```

### Container Build System

The `Dockerfile.worldserver` and `Dockerfile.authserver` are **self-contained builds** that copy pre-compiled SPK binaries from:
- `bin/` — authserver, worldserver, lua52_compiler, lua52_interpreter
- `lib/` — Boost, ICU, MariaDB client, readline, ncurses shared libraries

The SPK binaries hardcode Synology paths (`/var/packages/WoWServer/target/`), so both Dockerfiles create symlinks:
```
/var/packages/WoWServer/target/etc → /opt/wow/etc
/var/packages/WoWServer/target/database → /opt/wow/database
```

### Configuration Substitution Pattern

Server configs (`authserver.conf`, `worldserver.conf`) contain `__DB_PASSWORD__` placeholders. On container start, `entrypoint-*.sh` uses `sed` to replace them with the `DB_PASSWORD` env var (from `.env`'s `DOCKER_DB_ROOT_PASSWORD`).

### Module System

Game server modules are configured via `.conf.dist` files in `conf/modules/`:
- `1v1arena`, `Anticheat`, `mod_ahbot` (auction house bot), `mod_eluna` (Lua scripting engine), `playerbots`, `PvPScript`, `transmog`

These are mounted read-only into the worldserver container at `/opt/wow/etc/modules/`.

### Eluna Lua Scripts

`scripts/lua/` contains Lua scripts loaded by the Eluna engine at runtime (hot-reloadable):
- `super_hearthstone.lua` — teleportation, bank, repair NPC
- `portable_vendor.lua` — portable vendor NPC

### Realm IP Initialization

`ac-realm-init` is a one-shot MariaDB container running `scripts/realm-init.sh`. It polls the `acore_auth.realmlist` table (created by worldserver's DB migrations), then updates the address/port to match `REALM_IP` from `.env`. This decouples realm configuration from worldserver startup.

### Default Admin Account Creation

`ac-account-init` is a one-shot Python container (`scripts/create-default-account.py`) that runs after realm-init completes. It computes SRP6 salt/verifier and inserts the account directly into the `acore_auth.account` table, then sets GM level in `account_access`. Credentials are configured via `.env` (gitignored) — set `DEFAULT_ACCOUNT_USER` and `DEFAULT_ACCOUNT_PASS`. If unset, the service skips gracefully.

### Data Persistence

- `ac-database-data` — named Docker volume for all game data (accounts, characters, world state)
- `acore-logs` — named Docker volume for server logs
- `./scripts/lua/` — bind-mounted, changes take effect on worldserver reload
- Client data (maps/dbc/vmaps/mmaps) — bind-mounted from `DOCKER_CLIENT_DATA_PATH`

### Key Ports

| Port | Service |
|------|---------|
| 3724 | Authserver (game login) |
| 8085 | Worldserver (game world) |
| 7878 | SOAP (remote admin) |
| 8765 | Web registration |
| 63306 | MariaDB (external) |
| 8081 | phpMyAdmin (management profile) |

## Important Constraints

- **SPK binaries, not source**: There is no C++ build step in this repo. The `bin/` and `lib/` directories contain pre-compiled x86_64 Linux binaries extracted from the Synology SPK. Modifying server behavior means changing config files or Lua scripts, not recompiling.
- **No test suite**: This is an infrastructure/deployment repo. CI only validates the Docker Compose startup flow.
- **Apple Silicon**: x86_64 binaries require `DOCKER_DEFAULT_PLATFORM=linux/amd64`. All containers run under emulation.
- **`.env` is gitignored**: Users must create their own `.env`. The `.env` in the working tree is local only.
- **Worldserver must start first**: The worldserver runs DB migrations, creating tables that authserver and realm-init depend on.
