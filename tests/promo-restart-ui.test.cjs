const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const src=fs.readFileSync('web/promotion-ui.js','utf8');
const fn=src.slice(src.indexOf(' async function click(event)'),src.indexOf(' function mount()'));
async function run(){
 let complete, calls=[], dialogs=[];
 const finished=new Promise(r=>complete=r);
 const context={busy:false,dialog:null,root:{matchMedia:()=>({matches:false})},
  panel:{querySelector:()=>({animate:()=>({finished}),querySelectorAll:()=>[]})},
  PromotionCore:require('../web/promotion-core.js'),
  DemoData:{promotion:async(action,data)=>{calls.push({action,data});return {percent:15,code:'LP123ABC'};}},
  playTone:t=>calls.push(t),refresh:async()=>{},confirm:()=>true,showError:err=>{if(err instanceof Error)throw err;},
  openDialog:(title,body)=>dialogs.push({title,body}), e:s=>String(s),
 };
 vm.createContext(context);vm.runInContext(fn,context);
 const event=dataset=>({target:{closest:()=>({dataset,isConnected:true})}});
 await context.click(event({promoRestart:'campaign-1'}));
 assert.equal(calls[0]?.action,'campaign-restart','restart button calls atomic owner action');
 assert.equal(calls[0]?.data.campaignId,'campaign-1');
 context.confirm=()=>false;calls=[];
 await context.click(event({promoRestart:'campaign-1'}));assert.equal(calls.length,0,'declining does not restart');
 const pending=context.click(event({promoSpin:'campaign-1'}));
 await new Promise(r=>setImmediate(r));
 assert.equal(dialogs.length,0,'do not show reward before animation stops');
 complete();await pending;
 assert.equal(dialogs.length,1,'show congratulations after spin');
 assert.match(dialogs[0].title,/ยินดี/);assert.match(dialogs[0].body,/15%/);assert.match(dialogs[0].body,/แคป/);
 assert.equal(calls.at(-1),'success','success sound after finish');
 console.log('PASS reset confirmation and congratulations after animation');
}
run().catch(e=>{console.error(e);process.exitCode=1;});
