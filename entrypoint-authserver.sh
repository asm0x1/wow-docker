#!/bin/bash
# ============================================
# Authserver Entrypoint Script
# 替换配置中的占位符并启动 authserver
# Author: asm0x1
# ============================================

set -e

DB_PASSWORD="${DB_PASSWORD:-wow@asm0x1}"

echo ">> [entrypoint] 初始化 authserver 配置..."

sed "s/__DB_PASSWORD__/${DB_PASSWORD}/g" \
    /opt/wow/etc/authserver.conf.template \
    > /opt/wow/etc/authserver.conf

echo ">> [entrypoint] 数据库: ac-database:3306/acore_auth"
echo ">> [entrypoint] 端口: 3724"
echo ">> [entrypoint] 启动 authserver..."

exec /opt/wow/bin/authserver -c /opt/wow/etc/authserver.conf
