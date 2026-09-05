"""Read-only metadata for the existing test01/Test03 desktop sync incident.

No message bodies, credentials, device IDs, or attachment URLs are read.
Do not use a copied database without its WAL to diagnose a running client.
"""
import datetime
import json
import pathlib
import sqlite3


DATABASE = pathlib.Path(
    r"C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian"
) / "collaboration-cache.sqlite3"
ACCOUNT = "63bb07f7-89dc-449e-9e49-4b528f5215b7"
CONVERSATION = "2a2ea21f-2ad6-49b3-b3da-407d1e7e4136"


def inspect():
    connection = sqlite3.connect(DATABASE.as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA query_only=ON")
        connection.execute("BEGIN")
        integrity = connection.execute("PRAGMA quick_check").fetchone()[0]
        rows = connection.execute(
            """SELECT id, sequence, client_message_id, delivery_state,
                      created_at, updated_at
               FROM im_messages_cache
               WHERE terminal_account_id=? AND conversation_id=?
               ORDER BY sequence, id""",
            (ACCOUNT, CONVERSATION),
        ).fetchall()
        sync = connection.execute(
            """SELECT messages_synced_at, last_message_sequence
               FROM im_conversation_sync_state
               WHERE terminal_account_id=? AND conversation_id=?""",
            (ACCOUNT, CONVERSATION),
        ).fetchall()
        counts = {}
        for table in ("collaboration_event_cursors", "collaboration_event_inbox"):
            counts[table] = connection.execute(
                f"SELECT COUNT(*) FROM {table} WHERE terminal_account_id=?",
                (ACCOUNT,),
            ).fetchone()[0]
        return {
            "checkedAt": datetime.datetime.now().astimezone().isoformat(),
            "source": "installed-desktop-sqlite-read-only-transaction-not-ui",
            "accountId": ACCOUNT,
            "conversationId": CONVERSATION,
            "integrity": integrity,
            "messages": [dict(row) for row in rows],
            "sync": [dict(row) for row in sync],
            "eventTableCounts": counts,
        }
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        print(json.dumps(inspect(), indent=2))
    except (OSError, sqlite3.Error) as error:
        # Do not include exception text that could reveal unexpected data.
        print(json.dumps({"errorType": type(error).__name__}))
        raise SystemExit(1)
