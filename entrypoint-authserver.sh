#!/bin/bash
# ============================================
# Authserver Entrypoint Script
# 1. 配置 authserver
# 2. 初始化 Realm 地址（等待 worldserver 建表）
# 3. 创建默认管理员账户
# 4. 启动 authserver
# Author: asm0x1
# ============================================

set -e

DB_PASSWORD="${DB_PASSWORD:-wow@asm0x1}"
DB_HOST="${DB_HOST:-ac-database}"
DB_USER="${DB_USER:-root}"
REALM_IP="${REALM_IP:-127.0.0.1}"
REALM_PORT="${REALM_PORT:-8085}"

echo ">> [entrypoint] 初始化 authserver 配置..."

sed "s/__DB_PASSWORD__/${DB_PASSWORD}/g" \
    /opt/wow/etc/authserver.conf.template \
    > /opt/wow/etc/authserver.conf

# ============================================
# Realm 地址初始化
# ============================================
echo ">> [entrypoint] 等待 worldserver 创建 realmlist 表..."

for i in $(seq 1 60); do
    if mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" acore_auth \
        -e "SELECT id FROM realmlist LIMIT 1" 2>/dev/null; then
        echo ">> [entrypoint] 更新 Realm 地址: ${REALM_IP}:${REALM_PORT}"
        mariadb -h "$DB_HOST" -u"$DB_USER" -p"$DB_PASSWORD" acore_auth \
            -e "UPDATE realmlist SET address='${REALM_IP}', port='${REALM_PORT}' WHERE id=1;"
        echo ">> [entrypoint] Realm 地址已设置完成"
        break
    fi
    echo "  等待 realmlist 表... (${i}/60)"
    sleep 5
done

# ============================================
# 默认管理员账户创建
# ============================================
echo ">> [entrypoint] 创建默认管理员账户..."

DB_NAME="${DB_NAME:-acore_auth}"
DEFAULT_ACCOUNT_USER="${DEFAULT_ACCOUNT_USER:-}"
DEFAULT_ACCOUNT_PASS="${DEFAULT_ACCOUNT_PASS:-}"
DEFAULT_ACCOUNT_GMLEVEL="${DEFAULT_ACCOUNT_GMLEVEL:-3}"
DEFAULT_ACCOUNT_EXPANSION="${DEFAULT_ACCOUNT_EXPANSION:-2}"

python3 /opt/wow/create-account.py

echo ">> [entrypoint] 数据库: ${DB_HOST}:3306/acore_auth"
echo ">> [entrypoint] 端口: 3724"
echo ">> [entrypoint] 启动 authserver..."

exec /opt/wow/bin/authserver -c /opt/wow/etc/authserver.conf
