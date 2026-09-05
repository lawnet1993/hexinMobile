// Read-only audit of saved native evidence. No API calls or device writes.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../test/evidence/im-row-decode-20260903');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8').replace(/^\uFEFF/,''));
const checks=[];
const check=(name,action)=>{try{action();checks.push({name,passed:true});}catch{checks.push({name,passed:false});}};
for(const device of ['m3','m4']){
  const before=read(`${device}-before.json`),after=read(`${device}-after.json`);
  check(`${device}-complete-ledger-and-read-state-preserved`,()=>{
    assert.equal(after.integrity,'ok');
    assert.equal(after.messageLedger.length,510);
    assert.equal(new Set(after.messageLedger.map(row=>row.id)).size,510);
    for(const key of ['messageLedger','groupProjections','recipientRead','conversationMetadata','currentMembers']) assert.deepEqual(after[key],before[key]);
  });
  check(`${device}-existing-outbox-preserved`,()=>{
    const identities=doc=>doc.outbox.map(row=>[row.client_message_id,row.conversation_id,row.kind,row.created_at]).sort();
    assert.deepEqual(identities(after),identities(before));
  });
}
check('oa-drafts-and-notification-receipts-preserved',()=>{
  const before=read('m3-oa-before.json'),after=read('m3-oa-after.json');
  for(const key of ['drafts','readReceipts','outbox'])assert.deepEqual(after[key],before[key]);
});
const expanded=read('m3-expanded-decode.json');
check('native-510-history-uses-exactly-510-decodes-across-expanded-queries',()=>{
  assert.equal(expanded.rejected,0);
  assert(expanded.events.length>0 && expanded.events.length<80);
  assert.equal(expanded.events.reduce((sum,event)=>sum+event.rows-event.cacheHits,0),510);
  const windows=expanded.events.filter(event=>event.rows>80);
  assert.deepEqual(windows.map(event=>event.rows),[160,240,320,400,480,510]);
  assert(windows.every(event=>event.cacheHits>0));
  assert.equal(windows.at(-1).cacheHits,510);
});
check('native-swipe-reaches-first-message-with-sender-avatar',()=>{
  const history=read('native-history.json');
  assert.equal(history[0].last,510);
  assert.equal(history.at(-1).first,1);
  assert(history.at(-1).gestures>0);
  const xml=fs.readFileSync(path.join(root,history.at(-1).screenshot.replace(/\.png$/,'.xml')),'utf8');
  assert(xml.includes('AI-UAT-701-BATCH-0001'));
  assert(xml.includes('Test Terminal 04'));
  // Avatar appearance additionally reviewed from the corresponding PNG.
});
for(let i=1;i<=3;i++)check(`hot-reopen-${i}-latest-visible-and-no-repeat-decode`,()=>{
  const hot=read(`m3-hot-decode-${i}.json`);
  assert.equal(hot.pid,expanded.pid);assert.equal(hot.rejected,0);
  assert(hot.events.length>=expanded.events.length && hot.events.length<80);
  assert.deepEqual(hot.events.slice(0,expanded.events.length),expanded.events);
  assert(hot.events.slice(expanded.events.length).every(event=>event.cacheHits===event.rows));
  const xml=fs.readFileSync(path.join(root,`m3-hot-${i}.xml`),'utf8');
  assert(xml.includes('AI-UAT-701-BATCH-0510'));
});
check('m4-normal-latest-window-decode-and-reuse-observed',()=>{
  const latest=read('m4-latest-decode.json');
  assert.equal(latest.rejected,0);assert(latest.events.length>0 && latest.events.length<80);
  assert(latest.events.some(event=>event.rows>0 && event.cacheHits===event.rows));
  assert(fs.readFileSync(path.join(root,'m4-group-latest.xml'),'utf8').includes('AI-UAT-701-BATCH-0510'));
});
check('both-normal-installed-apks-match-and-remain-running',()=>{
  const hash=createHash('sha256').update(fs.readFileSync(path.join(root,'normal-706.apk'))).digest('hex').toUpperCase();
  const installs=read('install.json'),runtime=read('runtime.json');
  assert.deepEqual(runtime.map(row=>row.serial).sort(),['emulator-5556','emulator-5558']);
  for(const row of runtime){
    const install=installs.find(item=>item.serial===row.serial);
    assert.equal(install.sha256,hash);assert.equal(row.normalApkMatches,true);
    assert.equal(row.pid,install.pid);
    for(const field of ['fatalCount','unhandledCount','overflowCount','observerLogCount'])assert.equal(row[field],0);
    assert.equal(row.wifi,'1');assert.equal(row.mobileData,'1');
  }
});
const result={passed:checks.filter(row=>row.passed).length,total:checks.length,checks};
fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed!==result.total)process.exitCode=1;
