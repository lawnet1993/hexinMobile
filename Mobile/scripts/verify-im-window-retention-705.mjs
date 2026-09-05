// Offline evidence verification only: no API calls or device/database writes.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/im-window-retention-20260903');
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8').replace(/^\uFEFF/, ''));
const checks=[];
const check=(name, action)=>{try{action();checks.push({name,passed:true});}catch{checks.push({name,passed:false});}};
for(const device of ['m3','m4']){
  const before=read(`${device}-before.json`), after=read(`${device}-after.json`);
  check(`${device}-ledger-and-read-state-retained`,()=>{
    assert.equal(after.integrity,'ok');
    assert.equal(after.messageLedger.length,510);
    for(const key of ['messageLedger','groupProjections','recipientRead','conversationMetadata','currentMembers']){
      assert.deepEqual(after[key],before[key]);
    }
  });
  check(`${device}-existing-outbox-retained`,()=>{
    const identities=doc=>doc.outbox.map(row=>[row.client_message_id,row.conversation_id,row.kind,row.created_at]).sort();
    assert.deepEqual(identities(after),identities(before));
  });
}
check('oa-drafts-read-receipts-outbox-retained',()=>{
  const before=read('m3-oa-before.json'), after=read('m3-oa-after.json');
  for(const key of ['drafts','readReceipts','outbox']) assert.deepEqual(after[key],before[key]);
});
const expanded=read('m3-expanded-cache.json');
check('native-pagination-keeps-one-current-window-not-all-page-sizes',()=>{
  assert.equal(expanded.rejected,0);
  assert(expanded.events.length>0 && expanded.events.length<80);
  assert(expanded.events.every(row=>row.windows<=1 && row.messages<=510));
  assert.deepEqual(expanded.events.filter(row=>row.messages>0).map(row=>row.messages),[80,160,240,320,400,480,510]);
  assert.deepEqual(expanded.events.at(-1),{windows:1,messages:510});
});
check('native-gestures-reach-first-message',()=>{
  const history=read('native-history.json');
  assert.equal(history[0].last,510);
  assert.equal(history.at(-1).first,1);
  assert.equal(history.at(-1).gestures,24);
  const xml=fs.readFileSync(path.join(root,history.at(-1).screenshot.replace(/\.png$/,'.xml')),'utf8');
  assert(xml.includes('AI-UAT-701-BATCH-0001'));
});
for(let i=1;i<=3;i++) check(`hot-reopen-${i}-reuses-window-with-latest-visible`,()=>{
  const hot=read(`m3-hot-cache-${i}.json`);
  assert.equal(hot.pid,expanded.pid);
  assert.equal(hot.rejected,0);
  assert.deepEqual(hot.events,expanded.events);
  const xml=fs.readFileSync(path.join(root,`m3-hot-${i}.xml`),'utf8');
  assert(xml.includes('AI-UAT-701-BATCH-0510'));
});
const installs=read('install.json'), runtime=read('runtime.json');
check('both-installed-normal-builds-match-and-remain-running',()=>{
  assert.deepEqual(runtime.map(row=>row.serial).sort(),['emulator-5556','emulator-5558']);
  for(const row of runtime){
    assert.equal(row.normalApkMatches,true);
    assert.equal(row.pid,installs.find(item=>item.serial===row.serial).pid);
    for(const field of ['fatalCount','unhandledCount','overflowCount','observerLogCount']) assert.equal(row[field],0);
    assert.equal(row.wifi,'1');assert.equal(row.mobileData,'1');
  }
});
const result={passed:checks.filter(row=>row.passed).length,total:checks.length,checks};
fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed!==result.total)process.exitCode=1;
