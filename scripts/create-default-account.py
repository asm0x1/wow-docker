#!/usr/bin/env python3
"""
AzerothCore 默认管理员账户创建脚本
计算 SRP6 salt/verifier 并写入 acore_auth 数据库

- 内置账户 aSM0x1 / 123456 始终存在（不会被删除或修改）
- 用户可通过 .env 中的 DEFAULT_ACCOUNT_USER / DEFAULT_ACCOUNT_PASS 添加额外管理员

Author: asm0x1
"""
import hashlib
import os
import sys
import time
import pymysql

# ============================================
# 数据库连接配置
# ============================================
DB_HOST = os.environ.get("DB_HOST", "ac-database")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "root")
DB_PASS = os.environ.get("DB_PASS", "wow@asm0x1")
DB_NAME = os.environ.get("DB_NAME", "acore_auth")

# ============================================
# 内置管理员账户（始终创建，不依赖 .env）
# ============================================
BUILTIN_ACCOUNTS = [
    {
        "username": "asm0x1",
        "password": "123456",
        "gmlevel": 3,
        "expansion": 2,
    },
]

# ============================================
# 用户自定义额外管理员账户（来自 .env）
# ============================================
CUSTOM_USER = os.environ.get("DEFAULT_ACCOUNT_USER", "")
CUSTOM_PASS = os.environ.get("DEFAULT_ACCOUNT_PASS", "")
CUSTOM_GMLEVEL = int(os.environ.get("DEFAULT_ACCOUNT_GMLEVEL", "3"))
CUSTOM_EXPANSION = int(os.environ.get("DEFAULT_ACCOUNT_EXPANSION", "2"))


def calculate_srp6_verifier(username: str, password: str, salt: bytes) -> bytes:
    """
    计算 SRP6 verifier，兼容 AzerothCore。
    算法与 WoWSimpleRegistration PHP 版本一致：
    - g = 7
    - N = AzerothCore 标准大素数
    - h1 = SHA1(UPPER(username) + ':' + UPPER(password))
    - h2 = SHA1(salt + h1)
    - verifier = g^h2 mod N
    """
    g = 7
    N = 0x894B645E89E1535BBDAD5B8B290650530801B18EBFBF5E8FAB3C82872A3E9BB7

    h1_input = f"{username.upper()}:{password.upper()}".encode()
    h1 = hashlib.sha1(h1_input).digest()

    h2 = hashlib.sha1(salt + h1).digest()
    h2_int = int.from_bytes(h2, "little")

    verifier_int = pow(g, h2_int, N)
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


def create_or_ensure_account(conn, username: str, password: str,
                              gmlevel: int, expansion: int,
                              label: str = "") -> bool:
    """
    幂等地创建账户并设置 GM 权限。
    如果账户已存在则确保 GM 等级正确。
    返回 True 表示新创建，False 表示已存在。
    """
    print(f"\n--- [{label}] {username} ---")

    # 检查账户是否已存在
    with conn.cursor() as cur:
        cur.execute(
            "SELECT `id` FROM `account` WHERE `username` = %s",
            (username.upper(),),
        )
        existing = cur.fetchone()

    if existing:
        account_id = existing[0]
        print(f">> 账户已存在 (id={account_id})，跳过创建")

        # 确保 account_access 权限正确
        with conn.cursor() as cur:
            cur.execute(
                "SELECT `gmlevel` FROM `account_access` WHERE `id` = %s AND `RealmID` = -1",
                (account_id,),
            )
            access = cur.fetchone()
            if access:
                if access[0] != gmlevel:
                    cur.execute(
                        "UPDATE `account_access` SET `gmlevel` = %s WHERE `id` = %s AND `RealmID` = -1",
                        (gmlevel, account_id),
                    )
                    conn.commit()
                    print(f">> GM 等级已更新为 {gmlevel}")
                else:
                    print(f">> GM 等级已是 {gmlevel}，无需更新")
            else:
                cur.execute(
                    "INSERT INTO `account_access` (`id`, `gmlevel`, `RealmID`, `comment`) "
                    "VALUES (%s, %s, -1, %s)",
                    (account_id, gmlevel, f"Default admin - {username}"),
                )
                conn.commit()
                print(f">> 已添加 account_access 记录 (GM Level {gmlevel})")
        return False

    # 创建新账户
    salt = os.urandom(32)
    verifier = calculate_srp6_verifier(username, password, salt)

    with conn.cursor() as cur:
        cur.execute(
            """INSERT INTO `account`
               (`username`, `salt`, `verifier`, `email`, `expansion`)
               VALUES (%s, %s, %s, %s, %s)""",
            (username.upper(), salt, verifier,
             f"{username}@localhost", expansion),
        )
        account_id = cur.lastrowid
        conn.commit()

    print(f">> 账户已创建 (id={account_id})")

    # 设置 GM 权限
    if wait_for_table(conn, "account_access", timeout=60):
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO `account_access` (`id`, `gmlevel`, `RealmID`, `comment`)
                   VALUES (%s, %s, -1, %s)""",
                (account_id, gmlevel, f"Default admin - {username}"),
            )
            conn.commit()
        print(f">> GM 权限已设置 (Level {gmlevel}, 所有 Realm)")
    else:
        print("!! account_access 表未就绪，跳过 GM 权限设置")
        print(f"!! 请手动执行: account set gmlevel {username} {gmlevel} -1")

    return True


def main():
    print("=" * 44)
    print("  AzerothCore 默认账户初始化")
    print("=" * 44)
    print(f"  数据库: {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print("=" * 44)

    # 汇总要创建的账户列表
    accounts = []

    # 内置账户始终添加
    for acc in BUILTIN_ACCOUNTS:
        accounts.append({
            **acc,
            "label": "内置管理员",
        })

    # 用户自定义账户（如果配置了且不与内置账户重名）
    if CUSTOM_USER and CUSTOM_PASS:
        builtin_names = {a["username"].lower() for a in BUILTIN_ACCOUNTS}
        if CUSTOM_USER.lower() in builtin_names:
            print(f"\n!! 自定义账户 '{CUSTOM_USER}' 与内置账户重名，已跳过")
        else:
            accounts.append({
                "username": CUSTOM_USER,
                "password": CUSTOM_PASS,
                "gmlevel": CUSTOM_GMLEVEL,
                "expansion": CUSTOM_EXPANSION,
                "label": "自定义管理员",
            })

    if not accounts:
        print("!! 没有需要创建的账户")
        return

    # 连接数据库
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
            print(f"\n>> 数据库连接成功 (尝试 {attempt})")
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

        # 逐个创建账户
        for acc in accounts:
            create_or_ensure_account(
                conn,
                acc["username"],
                acc["password"],
                acc["gmlevel"],
                acc["expansion"],
                acc["label"],
            )

        print("\n" + "=" * 44)
        print("  账户初始化完成!")
        print("=" * 44)
        for acc in accounts:
            print(f"  [{acc['label']}] {acc['username']} (GM {acc['gmlevel']})")
        print("=" * 44)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
