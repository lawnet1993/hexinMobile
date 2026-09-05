import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/avatar-decode-performance-20260903');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8').replace(/^\uFEFF/, ''));
const checks = [];
function check(name, action) {
  try { action(); checks.push({ name, passed: true }); }
  catch { checks.push({ name, passed: false }); }
}
for (const device of ['m3', 'm4']) {
  const before = read(`${device}-before-im.json`), after = read(`${device}-after-im.json`);
  check(`${device}-schema-integrity-and-message-count`, () => {
    assert.equal(after.schemaVersion, 15); assert.equal(after.integrity, 'ok');
    assert.equal(after.tableRowCounts.im_messages, before.tableRowCounts.im_messages);
  });
  for (const key of ['messageLedger', 'groupProjections', 'conversationMetadata', 'currentMembers']) {
    check(`${device}-${key}-retained`, () => assert.deepEqual(after[key], before[key]));
  }
  const pending = doc => doc.outbox.map(row => [row.client_message_id, row.conversation_id, row.kind, row.created_at]);
  check(`${device}-pending-media-retained`, () => assert.deepEqual(pending(after), pending(before)));
  const oaBefore = read(`${device}-before-oa.json`), oaAfter = read(`${device}-after-oa.json`);
  for (const key of ['drafts', 'readReceipts', 'outbox']) {
    check(`${device}-oa-${key}-retained`, () => {
      assert(Array.isArray(oaBefore[key])); assert.deepEqual(oaAfter[key], oaBefore[key]);
    });
  }
}
for (const name of ['android-benchmark.json', 'android-benchmark-repeat.json']) {
  check(`${name}-actual-codec-sizes-and-samples`, () => {
    const rows = read(name).results;
    assert.deepEqual(rows.map(row => row.fixture), ['bundled-preset', 'synthetic-square', 'synthetic-landscape', 'synthetic-portrait']);
    const expected = [[96, 96], [96, 96], [192, 96], [96, 192]];
    for (const [i, row] of rows.entries()) {
      assert.deepEqual([row.sized.width, row.sized.height], expected[i]);
      assert.equal(row.sized.decodedRgbaBytes, row.sized.width * row.sized.height * 4);
      assert(row.sized.decodedRgbaBytes < row.original.decodedRgbaBytes);
      for (const sample of [row.original, row.sized]) {
        assert.equal(sample.coldResolveMicros.length, 5);
        assert(sample.coldResolveMicros.every(n => Number.isFinite(n) && n >= 0));
      }
    }
    // Deliberately no latency-success assertion: large PNG cold resize is
    // slower in the measured results and must remain visible in the report.
  });
}
for (const sample of read('normal-runtime.json')) {
  check(`${sample.serial}-normal-apk-runtime`, () => {
    assert.equal(sample.normalApkMatches, true);
    for (const key of ['fatalCount', 'unhandledCount', 'overflowCount', 'benchmarkLogCount']) assert.equal(sample[key], 0);
  });
}
check('normal-contact-open-and-single-back-five-cycles', () => {
  const result = read('after-avatar.json');
  assert.equal(result.completed, 5); assert.equal(result.sameProcess, true);
  assert(result.cycles.every(c => c.chatVerified && c.singleBackReturned));
});
const result = {passed: checks.filter(c => c.passed).length, total: checks.length, checks};
fs.writeFileSync(path.join(root, 'verification.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result));
if (result.passed !== result.total) process.exitCode = 1;
