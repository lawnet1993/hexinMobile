// Reads saved native/SQLite observations only; never sends or edits business data.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/im-batch-catchup-20260903');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8').replace(/^\uFEFF/, ''));
const group = '245e652d-14be-4c29-a7aa-57b7659fa4e6';
const accounts = {m3: 'c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc', m4: 'b6a2d272-aaca-4845-bbf8-294288c940a9'};
const checks = [];
function check(name, action) {
  try { action(); checks.push({name, passed: true}); }
  catch { checks.push({name, passed: false}); }
}
const journal = read('native-send-run.json');
const count = 510;
check('one-click-per-native-marker-and-network-finally', () => {
  assert.equal(journal.requested, count);
  assert.equal(journal.conversationId, group);
  for (const stage of ['about-to-click', 'clicked']) {
    assert.deepEqual(journal.events.filter(e => e.stage === stage).map(e => e.index), Array.from({length: count}, (_,i) => i + 1));
  }
  assert.equal(journal.events.at(-1).stage, 'network-restored');
});
const offline = read('m3-offline-after-send.json');
const before = read('m3-before-batch.json');
check('receiver-had-no-test-message-or-advanced-cursor-while-offline', () => {
  assert.equal(offline.messageLedger.length, 0);
  assert.deepEqual(offline.eventCursors, before.eventCursors);
});
const observed = read('batch-observations.json');
check('actual-500-event-page-and-following-page-observed-after-commit', () => {
  assert(observed.length >= 2);
  assert(observed.some((row,i) => row.eventCount === 500 && i < observed.length - 1));
  assert.equal(observed.reduce((sum,row) => sum + row.batchTestMessages, 0), count);
  for (const [i,row] of observed.entries()) {
    assert(row.batchMessagesPersisted);
    assert(row.markersOrderedFromOne);
    assert.equal(row.appliedCursor, row.lastEventSequence);
    assert(row.ackedCursor < row.appliedCursor);
    assert(row.firstEventSequence > row.ackedCursor);
    assert.equal(row.uniqueServerIds, row.persistedCount);
    assert.equal(row.uniqueClientIds, row.persistedCount);
    assert.equal(row.markerCount, row.persistedCount);
    if (i > 0) {
      // This observer omits batches without a message in the test group.
      // Intervening presence/read-only batches may legitimately advance ACK.
      assert(row.ackedCursor >= observed[i-1].appliedCursor);
      assert(row.firstEventSequence > observed[i-1].lastEventSequence);
      assert(row.elapsedMs > observed[i-1].elapsedMs);
    }
  }
  assert.equal(observed.at(-1).persistedCount, count);
  assert.equal(observed.at(-1).lastMarker, count);
});
const unread = read('m3-recovered-unread.json');
check('recovery-kept-persistent-unread-before-opening-chat', () => {
  const projection = unread.groupProjections.find(row => row.account_id === accounts.m3);
  assert.equal(projection.last_read_sequence, 0);
  assert.equal(projection.last_message_sequence, count);
  assert.equal(projection.unread_count, count);
  const cursors = unread.eventCursors.filter(row => row.account_id === accounts.m3);
  assert.equal(cursors.find(row => row.cursor_kind === 'applied').sequence, cursors.find(row => row.cursor_kind === 'acked').sequence);
});
const finals = {};
for (const device of ['m3','m4']) {
  const account = accounts[device];
  const initial = read(`${device}-before-batch.json`);
  const final = finals[device] = read(`${device}-final.json`);
  check(`${device}-complete-unique-ordered-ledger`, () => {
    assert.equal(final.integrity, 'ok');
    assert.equal(final.schemaVersion, 15);
    assert.equal(final.messageLedger.length, count);
    assert(final.messageLedger.every(row => row.account_id === account && row.sequence > 0));
    assert.deepEqual(final.messageLedger.map(row => row.sequence), Array.from({length: count}, (_,i) => i+1));
    assert.equal(new Set(final.messageLedger.map(row => row.id)).size, count);
    assert.equal(new Set(final.messageLedger.map(row => row.client_message_id)).size, count);
    assert(final.messageLedger.every(row => row.sender_id === accounts.m4 && row.kind === 'text' && row.local_status === 'sent'));
  });
  check(`${device}-original-conversations-and-outbox-retained`, () => {
    const others = doc => doc.conversationMetadata.filter(row => row.id !== group).sort((a,b) => `${a.account_id}:${a.id}`.localeCompare(`${b.account_id}:${b.id}`));
    assert.deepEqual(others(final), others(initial));
    const pending = doc => doc.outbox.map(row => [row.client_message_id,row.conversation_id,row.kind,row.created_at]).sort();
    assert.deepEqual(pending(final), pending(initial));
    assert.deepEqual(final.currentMembers, initial.currentMembers);
  });
  check(`${device}-final-read-cursor-persisted`, () => {
    const projection = final.groupProjections.find(row => row.account_id === account);
    assert.equal(projection.last_message_sequence, count);
    assert.equal(projection.last_read_sequence, count);
    assert.equal(projection.unread_count, 0);
  });
}
check('sender-and-receiver-have-identical-confirmed-message-identities', () => {
  const ledger = doc => doc.messageLedger.map(({account_id,...row}) => row);
  assert.deepEqual(ledger(finals.m3), ledger(finals.m4));
});
check('sender-receipt-changes-only-after-peer-reads', () => {
  assert.deepEqual(read('m4-receipt-before-703.json').recipientRead, []);
  const receipt = finals.m4.recipientRead.find(row => row.account_id === accounts.m4);
  assert.equal(receipt.last_recipient_read_sequence, count);
});
check('original-oa-drafts-receipts-and-outbox-retained', () => {
  const initial = read('m3-oa-before.json'), final = read('m3-oa-final.json');
  for (const key of ['drafts','readReceipts','outbox']) assert.deepEqual(final[key],initial[key]);
});
const runtime = read('normal-runtime-final.json');
for (const row of runtime) {
  check(`${row.serial}-normal-package-restored-no-observer`, () => {
    assert.equal(row.normalApkMatches, true);
    assert.equal(row.wifi, '1'); assert.equal(row.mobileData, '1');
    for (const key of ['fatalCount','unhandledCount','overflowCount','observerLogCount']) assert.equal(row[key], 0);
  });
}
assert.equal(runtime.length, 2);
const result = {passed: checks.filter(row => row.passed).length, total: checks.length, checks};
fs.writeFileSync(path.join(root, 'verification.json'), JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed !== result.total) process.exitCode=1;
