# 绿联 NAS 部署 AzerothCore 开源游戏服务端实践

> 一次在家用 NAS 上部署 Docker 容器化游戏服务端的技术记录，涵盖 Compose 编排、数据库管理、网络配置等实战经验。

---

## 前言

[AzerothCore](https://www.azerothcore.org/) 是一个采用 **AGPL v3.0 开源协议**的游戏服务器框架，由全球开发者社区共同维护。它不包含任何受版权保护的游戏资源（模型、贴图、音乐等），仅实现了网络通信与游戏逻辑模拟的服务器端功能。

本文记录我在绿联 NAS 上通过 Docker 部署该框架的技术过程，涉及容器编排、服务依赖管理、数据库迁移等常见 DevOps 场景，适合对 Docker 和家庭服务器感兴趣的读者参考。

> **声明：** 本文仅用于技术学习与交流。请遵守当地法律法规及游戏用户协议。本文不提供任何游戏客户端资源的获取方式。

---

## 项目结构

采用 Docker Compose 管理多服务依赖，运行时共 4 个容器：

```
ac-database (MariaDB 10.11)
    ├─► ac-worldserver (游戏世界服务器)
    │       └─► ac-authserver (认证登录服务器 + 自动初始化)
    └─► ac-registration (Web 注册页面, PHP 8.2)
```

**技术栈一览：**

| 组件 | 技术 |
|------|------|
| 数据库 | MariaDB 10.11 |
| 服务器 | C++ 编译的 AzerothCore 二进制 |
| Web | Apache 2.4 + PHP 8.2 |
| 容器编排 | Docker Compose v3 |
| 脚本 | Bash (entrypoint 自动初始化) |

---

## 部署步骤

### 1. 准备地图数据

首先需要客户端地图数据（服务端加载世界场景用）。这部分需要自行查阅 AzerothCore 社区文档，使用地图提取工具从游戏客户端导出。

将提取的数据放入项目目录：

```
docker/wow/
└── data/
    ├── maps/
    ├── dbc/
    ├── vmaps/
    ├── mmaps/
    └── cameras/
```

> 地图数据约 2-3GB，不包含在项目仓库中。

### 2. 修改配置

编辑 `nas/docker-compose.yml` 顶部，只需修改两个值：

```yaml
x-deploy-config:
  REALM_IP:      &REALM_IP      192.168.1.100   # ← 改成 NAS 的局域网 IP
  DB_ROOT_PASS:  &DB_ROOT_PASS  wow@asm0x1       # 数据库密码，按需修改
```

项目使用 YAML 锚点（`&name` / `*name`）实现配置集中管理——顶部定义一次，下方所有服务自动引用，告别"一处改、处处改"的维护噩梦。

### 3. 部署

**绿联 NAS（Docker → 项目 → 新建项目）：**

1. 项目名称：`wow`
2. 项目文件夹：选择步骤 1 创建的目录
3. 将修改后的 `nas/docker-compose.yml` 粘贴到编辑器
4. 点击「部署」

首次部署自动从 Docker Hub 拉取镜像，约 5-10 分钟。

**其他支持 Docker Compose 的环境（命令行）：**

```bash
docker compose -f nas/docker-compose.yml up -d
```

---

## 关键技术细节

### 容器启动顺序与依赖管理

服务间有严格的启动顺序依赖，通过 `depends_on` + `healthcheck` 实现：

```yaml
ac-worldserver:
  depends_on:
    ac-database:
      condition: service_healthy  # 等待数据库健康检查通过
```

入口脚本 `entrypoint-worldserver.sh` 在启动时自动完成：
- 数据库创建（`CREATE DATABASE IF NOT EXISTS`）
- 配置文件模板渲染（`sed` 替换占位符）
- 数据完整性修复（如缺失路径点的生物自动修正）
- 模块配置生成

这种 "entrypoint 自动化" 模式避免了手动执行 SQL 脚本的繁琐操作。

### NAS 环境的特殊处理

部分 NAS 的 Docker UI 不支持 Compose 的 `${VAR:-default}` 变量替换语法。项目采用了**锚点 + 直接值**的方案，彻底规避此问题：

```yaml
# ❌ 不可靠的写法（依赖 Compose 解析 .env）
environment:
  REALM_IP: ${REALM_IP:-127.0.0.1}

# ✅ 可靠的写法（锚点引用 + 直接值）
x-deploy-config:
  REALM_IP: &REALM_IP 192.168.1.100

environment:
  REALM_IP: *REALM_IP
```

### 数据持久化

所有持久数据存储在 Docker 命名卷 `ac-database-data` 中，包括账户、角色、世界状态等。容器删除后数据依然保留，重新部署自动恢复。

如需完全重置，删除项目时勾选「同时删除卷」。

---

## 防火墙配置

确保 NAS 防火墙放行以下端口：

| 端口 | 协议 | 用途 |
|------|------|------|
| 3724 | TCP | 游戏登录认证 |
| 8085 | TCP | 游戏世界通信 |
| 8765 | TCP | Web 注册页面 |

> 常见问题：只放了 3724 而忽略 8085，导致能登录但进不去游戏世界。

---

## 日常运维

### 调整服务参数

编辑 YAML 中 `x-bot-config` 部分，修改后重新部署：

```yaml
x-bot-config:
  BOT_MIN_COUNT:     10   # AI 玩家最小在线数
  BOT_MAX_COUNT:     30   # AI 玩家最大在线数
```

### 查看日志

命令行环境下：

```bash
docker compose -f nas/docker-compose.yml logs -f ac-worldserver
```

绿联 Docker UI：点击容器 → 日志。

### 更新镜像

1. 删除旧容器和镜像
2. 重新部署，自动拉取最新 `asm0x1/wow-*` 镜像

---

## 踩坑记录

1. **Apple Silicon Mac 本地开发**：需要 `export DOCKER_DEFAULT_PLATFORM=linux/amd64`，因为二进制是 x86_64 编译的
2. **NAS 上 `realmlist` 地址错误**：客户端能登录但进不去世界——排查发现 `REALM_IP` 配错了，改对后问题消失
3. **端口没放全**：NAS 防火墙容易只放 3724 忽略 8085，导致"能选服不能进"的尴尬

---

## 总结

通过这个项目，可以实践以下 Docker/DevOps 技能：

- **多容器编排**：服务依赖、健康检查、启动顺序
- **配置管理**：YAML 锚点、模板渲染、环境变量注入
- **数据持久化**：Docker 卷、数据库备份
- **网络调试**：端口映射、防火墙规则、客户端-服务端通信

对于一个家庭 NAS 来说，这也是检验其性能的好机会——2-3GB 地图数据加载、数百 MB 内存占用、多客户端并发连接，对 CPU 和磁盘 I/O 都是不小的考验。

---

> **关于 AzerothCore：** 这是一个采用 AGPL v3.0 协议的开源项目，源代码完全公开，不含任何受版权保护的游戏素材。所有代码由社区贡献者出于技术研究目的编写。本项目仅涉及服务端框架的技术部署，使用前请确保你了解并遵守适用的法律、法规及用户协议。
