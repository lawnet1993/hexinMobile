"""Read-only consistent SQLite snapshot; emit only grouped presence times."""
import json
import pathlib
import sqlite3
import subprocess
import tempfile

ADB = r"C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe"
PACKAGE = "com.hexing.zhilian.hexing_terminal_mobile"
DATABASE = "hexing-mobile-test-2496f299b56989b204541161-im.db"


def read(name):
    result = subprocess.run(
        [ADB, "-s", "dd00d66d", "exec-out", "run-as", PACKAGE,
         "cat", "databases/" + name], capture_output=True,
    )
    if result.returncode:
        raise RuntimeError("Snapshot unavailable")
    return result.stdout


def inspect():
    for _ in range(3):
        wal_before = read(DATABASE + "-wal")
        body = read(DATABASE)
        wal = read(DATABASE + "-wal")
        if wal_before == wal and body == read(DATABASE):
            break
    else:
        raise RuntimeError("Snapshot changed")
    # Temporary encrypted pages only; original DB is never opened for write.
    with tempfile.TemporaryDirectory(prefix="sa-presence-times-") as folder:
        target = pathlib.Path(folder) / DATABASE
        target.write_bytes(body)
        target.with_name(DATABASE + "-wal").write_bytes(wal)
        connection = sqlite3.connect(target.as_uri() + "?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        try:
            result = {}
            for table in ("im_members", "im_conversation_members"):
                rows = connection.execute(
                    "SELECT last_seen_at, COUNT(*) AS count FROM " + table +
                    " GROUP BY last_seen_at ORDER BY last_seen_at LIMIT 30"
                ).fetchall()
                result[table] = [dict(row) for row in rows]
            return result
        finally:
            connection.close()


if __name__ == "__main__":
    try:
        print(json.dumps(inspect(), ensure_ascii=False))
    except Exception:
        print('{"inspection":"unavailable"}')
        raise SystemExit(1)
