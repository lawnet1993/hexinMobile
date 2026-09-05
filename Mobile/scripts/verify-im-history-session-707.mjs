// Verify saved evidence only. No network or device/database mutations.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../test/evidence/im-history-session-20260903');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,name),'utf8').replace(/^\uFEFF/,''));
const checks=[];
const check=(name,fn)=>{try{fn();checks.push({name,passed:true});}catch{checks.push({name,passed:false});}};
for(const device of ['m3','m4']){
  const before=read(`${device}-before.json`),after=read(`${device}-after.json`);
  check(`${device}-ledger-and-authoritative-read-preserved`,()=>{
    assert.equal(after.integrity,'ok');
    assert.equal(after.messageLedger.length,510);
    assert.equal(new Set(after.messageLedger.map(row=>row.id)).size,510);
    for(const key of ['messageLedger','groupProjections','recipientRead','conversationMetadata'])assert.deepEqual(after[key],before[key]);
  });
  check(`${device}-existing-outbox-preserved`,()=>{
    const identity=doc=>doc.outbox.map(row=>[row.client_message_id,row.conversation_id,row.kind,row.created_at]).sort();
    assert.deepEqual(identity(after),identity(before));
  });
}
check('oa-drafts-notification-reads-and-outbox-preserved',()=>{
  const before=read('m3-oa-before.json'),after=read('m3-oa-after.json');
  for(const key of ['drafts','readReceipts','outbox'])assert.deepEqual(after[key],before[key]);
});
check('native-offline-history-and-reopen',()=>{
  const history=read('offline-history.json');
  assert.equal(history.offlineVerified,true);
  assert.equal(history.reachedFirst,true);
  assert.equal(history.offlineReopenLatest,true);
  assert.equal(history.networkRestored,true);
  assert.equal(history.observations[0].last,510);
  assert(history.observations.some(row=>row.first===1 && row.gestures>0));
  assert.equal(history.observations.at(-1).last,510);
  assert(fs.readFileSync(path.join(root,'m3-offline-reopened.xml'),'utf8').includes('AI-UAT-701-BATCH-0510'));
});
check('restored-online-latest-and-both-original-accounts-visible',()=>{
  for(const [serial,name] of [['emulator-5556','Test Terminal 03'],['emulator-5558','Test Terminal 04']]){
    assert(fs.readFileSync(path.join(root,`${serial}-installed.xml`),'utf8').includes(name));
  }
  for(const name of ['m3-online-restored','m4-group-latest']){
    assert(fs.readFileSync(path.join(root,`${name}.xml`),'utf8').includes('AI-UAT-701-BATCH-0510'));
  }
  assert.equal(read('online-restored.json').activeDefaultNetwork,true);
});
check('matching-normal-apks-stable-processes-and-no-runtime-fatal',()=>{
  const installs=read('install.json'),runtime=read('runtime.json');
  const hash=createHash('sha256').update(fs.readFileSync(path.join(root,'normal-707.apk'))).digest('hex').toUpperCase();
  assert.deepEqual(runtime.map(row=>row.serial).sort(),['emulator-5556','emulator-5558']);
  for(const row of runtime){
    const install=installs.find(item=>item.serial===row.serial);
    assert.equal(install.sha256,hash);assert.equal(row.normalApkMatches,true);assert.equal(row.pid,install.pid);
    for(const field of ['fatalCount','unhandledCount','overflowCount','observerLogCount'])assert.equal(row[field],0);
    assert.equal(row.wifi,'1');assert.equal(row.mobileData,'1');
  }
});
const result={passed:checks.filter(item=>item.passed).length,total:checks.length,checks};
fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(result.passed!==result.total)process.exitCode=1;
