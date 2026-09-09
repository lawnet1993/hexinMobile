"""Emit sanitized IM load metrics from a consistent, temporary device snapshot.

The database and WAL are read through run-as, opened read-only in a temporary
directory and discarded. Only AI-UAT-prefixed row counts, sequence/uniqueness
and timing aggregates are emitted; message bodies and identifiers are not.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sqlite3
import statistics
import subprocess
import tempfile


ADB = r"C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe"
PACKAGE = "com.hexing.zhilian.hexing_terminal_mobile"
DATABASE = "hexing-mobile-test-2496f299b56989b204541161-im.db"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--account", required=True)
    conversation = parser.add_mutually_exclusive_group(required=True)
    conversation.add_argument("--conversation-id")
    conversation.add_argument("--peer-account")
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--sender-account", required=True)
    parser.add_argument("--start-at", required=True)
    parser.add_argument("--end-at", required=True)
    parser.add_argument("--expected", type=int, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"(?:emulator-\d+|[A-Za-z0-9._:-]+)", args.serial):
        parser.error("invalid serial")
    if not re.fullmatch(r"test\d{2}", args.account):
        parser.error("only numbered test accounts are allowed")
    if not re.fullmatch(r"test\d{2}", args.sender_account):
        parser.error("only numbered test sender accounts are allowed")
    if args.conversation_id and not re.fullmatch(r"[0-9a-fA-F-]{36}", args.conversation_id):
        parser.error("invalid conversation id")
    if args.peer_account and not re.fullmatch(r"test\d{2}", args.peer_account):
        parser.error("only numbered test peer accounts are allowed")
    if not re.fullmatch(r"AI-UAT-[A-Z0-9-]+-", args.prefix):
        parser.error("only AI-UAT prefixes are allowed")
    if not 1 <= args.expected <= 100:
        parser.error("expected must be between 1 and 100")
    try:
        args.start_at = parse_time(args.start_at)
        args.end_at = parse_time(args.end_at)
    except ValueError:
        parser.error("start-at and end-at must be ISO-8601 timestamps")
    if args.start_at is None or args.end_at is None or args.end_at < args.start_at:
        parser.error("invalid timing window")
    return args


def read_device(serial: str, name: str) -> bytes:
    result = subprocess.run(
        [ADB, "-s", serial, "exec-out", "run-as", PACKAGE,
         "cat", "databases/" + name],
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError("consistent database snapshot unavailable")
    return result.stdout


def parse_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    normalized = value.replace("Z", "+00:00")
    parsed = dt.datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def rounded(value: float | None) -> float | None:
    return None if value is None else round(value, 3)


def main() -> None:
    args = parse_args()
    for _ in range(3):
        wal_before = read_device(args.serial, DATABASE + "-wal")
        body = read_device(args.serial, DATABASE)
        wal = read_device(args.serial, DATABASE + "-wal")
        if wal_before == wal and body == read_device(args.serial, DATABASE):
            break
    else:
        raise RuntimeError("database changed during snapshot")

    with tempfile.TemporaryDirectory(prefix="sa-im-load-") as temporary:
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
            conversation_id = args.conversation_id
            if args.peer_account:
                conversation_rows = connection.execute(
                    """
                    SELECT DISTINCT c.id
                    FROM im_conversations AS c
                    JOIN im_conversation_members AS member
                      ON member.account_id = c.account_id
                     AND member.conversation_id = c.id
                    WHERE c.account_id = ? AND c.type = 'direct'
                      AND member.username = ?
                    """,
                    (account_id, args.peer_account),
                ).fetchall()
                if len(conversation_rows) != 1:
                    raise RuntimeError("test direct conversation could not be resolved uniquely")
                conversation_id = conversation_rows[0]["id"]
            sender_rows = connection.execute(
                """
                SELECT DISTINCT id FROM im_members
                WHERE account_id = ? AND username = ?
                """,
                (account_id, args.sender_account),
            ).fetchall()
            if len(sender_rows) != 1:
                raise RuntimeError("test sender could not be resolved uniquely")
            sender_id = sender_rows[0]["id"]
            candidates = connection.execute(
                """
                SELECT id, client_message_id, sender_id, sequence,
                       created_at, updated_at, local_status
                FROM im_messages
                WHERE account_id = ? AND conversation_id = ?
                  AND sender_id = ?
                ORDER BY sequence
                """,
                (account_id, conversation_id, sender_id),
            ).fetchall()
            conversation_projection = connection.execute(
                """
                SELECT last_message_sequence, unread_count, last_read_sequence
                FROM im_conversations
                WHERE account_id = ? AND id = ?
                """,
                (account_id, conversation_id),
            ).fetchone()
            max_message_sequence = connection.execute(
                """
                SELECT COALESCE(MAX(sequence), 0)
                FROM im_messages
                WHERE account_id = ? AND conversation_id = ? AND is_deleted = 0
                """,
                (account_id, conversation_id),
            ).fetchone()[0]
            tail_messages = connection.execute(
                """
                SELECT message.sequence, message.created_at, message.kind,
                       member.username AS sender_username
                FROM im_messages AS message
                LEFT JOIN im_members AS member
                  ON member.account_id = message.account_id
                 AND member.id = message.sender_id
                WHERE message.account_id = ? AND message.conversation_id = ?
                  AND message.is_deleted = 0
                ORDER BY message.sequence DESC
                LIMIT 5
                """,
                (account_id, conversation_id),
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

    # Message content is encrypted/structured locally, so batch membership is
    # determined by the known sender, conversation and bounded UI-send window.
    # The AI-UAT prefix remains in the emitted result to correlate UI evidence.
    rows = []
    for row in candidates:
        created = parse_time(row["created_at"])
        if created and args.start_at <= created <= args.end_at:
            rows.append(row)
    sequences = [int(row["sequence"]) for row in rows]
    latencies = []
    created_times = []
    updated_times = []
    for row in rows:
        created = parse_time(row["created_at"])
        updated = parse_time(row["updated_at"])
        if created and updated:
            created_times.append(created)
            updated_times.append(updated)
            # updated_at is the most recent local upsert time. Conversation
            # reconciliation may rewrite an already-delivered message, so this
            # age is a storage freshness heuristic, not network delivery time.
            latencies.append((updated - created).total_seconds() * 1000)
    contiguous = all(
        current == previous + 1
        for previous, current in zip(sequences, sequences[1:])
    )
    result = {
        "serial": args.serial,
        "account": args.account,
        "conversationId": conversation_id,
        "conversationProjection": None if conversation_projection is None else {
            "lastMessageSequence": int(conversation_projection["last_message_sequence"]),
            "maxStoredMessageSequence": int(max_message_sequence),
            "unreadCount": int(conversation_projection["unread_count"]),
            "lastReadSequence": int(conversation_projection["last_read_sequence"]),
        },
        "tailMessages": [
            {
                "sequence": int(row["sequence"]),
                "createdAtUtc": parse_time(row["created_at"]).isoformat()
                if parse_time(row["created_at"]) else None,
                "kind": row["kind"],
                "senderAccount": row["sender_username"],
            }
            for row in tail_messages
        ],
        "prefix": args.prefix,
        "expected": args.expected,
        "received": len(rows),
        "complete": len(rows) == args.expected,
        "uniqueMessageIds": len({row["id"] for row in rows}),
        "uniqueSenderClientMessageKeys": len({
            (row["sender_id"], row["client_message_id"]) for row in rows
        }),
        "sequenceRange": None if not sequences else f"{min(sequences)}..{max(sequences)}",
        "sequenceContiguous": contiguous,
        "allSent": all(row["local_status"] == "sent" for row in rows),
        "outboxCount": int(outbox),
        "integrity": integrity,
        "eventCursors": {row["cursor_kind"]: int(row["sequence"]) for row in cursors},
        "createdAtUtcRange": None if not created_times else [
            min(created_times).isoformat(), max(created_times).isoformat()
        ],
        "localUpdatedAtUtcRange": None if not updated_times else [
            min(updated_times).isoformat(), max(updated_times).isoformat()
        ],
        "createdToLocalUpdateAgeMs": {
            "samples": len(latencies),
            "negativeSamples": sum(value < 0 for value in latencies),
            "clockSkewWarning": any(value < 0 for value in latencies),
            "min": rounded(min(latencies) if latencies else None),
            "average": rounded(statistics.fmean(latencies) if latencies else None),
            "p50": rounded(percentile(latencies, 0.50)),
            "p90": rounded(percentile(latencies, 0.90)),
            "p95": rounded(percentile(latencies, 0.95)),
            "max": rounded(max(latencies) if latencies else None),
        },
        "timingNote": (
            "createdToLocalUpdateAgeMs is not delivery latency because later "
            "reconciliation can rewrite updated_at; use profile sync event-age "
            "diagnostics for live-delivery timing"
        ),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
