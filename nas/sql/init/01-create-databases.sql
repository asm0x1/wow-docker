-- ============================================
-- AzerothCore 数据库初始化脚本
-- 创建空数据库，worldserver 启动时会自动建表
-- Author: asm0x1
-- ============================================
CREATE DATABASE IF NOT EXISTS `acore_auth` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_characters` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_world` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS `acore_playerbots` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

-- 授权 root 远程访问
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'wow@asm0x1';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
