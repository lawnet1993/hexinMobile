// Saved evidence only: no API or device/database mutations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../test/evidence/im-unread-navigation-20260903');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8').replace(/^\uFEFF/,''));
const xml=name=>fs.readFileSync(path.join(root,`${name}.xml`),'utf8');
const checks=[];
const check=(name,fn)=>{try{fn();checks.push({name,passed:true});}catch(error){checks.push({name,passed:false,error:error.message.slice(0,160)});}};
const accounts={m3:'c404c59a-6dc3-4e6b-a1dc-d5d0c20786cc',m4:'b6a2d272-aaca-4845-bbf8-294288c940a9'};
const ledger=(doc,device)=>doc.messageLedger.filter(row=>row.account_id===accounts[device]);
const projection=(doc,device)=>doc.groupProjections.find(row=>row.account_id===accounts[device]);
const receipt=doc=>doc.recipientRead.find(row=>row.account_id===accounts.m4).last_recipient_read_sequence;
const send=read('native-send.json');
check('exactly-100-native-clicks-with-no-replay',()=>{
  assert.equal(send.count,100);
  assert.deepEqual(send.events.filter(row=>row.stage==='clicked').map(row=>row.index),Array.from({length:100},(_,i)=>i+1));
  assert.equal(send.events.at(-1).stage,'clicks-complete');
});
for(const device of ['m3','m4']){
  check(`${device}-610-confirmed-unique-messages-and-original-510-preserved`,()=>{
    const before=read(`${device}-before.json`),after=read(`${device}-recheck-after.json`);
    assert.equal(after.integrity,'ok');
    const rows=ledger(after,device);
    assert.equal(rows.length,610);
    assert.equal(new Set(rows.map(row=>row.id)).size,610);
    assert.equal(new Set(rows.map(row=>row.client_message_id)).size,610);
    assert.deepEqual(rows.map(row=>row.sequence),Array.from({length:610},(_,i)=>i+1));
    assert(rows.every(row=>row.local_status==='sent'));
    assert.deepEqual(rows.slice(0,510),ledger(before,device));
  });
  check(`${device}-existing-outbox-preserved`,()=>{
    const identity=doc=>doc.outbox.map(row=>[row.client_message_id,row.conversation_id,row.kind,row.created_at]).sort();
    assert.deepEqual(identity(read(`${device}-before.json`)),identity(read(`${device}-recheck-after.json`)));
  });
}
check('sender-and-receiver-have-identical-canonical-ids',()=>{
  const keys=(doc,device)=>ledger(doc,device).map(({id,client_message_id,sequence,sender_id})=>({id,client_message_id,sequence,sender_id}));
  assert.deepEqual(keys(read('m3-recheck-after.json'),'m3'),keys(read('m4-recheck-after.json'),'m4'));
});
check('receiver-outside-chat-retains-100-unread-while-sender-has-zero',()=>{
  const incoming=projection(read('m3-unread.json'),'m3');
  assert.equal(incoming.last_message_sequence,610);assert.equal(incoming.last_read_sequence,510);assert.equal(incoming.unread_count,100);
  assert.equal(projection(read('m4-sent.json'),'m4').unread_count,0);
  assert.equal(receipt(read('m4-sent.json')),510);
});
check('initial-native-failure-remains-recorded-without-resetting-read-state',()=>{
  const first=read('native-scroll.json')[0];
  assert.equal(first.gestures,0);assert.equal(first.first,30);assert.equal(first.last,40);
  assert.equal(projection(read('m3-partial.json'),'m3').last_read_sequence,550);
  assert.equal(projection(read('m3-recheck-baseline.json'),'m3').unread_count,60);
});
check('fixed-first-unread-visible-and-only-visible-range-is-persisted-read',()=>{
  const screen=xml('m3-recheck-first-unread');
  assert(screen.includes(send.prefix+'0041'));assert(screen.includes('以下为未读消息'));
  assert(!screen.includes(send.prefix+'0100'));
  const partial=projection(read('m3-recheck-partial.json'),'m3');
  assert(partial.last_read_sequence>=551&&partial.last_read_sequence<590);
  assert.equal(partial.unread_count,610-partial.last_read_sequence);
  assert.equal(receipt(read('m4-recheck-partial.json')),partial.last_read_sequence);
});
check('native-forward-scroll-reaches-latest-and-receipts-follow',()=>{
  const observations=read('native-recheck-scroll.json');
  assert(observations.some(row=>row.gestures>0&&row.last===100));
  assert(xml('m3-recheck-latest').includes(send.prefix+'0100'));
  for(const device of ['m3','m4']){
    const row=projection(read(`${device}-recheck-after.json`),device);
    assert.equal(row.last_message_sequence,610);assert.equal(row.last_read_sequence,610);assert.equal(row.unread_count,0);
  }
  assert.equal(receipt(read('m4-recheck-after.json')),610);
});
check('oa-drafts-notification-receipts-outbox-preserved',()=>{
  const before=read('m3-oa-before.json'),after=read('m3-oa-after.json');
  for(const key of ['drafts','readReceipts','outbox'])assert.deepEqual(after[key],before[key]);
});
check('normal-apks-match-running-processes-and-no-runtime-fatal',()=>{
  const installs=read('install-reload-fixed.json'),runtime=read('runtime.json');
  const hash=createHash('sha256').update(fs.readFileSync(path.join(root,'normal-708-reload-fixed.apk'))).digest('hex').toUpperCase();
  assert.equal(runtime.length,2);
  for(const row of runtime){
    const install=installs.find(item=>item.serial===row.serial);
    assert.equal(install.sha256,hash);assert.equal(row.sha256,hash);assert.equal(row.pid,install.pid);
    for(const field of ['fatalCount','unhandledCount','overflowCount'])assert.equal(row[field],0);
  }
});
const result={passed:checks.filter(row=>row.passed).length,total:checks.length,checks};
fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed!==result.total)process.exitCode=1;
