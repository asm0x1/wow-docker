#!/bin/bash
# ============================================
# Worldserver Entrypoint Script
# 替换配置中的占位符并启动 worldserver
# Author: asm0x1
# ============================================

set -e

DB_PASSWORD="${DB_PASSWORD:-wow@asm0x1}"

echo ">> [entrypoint] 初始化 worldserver 配置..."

# 从模板生成实际配置
sed "s/__DB_PASSWORD__/${DB_PASSWORD}/g" \
    /opt/wow/etc/worldserver.conf.template \
    > /opt/wow/etc/worldserver.conf

# ============================================
# 导入 Playerbots 数据库基础表结构
# 原 SPK 预装了 MariaDB 数据目录，Docker 需要手动处理
# ============================================
PLAYERBOTS_BASE="/opt/wow/database/modules/mod-playerbots/data/sql/playerbots/base"
if [ -d "$PLAYERBOTS_BASE" ]; then
    echo ">> [entrypoint] 检查 Playerbots 基础表..."
    if ! mariadb -h ac-database -uroot -p"${DB_PASSWORD}" acore_playerbots \
        -e "SELECT 1 FROM version_db_playerbots LIMIT 1" 2>/dev/null; then
        echo ">> [entrypoint] 导入 Playerbots 基础表..."
        for sql_file in "$PLAYERBOTS_BASE"/*.sql; do
            echo "   - $(basename "$sql_file")"
            mariadb -h ac-database -uroot -p"${DB_PASSWORD}" acore_playerbots < "$sql_file" 2>/dev/null
        done
        echo ">> [entrypoint] Playerbots 基础表导入完成"
    else
        echo ">> [entrypoint] Playerbots 基础表已存在，跳过导入"
    fi
fi

echo ">> [entrypoint] 数据库: ac-database:3306, 数据库: acore_auth/acore_characters/acore_world"
echo ">> [entrypoint] 端口: 8085 (world), 7878 (SOAP)"
echo ">> [entrypoint] Lua脚本: /opt/wow/lua_scripts/"
echo ">> [entrypoint] 模块配置: /opt/wow/etc/modules/"
echo ">> [entrypoint] 启动 worldserver..."

exec /opt/wow/bin/worldserver -c /opt/wow/etc/worldserver.conf
