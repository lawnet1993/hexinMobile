"""Read-only metadata for the existing test01/Test03 desktop sync incident.

No message bodies, credentials, device IDs, or attachment URLs are read.
Do not use a copied database without its WAL to diagnose a running client.
"""
import argparse
import datetime
import json
import pathlib
import re
import sqlite3


DATABASE = pathlib.Path(
    r"C:\Users\86137\AppData\Roaming\com.jiucyun.hexingzhilian"
) / "collaboration-cache.sqlite3"
ACCOUNT = "63bb07f7-89dc-449e-9e49-4b528f5215b7"
DEFAULT_CONVERSATION = "2a2ea21f-2ad6-49b3-b3da-407d1e7e4136"
UUID_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)


def inspect(conversation_id: str):
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
            (ACCOUNT, conversation_id),
        ).fetchall()
        sync = connection.execute(
            """SELECT messages_synced_at, last_message_sequence
               FROM im_conversation_sync_state
               WHERE terminal_account_id=? AND conversation_id=?""",
            (ACCOUNT, conversation_id),
        ).fetchall()
        counts = {}
        for table in ("collaboration_event_cursors", "collaboration_event_inbox"):
            counts[table] = connection.execute(
                f"SELECT COUNT(*) FROM {table} WHERE terminal_account_id=?",
                (ACCOUNT,),
            ).fetchone()[0]
        cursors = connection.execute(
            """SELECT service, last_sequence, updated_at
               FROM collaboration_event_cursors
               WHERE terminal_account_id=?
               ORDER BY service""",
            (ACCOUNT,),
        ).fetchall()
        recent_events = connection.execute(
            """SELECT event_id, sequence, event_type, payload_json,
                      received_at, applied_at
               FROM collaboration_event_inbox
               WHERE terminal_account_id=?
               ORDER BY sequence DESC
               LIMIT 500""",
            (ACCOUNT,),
        ).fetchall()
        target_events = []
        for row in recent_events:
            try:
                payload = json.loads(row["payload_json"] or "{}")
            except (TypeError, json.JSONDecodeError):
                continue
            payload_conversation = (
                payload.get("conversationId")
                or payload.get("ConversationId")
                or payload.get("conversation_id")
            )
            if payload_conversation != conversation_id:
                continue
            target_events.append(
                {
                    "event_id": row["event_id"],
                    "sequence": row["sequence"],
                    "event_type": row["event_type"],
                    "received_at": row["received_at"],
                    "applied_at": row["applied_at"],
                }
            )
        return {
            "checkedAt": datetime.datetime.now().astimezone().isoformat(),
            "source": "installed-desktop-sqlite-read-only-transaction-not-ui",
            "accountId": ACCOUNT,
            "conversationId": conversation_id,
            "integrity": integrity,
            "messages": [dict(row) for row in rows],
            "sync": [dict(row) for row in sync],
            "eventTableCounts": counts,
            "eventCursors": [dict(row) for row in cursors],
            "recentTargetEvents": target_events,
        }
    finally:
        connection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--conversation-id", default=DEFAULT_CONVERSATION)
    arguments = parser.parse_args()
    if not UUID_PATTERN.fullmatch(arguments.conversation_id):
        raise SystemExit("Invalid conversation id.")
    try:
        print(json.dumps(inspect(arguments.conversation_id), indent=2))
    except (OSError, sqlite3.Error) as error:
        # Do not include exception text that could reveal unexpected data.
        print(json.dumps({"errorType": type(error).__name__}))
        raise SystemExit(1)
