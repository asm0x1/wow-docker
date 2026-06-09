#!/bin/bash
# ============================================
# Realm 地址初始化脚本
# 等待 worldserver 创建 realmlist 表后更新地址
# Author: asm0x1
# ============================================
#
# REALM_IP 读取优先级（从高到低）：
#   1. /env 文件（如果挂载了 .env → /env）
#   2. /etc/wow/realm-ip.conf（单行纯 IP 文件，NAS 兼容）
#   3. 环境变量 REALM_IP（Compose environment: 传入）
#   4. 默认值 127.0.0.1
# ============================================
set -e

# ---- 第1优先级：从挂载的 .env 文件加载 ----
if [ -f /env ]; then
    echo ">> [realm-init] 从 /env 加载环境变量..."
    set -a
    . /env
    set +a
    echo ">> [realm-init] REALM_IP=${REALM_IP:-<未设置>} (来源: /env)"
fi

# ---- 第2优先级：从纯文本配置文件读取 ----
if [ -f /etc/wow/realm-ip.conf ]; then
    FILE_IP=$(head -1 /etc/wow/realm-ip.conf | tr -d ' \n')
    if [ -n "$FILE_IP" ]; then
        echo ">> [realm-init] 从配置文件读取 REALM_IP: ${FILE_IP}"
        REALM_IP="$FILE_IP"
    fi
fi

# ---- 回退：环境变量或默认值 ----
DB_HOST="${DB_HOST:-ac-database}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-${DOCKER_DB_ROOT_PASSWORD:-wow@asm0x1}}"
REALM_IP="${REALM_IP:-127.0.0.1}"
REALM_PORT="${REALM_PORT:-${DOCKER_WORLD_EXTERNAL_PORT:-8085}}"

echo ">> [realm-init] 最终配置: ${REALM_IP}:${REALM_PORT}"
echo ">> [realm-init] 等待 worldserver 创建 realmlist 表..."

for i in $(seq 1 60); do
    if mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" acore_auth \
        -e "SELECT id FROM realmlist LIMIT 1" 2>/dev/null; then
        echo ">> [realm-init] 更新 Realm 地址: ${REALM_IP}:${REALM_PORT}"
        mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASS" acore_auth \
            -e "UPDATE realmlist SET address='${REALM_IP}', port='${REALM_PORT}' WHERE id=1;"
        echo ">> [realm-init] Realm 地址已设置完成"
        exit 0
    fi
    echo "  等待中... (${i}/60)"
    sleep 5
done

echo "!! [realm-init] 超时: worldserver 未在 5 分钟内创建 realmlist 表"
exit 1
