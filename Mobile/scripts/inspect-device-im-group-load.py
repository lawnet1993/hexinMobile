"""Inspect a bounded AI-UAT group burst from a consistent device snapshot.

Only aggregate counts, ordering, outbox and cursor health are emitted. Message
content, tokens, device identifiers and attachment addresses are never read.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sqlite3
import subprocess
import tempfile


ADB = r"C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe"
PACKAGE = "com.hexing.zhilian.hexing_terminal_mobile"
DATABASE = "hexing-mobile-test-2496f299b56989b204541161-im.db"
ALLOWED_SERIALS = {"emulator-5554", "emulator-5556", "emulator-5558"}
ALLOWED_ACCOUNTS = {"test02", "test03", "test04"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True, choices=sorted(ALLOWED_SERIALS))
    parser.add_argument("--account", required=True, choices=sorted(ALLOWED_ACCOUNTS))
    parser.add_argument("--title", required=True)
    parser.add_argument("--expected-per-sender", type=int)
    for account in sorted(ALLOWED_ACCOUNTS):
        parser.add_argument(f"--expected-{account}", type=int)
    args = parser.parse_args()
    if not re.fullmatch(r"AI-UAT-[A-Z0-9-]+", args.title):
        parser.error("only AI-UAT group titles are allowed")
    expected_values = [getattr(args, f"expected_{account}") for account in sorted(ALLOWED_ACCOUNTS)]
    if args.expected_per_sender is None and any(value is None for value in expected_values):
        parser.error("set expected-per-sender or all per-account expected counts")
    for value in [args.expected_per_sender, *expected_values]:
        if value is not None and not 0 <= value <= 200:
            parser.error("expected counts must be between 0 and 200")
    return args


def read_device(serial: str, name: str) -> bytes:
    result = subprocess.run(
        [
            ADB,
            "-s",
            serial,
            "exec-out",
            "run-as",
            PACKAGE,
            "cat",
            "databases/" + name,
        ],
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError("consistent database snapshot unavailable")
    return result.stdout


def stable_snapshot(serial: str) -> tuple[bytes, bytes]:
    for _ in range(5):
        wal_before = read_device(serial, DATABASE + "-wal")
        body = read_device(serial, DATABASE)
        wal_after = read_device(serial, DATABASE + "-wal")
        if wal_before == wal_after and body == read_device(serial, DATABASE):
            return body, wal_after
    raise RuntimeError("database changed during bounded snapshot")


def main() -> None:
    args = parse_args()
    body, wal = stable_snapshot(args.serial)
    with tempfile.TemporaryDirectory(prefix="sa-im-group-load-") as temporary:
        target = pathlib.Path(temporary) / DATABASE
        target.write_bytes(body)
        target.with_name(DATABASE + "-wal").write_bytes(wal)
        connection = sqlite3.connect(target.as_uri() + "?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        try:
            account_rows = connection.execute(
                """
                SELECT DISTINCT account_id FROM im_members
                WHERE username = ? AND is_current = 1
                """,
                (args.account,),
            ).fetchall()
            if len(account_rows) != 1:
                raise RuntimeError("current test account could not be resolved uniquely")
            account_id = account_rows[0]["account_id"]
            conversations = connection.execute(
                """
                SELECT id, last_message_sequence, last_read_sequence, unread_count
                FROM im_conversations
                WHERE account_id = ? AND title = ? AND type = 'group'
                """,
                (account_id, args.title),
            ).fetchall()
            if len(conversations) != 1:
                raise RuntimeError("AI-UAT group could not be resolved uniquely")
            conversation = conversations[0]
            rows = connection.execute(
                """
                SELECT m.id, m.sequence, m.sender_id, m.client_message_id,
                       m.local_status, member.username
                FROM im_messages AS m
                LEFT JOIN im_members AS member
                  ON member.account_id = m.account_id AND member.id = m.sender_id
                WHERE m.account_id = ? AND m.conversation_id = ?
                  AND m.is_deleted = 0
                ORDER BY m.sequence, m.id
                """,
                (account_id, conversation["id"]),
            ).fetchall()
            outbox = connection.execute(
                "SELECT COUNT(*) FROM im_outbox WHERE account_id = ?",
                (account_id,),
            ).fetchone()[0]
            cursors = connection.execute(
                """
                SELECT CASE WHEN state_key LIKE 'events.last_ack_sequence.%'
                            THEN 'acked' ELSE 'applied' END AS cursor_kind,
                       CAST(value AS INTEGER) AS sequence
                FROM im_sync_state
                WHERE account_id = ? AND (
                  state_key LIKE 'events.last_sequence.%'
                  OR state_key LIKE 'events.last_ack_sequence.%'
                )
                ORDER BY cursor_kind
                """,
                (account_id,),
            ).fetchall()
            integrity = connection.execute("PRAGMA quick_check").fetchone()[0]
        finally:
            connection.close()

    allowed_senders = sorted(ALLOWED_ACCOUNTS)
    sender_counts = {
        sender: sum(row["username"] == sender for row in rows)
        for sender in allowed_senders
    }
    sequences = [int(row["sequence"]) for row in rows]
    expected_counts = {
        sender: (
            getattr(args, f"expected_{sender}")
            if getattr(args, f"expected_{sender}") is not None
            else args.expected_per_sender
        )
        for sender in allowed_senders
    }
    expected_total = sum(expected_counts.values())
    result = {
        "serial": args.serial,
        "account": args.account,
        "title": args.title,
        "expectedPerSender": args.expected_per_sender,
        "expectedSenderCounts": expected_counts,
        "expectedTotal": expected_total,
        "receivedTotal": len(rows),
        "complete": len(rows) == expected_total
        and all(sender_counts[sender] == expected_counts[sender] for sender in allowed_senders),
        "senderCounts": sender_counts,
        "uniqueMessageIds": len({row["id"] for row in rows}),
        "uniqueSenderClientMessageKeys": len(
            {(row["sender_id"], row["client_message_id"]) for row in rows}
        ),
        "sequenceStrictlyIncreasing": all(
            current > previous for previous, current in zip(sequences, sequences[1:])
        ),
        "sequenceRange": None if not sequences else f"{min(sequences)}..{max(sequences)}",
        "allSent": all(row["local_status"] == "sent" for row in rows),
        "outboxCount": int(outbox),
        "integrity": integrity,
        "conversationProjection": {
            "lastMessageSequence": int(conversation["last_message_sequence"]),
            "lastReadSequence": int(conversation["last_read_sequence"]),
            "unreadCount": int(conversation["unread_count"]),
        },
        "eventCursors": {
            row["cursor_kind"]: int(row["sequence"]) for row in cursors
        },
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
