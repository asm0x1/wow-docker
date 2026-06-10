# AzerothCore Docker - 魔兽世界 3.3.5a 服务端

改编自群晖 DSM 套件版 (WoWServer v1.0.52)，将 SPK 预编译二进制打包为 Docker 容器。
**非源码编译** — 使用群晖 SPK 提取的 x86_64 二进制，Ubuntu 22.04 运行。

> Author: asm0x1

## ⚠️ 免责声明

本项目仅用于**技术学习与研究**，非商业用途。

- 本仓库是一个 **Docker 容器化部署方案**，不包含任何游戏客户端素材（模型、贴图、音乐、地图等）。
- `bin/` 目录下的二进制文件编译自 [AzerothCore](https://github.com/azerothcore/azerothcore) 开源项目（AGPL v3.0），源码可在其官方仓库获取。二进制源自群晖 SPK 套件 WoWServer v1.0.52。
- 使用前请确保你拥有合法的游戏客户端，并遵守相关用户协议及当地法律法规。
- 本项目与暴雪娱乐（Blizzard Entertainment）无任何关联。所有商标归其各自所有者所有。

## 部署方式

| 方式 | 适用场景 | 说明 |
|------|----------|------|
| **本地部署** | Mac/Linux 开发测试 | `docker compose up -d`，本地构建镜像 |
| **NAS 部署** | 绿联 NAS（无命令行） | 拉取 Docker Hub 镜像，UI 操作 |

> NAS 部署详见 [`nas/部署说明.md`](nas/部署说明.md)，只需改 YAML 顶部 2 个值即可部署。

## 快速开始（本地）

```bash
# 1. 复制 .env 模板并编辑
cp .env.dist .env
# 改 REALM_IP 为你本机 IP
#   macOS:  ipconfig getifaddr en0
#   Linux:  hostname -I

# 2. Apple Silicon Mac 必须设置 (Intel Mac 跳过)
export DOCKER_DEFAULT_PLATFORM=linux/amd64

# 3. 启动
docker compose up -d
```

首次启动 worldserver 自动执行数据库迁移和 playerbots 初始化，等待 1-2 分钟。

启动后访问：
| 端口 | 服务 |
|------|------|
| 3724 | 游戏登录 (authserver) |
| 8085 | 游戏世界 (worldserver) |
| 8765 | Web 注册页面 |
| 7878 | SOAP 远程管理 |
| 63306 | MariaDB (外部连接) |
| 8081 | phpMyAdmin (`--profile management`) |

内置管理员账户 `asm0x1` / `123456`（GM Level 3）始终存在。
可在 `.env` 中配置 `DEFAULT_ACCOUNT_USER` / `DEFAULT_ACCOUNT_PASS` 添加额外管理员。

## 目录结构

```
wow-docker/
├── bin/                     # SPK 预编译二进制 (worldserver, authserver)
├── conf/modules/            # 模块配置 (.conf.dist)
├── data/                    # 客户端地图数据（需自行提取，~2-3GB）
│   ├── maps/
│   ├── dbc/
│   ├── vmaps/
│   ├── mmaps/
│   └── cameras/
├── database/                # 数据库 SQL (migrations, playerbots)
├── lib/                     # SPK 预编译依赖库
├── scripts/lua/             # Eluna Lua 脚本（热加载）
│   └── extensions/          # Eluna 扩展库
├── sql/init/                # 数据库初始化 SQL
├── WoWRegistration/         # Web 注册页面 (WoWSimpleRegistration)
├── .env.dist                # .env 模板（本地部署用）
├── Dockerfile.*             # Docker 镜像构建文件
├── docker-compose.yml       # 本地部署 Compose 文件
├── entrypoint-*.sh          # 容器入口脚本
└── nas/
    ├── docker-compose.yml   # NAS 部署 Compose 文件
    └── 部署说明.md          # NAS 部署详细说明（含配置模板）
```

> `data/` 目录需要从魔兽世界 3.3.5a 客户端提取。使用 [AzerothCore 地图提取工具](https://www.azerothcore.org/wiki/client-setup) 生成 maps/dbc/vmaps/mmaps/cameras，放入对应子目录。

## 服务架构

```
ac-database (MariaDB 10.11)
  ├─► ac-worldserver (建库 + 迁移 + playerbots 初始化 + 游戏世界)
  ├─► ac-authserver (realm 初始化 → 管理员账户创建 → 认证服务启动)
  │     └─► ac-registration (Web 注册，PHP 8.2 + WoWSimpleRegistration)
  └─► phpmyadmin (可选，--profile management)
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| **REALM_IP** | 127.0.0.1 | **本机 IP（必改）** |
| DEFAULT_ACCOUNT_USER | (空) | 额外自定义管理员用户名（可选） |
| DEFAULT_ACCOUNT_PASS | (空) | 额外自定义管理员密码（可选） |
| DEFAULT_ACCOUNT_GMLEVEL | 3 | 默认管理员 GM 等级 |
| DEFAULT_ACCOUNT_EXPANSION | 2 | 默认账号资料片 (0=经典/1=TBC/2=WotLK) |
| DOCKER_WORLD_EXTERNAL_PORT | 8085 | 世界服务器端口 |
| DOCKER_AUTH_EXTERNAL_PORT | 3724 | 认证服务器端口 |
| DOCKER_REGISTRATION_EXTERNAL_PORT | 8765 | Web 注册页面端口 |
| DOCKER_SOAP_EXTERNAL_PORT | 7878 | SOAP 远程管理端口 |
| DOCKER_DB_EXTERNAL_PORT | 63306 | MariaDB 外部端口 |
| DOCKER_DB_ROOT_PASSWORD | wow@asm0x1 | MariaDB root 密码 |
| BOT_MIN_COUNT | 15 | 最少在线假人数量 |
| BOT_MAX_COUNT | 20 | 最多在线假人数量 |
| BOT_MIN_LEVEL | 1 | 假人最低等级 |
| BOT_MAX_LEVEL | 80 | 假人最高等级 |
| BOT_ALLIANCE_RATIO | 50 | 联盟阵营比例 (%) |
| BOT_HORDE_RATIO | 50 | 部落阵营比例 (%) |

## 实用命令

### 服务管理

```bash
docker compose up -d                     # 启动所有服务
docker compose down                      # 停止所有服务
docker compose down -v                   # 停止并清除数据库（完全重置）
docker compose restart ac-worldserver    # 重启世界服务器
docker compose logs -f ac-worldserver    # 查看世界服务器日志
docker compose logs -f ac-authserver     # 查看认证服务器日志
docker compose --profile management up -d phpmyadmin  # 启动 phpMyAdmin
```

### 创建 GM 账号（控制台）

```bash
docker attach acore-worldserver
# 输入命令后回车：
account create <用户名> <密码>
account set gmlevel <用户名> 3 -1
# 按 Ctrl+P Ctrl+Q 退出控制台
```

### 查看在线玩家

```bash
docker attach acore-worldserver
# 输入：
account onlinelist
# Ctrl+P Ctrl+Q 退出
```

## GM 命令参考

### GM 权限等级

| 等级 | 权限 |
|------|------|
| 0 | 普通玩家 |
| 1 | 初级 GM |
| 2 | 中级 GM |
| 3 | 管理员（全部权限） |

### 控制台命令

| 命令 | 说明 |
|------|------|
| `account create <用户> <密码>` | 创建账号 |
| `account delete <用户>` | 删除账号 |
| `account set gmlevel <用户> <0-3> <领域ID>` | 设置 GM 等级 |
| `account set addon <用户> <0-2>` | 设置资料片 |
| `account set password <用户> <新密码> <新密码>` | 修改密码 |
| `account onlinelist` | 在线玩家列表 |
| `ban account <用户> <时间> <原因>` | 封禁账号 |
| `unban account <用户>` | 解封账号 |

### 游戏中命令（聊天框输入）

| 命令 | 说明 |
|------|------|
| `.gm on` / `.gm off` | 开关 GM 模式 |
| `.additem <物品ID> [数量]` | 添加物品 |
| `.addmoney <数量>` | 添加金币（铜币单位） |
| `.levelup [等级]` | 提升等级 |
| `.learn <技能ID>` | 学习技能 |
| `.learn all myclass` | 学习本职业所有技能 |
| `.learn all crafts` | 学习所有商业技能 |
| `.tele <地图名>` | 传送到地图 |
| `.go <x> <y> <z> <map>` | 传送到坐标 |
| `.goname <玩家名>` | 传送到玩家身边 |
| `.revive` | 复活 |
| `.npc add <NPC_ID>` | 创建 NPC |
| `.npc delete` | 删除选中的 NPC |
| `.modify speed <倍率>` | 修改移动速度 |
| `.modify money <数量>` | 修改金币 |
| `.kick <玩家名>` | 踢出玩家 |
| `.saveall` | 保存所有在线玩家 |
| `.server shutdown <秒>` | 关闭服务器 |

### 常用传送点

| 命令 | 目的地 |
|------|--------|
| `.go -8833 627 94 0` | 暴风城 |
| `.go 1569 -4397 7 1` | 奥格瑞玛 |
| `.go -4928 -943 501 0` | 铁炉堡 |
| `.go 1642 239 -43 0` | 幽暗城 |
| `.go 5804 624 647 571` | 达拉然 |
| `.go -1850 5431 -10 530` | 沙塔斯 |

### 常用物品 ID

| 物品 ID | 名称 |
|---------|------|
| 6948 | 炉石 |
| 32837 | 埃辛诺斯战刃 (主手) |
| 32838 | 埃辛诺斯战刃 (副手) |
| 36942 | 霜之哀伤 |
| 49623 | 影之哀伤 |
| 34334 | 索利达尔，群星之怒 |
| 19019 | 雷霆之怒，逐风者的祝福之剑 |
| 17182 | 萨弗拉斯，炎魔拉格纳罗斯之手 |

## 模块与脚本

### 模块（`conf/modules/`）

| 模块 | 说明 |
|------|------|
| 1v1arena | 1v1 竞技场 |
| Anticheat | 反作弊 |
| mod_ahbot | 拍卖行机器人 |
| mod_eluna | Lua 脚本引擎 |
| playerbots | 玩家机器人 |
| PvPScript | PvP 脚本 |
| transmog | 幻化 |

### Lua 脚本（`scripts/lua/`）

- `super_hearthstone.lua` — 超级炉石（传送/银行/修理）
- `portable_vendor.lua` — 随身商人

Lua 脚本通过 Eluna 引擎热加载，修改后无需重启容器，worldserver 会检测文件变更自动重载。

### Playerbots 假人系统（`conf/modules/playerbots.conf.dist`）

服务端内置玩家机器人，模拟真实玩家行为。首次启动自动导入基础数据，启动后假人自动登录。

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `AiPlayerbot.Enabled` | 1 | 启用假人系统 |
| `AiPlayerbot.RandomBotAutologin` | 1 | 启动时自动登录随机假人 |
| `AiPlayerbot.MinRandomBots` | 15 | 最少在线假人数 |
| `AiPlayerbot.MaxRandomBots` | 20 | 最多在线假人数 |
| `AiPlayerbot.RandomBotMinLevel` | 1 | 假人最低等级 |
| `AiPlayerbot.RandomBotMaxLevel` | 80 | 假人最高等级 |
| `AiPlayerbot.SyncLevelWithPlayers` | 1 | 与在线玩家等级同步 |
| `AiPlayerbot.RandomBotAllianceRatio` | 50 | 联盟比例 (%) |
| `AiPlayerbot.RandomBotHordeRatio` | 50 | 部落比例 (%) |
| `AiPlayerbot.RandomBotJoinBG` | 1 | 假人参与战场 |
| `AiPlayerbot.RandomBotJoinLfg` | 1 | 假人参与随机副本 |
| `AiPlayerbot.RandomBotGuildCount` | 20 | 假人公会数量 |

**游戏中交互**：
- 聊天框输入私语指令控制队伍中的假人（跟随、攻击、治疗等）
- 假人会自行组队、刷怪、做任务、排战场和副本
- 假人会在世界频道聊天互动

修改配置后重启 worldserver 生效：
```bash
docker compose restart ac-worldserver
```

## Web 注册邮箱配置（可选）

注册页面支持 SMTP 发信，用于密码找回和双因素认证 (2FA)。
配置文件：`WoWRegistration/application/config/config.php`

| 配置项 | 说明 |
|--------|------|
| `smtp_host` | SMTP 服务器地址 |
| `smtp_port` | SMTP 端口 (587 TLS / 465 SSL) |
| `smtp_auth` | 启用 SMTP 认证 (true/false) |
| `smtp_user` | SMTP 邮箱账号 |
| `smtp_pass` | SMTP 邮箱密码或授权码 |
| `smtp_secure` | 加密方式 (tls / ssl) |
| `smtp_mail` | 发件人邮箱地址 |

### 示例

**QQ 邮箱：**
```php
$config['smtp_host'] = 'smtp.qq.com';
$config['smtp_port'] = 465;
$config['smtp_secure'] = 'ssl';
$config['smtp_user'] = 'your-qq@qq.com';
$config['smtp_pass'] = 'QQ邮箱授权码';
$config['smtp_mail'] = 'your-qq@qq.com';
```

**163 邮箱：**
```php
$config['smtp_host'] = 'smtp.163.com';
$config['smtp_port'] = 465;
$config['smtp_secure'] = 'ssl';
$config['smtp_user'] = 'your-account@163.com';
$config['smtp_pass'] = '邮箱授权码';
$config['smtp_mail'] = 'your-account@163.com';
```

**Gmail：**
```php
$config['smtp_host'] = 'smtp.gmail.com';
$config['smtp_port'] = 587;
$config['smtp_secure'] = 'tls';
$config['smtp_user'] = 'your-account@gmail.com';
$config['smtp_pass'] = '应用专用密码';
$config['smtp_mail'] = 'your-account@gmail.com';
```

> 注意：如需启用 2FA，还需将 `$config['2fa_support']` 设为 `true`。

## 客户端连接

1. 将魔兽世界 3.3.5a (12340) 客户端目录下的 `Data/zhCN/realmlist.wtf` 改为：
   ```
   set realmlist 你的服务器IP
   ```
2. 运行 `Wow.exe` 启动游戏
3. 使用 Web 注册页面或 GM 命令创建的账号登录

## 数据持久化

| 数据 | 存储位置 |
|------|----------|
| 游戏数据库（账号/角色/世界） | Docker volume `ac-database-data` |
| 服务端日志 | Docker volume `acore-logs` |
| Lua 脚本 | `./scripts/lua/` (bind mount) |
| 模块配置 | `./conf/modules/` (bind mount) |
| 客户端地图数据 | `./data/` (bind mount) |

## 注意事项

- **Apple Silicon (M1/M2/M3)**：SPK 二进制为 x86_64，需 `export DOCKER_DEFAULT_PLATFORM=linux/amd64`，运行有性能损耗。
- **非源码编译**：`bin/` 和 `lib/` 是预编译的 SPK 二进制，修改服务端行为需改配置或 Lua 脚本。
- **首次启动**：worldserver 需要执行数据库迁移，请耐心等待 1-2 分钟。
- **NAS 部署**：使用 `nas/docker-compose.yml`，镜像从 Docker Hub 拉取（`asm0x1/wow-worldserver` 等），无需本地构建。配置在 YAML 文件顶部用锚点定义，改一处即可。
- **`.env` 已 gitignore**：本地部署使用 `.env.dist` 模板。

## Docker Hub 镜像

| 镜像 | 大小 |
|------|------|
| `asm0x1/wow-worldserver:latest` | ~632MB |
| `asm0x1/wow-authserver:latest` | ~605MB |
| `asm0x1/wow-registration:latest` | ~183MB |

## 依赖

- Docker >= 20.10
- Docker Compose >= 2.0
- 魔兽世界 3.3.5a (12340) 客户端
