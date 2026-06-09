#!/bin/bash
# ============================================
# Realm 地址初始化脚本
# 等待 worldserver 创建 realmlist 表后更新地址
# Author: asm0x1
# ============================================
set -e

DB_HOST="${DB_HOST:-ac-database}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-wow@asm0x1}"
REALM_IP="${REALM_IP:-127.0.0.1}"
REALM_PORT="${REALM_PORT:-8085}"

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
