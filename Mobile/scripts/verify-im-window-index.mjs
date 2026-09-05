import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

// Read-only audit of the captured evidence; never touches device databases.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/im-window-index-20260903');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8').replace(/^\uFEFF/, ''));
const checks = [];
function check(name, action) {
  try { action(); checks.push({ name, passed: true }); }
  catch { checks.push({ name, passed: false }); }
}
for (const device of ['m3', 'm4']) {
  const before = read(`${device}-before-im.json`);
  const after = read(`${device}-after-im.json`);
  check(`${device}-schema-and-integrity`, () => {
    assert.equal(before.schemaVersion, 14); assert.equal(after.schemaVersion, 15);
    assert.equal(after.integrity, 'ok');
  });
  check(`${device}-ordering-index-used`, () => {
    assert(before.messageWindowOrderingPlan.some(p => p.detail.includes('TEMP B-TREE')));
    assert(after.messageWindowOrderingPlan.some(p => p.detail.includes('ix_im_messages_visible_window')));
    assert(!after.messageWindowOrderingPlan.some(p => p.detail.includes('TEMP B-TREE')));
  });
  check(`${device}-non-event-table-counts-preserved`, () => {
    const { im_event_inbox: _before, ...oldCounts } = before.tableRowCounts;
    const { im_event_inbox: _after, ...newCounts } = after.tableRowCounts;
    assert.deepEqual(newCounts, oldCounts);
  });
  check(`${device}-live-event-count-reconciled`, () => {
    // The running app continues receiving presence events during installation.
    // Reconcile every extra row against captured event IDs/types, not an
    // arbitrary tolerance or an unchecked assumption that counts may grow.
    const known = new Set(before.recentEvents.map(row => row.event_id));
    const extra = after.recentEvents.filter(row => !known.has(row.event_id));
    assert.equal(after.tableRowCounts.im_event_inbox - before.tableRowCounts.im_event_inbox, extra.length);
    assert(extra.every(row => row.type === 'presence.changed'));
    for (const cursor of before.eventCursors) {
      const next = after.eventCursors.find(row => row.account_id === cursor.account_id && row.cursor_kind === cursor.cursor_kind);
      assert(next && next.sequence >= cursor.sequence);
    }
  });
  for (const key of ['messageLedger', 'groupProjections', 'conversationMetadata', 'currentMembers']) {
    check(`${device}-${key}-preserved`, () => assert.deepEqual(after[key], before[key]));
  }
  const pending = doc => doc.outbox.map(row => [row.client_message_id, row.conversation_id, row.kind, row.created_at]);
  check(`${device}-pending-media-preserved`, () => assert.deepEqual(pending(after), pending(before)));
  const oaBefore = read(`${device}-before-oa.json`);
  const oaAfter = read(`${device}-after-oa.json`);
  for (const key of ['drafts', 'readReceipts', 'outbox']) {
    check(`${device}-oa-${key}-preserved`, () => {
      assert(Array.isArray(oaBefore[key])); assert.deepEqual(oaAfter[key], oaBefore[key]);
    });
  }
}
for (const file of ['android-benchmark.json', 'android-benchmark-repeat.json']) {
  const report = read(file);
  check(`${file}-three-sizes-and-equivalence`, () => {
    assert.deepEqual(report.results.map(r => r.confirmedFixtureRows), [1000, 10000, 50000]);
    for (const result of report.results) {
      assert.equal(result.sameRowsAndReceipts, true);
      assert.equal(result.encryptedDecodedContentMatches, true);
      assert.equal(result.visibleWindowRows, 80);
      assert(result.beforePlan.some(p => p.includes('TEMP B-TREE')));
      assert(!result.afterPlan.some(p => p.includes('TEMP B-TREE')));
    }
  });
}
for (const sample of read('normal-runtime.json')) {
  check(`${sample.serial}-normal-apk-runtime`, () => {
    assert.equal(sample.normalApkMatches, true);
    for (const key of ['fatalCount', 'unhandledCount', 'overflowCount', 'benchmarkLogCount']) assert.equal(sample[key], 0);
  });
}
for (const name of ['before-index', 'after-index']) {
  check(`${name}-five-native-contact-open-back`, () => {
    const result = read(`${name}.json`);
    assert.equal(result.completed, 5); assert.equal(result.sameProcess, true);
    assert(result.cycles.every(c => c.chatVerified && c.singleBackReturned));
  });
}
check('updated-offline-three-open-back-and-network-restored', () => {
  const result = read('after-index-offline.json');
  assert.equal(result.completed, 3); assert.equal(result.sameProcess, true);
  assert(result.cycles.every(c => c.chatVerified && c.singleBackReturned));
  const network = read('network-restore.json');
  assert.deepEqual(network, {wifiBefore: '1', dataBefore: '1', wifiDuring: '0', dataDuring: '0', wifiAfter: '1', dataAfter: '1'});
});
const result = { passed: checks.filter(c => c.passed).length, total: checks.length, checks };
fs.writeFileSync(path.join(root, 'verification.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result));
if (result.passed !== result.total) process.exitCode = 1;
