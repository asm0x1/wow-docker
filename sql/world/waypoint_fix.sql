-- ============================================
-- 修复没有路径点数据的生物
-- 将所有 MovementType=2 (waypoint) 但无 waypoint_data 的生物
-- 改为 MovementType=1 (随机移动)，半径 5 码
-- Author: asm0x1
-- ============================================

UPDATE creature c
LEFT JOIN waypoint_data w ON c.id1 = w.id
SET c.MovementType = 1, c.wander_distance = 5
WHERE c.MovementType = 2 AND w.id IS NULL;
