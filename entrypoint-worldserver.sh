#!/bin/bash
# ============================================
# Worldserver Entrypoint Script
# 替换配置中的占位符并启动 worldserver
# Author: asm0x1
# ============================================

set -e

DB_PASSWORD="${DB_PASSWORD:-wow@asm0x1}"

echo ">> [entrypoint] 初始化 worldserver 配置..."

# ============================================
# 确保数据库存在 (MariaDB 容器启动时无 init 脚本)
# ============================================
echo ">> [entrypoint] 创建数据库 (如不存在)..."
mariadb -h ac-database -uroot -p"${DB_PASSWORD}" <<'EOSQL'
CREATE DATABASE IF NOT EXISTS `acore_auth` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_characters` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_world` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_playerbots` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOSQL
echo ">> [entrypoint] 数据库检查完成"

# 从模板生成实际配置
sed "s/__DB_PASSWORD__/${DB_PASSWORD}/g" \
    /opt/wow/etc/worldserver.conf.template \
    > /opt/wow/etc/worldserver.conf

# 生成模块配置（从 .conf.dist 模板替换占位符）
BOT_MIN_COUNT="${BOT_MIN_COUNT:-15}"
BOT_MAX_COUNT="${BOT_MAX_COUNT:-20}"
BOT_MIN_LEVEL="${BOT_MIN_LEVEL:-1}"
BOT_MAX_LEVEL="${BOT_MAX_LEVEL:-80}"
BOT_ALLIANCE_RATIO="${BOT_ALLIANCE_RATIO:-50}"
BOT_HORDE_RATIO="${BOT_HORDE_RATIO:-50}"

for template in /opt/wow/etc/modules/*.conf.dist; do
    [ -f "$template" ] || continue
    target="${template%.dist}"
    echo ">> [entrypoint] 生成模块配置: $(basename "$target")"
    sed -e "s/__BOT_MIN_COUNT__/${BOT_MIN_COUNT}/g" \
        -e "s/__BOT_MAX_COUNT__/${BOT_MAX_COUNT}/g" \
        -e "s/__BOT_MIN_LEVEL__/${BOT_MIN_LEVEL}/g" \
        -e "s/__BOT_MAX_LEVEL__/${BOT_MAX_LEVEL}/g" \
        -e "s/__BOT_ALLIANCE_RATIO__/${BOT_ALLIANCE_RATIO}/g" \
        -e "s/__BOT_HORDE_RATIO__/${BOT_HORDE_RATIO}/g" \
        "$template" > "$target"
done

# ============================================
# 修复没有路径点的生物（MovementType=2 → 随机移动）
# 确保所有 waypoint 生物都有对应数据，否则改为随机移动
# ============================================
echo ">> [entrypoint] 检查并修复缺失路径点的生物..."
mariadb -h ac-database -uroot -p"${DB_PASSWORD}" acore_world <<'EOSQL'
UPDATE creature c
LEFT JOIN waypoint_data w ON c.id1 = w.id
SET c.MovementType = 1, c.wander_distance = 5
WHERE c.MovementType = 2 AND w.id IS NULL;
EOSQL
echo ">> [entrypoint] 路径点检查完成"

# ============================================
# 导入 Playerbots 数据库基础表结构
# 原 SPK 预装了 MariaDB 数据目录，Docker 需要手动处理
# ============================================
PLAYERBOTS_BASE="/opt/wow/database/modules/mod-playerbots/data/sql/playerbots/base"
if [ -d "$PLAYERBOTS_BASE" ]; then
    echo ">> [entrypoint] 检查 Playerbots 基础表..."
    if ! mariadb -h ac-database -uroot -p"${DB_PASSWORD}" acore_playerbots \
        -e "SELECT 1 FROM ai_playerbot_texts LIMIT 1" 2>/dev/null; then
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
