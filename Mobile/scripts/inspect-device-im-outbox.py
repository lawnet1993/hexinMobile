"""Read-only metadata snapshot; never export message bodies or credentials."""
import argparse
import json
import pathlib
import re
import sqlite3
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument("--serial", required=True)
parser.add_argument("--conversation-id", default="c4906953-10bd-4671-b984-c50ed3951349")
parser.add_argument("--client-message-id", default="46bce48c-c409-45ae-99ee-4942a8d31320")
parser.add_argument("--message-ledger", action="store_true")
parser.add_argument("--member-presence", action="store_true")
parser.add_argument("--recipient-read", action="store_true")
args = parser.parse_args()
adb = r"C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe"
package = "com.hexing.zhilian.hexing_terminal_mobile"
database = "hexing-mobile-test-2496f299b56989b204541161-im.db"


def read(name):
    result = subprocess.run(
        [adb, "-s", args.serial, "exec-out", "run-as", package,
         "cat", "databases/" + name], capture_output=True, check=False,
    )
    if result.returncode:
        raise RuntimeError("Snapshot unavailable")
    return result.stdout


for attempt in range(3):
    wal_before = read(database + "-wal")
    body = read(database)
    wal = read(database + "-wal")
    if wal_before == wal and body == read(database):
        break
else:
    raise RuntimeError("Database changed during snapshot; no result emitted")

