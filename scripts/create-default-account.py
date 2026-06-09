#!/usr/bin/env python3
"""
AzerothCore 默认管理员账户创建脚本
计算 SRP6 salt/verifier 并写入 acore_auth 数据库
Author: asm0x1
"""
import hashlib
import os
import sys
import time
import pymysql

# ============================================
# 从环境变量读取配置
# ============================================
DB_HOST = os.environ.get("DB_HOST", "ac-database")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "root")
DB_PASS = os.environ.get("DB_PASS", "wow@asm0x1")
DB_NAME = os.environ.get("DB_NAME", "acore_auth")

ACCOUNT_USER = os.environ.get("DEFAULT_ACCOUNT_USER", "")
ACCOUNT_PASS = os.environ.get("DEFAULT_ACCOUNT_PASS", "")
ACCOUNT_GMLEVEL = int(os.environ.get("DEFAULT_ACCOUNT_GMLEVEL", "3"))
ACCOUNT_EXPANSION = int(os.environ.get("DEFAULT_ACCOUNT_EXPANSION", "2"))


def calculate_srp6_verifier(username: str, password: str, salt: bytes) -> bytes:
    """
    计算 SRP6 verifier，兼容 AzerothCore。
    算法与 WoWSimpleRegistration PHP 版本一致：
    - g = 7
    - N = AzerothCore 标准大素数
    - h1 = SHA1(UPPER(username) + ':' + UPPER(password))
    - h2 = SHA1(salt + h1)  (AzerothCore 不使用 strrev)
    - verifier = g^h2 mod N
    """
    g = 7
    N = 0x894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7

    # h1 = SHA1(UPPER(username) + ':' + UPPER(password))
    h1_input = f"{username.upper()}:{password.upper()}".encode()
    h1 = hashlib.sha1(h1_input).digest()

    # h2 = SHA1(salt + h1)
    h2 = hashlib.sha1(salt + h1).digest()

    # 转换为整数 (little-endian)
    h2_int = int.from_bytes(h2, "little")

    # verifier = g^h2 mod N
    verifier_int = pow(g, h2_int, N)

    # 转换回字节 (little-endian), 补零到 32 字节
    verifier_bytes = verifier_int.to_bytes(32, "little")
    return verifier_bytes


def wait_for_table(conn, table_name: str, timeout: int = 300) -> bool:
    """等待数据库表存在"""
    start = time.time()
    while time.time() - start < timeout:
        try:
            with conn.cursor() as cur:
                cur.execute(f"SELECT 1 FROM `{table_name}` LIMIT 1")
                return True
        except Exception:
            pass
        print(f"  等待表 {table_name} 就绪... ({int(time.time() - start)}s/{timeout}s)")
        time.sleep(5)
    return False


def main():
    print("============================================")
    print("   AzerothCore 默认账户初始化")
    print("============================================")

    # 检查是否配置了默认账户
    if not ACCOUNT_USER or not ACCOUNT_PASS:
        print("!! 未配置 DEFAULT_ACCOUNT_USER / DEFAULT_ACCOUNT_PASS，跳过默认账户创建")
        print("!! 在 .env 文件中设置这两个变量以启用自动创建")
        return

    print(f"  数据库: {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print(f"  账户名: {ACCOUNT_USER}")
    print(f"  GM 等级: {ACCOUNT_GMLEVEL}")
    print("============================================")

    # 连接数据库 (重试直到成功)
    conn = None
    for attempt in range(1, 61):
        try:
            conn = pymysql.connect(
                host=DB_HOST,
                port=DB_PORT,
                user=DB_USER,
                password=DB_PASS,
                database=DB_NAME,
                charset="utf8mb4",
            )
            print(f">> 数据库连接成功 (尝试 {attempt})")
            break
        except Exception as e:
            print(f"  等待数据库就绪... ({attempt}/60): {e}")
            time.sleep(5)
    else:
        print("!! 无法连接数据库，超时退出")
        sys.exit(1)

    try:
        # 等待 account 表就绪
        if not wait_for_table(conn, "account"):
            print("!! account 表未在超时时间内就绪")
            sys.exit(1)
        print(">> account 表已就绪")

        # 检查账户是否已存在 (幂等)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT `id` FROM `account` WHERE `username` = %s",
                (ACCOUNT_USER.upper(),),
            )
            existing = cur.fetchone()

        if existing:
            account_id = existing[0]
            print(f">> 账户 '{ACCOUNT_USER}' 已存在 (id={account_id})，跳过创建")

            # 仍然确保 account_access 权限正确
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT `gmlevel` FROM `account_access` WHERE `id` = %s AND `RealmID` = -1",
                    (account_id,),
                )
                access = cur.fetchone()
                if access:
                    if access[0] != ACCOUNT_GMLEVEL:
                        cur.execute(
                            "UPDATE `account_access` SET `gmlevel` = %s WHERE `id` = %s AND `RealmID` = -1",
                            (ACCOUNT_GMLEVEL, account_id),
                        )
                        conn.commit()
                        print(f">> GM 等级已更新为 {ACCOUNT_GMLEVEL}")
                    else:
                        print(f">> GM 等级已是 {ACCOUNT_GMLEVEL}，无需更新")
                else:
                    cur.execute(
                        "INSERT INTO `account_access` (`id`, `gmlevel`, `RealmID`, `comment`) VALUES (%s, %s, -1, %s)",
                        (account_id, ACCOUNT_GMLEVEL, "Default admin account"),
                    )
                    conn.commit()
                    print(f">> 已添加 account_access 记录 (GM Level {ACCOUNT_GMLEVEL})")
            return

        # 生成随机 salt
        salt = os.urandom(32)

        # 计算 SRP6 verifier
        verifier = calculate_srp6_verifier(ACCOUNT_USER, ACCOUNT_PASS, salt)

        print(f">> SRP6 salt/verifier 已计算")

        # 插入 account 记录
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO `account`
                   (`username`, `salt`, `verifier`, `email`, `expansion`)
                   VALUES (%s, %s, %s, %s, %s)""",
                (
                    ACCOUNT_USER.upper(),
                    salt,
                    verifier,
                    f"{ACCOUNT_USER}@localhost",
                    ACCOUNT_EXPANSION,
                ),
            )
            account_id = cur.lastrowid
            conn.commit()

        print(f">> 账户 '{ACCOUNT_USER}' 已创建 (id={account_id})")

        # 等待 account_access 表就绪 (可能稍晚于 account 表创建)
        if not wait_for_table(conn, "account_access", timeout=60):
            print("!! account_access 表未就绪，跳过 GM 权限设置")
            print("!! 请手动执行: account set gmlevel {ACCOUNT_USER} 3 -1")
            return

        # 插入 account_access 记录 (GM Level 3, 所有 Realm)
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO `account_access` (`id`, `gmlevel`, `RealmID`, `comment`)
                   VALUES (%s, %s, -1, %s)""",
                (account_id, ACCOUNT_GMLEVEL, "Default admin account"),
            )
            conn.commit()

        print(f">> GM 权限已设置 (Level {ACCOUNT_GMLEVEL}, 所有 Realm)")
        print("============================================")
        print("   默认管理员账户创建完成!")
        print(f"   用户名: {ACCOUNT_USER}")
        print(f"   密码:   {ACCOUNT_PASS}")
        print(f"   GM:     Level {ACCOUNT_GMLEVEL}")
        print("============================================")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
