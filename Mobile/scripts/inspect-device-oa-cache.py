"""Read-only OA cache metadata. Does not decrypt or print business payloads."""
import argparse
import datetime
import json
import pathlib
import sqlite3
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--account-id', required=True, type=uuid.UUID)
args = parser.parse_args()
account = str(args.account_id)
adb = r'C:\Users\86137\AppData\Local\Android\Sdk\platform-tools\adb.exe'
package = 'com.hexing.zhilian.hexing_terminal_mobile'
database = 'hexing-mobile-test-2496f299b56989b204541161-oa.db'


def read(name):
    result = subprocess.run([adb, '-s', args.serial, 'exec-out', 'run-as',
                             package, 'cat', 'databases/' + name],
                            capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError('OA snapshot unavailable')
    return result.stdout


for attempt in range(3):
    wal_before = read(database + '-wal')
    body = read(database)
    wal = read(database + '-wal')
    if wal_before == wal and body == read(database):
        break
else:
    raise RuntimeError('OA database changed during snapshot; no result emitted')

with tempfile.TemporaryDirectory(prefix='sa-oa-metadata-') as temporary:
    target = pathlib.Path(temporary) / database
    target.write_bytes(body)
    target.with_name(database + '-wal').write_bytes(wal)
    connection = sqlite3.connect(target.as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row

    def rows(query):
        return [dict(row) for row in connection.execute(query, (account,))]

    try:
        print(json.dumps({
            'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'accountId': account,
            'schemaVersion': connection.execute('PRAGMA user_version').fetchone()[0],
            'cursor': rows("SELECT value, updated_at FROM oa_sync_state WHERE account_id=? AND state_key='last-event-sequence'"),
            'caches': rows('SELECT cache_key, updated_at FROM oa_cache WHERE account_id=? ORDER BY cache_key'),
            'events': rows('SELECT sequence, event_id, type, created_at, applied_at FROM oa_event_inbox WHERE account_id=? ORDER BY sequence DESC LIMIT 12'),
            'readReceipts': rows('SELECT notification_id, read_at, state, attempts FROM oa_notification_reads WHERE account_id=? ORDER BY read_at'),
            'outbox': rows('SELECT id, command_type, state, attempts, created_at FROM oa_outbox WHERE account_id=? ORDER BY created_at'),
            'drafts': rows('SELECT id, application_key, template_id, updated_at FROM oa_approval_drafts WHERE account_id=? ORDER BY updated_at'),
        }, indent=2))
    finally:
        connection.close()
