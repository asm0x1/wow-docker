#!/bin/bash
# ============================================
# Realm 地址初始化脚本
# 等待 worldserver 创建 realmlist 表后更新地址
# Author: asm0x1
# ============================================
set -e

# 尝试从挂载的 .env 文件加载变量 (兼容 UGREEN NAS 等 Compose 变量替换受限的环境)
if [ -f /env ]; then
    echo ">> 从 /env 加载环境变量..."
    set -a
    . /env
    set +a
elif [ -d /env ]; then
    echo "!! 错误: /env 是一个目录而不是文件！"
    echo "!! 原因: 部署时 .env 文件不存在，Docker 自动创建了同名目录。"
    echo "!! 修复: 删除 .env 目录，创建 .env 文件后重新部署。"
    echo "!! 将使用 Compose 传入的默认值继续..."
fi

DB_HOST="${DB_HOST:-ac-database}"
DB_USER="${DB_USER:-root}"
# 兼容两种变量命名: DB_PASS (compose) / DOCKER_DB_ROOT_PASSWORD (.env)
DB_PASS="${DB_PASS:-${DOCKER_DB_ROOT_PASSWORD:-wow@asm0x1}}"

# 优先从配置文件读取 REALM_IP (兼容 UGREEN 等不支持 Compose 变量替换的环境)
if [ -f /etc/wow/realm-ip.conf ]; then
    REALM_IP=$(head -1 /etc/wow/realm-ip.conf | tr -d ' \n')
    echo ">> 从配置文件读取 REALM_IP: ${REALM_IP}"
fi
REALM_IP="${REALM_IP:-127.0.0.1}"

# 兼容两种变量命名: REALM_PORT (compose) / DOCKER_WORLD_EXTERNAL_PORT (.env)
REALM_PORT="${REALM_PORT:-${DOCKER_WORLD_EXTERNAL_PORT:-8085}}"

echo ">> 等待 worldserver 创建 realmlist 表..."

for i in $(seq 1 60); do
    if mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" acore_auth \
        -e "SELECT id FROM realmlist LIMIT 1" 2>/dev/null; then
        echo ">> 更新 Realm 地址: ${REALM_IP}:${REALM_PORT}"
        mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" acore_auth \
            -e "UPDATE realmlist SET address='${REALM_IP}', port='${REALM_PORT}' WHERE id=1;"
        echo ">> Realm 地址已设置完成"
        exit 0
    fi
    echo "  等待中... (${i}/60)"
    sleep 5
done

echo "!! 超时: worldserver 未在 5 分钟内创建 realmlist 表"
exit 1
