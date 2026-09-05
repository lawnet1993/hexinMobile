// Read saved, redacted evidence only. Does not call APIs or mutate app data.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../test/evidence/im-composer-20260903');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,`${name}.json`),'utf8').replace(/^\uFEFF/,''));
const xml=name=>fs.readFileSync(path.join(root,`${name}.xml`),'utf8');
const checks=[];
const check=(name,fn)=>{try{fn();checks.push({name,passed:true});}catch(error){checks.push({name,passed:false,error:error.message.slice(0,140)});}};
const online=read('native-online'),offline=read('native-offline');
for(const phase of ['online','offline']){
  const journal=phase==='online'?online:offline;
  check(`${phase}-exact-pair-no-replayed-clicks-next-draft-preserved`,()=>{
    for(const stage of ['about-to-send-and-type','sent-and-typed','next-draft-preserved','about-to-send-second','second-clicked','phase-complete']){
      assert.equal(journal.events.filter(e=>e.stage===stage).length,1);
    }
    assert.equal(journal.events.find(e=>e.stage==='next-draft-preserved').detail.exact,true);
    const expected=journal.prefix+(phase==='online'?'02':'04');
    const input=[...xml(`m4-${phase}-next-draft`).matchAll(/<node\b[^>]*>/g)].map(m=>m[0]).find(s=>s.includes('class="android.widget.EditText"'));
    assert(input?.includes(`text="${expected}"`));
  });
}
for(const device of ['m3','m4']){
  check(`${device}-614-unique-confirmed-and-original-610-preserved`,()=>{
    const before=read(`${device}-before`),after=read(`${device}-after`);
    const rows=after.messageLedger;
    assert.equal(after.integrity,'ok');
    assert.equal(rows.length,614);
    assert.equal(new Set(rows.map(m=>m.id)).size,614);
    assert.equal(new Set(rows.map(m=>m.client_message_id)).size,614);
    assert.deepEqual(rows.map(m=>m.sequence),Array.from({length:614},(_,i)=>i+1));
    assert(rows.every(m=>m.local_status==='sent'));
    assert.deepEqual(rows.slice(0,610),before.messageLedger);
  });
  check(`${device}-original-outbox-identities-preserved`,()=>{
    const identity=doc=>doc.outbox.map(m=>[m.client_message_id,m.conversation_id,m.kind,m.created_at]).sort();
    assert.deepEqual(identity(read(`${device}-after`)),identity(read(`${device}-before`)));
  });
}
check('both-devices-have-identical-server-and-client-message-ids',()=>{
  const keys=doc=>doc.messageLedger.map(({id,client_message_id,sequence,sender_id})=>({id,client_message_id,sequence,sender_id}));
  assert.deepEqual(keys(read('m3-after')),keys(read('m4-after')));
});
check('offline-queue-has-two-durable-messages-and-confirmation-reuses-client-ids',()=>{
  const queued=read('m4-offline-queued'),after=read('m4-after');
  assert.equal(queued.outbox.length,2);
  assert.equal(queued.messageLedger.length,614);
  const pending=queued.messageLedger.filter(m=>m.sequence===0);
  assert.equal(pending.length,2);
  assert(pending.every(m=>m.local_status==='pending'));
  assert.deepEqual(pending.map(m=>m.client_message_id).sort(),queued.outbox.map(m=>m.client_message_id).sort());
  assert.deepEqual(pending.map(m=>m.client_message_id).sort(),after.messageLedger.filter(m=>m.sequence>612).map(m=>m.client_message_id).sort());
  assert.equal(after.outbox.length,0);
  assert.equal(offline.events.at(-1).stage,'network-restored');
});
check('both-zero-unread-and-peer-receipt-614',()=>{
  for(const device of ['m3','m4']){
    const row=read(`${device}-after`).groupProjections[0];
    assert.equal(row.last_message_sequence,614);
    assert.equal(row.last_read_sequence,614);
    assert.equal(row.unread_count,0);
  }
  assert.equal(read('m4-after').recipientRead[0].last_recipient_read_sequence,614);
});
check('final-native-screens-show-all-four-markers',()=>{
  for(const device of ['m3','m4']){
    const screen=xml(device==='m3'?'m3-final-received':'m4-final-receipts');
    for(let i=1;i<=4;i++)assert(screen.includes(online.prefix+String(i).padStart(2,'0')));
  }
});
check('oa-drafts-and-notification-receipts-unchanged',()=>{
  const before=read('m3-oa-before'),after=read('m3-oa-after');
  for(const key of ['drafts','readReceipts','outbox'])assert.deepEqual(after[key],before[key]);
  assert.equal(after.drafts.length,2);
  assert.equal(after.readReceipts.length,10);
});
check('normal-installed-apk-matches-live-processes-no-fatal-and-radios-restored',()=>{
  const hash=createHash('sha256').update(fs.readFileSync(path.join(root,'normal-709.apk'))).digest('hex').toUpperCase();
  const installs=read('install'),runtime=read('runtime');
  assert.equal(runtime.length,2);
  for(const row of runtime){
    const install=installs.find(i=>i.serial===row.serial);
    assert.equal(row.sha256,hash);assert.equal(install.sha256,hash);
    assert.equal(row.pid,install.pid);
    for(const key of ['fatalCount','unhandledCount','overflowCount'])assert.equal(row[key],0);
    assert.equal(row.wifiOn,'1');assert.equal(row.mobileDataOn,'1');
  }
});
const result={passed:checks.filter(c=>c.passed).length,total:checks.length,checks};
fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed!==result.total)process.exitCode=1;