# SQLite reads a consistent DB + WAL copy. Originals are never opened for write.
# Temporary encrypted pages are removed automatically; only metadata is emitted.
with tempfile.TemporaryDirectory(prefix="sa-im-metadata-") as temporary:
    target = pathlib.Path(temporary) / database
    target.write_bytes(body)
    target.with_name(database + "-wal").write_bytes(wal)
    connection = sqlite3.connect(target.as_uri() + "?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute("""
            SELECT client_message_id, conversation_id, kind, attempts,
                   created_at, next_retry_at,
                   EXISTS(SELECT 1 FROM im_sync_state s
                          WHERE s.account_id = o.account_id
                            AND s.state_key = 'outbox.transport.' || o.client_message_id
                            AND s.value = '1') AS retry_on_connection_change
            FROM im_outbox o ORDER BY created_at, rowid
        """).fetchall()
        target_conversation = args.conversation_id
        messages = connection.execute("""
            SELECT account_id, COUNT(*) AS message_count,
                   MIN(sequence) AS minimum_sequence, MAX(sequence) AS maximum_sequence
            FROM im_messages WHERE conversation_id = ? GROUP BY account_id
        """, (target_conversation,)).fetchall()
        target = connection.execute("""
            SELECT account_id, id, client_message_id, sequence, local_status
            FROM im_messages WHERE client_message_id = ?
        """, (args.client_message_id,)).fetchall()
        ledger = connection.execute("""
            SELECT account_id, id, client_message_id, sender_id, sequence,
                   kind, local_status, created_at
            FROM im_messages WHERE conversation_id = ? ORDER BY sequence
        """, (target_conversation,)).fetchall() if args.message_ledger else []
        conversations = connection.execute("""
            SELECT account_id, last_message_sequence, last_read_sequence,
                   unread_count, unread_mention_sequences_json
            FROM im_conversations WHERE id = ?
        """, (target_conversation,)).fetchall()
        recipient_reads = connection.execute("""
            SELECT account_id, CAST(value AS INTEGER) AS last_recipient_read_sequence
            FROM im_sync_state WHERE state_key = ? ORDER BY account_id
        """, ("recipient.read." + target_conversation,)).fetchall() if args.recipient_read else []
        failures = connection.execute("SELECT kind, last_error FROM im_outbox").fetchall()
        statuses = [{"kind": row["kind"], "httpStatus":
                     match.group(1) if (match := re.search(r"HTTP (\d{3})", row["last_error"])) else None}
                    for row in failures]
        history = connection.execute("""
            SELECT account_id, state_key, value FROM im_sync_state
            WHERE state_key LIKE 'history.%'
        """).fetchall()
        summaries = connection.execute("""
            SELECT c.account_id, c.id, c.type, c.last_message_sequence,
                   c.last_read_sequence, c.unread_count,
                   (SELECT COUNT(*) FROM im_messages m WHERE m.account_id = c.account_id
                    AND m.conversation_id = c.id) AS local_message_count
            FROM im_conversations c
        """).fetchall()
        schema_version = connection.execute("PRAGMA user_version").fetchone()[0]
        member_presence = []
        directory_presence = []
        if args.member_presence and schema_version >= 14:
            member_presence = connection.execute("""
                SELECT account_id, id, is_online, last_seen_at, updated_at
                FROM im_conversation_members WHERE conversation_id = ?
                ORDER BY position LIMIT 100
            """, (target_conversation,)).fetchall()
            directory_presence = connection.execute("""
                SELECT m.account_id, m.id, m.is_online, m.last_seen_at, m.updated_at
                FROM im_members m WHERE EXISTS (
                    SELECT 1 FROM im_conversation_members c
                    WHERE c.account_id = m.account_id AND c.id = m.id
                    AND c.conversation_id = ?)
                LIMIT 100
            """, (target_conversation,)).fetchall()
        current_members = connection.execute("""
            SELECT account_id, id, username FROM im_members WHERE is_current = 1
        """).fetchall()
        cursors = connection.execute("""
            SELECT account_id,
                   CASE WHEN state_key LIKE 'events.last_ack_sequence.%'
                        THEN 'acked' ELSE 'applied' END AS cursor_kind,
                   CAST(value AS INTEGER) AS sequence
            FROM im_sync_state
            WHERE state_key LIKE 'events.last_sequence.%'
               OR state_key LIKE 'events.last_ack_sequence.%'
        """).fetchall()
        inbox = connection.execute("""
            SELECT account_id, sequence, event_id, type, created_at
            FROM im_event_inbox ORDER BY sequence DESC LIMIT 20
        """).fetchall()
        # Ordering-only EXPLAIN on the read-only snapshot. No payload SELECT is
        # executed; the full receipt projection is covered by the fixture tests.
        window_plan = connection.execute("""
            EXPLAIN QUERY PLAN SELECT * FROM im_messages
            WHERE account_id = ? AND conversation_id = ? AND is_deleted = 0
            ORDER BY CASE WHEN sequence = 0 THEN 1 ELSE 0 END DESC,
                     sequence DESC, created_at DESC LIMIT 80
        """, ("plan-only-account", target_conversation)).fetchall()
        table_counts = {}
        for entry in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'"):
            name = entry[0]
            if re.fullmatch(r"im_[a-z_]+", name):
                table_counts[name] = connection.execute('SELECT COUNT(*) FROM "' + name + '"').fetchone()[0]
        print(json.dumps({"schemaVersion": schema_version,
                          **({"recipientRead": [dict(row) for row in recipient_reads]}
                             if args.recipient_read else {}),
                          "messageWindowOrderingPlan": [dict(row) for row in window_plan],
                          "tableRowCounts": table_counts,
                          "integrity": connection.execute("PRAGMA quick_check").fetchone()[0],
                          "memberPresence": [dict(row) for row in member_presence],
                          "directoryPresence": [dict(row) for row in directory_presence],
                          "eventCursors": [dict(row) for row in cursors],
                          "recentEvents": [dict(row) for row in inbox],
                          "currentMembers": [dict(row) for row in current_members],
                          "outbox": [dict(row) for row in rows],
                          "messageLedger": [dict(row) for row in ledger],
                          "failures": statuses,
                          "groupMessages": [dict(row) for row in messages],
                          "targetMessage": [dict(row) for row in target],
                          "groupProjections": [dict(row) for row in conversations],
                          "historyRepairState": [dict(row) for row in history],
                          "conversationMetadata": [dict(row) for row in summaries]}, indent=2))
    finally:
        connection.close()
